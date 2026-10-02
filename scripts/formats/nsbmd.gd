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
func build_model(index := 0) -> MeshInstance3D:
	var model: Dictionary = models[index]
	var batches := {}   # material id -> {pos, nrm, uv}
	_run_sbc(model, batches)

	var mesh := ArrayMesh.new()
	for mat_id: int in batches:
		var b: Dictionary = batches[mat_id]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.pos
		arrays[Mesh.ARRAY_NORMAL] = b.nrm
		arrays[Mesh.ARRAY_TEX_UV] = b.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _make_material(model.materials[mat_id], b.uv))
	var inst := MeshInstance3D.new()
	inst.name = model.name
	inst.mesh = mesh
	return inst


func _make_material(m: Dictionary, uvs: PackedVector2Array) -> StandardMaterial3D:
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
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	return mat


# --- render commands (SBC): walk the skeleton, then draw meshes -------------

func _run_sbc(model: Dictionary, batches: Dictionary) -> void:
	var nodes: Array = model.nodes
	var stack: Array[Transform3D] = []
	stack.resize(32)
	stack.fill(Transform3D.IDENTITY)
	var current := Transform3D.IDENTITY
	var material := 0
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
				p += 1
			0x04:   # MAT
				material = d[p]
				p += 1
			0x05:   # SHP
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
				current = current * (nodes[id].xform as Transform3D)
				model.world[nodes[id].name] = current
				if store >= 0:
					stack[store] = current
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
		stack: Array[Transform3D], batches: Dictionary) -> void:
	if not batches.has(mat_id):
		batches[mat_id] = {
			"pos": PackedVector3Array(),
			"nrm": PackedVector3Array(),
			"uv": PackedVector2Array(),
		}
	var out: Dictionary = batches[mat_id]
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
					Vector2(st.x / tex_w, st.y / tex_h)])
				count += 1
				_assemble(prim, buf, count, out)


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


## Enlarges a texture by a whole factor with nearest-neighbour, so the GPU's
## smoothing only blends a thin sliver at each texel edge ("sharp bilinear").
## Plain bilinear on these tiny textures blurs them and bleeds neighbouring
## regions of the atlas into each other (the DS never smooths texels).
static func _sharpen(src: Image) -> Image:
	var factor := clampi(1024 / maxi(src.get_width(), src.get_height()), 1, 8)
	var img := src.duplicate() as Image
	if rotsprite_tolerance >= 0 and factor > 1:
		var passes := int(log(factor) / log(2.0))
		img = RotSprite.upscale(src, passes, rotsprite_tolerance)
	elif factor > 1:
		img.resize(img.get_width() * factor, img.get_height() * factor, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return img
