class_name NitroLz
extends RefCounted
## Decompressor for Nintendo DS LZ77 (type 0x10) and LZ77-extended (type 0x11).


static func is_compressed(src: PackedByteArray) -> bool:
	return src.size() > 4 and (src[0] == 0x10 or src[0] == 0x11)


static func decompress(src: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if not is_compressed(src):
		return out
	var kind := src[0]
	var size := src[1] | (src[2] << 8) | (src[3] << 16)
	var pos := 4
	if size == 0:
		size = src.decode_u32(4)
		pos = 8
	out.resize(size)
	var o := 0
	while o < size and pos < src.size():
		var flags := src[pos]
		pos += 1
		for bit in 8:
			if o >= size or pos >= src.size():
				break
			if flags & (0x80 >> bit) == 0:
				out[o] = src[pos]
				o += 1
				pos += 1
				continue
			var b0 := src[pos]
			var b1 := src[pos + 1]
			pos += 2
			var length: int
			var disp: int
			if kind == 0x10:
				length = (b0 >> 4) + 3
				disp = (((b0 & 0xF) << 8) | b1) + 1
			else:
				var indicator := b0 >> 4
				if indicator == 0:
					length = (((b0 & 0xF) << 4) | (b1 >> 4)) + 0x11
					var b2 := src[pos]
					pos += 1
					disp = (((b1 & 0xF) << 8) | b2) + 1
				elif indicator == 1:
					var b2 := src[pos]
					var b3 := src[pos + 1]
					pos += 2
					length = (((b0 & 0xF) << 12) | (b1 << 4) | (b2 >> 4)) + 0x111
					disp = (((b2 & 0xF) << 8) | b3) + 1
				else:
					length = indicator + 1
					disp = (((b0 & 0xF) << 8) | b1) + 1
			for i in length:
				if o >= size:
					break
				out[o] = out[o - disp] if o >= disp else 0
				o += 1
	return out
