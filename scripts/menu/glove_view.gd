class_name GloveView
extends SubViewportContainer
## The game's own pointing glove (a 3D model from the ROM), shown beside the highlighted
## file. It points to the right, bobs a little and has a dark outline so that it stands
## out on the pale panel.

const FILE := "enemy/finger.nsbmd"
const YAW := 118.0            # degrees: shows the glove from the side, finger to the right
const TILT := -8.0            # degrees: the fingertip is raised a little
const OUTLINE := 0.07         # how much the dark shell is bigger than the glove

var _pivot := Node3D.new()
var _time := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = get_viewport().msaa_3d
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0, 7.5)
	vp.add_child(cam)
	vp.add_child(_pivot)

	var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + FILE)
	if NitroLz.is_compressed(bytes):
		bytes = NitroLz.decompress(bytes)
	var parsed := Nsbmd.new()
	if parsed.parse(bytes) != OK or parsed.models.is_empty():
		return
	var glove := parsed.build_model(0)
	var box := glove.get_aabb()
	var holder := Node3D.new()
	holder.add_child(glove)
	glove.position = -box.get_center()
	# The dark shell: the same mesh, bigger, drawn from the inside only.
	var shell := parsed.build_model(0)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color("1a1a22")
	black.cull_mode = BaseMaterial3D.CULL_FRONT
	shell.material_override = black
	shell.position = -box.get_center() * (1.0 + OUTLINE)
	shell.scale = Vector3.ONE * (1.0 + OUTLINE)
	holder.add_child(shell)
	holder.scale = Vector3.ONE * (3.4 / maxf(box.size.x, maxf(box.size.y, box.size.z)))
	holder.rotation_degrees = Vector3(0.0, YAW, TILT)
	_pivot.add_child(holder)


func _process(delta: float) -> void:
	_time += delta
	# Bobs toward the file and back.
	_pivot.position.x = sin(_time * 7.0) * 0.16
