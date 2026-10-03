class_name Nftr
extends RefCounted
## Reader for Nintendo bitmap fonts (NFTR): glyph bitmaps, widths and the
## character -> glyph map.
##
## NSMB's fonts have unreliable block size fields, so the blocks are located by
## their names (PLGC glyphs, HDWC widths, PAMC character map) instead.

var cell_w := 0
var cell_h := 0
var bpp := 1
var glyph_count := 0
var widths: Array[Vector3i] = []      # per glyph: (left bearing, glyph width, advance)
var char_to_glyph := {}               # unicode code point -> glyph index
var _glyphs := PackedByteArray()
var _cell_size := 0


## `offset` is where the "RTFN" magic starts inside `data`.
func parse(data: PackedByteArray, offset: int) -> Error:
	if data.slice(offset, offset + 4).get_string_from_ascii() != "RTFN":
		return ERR_FILE_UNRECOGNIZED
	var plgc := _find(data, "PLGC", offset)
	var hdwc := _find(data, "HDWC", plgc)
	var pamc := _find(data, "PAMC", hdwc)
	if plgc < 0 or hdwc < 0 or pamc < 0:
		return ERR_FILE_CORRUPT

	cell_w = data[plgc + 8]
	cell_h = data[plgc + 9]
	_cell_size = data.decode_u16(plgc + 10)
	bpp = data[plgc + 14]
	glyph_count = (hdwc - (plgc + 16)) / maxi(_cell_size, 1)
	_glyphs = data.slice(plgc + 16, hdwc)

	# Widths: possibly several HDWC blocks one after another.
	var p := hdwc
	while data.slice(p, p + 4).get_string_from_ascii() == "HDWC":
		var first := data.decode_u16(p + 8)
		var last := data.decode_u16(p + 10)
		if widths.size() < last + 1:
			widths.resize(last + 1)
		for g in range(first, last + 1):
			var q := p + 16 + (g - first) * 3
			widths[g] = Vector3i(data.decode_s8(q), data[q + 1], data[q + 2])
		p += 16 + (last - first + 1) * 3
		p = (p + 3) & ~3   # blocks are word aligned

	_read_maps(data, pamc)
	return OK


static func _find(data: PackedByteArray, tag: String, from: int) -> int:
	if from < 0:
		return -1
	var t := tag.to_ascii_buffer()
	for i in range(from, mini(data.size() - 4, from + 200000)):
		if data[i] == t[0] and data[i + 1] == t[1] and data[i + 2] == t[2] and data[i + 3] == t[3]:
			return i
	return -1


func _read_maps(data: PackedByteArray, start: int) -> void:
	var p := start
	while data.slice(p, p + 4).get_string_from_ascii() == "PAMC":
		var first := data.decode_u16(p + 8)
		var last := data.decode_u16(p + 10)
		var kind := data.decode_u16(p + 12)
		var next := data.decode_u32(p + 16)
		var q := p + 20
		var count := 0
		match kind:
			0:   # consecutive glyphs starting at a given index
				var base := data.decode_u16(q)
				for c in range(first, last + 1):
					char_to_glyph[c] = base + (c - first)
				count = 2
			1:   # one glyph index per character
				for c in range(first, last + 1):
					var g := data.decode_u16(q + (c - first) * 2)
					if g != 0xFFFF:
						char_to_glyph[c] = g
				count = (last - first + 1) * 2
			2:   # explicit pairs
				var pairs := data.decode_u16(q)
				for i in pairs:
					char_to_glyph[data.decode_u16(q + 2 + i * 4)] = data.decode_u16(q + 4 + i * 4)
				count = 2 + pairs * 4
		p = (q + count + 3) & ~3
		if next == 0:
			break


## Width in pixels of the glyph for a character, or the cell width if unknown.
func advance_of(character: int) -> int:
	var g: int = char_to_glyph.get(character, -1)
	if g >= 0 and g < widths.size():
		return widths[g].z
	return cell_w


## Glyph bitmap as an image with alpha (white where the font is "on").
func glyph_image(index: int) -> Image:
	var img := Image.create(cell_w, cell_h, false, Image.FORMAT_RGBA8)
	if index < 0 or index >= glyph_count:
		return img
	var base := index * _cell_size
	var levels := (1 << bpp) - 1
	for y in cell_h:
		for x in cell_w:
			var bit := (y * cell_w + x) * bpp
			var value := (_glyphs[base + (bit >> 3)] >> (8 - bpp - (bit & 7))) & levels
			# This font only ever uses one non-zero level, so any ink counts as fully opaque.
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if value > 0 else 0.0))
	return img
