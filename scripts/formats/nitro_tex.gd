class_name NitroTex
extends RefCounted
## Decodes the TEX0 block of NSBMD / NSBTX files into Godot images.

var d := PackedByteArray()
var textures := {}   # name -> {offset, format, w, h, color0}
var palettes := {}   # name -> byte offset into d
var _tex_data := 0
var _comp_data := 0
var _comp_info := 0
var _cache := {}


func parse(data: PackedByteArray, block: int) -> void:
	d = data
	_tex_data = block + d.decode_u32(block + 0x14)
	_comp_data = block + d.decode_u32(block + 0x24)
	_comp_info = block + d.decode_u32(block + 0x28)
	var pal_data := block + d.decode_u32(block + 0x38)
	for e in NitroDict.read(d, block + d.decode_u16(block + 0x0E)):
		var p: int = e.entry
		var param := d.decode_u16(p + 2)
		textures[e.name] = {
			"offset": d.decode_u16(p) << 3,
			"format": (param >> 10) & 7,
			"w": 8 << ((param >> 4) & 7),
			"h": 8 << ((param >> 7) & 7),
			"color0": (param >> 13) & 1,
		}
	for e in NitroDict.read(d, block + d.decode_u32(block + 0x34)):
		palettes[e.name] = pal_data + (d.decode_u16(e.entry) << 3)


func has_texture(tex_name: String) -> bool:
	return textures.has(tex_name)


func get_image(tex_name: String, pal_name: String) -> Image:
	var key := tex_name + "|" + pal_name
	if _cache.has(key):
		return _cache[key]
	var img := _decode(textures[tex_name], palettes.get(pal_name, -1))
	_cache[key] = img
	return img


static func _bgr555(c: int, alpha := 255) -> int:
	var r := (c & 31) * 255 / 31
	var g := ((c >> 5) & 31) * 255 / 31
	var b := ((c >> 10) & 31) * 255 / 31
	return r | (g << 8) | (b << 16) | (alpha << 24)


func _palette(off: int, count: int) -> PackedInt32Array:
	var pal := PackedInt32Array()
	pal.resize(count)
	if off < 0:
		for i in count:
			var v := i * 255 / maxi(count - 1, 1)
			pal[i] = v | (v << 8) | (v << 16) | (255 << 24)
		return pal
	for i in count:
		if off + i * 2 + 2 <= d.size():
			pal[i] = _bgr555(d.decode_u16(off + i * 2))
	return pal


func _decode(t: Dictionary, pal_off: int) -> Image:
	var w: int = t.w
	var h: int = t.h
	var fmt: int = t.format
	var o: int = t.offset
	var pix := PackedInt32Array()
	pix.resize(w * h)
	var c0_clear: bool = t.color0 == 1
	match fmt:
		1, 6:
			var pal := _palette(pal_off, 32 if fmt == 1 else 8)
			for i in w * h:
				var b := d[_tex_data + o + i]
				var idx := b & (31 if fmt == 1 else 7)
				var a := ((b >> 5) * 255 / 7) if fmt == 1 else ((b >> 3) * 255 / 31)
				pix[i] = (pal[idx] & 0xFFFFFF) | (a << 24)
		2, 3, 4:
			var bpp: int = [0, 0, 2, 4, 8][fmt]
			var pal := _palette(pal_off, 1 << bpp)
			for i in w * h:
				var bit := i * bpp
				var byte := d[_tex_data + o + (bit >> 3)]
				var idx := (byte >> (bit & 7)) & ((1 << bpp) - 1)
				var c := pal[idx]
				if idx == 0 and c0_clear:
					c &= 0xFFFFFF
				pix[i] = c
		5:
			_decode_compressed(pix, w, h, o, pal_off)
		7:
			for i in w * h:
				var c := d.decode_u16(_tex_data + o + i * 2)
				pix[i] = _bgr555(c, 255 if c & 0x8000 else 0)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pix.to_byte_array())


func _decode_compressed(pix: PackedInt32Array, w: int, h: int, o: int, pal_off: int) -> void:
	var bw := w / 4
	var pal_base := pal_off if pal_off >= 0 else 0
	for by in h / 4:
		for bx in bw:
			var block := by * bw + bx
			var texels := d.decode_u32(_comp_data + o + block * 4)
			var info := d.decode_u16(_comp_info + (o >> 1) + block * 2)
			var mode := info >> 14
			var base := pal_base + (info & 0x3FFF) * 4
			var c0 := d.decode_u16(base)
			var c1 := d.decode_u16(base + 2)
			var cols := PackedInt32Array([_bgr555(c0), _bgr555(c1), 0, 0])
			match mode:
				0:
					cols[2] = _bgr555(d.decode_u16(base + 4))
					cols[3] = 0
				1:
					cols[2] = _mix(c0, c1, 1, 1, 2)
					cols[3] = 0
				2:
					cols[2] = _bgr555(d.decode_u16(base + 4))
					cols[3] = _bgr555(d.decode_u16(base + 6))
				3:
					cols[2] = _mix(c0, c1, 5, 3, 8)
					cols[3] = _mix(c0, c1, 3, 5, 8)
			for i in 16:
				var idx := (texels >> (i * 2)) & 3
				pix[(by * 4 + (i >> 2)) * w + bx * 4 + (i & 3)] = cols[idx]


static func _mix(c0: int, c1: int, k0: int, k1: int, div: int) -> int:
	var r := ((c0 & 31) * k0 + (c1 & 31) * k1) / div
	var g := (((c0 >> 5) & 31) * k0 + ((c1 >> 5) & 31) * k1) / div
	var b := (((c0 >> 10) & 31) * k0 + ((c1 >> 10) & 31) * k1) / div
	return _bgr555(r | (g << 5) | (b << 10))
