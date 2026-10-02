class_name RotSprite
extends RefCounted
## Pixel-art upscaler based on the enlargement step of RotSprite: Scale2x
## applied repeatedly, where two colours that are close enough count as equal.
## That tolerance lets it rebuild smooth diagonals even on textures that are
## shaded or dithered, which plain Scale2x leaves untouched.


## Enlarges `src` by 2^passes. `tolerance` is the colour distance (0-255 per
## channel, RGBA combined) under which two pixels are treated as the same.
static func upscale(src: Image, passes := 3, tolerance := 40) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	for i in passes:
		data = _scale2x(data, w, h, tolerance * tolerance)
		w *= 2
		h *= 2
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _same(a: int, b: int, t2: int) -> bool:
	if a == b:
		return true
	var dr := (a & 255) - (b & 255)
	var dg := ((a >> 8) & 255) - ((b >> 8) & 255)
	var db := ((a >> 16) & 255) - ((b >> 16) & 255)
	var da := ((a >> 24) & 255) - ((b >> 24) & 255)
	return dr * dr + dg * dg + db * db + da * da <= t2


static func _scale2x(src: PackedByteArray, w: int, h: int, t2: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * 16)
	var ow := w * 2
	for y in h:
		var up := maxi(y - 1, 0) * w
		var down := mini(y + 1, h - 1) * w
		var row := y * w
		for x in w:
			var left := maxi(x - 1, 0)
			var right := mini(x + 1, w - 1)
			var p := src.decode_u32((row + x) * 4)
			var a := src.decode_u32((up + x) * 4)
			var d := src.decode_u32((down + x) * 4)
			var c := src.decode_u32((row + left) * 4)
			var b := src.decode_u32((row + right) * 4)
			var p1 := p
			var p2 := p
			var p3 := p
			var p4 := p
			var ca := _same(c, a, t2)
			var ab := _same(a, b, t2)
			var dc := _same(d, c, t2)
			var bd := _same(b, d, t2)
			if ca and not _same(c, d, t2) and not ab:
				p1 = a
			if ab and not ca and not bd:
				p2 = b
			if dc and not bd and not ca:
				p3 = c
			if bd and not ab and not dc:
				p4 = d
			var o := (y * 2 * ow + x * 2) * 4
			out.encode_u32(o, p1)
			out.encode_u32(o + 4, p2)
			out.encode_u32(o + ow * 4, p3)
			out.encode_u32(o + ow * 4 + 4, p4)
	return out
