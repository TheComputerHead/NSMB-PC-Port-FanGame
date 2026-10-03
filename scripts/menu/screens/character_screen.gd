extends MenuScreen
## "Choose your hero": the touch-screen panel of the other menus, with Mario and Luigi
## in two cards. The one being chosen walks in place in front of turning rays of light
## and says his line; the other waits, a little dimmer. Confirming makes him jump with his
## shout, then the screen closes on him.

const CHARACTERS := [
	{
		"id": "mario", "name": "Mario", "theme": "red", "yaw": 12.0,
		"tint": Color("d8423c"), "glow": Color(1.0, 0.82, 0.55),
		"hover": ["SAR_MARIO_BASE", "SE_VOC_MA_HOH"],
		"confirm": ["SAR_VS_COMMON_MARIO_BASE", "SE_VOC_MA_JUMP_03"],
	},
	{
		"id": "luigi", "name": "Luigi", "theme": "green", "yaw": -12.0,
		"tint": Color("2f9c4a"), "glow": Color(0.75, 1.0, 0.7),
		"hover": ["SAR_LUIGI_BASE", "SE_VOC_LU_HOH"],
		"confirm": ["SAR_VS_COMMON_LUIGI_BASE", "SE_VOC_LU_JUMP_03"],
	},
]
const PANEL_SIZE := Vector2(940, 575)
const CARD_SIZE := Vector2(400, 470)
const BAR_HEIGHT := 60.0


## Light rays turning slowly behind the chosen hero.
class Rays extends Control:
	var color := Color.WHITE
	var strength := 0.0   # 0..1, how visible they are
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle += delta * 0.25
		queue_redraw()

	func _draw() -> void:
		if strength <= 0.01:
			return
		var center := Vector2(size.x * 0.5, size.y * 0.55)
		var reach := size.length()
		var count := 9
		for i in count:
			var a0 := _angle + TAU * i / count
			var a1 := a0 + TAU / count * 0.45
			var points := PackedVector2Array([center, center + Vector2.from_angle(a0) * reach, center + Vector2.from_angle(a1) * reach])
			draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.32 * strength))


var _panel: QuiltPanel
var _cards: Array[Panel] = []
var _rays: Array[Rays] = []
var _views: Array[CharacterView] = []
var _shadows: Array[TextureRect] = []
var _badges: Array[TextureRect] = []
var _plates: Array[Button] = []
var _selected := -1
var _locked := false


func back_target() -> String:
	return "file"


func help_items() -> Array:
	return [
		{"kind": "left_right", "text": "Choose"},
		{"kind": "accept", "text": "Confirm"},
		{"kind": "back", "text": "Back"},
	]


func _unhandled_input(event: InputEvent) -> void:
	if _locked:
		get_viewport().set_input_as_handled()
		return
	super(event)


func _ready() -> void:
	super()
	_panel = QuiltPanel.new()
	_panel.bar_height = BAR_HEIGHT
	add_child(_panel)
	_panel.set_title("Choose your hero!")
	for i in CHARACTERS.size():
		_build_card(i)
	resized.connect(_layout)
	_layout()
	_plates[0].grab_focus.call_deferred()
	_select.call_deferred(0)


func _build_card(i: int) -> void:
	var info: Dictionary = CHARACTERS[i]
	var card := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = (info.tint as Color).darkened(0.45)
	style.set_corner_radius_all(18)
	style.set_border_width_all(4)
	style.border_color = (info.tint as Color).lightened(0.2)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(card)

	var rays := Rays.new()
	rays.color = info.glow
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var window := Control.new()   # clips the rays to the card, while the hero may jump out of it
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(rays)
	card.add_child(window)

	var shadow := TextureRect.new()
	shadow.texture = _shadow_texture()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shadow)

	var view := CharacterView.new(info.id, info.yaw)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.resized.connect(func() -> void: view.pivot_offset = view.size / 2.0)
	card.add_child(view)

	var badge := TextureRect.new()
	badge.texture = HudIcons.texture(info.id)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(badge)

	var plate := MenuStyle.button(info.name, 34, Vector2(280, 60), info.theme)
	plate.focus_entered.connect(_select.bind(i))
	plate.pressed.connect(_confirm.bind(i))
	_panel.add_child(plate)

	_cards.append(card)
	_rays.append(rays)
	_views.append(view)
	_shadows.append(shadow)
	_badges.append(badge)
	_plates.append(plate)


