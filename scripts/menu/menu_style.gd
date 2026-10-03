class_name MenuStyle
extends RefCounted
## Shared look of the menus, taken from the original game's menu palette: flat coloured
## buttons with a light top edge, a dark bottom edge and a small highlight in the corner,
## and yellow text with a black outline.

const YELLOW := Color("fff700")
const BLACK := Color("000000")
const INK := BLACK

# Colours read from the ROM's menu palette: body, light edge, dark edge.
const THEMES := {
	"green": [Color("42ce00"), Color("c5de9c"), Color("5a8421")],
	"red": [Color("ff0000"), Color("ffc58c"), Color("9c0808")],
	"blue": [Color("4a84ff"), Color("6bcef7"), Color("004a84")],
	"grey": [Color("7b7b7b"), Color("adadad"), Color("4a4a4a")],
}

const SKIN_W := 24      # skin size in "game pixels"
const SKIN_H := 16
const PIXEL := 4        # screen pixels per game pixel
const MARGIN := 6       # game pixels that are not stretched

static var _skins := {}
static var _font: Font
static var _baked := false   # true when the font already contains its black outline


## Chunky rounded font: the best bold system font available.
static func font() -> Font:
	if _font == null:
		_font = GameFont.get_font()
		_baked = _font != null
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Arial Rounded MT Bold", "Segoe UI Black", "Arial Black", "Verdana"])
		f.font_weight = 800
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
	return _font


## 9-patch skin for a button colour theme, drawn pixel by pixel like the original.
static func skin(theme: String, lighten := 0.0) -> StyleBoxTexture:
	var smooth := Settings.texture_smoothing
	var key := "%s_%.2f_%s" % [theme, lighten, smooth]
	if _skins.has(key):
		return _skins[key]
	var colors: Array = THEMES[theme]
	var body: Color = (colors[0] as Color).lerp(Color.WHITE, lighten)
	var light: Color = colors[1]
	var dark: Color = colors[2]
	var img := Image.create(SKIN_W, SKIN_H, false, Image.FORMAT_RGBA8)
	for y in SKIN_H:
		for x in SKIN_W:
			var corner := (x == 0 or x == SKIN_W - 1) and (y == 0 or y == SKIN_H - 1)
			if corner:
				continue
			var c := body
			var edge := x == 0 or y == 0 or x == SKIN_W - 1 or y == SKIN_H - 1
			var near_corner := (x <= 1 or x >= SKIN_W - 2) and (y <= 1 or y >= SKIN_H - 2)
			if edge or (near_corner and ((x == 1 or x == SKIN_W - 2) and (y == 1 or y == SKIN_H - 2))):
				c = BLACK
			elif y <= 2:
				c = light
			elif y >= SKIN_H - 4:
				c = dark
			elif x >= SKIN_W - 2:
				c = dark
			img.set_pixel(x, y, c)
	# highlight in the top-left corner
	for p in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]:
		img.set_pixel(p.x, p.y, light)
	img.set_pixel(5, 6, dark)
	if smooth:
		# Same smoothing as the ROM textures, so the buttons match the background.
		img = RotSprite.upscale(img, 2, Settings.SMOOTHING_TOLERANCE)
	else:
		img.resize(SKIN_W * PIXEL, SKIN_H * PIXEL, Image.INTERPOLATE_NEAREST)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	box.set_texture_margin_all(MARGIN * PIXEL)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.draw_center = true
	_skins[key] = box
	return box


static func style_label(label: Label, size: int, color := YELLOW) -> void:
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", fsize(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", BLACK)
	label.add_theme_constant_override("outline_size", outline(size))


static func label(text: String, size := 28, color := YELLOW) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_label(l, size, color)
	return l


static func button(text: String, size := 30, min_size := Vector2(440, 68), theme := "green") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", fsize(size))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(c, YELLOW)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	b.add_theme_color_override("font_outline_color", BLACK)
	b.add_theme_constant_override("outline_size", outline(size))
	b.add_theme_stylebox_override("normal", skin(theme))
	b.add_theme_stylebox_override("hover", skin(theme, 0.3))
	b.add_theme_stylebox_override("focus", skin(theme, 0.3))
	b.add_theme_stylebox_override("pressed", skin(theme, -0.0))
	b.add_theme_stylebox_override("disabled", skin("grey"))
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if Settings.texture_smoothing else CanvasItem.TEXTURE_FILTER_NEAREST
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.focus_entered.connect(_pop.bind(b, 1.05))
	b.focus_entered.connect(func() -> void: GameAudio.ui_cursor())
	b.pressed.connect(func() -> void:
		if text.begins_with("Back") or text.begins_with("Cancel"):
			GameAudio.ui_back()
		else:
			GameAudio.ui_decide())
	b.pressed.connect(_squash.bind(b))
	b.focus_exited.connect(_pop.bind(b, 1.0))
	b.mouse_entered.connect(func() -> void: if not b.disabled: b.grab_focus())
	return b


static func _pop(b: Control, target: float) -> void:
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE * target, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Text size on screen: the game font has small letters, so it is drawn a bit larger.
static func fsize(size: int) -> int:
	font()
	return roundi(size * 1.35) if _baked else size


## Outline thickness for Godot's own outline (the game font has its own).
static func outline(size: int) -> int:
	font()
	return 0 if _baked else maxi(size / 5, 4)


## A quick squash and rebound when a button is pressed.
static func _squash(b: Control) -> void:
	b.scale = Vector2(1.04, 0.88)
	b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Text in the game's thin font without outline (like the white "Select a file." bar).
static func plain_label(text: String, size := 22, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plain := GameFont.get_font(true)
	if plain:
		l.add_theme_font_override("font", plain)
		l.add_theme_font_size_override("font_size", roundi(size * 1.35))
	else:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
