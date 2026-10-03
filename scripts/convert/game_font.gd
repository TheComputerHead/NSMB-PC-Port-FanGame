class_name GameFont
extends RefCounted
## The game's own font, taken from the ROM: the large DS system font (11x15 pixels,
## Latin with accents, kana, button symbols). Every glyph is enlarged with RotSprite and
## saved as a bitmap font (BMFont text format + PNG atlas) that Godot loads like any other
## font. Text colour tints the white part only.
##
## Two versions: the default has a black outline and slightly thicker strokes (menu text);
## the "plain" one keeps the original thin strokes without any outline (like the white
## "Select a file." of the original).

const DIR := "user://assets/ui/"
const PASSES := 2          # enlargement: 2^2 = 4x
const OUTLINE := 2         # outline thickness in enlarged pixels
const FATTEN := 1          # the strokes are 1px thin in the original: thicken them a little
const GUTTER := 2          # empty pixels between glyphs in the atlas (avoids smoothing bleed)
const COLUMNS := 24

static var _fonts := {}


## The font, or null if the ROM's font could not be built.
static func get_font(plain := false) -> Font:
	if not _fonts.has(plain) and ensure(plain):
		var f := FontFile.new()
		if f.load_bitmap_font(_path(plain, "fnt")) == OK:
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
			_fonts[plain] = f
	return _fonts.get(plain)


static func _path(plain: bool, extension: String) -> String:
	return DIR + ("game_font_plain." if plain else "game_font.") + extension


static func ensure(plain := false) -> bool:
	if FileAccess.file_exists(_path(plain, "fnt")) and FileAccess.file_exists(_path(plain, "png")):
		return true
	return _build(plain)


## Finds the biggest NFTR font among the LZ77-tagged blobs of the ARM9 program.
static func _find_font(arm9: PackedByteArray) -> Nftr:
	var best: Nftr
	for i in range(0, arm9.size() - 16):
		if arm9[i] != 0x4C or arm9[i + 1] != 0x5A or arm9[i + 2] != 0x37 or arm9[i + 3] != 0x37 or arm9[i + 4] != 0x10:
			continue
		var raw := NitroLz.decompress(arm9.slice(i, i + 0x8000))
		if raw.size() < 64 or raw.slice(0, 4).get_string_from_ascii() != "RTFN":
			continue
		var font := Nftr.new()
		if font.parse(raw, 0) == OK and (best == null or font.glyph_count > best.glyph_count):
			best = font
	return best


static func _build(plain: bool) -> bool:
	var arm9 := FileAccess.get_file_as_bytes(RomExtractor.CODE_DIR + "arm9.bin")
	if arm9.is_empty():
		return false
	var font := _find_font(arm9)
	if font == null or font.char_to_glyph.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(DIR)

	var outline := 0 if plain else OUTLINE
	var fatten := 0 if plain else FATTEN
	var scale := 1 << PASSES
	var cell_w := font.cell_w * scale + outline * 2
	var cell_h := font.cell_h * scale + outline * 2
	var chars: Array = font.char_to_glyph.keys()
	chars.sort()
	var rows := (chars.size() + COLUMNS - 1) / COLUMNS
	var stride_x := cell_w + GUTTER
	var stride_y := cell_h + GUTTER
	var atlas := Image.create(COLUMNS * stride_x, rows * stride_y, false, Image.FORMAT_RGBA8)
	var lines := PackedStringArray()
	for n in chars.size():
		var code: int = chars[n]
		var glyph: int = font.char_to_glyph[code]
		var img := _bake(font.glyph_image(glyph), outline, fatten)
		var x := (n % COLUMNS) * stride_x
		var y := (n / COLUMNS) * stride_y
		atlas.blit_rect(img, Rect2i(0, 0, cell_w, cell_h), Vector2i(x, y))
		var metrics: Vector3i = font.widths[glyph] if glyph < font.widths.size() else Vector3i(0, font.cell_w, font.cell_w)
		lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=0 xadvance=%d page=0 chnl=15" % [
			code, x, y, cell_w, cell_h, metrics.x * scale - outline,
			maxi(metrics.z, 1) * scale + outline * 2])
	atlas.save_png(_path(plain, "png"))

	var header := PackedStringArray([
		'info face="NSMB" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0' % (font.cell_h * scale),
		"common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % [
			cell_h, outline + 13 * scale, atlas.get_width(), atlas.get_height()],
		'page id=0 file="%s"' % _path(plain, "png").get_file(),
		"chars count=%d" % chars.size(),
	])
	var file := FileAccess.open(_path(plain, "fnt"), FileAccess.WRITE)
	file.store_string("\n".join(header + lines) + "\n")
	return true


## Enlarged white glyph, optionally on a black outline, in a cell with room for the outline.
static func _bake(src: Image, outline: int, fatten: int) -> Image:
	var big := RotSprite.upscale(src, PASSES, 40)
	var w := big.get_width()
	var h := big.get_height()
	var rect := Rect2i(0, 0, w, h)
	if fatten > 0:
		var thick := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for dy in range(-fatten, fatten + 1):
			for dx in range(-fatten, fatten + 1):
				thick.blend_rect(big, rect, Vector2i(dx, dy))
		big = thick
	if outline <= 0:
		return big
	var shadow := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if big.get_pixel(x, y).a > 0.1:
				shadow.set_pixel(x, y, Color.BLACK)
	var out := Image.create(w + outline * 2, h + outline * 2, false, Image.FORMAT_RGBA8)
	# Stamp the silhouette around a ring (and a smaller one) to thicken it evenly.
	for radius in [outline, outline * 0.5]:
		for step in 16:
			var angle := TAU * step / 16.0
			out.blend_rect(shadow, rect, Vector2i(
				outline + roundi(cos(angle) * radius), outline + roundi(sin(angle) * radius)))
	out.blend_rect(shadow, rect, Vector2i(outline, outline))
	out.blend_rect(big, rect, Vector2i(outline, outline))
	return out
