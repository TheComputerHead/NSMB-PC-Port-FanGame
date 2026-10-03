class_name NitroBlz
extends RefCounted
## Decompressor for "backward LZ" (BLZ), used by the DS for the ARM9 program and overlays.
## The data is read from its end towards its start.


static func decompress(src: PackedByteArray) -> PackedByteArray:
	var size := src.size()
	if size < 8:
		return src
	var inc_len := src.decode_u32(size - 4)
	if inc_len == 0:
		return src
	var header_len := src[size - 5]
	var enc_len := src.decode_u32(size - 8) & 0xFFFFFF
	var plain_len := size - enc_len                 # leading part that is not compressed
	var raw_len := size + inc_len
	var out := PackedByteArray()
	out.resize(raw_len)
	for i in plain_len:
		out[i] = src[i]

	var pak := size - header_len
	var raw := raw_len
	var pak_end := plain_len
	while raw > 0 and pak > pak_end:
		pak -= 1
		var flags := src[pak]
		for bit in 8:
			if raw <= 0 or pak <= pak_end:
				break
			if flags & 0x80 == 0:
				pak -= 1
				raw -= 1
				out[raw] = src[pak]
			else:
				pak -= 1
				var pos := src[pak] << 8
				pak -= 1
				pos |= src[pak]
				var length := (pos >> 12) + 3
				pos = (pos & 0xFFF) + 3
				for k in length:
					raw -= 1
					out[raw] = out[raw + pos] if raw + pos < raw_len else 0
			flags <<= 1
	return out
