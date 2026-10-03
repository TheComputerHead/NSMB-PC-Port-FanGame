class_name CharacterView
extends SubViewportContainer
## A Mario or Luigi model from the ROM shown on top of the 2D menu,
## rendered in its own transparent 3D viewport.

const FILES := {
	"mario": ["player/mario_model_LZ.bin", "player/mario_head_cap_LZ.bin"],
	"luigi": ["player/luigi_model_LZ.bin", "player/luigi_head_cap_LZ.bin"],
}

## Stand-in pose until animations exist: arms swung down.
const ARMS_DOWN := {"arm_l1": 72.0, "arm_r1": 72.0, "arm_l2": 10.0, "arm_r2": 10.0}

var character := "mario"
var base_yaw := 0.0     # radians
var sway := 0.35        # how far it turns back and forth, radians
var head_only := false  # show only the head (for icons)
const ANIMATION_FPS := 60.0   # one animation frame per frame of the DS (60 Hz)
const CALM_JOINTS := [8, 15]     # torso ("spin") and head: the parts that twist in the waiting animation
const CALM_AMOUNT := 0.3         # how much of their movement is kept
const BLEND_TIME := 0.25         # seconds to melt from one animation into the next

var _pivot := Node3D.new()
var _time := 0.0
var _rig: NsbmdRig
var _head_mesh: MeshInstance3D
var _pack: NitroAnim
var _animation := ""
var _frame := 0.0
var _loop := true
var _finished := false
var _calm := false
var _last_pose: Array[Transform3D] = []   # what was shown last, to melt into a new animation
var _blend := 1.0
var _loop_gap: Array[Dictionary] = []   # per joint: what separates the end of the animation from its start


func _init(which := "mario", yaw_degrees := 0.0, only_head := false) -> void:
	character = which
	base_yaw = deg_to_rad(yaw_degrees)
	head_only = only_head


func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_time = randf() * TAU

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = get_viewport().msaa_3d
	vp.handle_input_locally = false
	add_child(vp)

	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0, 7.5)
	vp.add_child(cam)
	vp.add_child(_pivot)

	reload()


## Rebuilds the model (e.g. after the texture smoothing option changed).
func reload() -> void:
	for child in _pivot.get_children():
		child.queue_free()
	_rig = null
	_head_mesh = null
	if head_only:
		var model := build_head(character)
		if model:
			_pivot.add_child(model)
	else:
		_build_animated()
		play("wait")


## Plays one of the character's own animations: "wait", "walk", "run" (packed with the
## character) or "jump", "jumped", "turn" (shared). `loop` false stops on the last frame.
func play(animation: String, loop := true) -> void:
	if _rig == null:
		return
	# "<name>_calm": the same animation with the twisting of the torso and head softened.
	_calm = animation.ends_with("_calm")
	animation = animation.trim_suffix("_calm")
	var pack := _pack_for(animation)
	if pack == null:
		return
	_animation = pack[1]
	_pack = pack[0]
	_frame = randf() * pack[0].frame_count(pack[1]) if loop else 0.0   # two heroes never move in step
	_loop = loop
	_finished = false
	_blend = 0.0 if not _last_pose.is_empty() else 1.0
	_measure_loop_gap()


## True once a non-looping animation has reached its last frame.
func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	_time += delta
	_pivot.rotation.y = base_yaw + sin(_time * 0.9) * sway
	_pivot.position.y = sin(_time * 1.6) * 0.05 if _rig == null else 0.0
	if _rig and _pack:
		var frames := float(_pack.frame_count(_animation))
		_frame += delta * ANIMATION_FPS
		if _frame >= frames:
			if _loop:
				_frame = fmod(_frame, frames)
			else:
				_frame = frames - 1.0
				_finished = true
		var pose := _pack.pose(_animation, _frame)
		if _loop:
			_close_loop(pose, _frame / frames)
		if _calm:
			var rest := _pack.pose(_animation, 0.0)
			for joint in CALM_JOINTS:
				var q0 := rest[joint].basis.get_rotation_quaternion()
				var q1 := pose[joint].basis.get_rotation_quaternion()
				pose[joint] = Transform3D(Basis(q0.slerp(q1, CALM_AMOUNT)), pose[joint].origin)
		if _blend < 1.0:
			_blend = minf(_blend + delta / BLEND_TIME, 1.0)
			pose = _mix(_last_pose, pose, _blend)
		_last_pose = pose
		_rig.apply_pose(pose)
		if _head_mesh:
			_head_mesh.transform = _rig.node_transform("face_1")


## Makes a looping animation meet itself without changing its speed or its length: the
## gap between its last pose and its first is spread evenly over the whole cycle, so that
## at the end the pose is exactly the one the next cycle starts with. `progress` is 0 at
## the start of the cycle and 1 at its end.
func _close_loop(pose: Array[Transform3D], progress: float) -> void:
	for i in pose.size():
		var gap: Dictionary = _loop_gap[i]
		var rotation := Quaternion.IDENTITY.slerp(gap.rotation, progress) * pose[i].basis.get_rotation_quaternion()
		pose[i] = Transform3D(
			Basis(rotation) * Basis.from_scale(pose[i].basis.get_scale()),
			pose[i].origin + (gap.origin as Vector3) * progress)


