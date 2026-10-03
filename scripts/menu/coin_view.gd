class_name CoinView
extends SubViewportContainer
## The game's own coin model, spinning, as a small icon.

const FILE := "enemy/coin.nsbmd"

var _pivot := Node3D.new()   # starts turned so that the coin shows its face


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
	_pivot.rotation.y = PI / 2.0

	var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + FILE)
	if NitroLz.is_compressed(bytes):
		bytes = NitroLz.decompress(bytes)
	var parsed := Nsbmd.new()
	if parsed.parse(bytes) != OK or parsed.models.is_empty():
		return
	var mesh := parsed.build_model(0)
	var box := mesh.get_aabb()
	mesh.position -= box.get_center()
	var holder := Node3D.new()
	holder.add_child(mesh)
	holder.scale = Vector3.ONE * (3.2 / maxf(box.size.x, box.size.y))
	_pivot.add_child(holder)


func _process(delta: float) -> void:
	_pivot.rotation.y += delta * 3.0
