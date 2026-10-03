extends Control
## The menu: owns the background and the logo, and swaps screens in and out.
## Dev options: --screen=<title|main|file|character|options|controls>, --shot=<png>, --slot=N.

const SCREENS := {
	"title": preload("res://scripts/menu/screens/title_screen.gd"),
	"main": preload("res://scripts/menu/screens/main_screen.gd"),
	"file": preload("res://scripts/menu/screens/file_screen.gd"),
	"character": preload("res://scripts/menu/screens/character_screen.gd"),
	"name": preload("res://scripts/menu/screens/name_screen.gd"),
	"options": preload("res://scripts/menu/screens/options_screen.gd"),
	"controls": preload("res://scripts/menu/screens/controls_screen.gd"),
}

## Circle that closes on the pressed button and opens on the next screen, like the
## level transitions of the game.
const IRIS_SHADER := """
shader_type canvas_item;
uniform float radius = 2.4;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec2 rect_size = vec2(1152.0, 648.0);
void fragment() {
	vec2 p = (UV - center) * rect_size / rect_size.y;
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(radius, radius + 0.004, length(p)));
}
"""
const IRIS_OPEN := 2.4

var mode := "title"
var current_slot := 0   # save slot chosen on the file screen (1-3)
var pending_character := ""   # hero chosen for a new game, waiting for a name
var device := "keyboard"   # "keyboard" or "pad": decides which button names are shown

var _screen: MenuScreen
var _busy := false
var _bg: MenuBackground
var _logo: TextureRect
var _logo_aspect := 1.78
var _sparkles: Sparkles
var _screens: Control
var _help: HelpBar
var _iris: ColorRect
var _iris_material: ShaderMaterial
var _toast: Label
var _toast_tween: Tween
var _time := 0.0
var _logo_drop := 0.0          # vertical offset of the logo while it falls in
var dev_world := 0              # dev: --world=N shows that world's scenery at once
var _go_after_shot_wait := ""   # dev: change screen before the screenshot to catch the iris


func _ready() -> void:
	Settings.load_and_apply(get_viewport())
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()
	var first := "title"
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			first = arg.trim_prefix("--screen=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--slot="):
			current_slot = int(arg.trim_prefix("--slot="))
		elif arg == "--pad":
			device = "pad"
		elif arg.begins_with("--pending="):
			pending_character = arg.trim_prefix("--pending=")
		elif arg.begins_with("--world="):
			dev_world = int(arg.trim_prefix("--world="))
		elif arg.begins_with("--go="):
			_go_after_shot_wait = arg.trim_prefix("--go=")
	_show(first)
	if dev_world > 0:
		set_world(dev_world)
		_bg.finish_fade()
	GameAudio.play_music("BGM_SELECT")
	if shot == "":
		_open_iris_at_start()
	if shot != "":
		_take_shot(shot)


func _build() -> void:
	_bg = MenuBackground.new()
	add_child(_bg)

	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/logo.png"):
		var tex: Texture2D = load("res://assets/logo.png")
		_logo.texture = tex
		_logo_aspect = tex.get_width() / float(tex.get_height())
	add_child(_logo)

	_sparkles = Sparkles.new()
	_sparkles.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_sparkles)

	_screens = Control.new()
	_screens.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_screens.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_screens)

	_help = HelpBar.new()
	_help.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_help.offset_top = -52
	_help.offset_bottom = -12
	add_child(_help)

	_toast = MenuStyle.label("", 26)
	_toast.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_toast.offset_top -= 110
	_toast.offset_bottom -= 110
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.modulate.a = 0.0
	_toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_toast)

	var shader := Shader.new()
	shader.code = IRIS_SHADER
	_iris_material = ShaderMaterial.new()
	_iris_material.shader = shader
	_iris_material.set_shader_parameter("radius", IRIS_OPEN)
	_iris = ColorRect.new()
	_iris.material = _iris_material
	_iris.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_iris.mouse_filter = MOUSE_FILTER_IGNORE
	_iris.visible = false
	add_child(_iris)


func _input(event: InputEvent) -> void:
	var new_device := device
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.6):
		new_device = "pad"
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		new_device = "keyboard"
	if new_device != device:
		device = new_device
		_refresh_help()


