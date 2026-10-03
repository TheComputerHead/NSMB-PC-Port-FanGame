class_name Nsbmd
extends RefCounted
## Parser for Nintendo DS 3D models (.nsbmd) and texture packs (.nsbtx).
##
## Call `parse()`, then `build_model()` to get a Godot Node3D.

const POLY_FRONT := 0x80
const POLY_BACK := 0x40

## Colour tolerance for RotSprite upscaling of textures; negative = plain integer scaling.
static var rotsprite_tolerance := -1

var d := PackedByteArray()
var models: Array[Dictionary] = []
var tex: NitroTex


## Accepts raw file contents (decompressed). `external_tex` can supply textures
## for models that keep them in a separate .nsbtx.
func parse(data: PackedByteArray, external_tex: NitroTex = null) -> Error:
	d = data
	var magic := d.slice(0, 4).get_string_from_ascii()
	if magic != "BMD0" and magic != "BTX0":
		return ERR_FILE_UNRECOGNIZED
	tex = external_tex
	for i in d.decode_u16(0x0E):
		var block := d.decode_u32(0x10 + i * 4)
		match d.slice(block, block + 4).get_string_from_ascii():
			"MDL0":
				for e in NitroDict.read(d, block + 8):
					models.append(_parse_model(block + d.decode_u32(e.entry), e.name))
			"TEX0":
				tex = NitroTex.new()
				tex.parse(d, block)
	return OK


func _fx16(off: int) -> float:
	return d.decode_s16(off) / 4096.0


func _fx32(off: int) -> float:
	return d.decode_s32(off) / 4096.0


func _parse_model(m: int, model_name: String) -> Dictionary:
	var model := {
		"name": model_name,
		"start": m,
		"sbc": m + d.decode_u32(m + 4),
		"pos_scale": _fx32(m + 0x1C),
		"nodes": [],
		"materials": [],
		"meshes": [],
		"droop": {},
		"world": {},   # node name -> bind-pose transform, filled by build_model()
	}
	for e in NitroDict.read(d, m + 0x40):
		model.nodes.append(_parse_node(m + 0x40 + d.decode_u32(e.entry), e.name))

	var mat_block := m + d.decode_u32(m + 8)
	var tex_for := _material_links(mat_block, mat_block + d.decode_u16(mat_block))
	var pal_for := _material_links(mat_block, mat_block + d.decode_u16(mat_block + 2))
	var mats := NitroDict.read(d, mat_block + 4)
	for i in mats.size():
		var p := mat_block + d.decode_u32(mats[i].entry)
		model.materials.append({
			"name": mats[i].name,
			"polygon_attr": d.decode_u32(p + 0x0C),
			"tex_param": d.decode_u32(p + 0x14),
			"texture": tex_for.get(i, ""),
			"palette": pal_for.get(i, ""),
			"width": d.decode_u16(p + 0x20),
			"height": d.decode_u16(p + 0x22),
		})

	var mesh_block := m + d.decode_u32(m + 0x0C)
	for e in NitroDict.read(d, mesh_block):
		var p := mesh_block + d.decode_u32(e.entry)
		model.meshes.append({
			"name": e.name,
			"dl": p + d.decode_u32(p + 8),
			"dl_size": d.decode_u32(p + 12),
		})
	return model


## Maps material index -> texture/palette name.
func _material_links(mat_block: int, dict_off: int) -> Dictionary:
	var out := {}
	for e in NitroDict.read(d, dict_off):
		var list := mat_block + d.decode_u16(e.entry)
		for i in d[e.entry + 2]:
			out[d[list + i]] = e.name
	return out


func _parse_node(p: int, node_name: String) -> Dictionary:
	var flags := d.decode_u16(p)
	var m00 := _fx16(p + 2)
	p += 4
	var origin := Vector3.ZERO
	var basis := Basis.IDENTITY
	var scale := Vector3.ONE
	if not flags & 1:
		origin = Vector3(_fx32(p), _fx32(p + 4), _fx32(p + 8))
		p += 12
	if not flags & 2:
		if flags & 8:
			basis = _pivot_basis(flags, _fx16(p), _fx16(p + 2))
			p += 4
		else:
			var v := [m00]
			for i in 8:
				v.append(_fx16(p + i * 2))
			p += 16
			basis = Basis(
				Vector3(v[0], v[1], v[2]),
				Vector3(v[3], v[4], v[5]),
				Vector3(v[6], v[7], v[8]))
	if not flags & 4:
		scale = Vector3(_fx32(p), _fx32(p + 4), _fx32(p + 8))
	# The DS uses row vectors, so the rows we read are Godot's basis columns.
	return {
		"name": node_name,
		"xform": Transform3D(basis * Basis.from_scale(scale), origin),
	}