func _layout() -> void:
	var scale := minf(1.0, minf(size.x * 0.92 / PANEL_SIZE.x, size.y * 0.8 / PANEL_SIZE.y))
	var panel_size := PANEL_SIZE * scale
	_panel.size = panel_size
	_panel.position = Vector2((size.x - panel_size.x) * 0.5, size.y * 0.5 - panel_size.y * 0.5 + 10.0)
	_panel.bar_height = BAR_HEIGHT * scale
	_panel.queue_redraw()
	var card_size := CARD_SIZE * scale
	var gap := (panel_size.x - card_size.x * 2.0) / 3.0
	for i in _cards.size():
		var origin := Vector2(gap + i * (card_size.x + gap), BAR_HEIGHT * scale + 16.0 * scale)
		_cards[i].position = origin
		_cards[i].size = card_size
		_views[i].position = Vector2(card_size.x * 0.05, card_size.y * 0.02)
		_views[i].size = Vector2(card_size.x * 0.9, card_size.y * 0.78)
		_shadows[i].position = Vector2(card_size.x * 0.2, card_size.y * 0.74)
		_shadows[i].size = Vector2(card_size.x * 0.6, card_size.y * 0.1)
		_badges[i].position = Vector2(12, 10) * scale
		_badges[i].size = Vector2(52, 52) * scale
		var plate_size := Vector2(280, 60) * scale
		_plates[i].size = plate_size
		_plates[i].position = origin + Vector2((card_size.x - plate_size.x) * 0.5, card_size.y - plate_size.y - 14.0 * scale)


## The hero steps forward under rays of light and walks in place; the other waits.
## Changing hero plays his voice.
func _select(index: int) -> void:
	if index == _selected:
		return
	if _selected != -1:
		var voice: Array = CHARACTERS[index].hover
		GameAudio.play_sound(voice[0], voice[1])
	_selected = index
	for i in _views.size():
		var chosen := i == index
		var view := _views[i]
		view.sway = 0.25 if chosen else 0.08
		var tween := create_tween().set_parallel(true)
		tween.tween_property(view, "scale", Vector2.ONE * (1.08 if chosen else 0.94), 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "modulate", Color.WHITE if chosen else Color(0.62, 0.62, 0.7), 0.25)
		tween.tween_property(_rays[i], "strength", 1.0 if chosen else 0.0, 0.3)
		tween.tween_property(_cards[i], "modulate", Color.WHITE if chosen else Color(0.75, 0.75, 0.8), 0.25)
		tween.tween_property(_shadows[i], "modulate:a", 0.9 if chosen else 0.5, 0.25)


## He shouts and jumps, then the screen closes on him and the name is asked next.
func _confirm(index: int) -> void:
	if _locked or root.is_busy():
		return
	_locked = true
	var info: Dictionary = CHARACTERS[index]
	var voice: Array = info.confirm
	GameAudio.play_sound(voice[0], voice[1])
	var view := _views[index]
	view.play("jump", false)
	var rest := view.position.y
	var jump := create_tween()
	jump.tween_property(view, "position:y", rest - 90.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(view, "position:y", rest, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.9).timeout
	root.pending_character = info.id
	var centre := (view.global_position + view.size / 2.0) / root.size
	root.go("name", centre)


## A soft dark ellipse for the hero's shadow.
static func _shadow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.55))
	gradient.set_color(1, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture
