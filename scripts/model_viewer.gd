extends Node3D
## Dev tool: shows a model from the extracted ROM assets.
## Usage: godot --path . res://scenes/model_viewer.tscn -- --model=player/mario_model_LZ.bin [--shot=out.png]

var _pivot := Node3D.new()


func _ready() -> void:
	var rel := "player/mario_model_LZ.bin"
	var shot := ""
	var yaw := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			rel = arg.trim_prefix("--model=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--yaw="):
			yaw = deg_to_rad(float(arg.trim_prefix("--yaw=")))

	var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + rel)
	if NitroLz.is_compressed(bytes):
		bytes = NitroLz.decompress(bytes)
	var parsed := Nsbmd.new()
	var err := parsed.parse(bytes)
	if err != OK or parsed.models.is_empty():
		push_error("Cannot read model %s (%s)" % [rel, error_string(err)])
		get_tree().quit(1)
		return
	var model := parsed.build_model(0)
	add_child(_pivot)
	_pivot.add_child(model)

	var box := model.get_aabb()
	print("model ", parsed.models[0].name, " aabb ", box, " nodes ", parsed.models[0].nodes.size())
	_pivot.position = -box.get_center()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 0, box.size.length() * 1.3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.55, 0.85)
	add_child(env)

	if shot != "":
		_pivot.rotation.y = yaw
		set_process(false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _process(delta: float) -> void:
	_pivot.rotate_y(delta * 0.8)