## Switches to another screen: the iris closes on the focused button, the screen changes,
## the iris opens again.
func go(screen_name: String, iris_center := Vector2(-1, -1)) -> void:
	if _busy:
		return
	_busy = true
	var center := iris_center if iris_center.x >= 0.0 else _focus_center()
	_iris_material.set_shader_parameter("rect_size", size)
	_iris_material.set_shader_parameter("center", center)
	_iris.visible = true
	var close := create_tween()
	close.tween_method(_set_iris, IRIS_OPEN, 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await close.finished
	_show(screen_name)
	await get_tree().process_frame
	_iris_material.set_shader_parameter("center", iris_center if iris_center.x >= 0.0 else _focus_center())
	var open := create_tween()
	open.tween_method(_set_iris, 0.0, IRIS_OPEN, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await open.finished
	_iris.visible = false
	_busy = false


## True while the screen is changing (the iris closing or opening): a request to change
## screen is ignored then.
func is_busy() -> bool:
	return _busy


func _set_iris(radius: float) -> void:
	_iris_material.set_shader_parameter("radius", radius)


## Centre of the focused button in 0..1 screen coordinates (the screen centre if none).
func _focus_center() -> Vector2:
	var focus := get_viewport().gui_get_focus_owner()
	if focus and size.x > 0.0 and size.y > 0.0:
		var rect := focus.get_global_rect()
		return ((rect.position + rect.size * 0.5) / size).clamp(Vector2.ZERO, Vector2.ONE)
	return Vector2(0.5, 0.5)


func _show(screen_name: String) -> void:
	var first_screen := _screen == null
	if _screen:
		_screen.queue_free()
	_screen = SCREENS[screen_name].new()
	_screen.root = self
	mode = _screen.mode
	_screens.add_child(_screen)
	if not first_screen:
		GameAudio.play_sound("SAR_VS_COMMON_MENU", "SE_SYS_WINDOW_OPEN")
	if screen_name in ["title", "main", "options", "controls"]:
		set_world(last_world())
	_refresh_help()


## The scenery of a world (1-8) behind the menu.
func set_world(world: int) -> void:
	_bg.set_world(world)


## World reached in the file used last (1 when there is none).
func last_world() -> int:
	var data := SaveData.load_slot(Settings.last_slot)
	return int(data.world) if not data.is_empty() else 1


func _refresh_help() -> void:
	if _screen:
		_help.set_items(device, _screen.help_items())


func toast(text: String, seconds := 1.8) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	_time += delta
	var s := size
	var k := 1.0 - exp(-delta * 9.0)

	var logo_w := 230.0
	var logo_pos := Vector2(18, 10)
	match mode:
		"title":
			logo_w = minf(s.x * 0.5, 660.0)
			logo_pos = Vector2((s.x - logo_w) / 2.0, s.y * 0.04)
		"main":
			logo_w = minf(s.x * 0.40, 520.0)
			logo_pos = Vector2(s.x * 0.05, s.y * 0.10)
	logo_pos.y += sin(_time * 1.3) * 4.0 if mode == "title" else 0.0
	logo_pos.y += _logo_drop
	# The scenery slides: castle on the right for the title, on the left when the menu
	# (which sits on the right) is open.
	_bg.target_free_offset = MenuBackground.FREE_OFFSET if mode == "title" else MenuBackground.FREE_OFFSET_MENU
	var logo_size := Vector2(logo_w, logo_w / _logo_aspect)
	_logo.position = _logo.position.lerp(logo_pos, k)
	_logo.size = _logo.size.lerp(logo_size, k)
	_sparkles.area = Rect2(_logo.position, _logo.size)
	if _iris.visible:
		_iris_material.set_shader_parameter("rect_size", s)


func _take_shot(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	if _go_after_shot_wait != "":
		go(_go_after_shot_wait)
		await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## The logo falls from above the window and bounces into place.
func logo_drop() -> void:
	_logo_drop = -(_logo.size.y + size.y * 0.2)
	_logo.position.y += _logo_drop
	var tween := create_tween()
	tween.tween_property(self, "_logo_drop", 0.0, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func burst_sparkles(count: int) -> void:
	_sparkles.burst(count)


## At launch the screen opens from a point like the start of a level.
func _open_iris_at_start() -> void:
	_busy = true
	_iris_material.set_shader_parameter("rect_size", size)
	_iris_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	_set_iris(0.0)
	_iris.visible = true
	var open := create_tween()
	open.tween_method(_set_iris, 0.0, IRIS_OPEN, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await open.finished
	_iris.visible = false
	_busy = false


## Rebuilds the help line (a screen calls this when what its buttons do changes).
func refresh_help() -> void:
	_refresh_help()