## Measures, for every joint, the gap between the last pose of the animation and its first.
func _measure_loop_gap() -> void:
	var start := _pack.pose(_animation, 0.0)
	var end := _pack.pose(_animation, float(_pack.frame_count(_animation)))
	_loop_gap.clear()
	for i in start.size():
		_loop_gap.append({
			"rotation": start[i].basis.get_rotation_quaternion() * end[i].basis.get_rotation_quaternion().inverse(),
			"origin": start[i].origin - end[i].origin,
		})


## Poses `a` and `b` mixed: weight 0 is all `a`, 1 all `b`.
static func _mix(a: Array[Transform3D], b: Array[Transform3D], weight: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in b.size():
		var from: Transform3D = a[i]
		var to: Transform3D = b[i]
		out.append(Transform3D(
			Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), weight)) \
				* Basis.from_scale(from.basis.get_scale().lerp(to.basis.get_scale(), weight)),
			from.origin.lerp(to.origin, weight)))
	return out


func _build_animated() -> void:
	var body := _load(FILES[character][0])
	if body == null:
		return
	_rig = body.build_rig(0)
	_rig.apply_pose([])
	var box := _rig.bounds()
	var holder := Node3D.new()
	var inner := Node3D.new()
	holder.add_child(inner)
	inner.add_child(_rig)
	var head := _load(FILES[character][1])
	if head:
		_head_mesh = head.build_model(0)
		_head_mesh.transform = _rig.node_transform("face_1")
		inner.add_child(_head_mesh)
		box = box.merge(_head_mesh.transform * _head_mesh.get_aabb())
	# Centre on the standing body (the bind pose has its arms spread, so only its height
	# is used) and scale to a fixed height.
	inner.position = -Vector3(box.get_center().x, box.get_center().y, box.get_center().z)
	holder.scale = Vector3.ONE * (3.3 / box.size.y)
	_pivot.add_child(holder)


## [NitroAnim, name in the pack] for an animation, loading the pack on first use.
func _pack_for(animation: String) -> Array:
	var own := "pl_%s_LZ.bin" % character
	var named := animation
	if character == "luigi" and animation in ["wait", "walk", "run"]:
		named = "L_" + animation
	for file in [own, "pl_LZ.bin", "pl_map_LZ.bin", "pl_ttl_LZ.bin"]:
		var pack := _load_pack(file)
		if pack and pack.has_animation(named):
			return [pack, named]
	return []


static var _packs := {}


static func _load_pack(file: String) -> NitroAnim:
	if not _packs.has(file):
		var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + "player/" + file)
		if NitroLz.is_compressed(bytes):
			bytes = NitroLz.decompress(bytes)
		var pack := NitroAnim.new()
		_packs[file] = pack if pack.parse(bytes) == OK else null
	return _packs[file]


static func _load(rel: String) -> Nsbmd:
	var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + rel)
	if NitroLz.is_compressed(bytes):
		bytes = NitroLz.decompress(bytes)
	var parsed := Nsbmd.new()
	if parsed.parse(bytes) != OK or parsed.models.is_empty():
		return null
	return parsed


## Body and head assembled, centred on the origin and scaled to a fixed size.
static func build(which: String) -> Node3D:
	var files: Array = FILES[which]
	var body := _load(files[0])
	if body == null:
		return null
	var root := Node3D.new()
	var body_mesh := body.build_model(0, ARMS_DOWN)
	root.add_child(body_mesh)
	var box := body_mesh.get_aabb()
	var head := _load(files[1])
	if head:
		var head_mesh := head.build_model(0)
		head_mesh.transform = body.models[0].world.get("face_1", Transform3D.IDENTITY)
		root.add_child(head_mesh)
		box = box.merge(head_mesh.transform * head_mesh.get_aabb())
	for child in root.get_children():
		child.position -= box.get_center()
	var holder := Node3D.new()
	holder.add_child(root)
	holder.scale = Vector3.ONE * (3.3 / maxf(box.size.x, box.size.y))
	return holder


## Just the head, turned to face the camera, centred and scaled to fill the view.
static func build_head(which: String) -> Node3D:
	var files: Array = FILES[which]
	var body := _load(files[0])
	var head := _load(files[1])
	if body == null or head == null:
		return null
	body.build_model(0, ARMS_DOWN)   # runs the skeleton so that the head's orientation is known
	var head_mesh := head.build_model(0)
	var facing: Transform3D = body.models[0].world.get("face_1", Transform3D.IDENTITY)
	head_mesh.transform = Transform3D(facing.basis, Vector3.ZERO)
	var box: AABB = head_mesh.transform * head_mesh.get_aabb()
	head_mesh.position -= box.get_center()
	var holder := Node3D.new()
	holder.add_child(head_mesh)
	holder.scale = Vector3.ONE * (3.0 / maxf(box.size.x, box.size.y))
	return holder
