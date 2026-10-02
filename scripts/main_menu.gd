extends Control
## Title screen: Play / Options / Quit, with Mario turning on the right.

const BODY := "player/mario_model_LZ.bin"
const HEAD := "player/mario_head_cap_LZ.bin"

@onready var main_box: VBoxContainer = %MainBox
@onready var options_box: VBoxContainer = %OptionsBox
@onready var mario_root: Node3D = %MarioRoot
@onready var status: Label = %Status
@onready var title: Label = %Title
@onready var logo: TextureRect = %Logo


func _ready() -> void:
	Settings.load_and_apply(get_viewport())
	_load_logo()
	_build_mario()
	%PlayButton.pressed.connect(_on_play)
	%OptionsButton.pressed.connect(_show_options.bind(true))
	%QuitButton.pressed.connect(get_tree().quit)
	%BackButton.pressed.connect(_show_options.bind(false))

	%Fullscreen.button_pressed = Settings.fullscreen
	%Fullscreen.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply(get_viewport()))
	%Msaa.selected = Settings.msaa
	%Msaa.item_selected.connect(func(i: int) -> void:
		Settings.msaa = i
		Settings.apply(get_viewport()))
	%Volume.value = Settings.master_volume
	%Volume.value_changed.connect(func(v: float) -> void:
		Settings.master_volume = v
		Settings.apply(get_viewport()))
	_show_options(false)
	_screenshot_if_asked()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and options_box.visible:
		_show_options(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	mario_root.rotate_y(delta * 0.6)


func _show_options(show: bool) -> void:
	if not show:
		Settings.save()
	options_box.visible = show
	main_box.visible = not show
	(%BackButton if show else %PlayButton).grab_focus()


func _on_play() -> void:
	status.text = "The game itself is not built yet."


func _load_model(rel: String) -> Nsbmd:
	var bytes := FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + rel)
	if NitroLz.is_compressed(bytes):
		bytes = NitroLz.decompress(bytes)
	var parsed := Nsbmd.new()
	if parsed.parse(bytes) != OK or parsed.models.is_empty():
		return null
	return parsed


func _build_mario() -> void:
	var body := _load_model(BODY)
	if body == null:
		status.text = "Assets missing: run the ROM setup again."
		return
	var body_mesh := body.build_model(0)
	mario_root.add_child(body_mesh)
	var head := _load_model(HEAD)
	if head:
		var head_mesh := head.build_model(0)
		head_mesh.transform = body.models[0].world.get("face_1", Transform3D.IDENTITY)
		mario_root.add_child(head_mesh)
	# Centre the model on its own origin so it turns in place.
	var box := body_mesh.get_aabb()
	for child in mario_root.get_children():
		child.position -= box.get_center()
	mario_root.scale = Vector3.ONE * (2.6 / maxf(box.size.x, box.size.y))


func _screenshot_if_asked() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))
			get_tree().quit()


## The logo is an image in assets/; fall back to plain text if it is missing.
func _load_logo() -> void:
	var img := Image.load_from_file("res://assets/logo.png")
	if img == null:
		return
	img.generate_mipmaps()
	logo.texture = ImageTexture.create_from_image(img)
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.visible = true
	title.visible = false
