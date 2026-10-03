class_name PipeStyle
extends RefCounted
## The main menu's buttons, as in the original: horizontal warp pipes that stick out of the
## right edge of the screen, with a flared lip on the left. The selected pipe is bright,
## the others are dark. Colours come from the ROM's menu palette.

# body, light edge, dark edge
const COLORS := {
	"green": {
		"bright": [Color("42ce00"), Color("c5de9c"), Color("5a8421")],
		"dim": [Color("197b31"), Color("3ab54a"), Color("005a21")],
	},
	"blue": {
		"bright": [Color("4a84ff"), Color("6bcef7"), Color("004a84")],
		"dim": [Color("315aad"), Color("4a8ca5"), Color("003152")],
	},
}
const OUTLINE := Color("0b1a10")
const TEXT_DIM := Color("9c9c9c")
const BAR_YELLOW := Color("f8c000")
const BAR_EDGE := Color("b88800")

const W := 40          # skin size in game pixels
const H := 22
const CAP := 6         # width of the flared lip
const PIXEL := 4       # screen pixels per game pixel

static var _skins := {}


static func skin(theme: String, bright: bool) -> StyleBoxTexture:
	var smooth := Settings.texture_smoothing
	var key := "%s_%s_%s" % [theme, bright, smooth]
	if _skins.has(key):
		return _skins[key]
	var set: Array = COLORS[theme]["bright" if bright else "dim"]
	var body: Color = set[0]
	var light: Color = set[1]
	var dark: Color = set[2]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var c := Color(0, 0, 0, 0)
			if x < CAP:
				c = _cap_pixel(x, y, body, light, dark)
			elif y >= 2 and y <= H - 3:
				c = _body_pixel(y, body, light, dark)
			img.set_pixel(x, y, c)
	if smooth:
		img = RotSprite.upscale(img, 2, Settings.SMOOTHING_TOLERANCE)
	else:
		img.resize(W * PIXEL, H * PIXEL, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	box.texture_margin_left = CAP * PIXEL
	box.texture_margin_right = 3 * PIXEL
	box.texture_margin_top = 3 * PIXEL
	box.texture_margin_bottom = 3 * PIXEL
	box.content_margin_left = CAP * PIXEL + 16
	box.content_margin_right = 24
	_skins[key] = box
	return box


static func _cap_pixel(x: int, y: int, body: Color, light: Color, dark: Color) -> Color:
	if (x == 0 and (y == 0 or y == H - 1)):
		return Color(0, 0, 0, 0)   # cut corners
	if y == 0 or y == H - 1 or x == 0 or x == CAP - 1:
		return OUTLINE
	if x == 1:
		return light
	if x >= CAP - 3:
		return dark
	if y == 1 or y == H - 2:
		return dark
	return body


static func _body_pixel(y: int, body: Color, light: Color, dark: Color) -> Color:
	if y == 2 or y == H - 3:
		return OUTLINE
	var t := y - 3
	if t <= 1:
		return light
	if t >= 13:
		return dark
	if t >= 9:
		return body.lerp(dark, 0.4)
	return body


## A pipe-shaped menu button.
static func button(text: String, theme := "green", size := 30, min_size := Vector2(460, 74)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", MenuStyle.font())
	b.add_theme_font_size_override("font_size", MenuStyle.fsize(size))
	b.add_theme_constant_override("outline_size", MenuStyle.outline(size))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_color_override("font_color", TEXT_DIM)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, MenuStyle.YELLOW)
	b.add_theme_stylebox_override("normal", skin(theme, false))
	b.add_theme_stylebox_override("hover", skin(theme, true))
	b.add_theme_stylebox_override("focus", skin(theme, true))
	b.add_theme_stylebox_override("pressed", skin(theme, true))
	b.add_theme_stylebox_override("disabled", skin(theme, false))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if Settings.texture_smoothing else CanvasItem.TEXTURE_FILTER_NEAREST
	b.focus_entered.connect(func() -> void: GameAudio.ui_cursor())
	b.pressed.connect(func() -> void: GameAudio.ui_decide())
	b.mouse_entered.connect(func() -> void: if not b.disabled: b.grab_focus())
	return b


## The yellow title bar above the pipes.
static func header(text: String, size := 28, min_size := Vector2(460, 56)) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BAR_YELLOW
	style.border_color = BAR_EDGE
	style.border_width_bottom = 4
	style.content_margin_left = 48
	style.content_margin_right = 24
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = min_size
	var label := MenuStyle.label(text, size, Color.WHITE)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(label)
	return panel