static func _pivot_basis(flags: int, a: float, b: float) -> Basis:
	var sel := (flags >> 4) & 0xF
	var row := sel / 3
	var col := sel % 3
	var rows: Array[int] = []
	var cols: Array[int] = []
	for i in 3:
		if i != row:
			rows.append(i)
		if i != col:
			cols.append(i)
	var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	m[row][col] = -1.0 if flags & 0x100 else 1.0
	m[rows[0]][cols[0]] = a
	m[rows[0]][cols[1]] = b
	m[rows[1]][cols[0]] = -b if flags & 0x200 else b
	m[rows[1]][cols[1]] = -a if flags & 0x400 else a
	return Basis(
		Vector3(m[0][0], m[0][1], m[0][2]),
		Vector3(m[1][0], m[1][1], m[1][2]),
		Vector3(m[2][0], m[2][1], m[2][2]))


## Builds the model (bind pose) as a MeshInstance3D.
## `droop` maps node names to an angle in degrees: the limb is swung down by that
## much (a stand-in pose until real animations are decoded).
func build_model(index := 0, droop := {}) -> MeshInstance3D:
	var model: Dictionary = models[index]
	model["droop"] = droop
	var batches := {}   # material id -> {pos, nrm, uv}
	_run_sbc(model, batches)

	var mesh := ArrayMesh.new()
	for mat_id: int in batches:
		var b: Dictionary = batches[mat_id]
		var material: Dictionary = model.materials[mat_id]
		var uvs := _mirrored_uvs(material, b.uv)
		_add_surface(mesh, b, uvs, _make_material(material, uvs, _mirror_flags(material)))
	var inst := MeshInstance3D.new()
	inst.name = model.name
	inst.mesh = mesh
	return inst


## Builds the model with a skeleton: every vertex is attached to the node it was drawn
## with, so the rig can be posed by an animation (see NsbmdRig.apply_pose).
func build_rig(index := 0) -> NsbmdRig:
	var model: Dictionary = models[index]
	model["droop"] = {}
	var batches := {}   # material id -> {pos, nrm, uv, bones}
	_run_sbc(model, batches, 1)
	var bind := skeleton(index, [])

	var mesh := ArrayMesh.new()
	var box := AABB()
	var first := true
	for mat_id: int in batches:
		var b: Dictionary = batches[mat_id]
		var material: Dictionary = model.materials[mat_id]
		var uvs := _mirrored_uvs(material, b.uv)
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var bones_of_vertex: PackedInt32Array = b.bones
		for i in bones_of_vertex.size():
			bones.append_array([bones_of_vertex[i], 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
			var at: Vector3 = (bind[bones_of_vertex[i]] as Transform3D) * (b.pos as PackedVector3Array)[i]
			box = AABB(at, Vector3.ZERO) if first else box.expand(at)
			first = false
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.pos
		arrays[Mesh.ARRAY_NORMAL] = b.nrm
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _make_material(material, uvs, _mirror_flags(material)))
	mesh.custom_aabb = box.grow(box.size.length())
	var rig := NsbmdRig.new()
	rig.source = self
	rig.model_index = index
	rig.bind_bounds = box
	rig.setup(mesh, model.nodes.size())
	return rig


## World transform of every node (by id) for a pose: a list of local transforms from an
## animation, or empty for the model's own bind pose.
func skeleton(index := 0, pose: Array = []) -> Dictionary:
	var model: Dictionary = models[index]
	model["droop"] = {}
	_run_sbc(model, {}, 2, pose)
	return model.world_ids


## (mirror in s, mirror in t): the DS can repeat a texture mirrored; Godot cannot, so a
## mirrored copy is put next to the picture (see _make_material) and the UVs shrink to fit.
static func _mirror_flags(material: Dictionary) -> Vector2i:
	return Vector2i(
		1 if (material.tex_param & 0x10000) != 0 and (material.tex_param & 0x40000) != 0 else 0,
		1 if (material.tex_param & 0x20000) != 0 and (material.tex_param & 0x80000) != 0 else 0)


static func _mirrored_uvs(material: Dictionary, source: PackedVector2Array) -> PackedVector2Array:
	var flags := _mirror_flags(material)
	if flags == Vector2i.ZERO:
		return source
	var uvs := source.duplicate()
	for i in uvs.size():
		if flags.x:
			uvs[i].x *= 0.5
		if flags.y:
			uvs[i].y *= 0.5
	return uvs


static func _add_surface(mesh: ArrayMesh, batch: Dictionary, uvs: PackedVector2Array, material: Material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = batch.pos
	arrays[Mesh.ARRAY_NORMAL] = batch.nrm
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _make_material(m: Dictionary, uvs: PackedVector2Array, mirror := Vector2i.ZERO) -> StandardMaterial3D:
	var mirror_s := mirror.x != 0
	var mirror_t := mirror.y != 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Wrapping only matters if UVs leave the texture; otherwise clamp so linear
	# filtering cannot pull in texels from the opposite edge.
	var tiles := false
	for uv in uvs:
		if uv.x < -0.001 or uv.x > 1.001 or uv.y < -0.001 or uv.y > 1.001:
			tiles = true
			break
	mat.texture_repeat = tiles and (m.tex_param & 0x30000) != 0
	var attr: int = m.polygon_attr
	match attr & 0xC0:
		POLY_FRONT:
			mat.cull_mode = BaseMaterial3D.CULL_BACK
		POLY_BACK:
			mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex and tex.has_texture(m.texture):
		var img := _sharpen(tex.get_image(m.texture, m.palette))
		if mirror_s or mirror_t:
			img = _with_mirror(img, mirror_s, mirror_t)
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	return mat


## The picture followed by its mirror image (sideways and/or downwards), so that
## ordinary repeating gives the DS's mirrored repeat.
static func _with_mirror(img: Image, mirror_s: bool, mirror_t: bool) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w * (2 if mirror_s else 1), h * (2 if mirror_t else 1), false, img.get_format())
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var flipped_x := img.duplicate() as Image
	flipped_x.flip_x()
	var flipped_y := img.duplicate() as Image
	flipped_y.flip_y()
	var flipped_xy := flipped_x.duplicate() as Image
	flipped_xy.flip_y()
	if mirror_s:
		out.blit_rect(flipped_x, Rect2i(0, 0, w, h), Vector2i(w, 0))
	if mirror_t:
		out.blit_rect(flipped_y, Rect2i(0, 0, w, h), Vector2i(0, h))
	if mirror_s and mirror_t:
		out.blit_rect(flipped_xy, Rect2i(0, 0, w, h), Vector2i(w, h))
	return out


# --- render commands (SBC): walk the skeleton, then draw meshes -------------

## `mode`: 0 = meshes in world space (bind pose or drooped), 1 = meshes in the space of
## the node that owns them (for a rig), 2 = skeleton only. `pose` replaces the nodes'
## own transforms with the local transforms of an animation.
func _run_sbc(model: Dictionary, batches: Dictionary, mode := 0, pose: Array = []) -> void:
	var nodes: Array = model.nodes
	var stack: Array[Transform3D] = []
	stack.resize(32)
	stack.fill(Transform3D.IDENTITY)
	var flat: Array[Transform3D] = stack.duplicate()   # identity matrices, for rig meshes
	var slot_node := PackedInt32Array()               # which node each stack slot belongs to
	slot_node.resize(32)
	var current_node := 0
	var current := Transform3D.IDENTITY
	var material := 0
	model["world_ids"] = {}
	var p: int = model.sbc
	while p < d.size():
		var op := d[p]
		p += 1
		match op & 0x1F:
			0x00:
				pass
			0x01:
				return
			0x02:   # NODE: id, visibility
				p += 2
			0x03:   # MTX: load stack slot
				current = stack[d[p]]
				current_node = slot_node[d[p]]
				p += 1
			0x04:   # MAT
				material = d[p]
				p += 1
			0x05:   # SHP
				if mode == 1:
					_draw_mesh(model, model.meshes[d[p]], material, Transform3D.IDENTITY, flat, batches, true, current_node, slot_node)
				elif mode == 0:
					_draw_mesh(model, model.meshes[d[p]], material, current, stack, batches)
				p += 1
			0x06:   # NODEDESC: id, parent, flags, [store], [restore]
				var id := d[p]
				p += 3
				var store := -1
				var restore := -1
				if op & 0x20:
					store = d[p]
					p += 1
				if op & 0x40:
					restore = d[p]
					p += 1
				if restore >= 0:
					current = stack[restore]
				var local: Transform3D = nodes[id].xform
				if id < pose.size() and pose[id] != null:
					local = pose[id]
				current = current * local
				var swing: float = model.droop.get(nodes[id].name, 0.0)
				if swing != 0.0:
					var side := signf(current.basis.x.x)
					current.basis = Basis(Vector3.BACK, deg_to_rad(-swing) * side) * current.basis
				model.world[nodes[id].name] = current
				model.world_ids[id] = current
				current_node = id
				if store >= 0:
					stack[store] = current
					slot_node[store] = id
			0x07, 0x08:   # billboards
				pass
			0x09:   # NODEMIX: dest, count, count * (src, inv, weight)
				var count := d[p + 1]
				p += 2 + count * 3
			0x0B:   # POSSCALE: handled when vertices are read
				pass
			0x0C, 0x0D:   # ENVMAP / PRJMAP
				p += 2
			0x0A:   # CALLDL
				p += 12
			_:
				push_warning("Unknown SBC opcode 0x%02X at 0x%X" % [op, p - 1])
				return


# --- GX display list interpreter -------------------------------------------

func _draw_mesh(model: Dictionary, mesh: Dictionary, mat_id: int, start: Transform3D,
		stack: Array[Transform3D], batches: Dictionary, rig := false, start_node := 0,
		slot_node := PackedInt32Array()) -> void:
	var node := start_node
	var out := _batch(batches, mat_id, node, rig)
	var material: Dictionary = model.materials[mat_id]
	var tex_w := float(material.width)
	var tex_h := float(material.height)
	if tex and tex.has_texture(material.texture):
		tex_w = tex.textures[material.texture].w
		tex_h = tex.textures[material.texture].h
	var scale: float = model.pos_scale

	var current := start
	var vtx := Vector3.ZERO
	var nrm := Vector3.UP
	var st := Vector2.ZERO
	var prim := 0
	var buf: Array = []   # vertices of the current primitive: [pos, nrm, uv]
	var count := 0

	var p: int = mesh.dl
	var end: int = p + mesh.dl_size
	while p < end:
		var cmds := [d[p], d[p + 1], d[p + 2], d[p + 3]]
		p += 4
		for cmd: int in cmds:
			var emit := false
			match cmd:
				0x00, 0x41, 0x11, 0x15:
					pass
				0x14:
					current = stack[d.decode_u32(p) & 31]
					if rig:
						node = slot_node[d.decode_u32(p) & 31]
					p += 4
				0x10, 0x12, 0x13, 0x20, 0x29, 0x2A, 0x2B, 0x30, 0x31, 0x32, 0x33:
					p += 4
				0x1B, 0x1C:
					p += 12
				0x21:
					var v := d.decode_u32(p)
					nrm = Vector3(_s10(v & 0x3FF), _s10((v >> 10) & 0x3FF), _s10((v >> 20) & 0x3FF)) / 512.0
					p += 4
				0x22:
					st = Vector2(d.decode_s16(p), d.decode_s16(p + 2)) / 16.0
					p += 4
				0x23:
					vtx = Vector3(_fx16(p), _fx16(p + 2), _fx16(p + 4)) * scale
					p += 8
					emit = true
				0x24:
					var v := d.decode_u32(p)
					vtx = Vector3(_s10(v & 0x3FF), _s10((v >> 10) & 0x3FF), _s10((v >> 20) & 0x3FF)) / 64.0 * scale
					p += 4
					emit = true
				0x25:
					vtx = Vector3(_fx16(p), _fx16(p + 2), vtx.z / scale) * scale
					p += 4
					emit = true
				0x26:
					vtx = Vector3(_fx16(p), vtx.y / scale, _fx16(p + 2)) * scale
					p += 4
					emit = true
				0x27:
					vtx = Vector3(vtx.x / scale, _fx16(p), _fx16(p + 2)) * scale
					p += 4
					emit = true
				0x28:
					var v := d.decode_u32(p)
					vtx += Vector3(_s10(v & 0x3FF), _s10((v >> 10) & 0x3FF), _s10((v >> 20) & 0x3FF)) / 4096.0 * scale
					p += 4
					emit = true
				0x40:
					prim = d.decode_u32(p) & 3
					p += 4
					buf.clear()
					count = 0
				_:
					push_warning("Unknown GX command 0x%02X at 0x%X" % [cmd, p])
					return
			if emit:
				buf.append([current * vtx, (current.basis * nrm).normalized(),
					Vector2(st.x / tex_w, st.y / tex_h), node])
				count += 1
				_assemble(prim, buf, count, out)


## The vertex batch of a material (and, for a rig, of the node that owns the vertices).
static func _batch(batches: Dictionary, mat_id: int, node: int, rig: bool) -> Dictionary:
	if not batches.has(mat_id):
		batches[mat_id] = {
			"pos": PackedVector3Array(),
			"nrm": PackedVector3Array(),
			"uv": PackedVector2Array(),
			"bones": PackedInt32Array(),   # node of every vertex
		}
	return batches[mat_id]


static func _s10(v: int) -> int:
	return v - 1024 if v >= 512 else v


## Turns the vertices gathered so far into triangles, as the DS hardware would.
## `count` is the number of vertices since BEGIN_VTXS.
static func _assemble(prim: int, buf: Array, count: int, out: Dictionary) -> void:
	var n := buf.size()
	match prim:
		0:
			if n == 3:
				_tri(out, buf[0], buf[1], buf[2])
				buf.clear()
		1:
			if n == 4:
				_tri(out, buf[0], buf[1], buf[2])
				_tri(out, buf[0], buf[2], buf[3])
				buf.clear()
		2:
			if count >= 3:
				if count % 2 == 1:
					_tri(out, buf[n - 3], buf[n - 2], buf[n - 1])
				else:
					_tri(out, buf[n - 2], buf[n - 3], buf[n - 1])
		3:
			if count >= 4 and count % 2 == 0:
				_tri(out, buf[n - 4], buf[n - 3], buf[n - 1])
				_tri(out, buf[n - 4], buf[n - 1], buf[n - 2])


## The DS treats counter-clockwise triangles as front-facing, Godot clockwise,
## so the winding is flipped here.
static func _tri(out: Dictionary, a: Array, b: Array, c: Array) -> void:
	for v: Array in [a, c, b]:
		out.pos.append(v[0])
		out.nrm.append(v[1])
		out.uv.append(v[2])
		out.bones.append(v[3])


## Enlarges a texture by a whole factor with nearest-neighbour, so the GPU's
## smoothing only blends a thin sliver at each texel edge ("sharp bilinear").
## Plain bilinear on these tiny textures blurs them and bleeds neighbouring
## regions of the atlas into each other (the DS never smooths texels).
static func _sharpen(src: Image) -> Image:
	var factor := clampi(1024 / maxi(src.get_width(), src.get_height()), 1, 8)
	var img := src.duplicate() as Image
	if rotsprite_tolerance >= 0 and factor > 1:
		var passes := int(log(factor) / log(2.0))
		img = _smooth_cached(src, passes)
	elif factor > 1:
		img.resize(img.get_width() * factor, img.get_height() * factor, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return img


## RotSprite upscaling is slow-ish, so results are kept in user://cache/.
static func _smooth_cached(src: Image, passes: int) -> Image:
	var path := "user://cache/rot_%d_%dx%d_%d_%d.png" % [
		hash(src.get_data()), src.get_width(), src.get_height(), passes, rotsprite_tolerance]
	if FileAccess.file_exists(path):
		var cached := Image.load_from_file(path)
		if cached:
			return cached
	var out := RotSprite.upscale(src, passes, rotsprite_tolerance)
	DirAccess.make_dir_recursive_absolute("user://cache")
	out.save_png(path)
	return out
