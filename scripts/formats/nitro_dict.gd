class_name NitroDict
extends RefCounted
## Reads the "name dictionary" structure used all over Nitro (NSBMD/NSBTX...) files.


## Returns [{name: String, entry: int}, ...] where `entry` is the absolute
## offset of the entry's data.
static func read(d: PackedByteArray, off: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := d[off + 1]
	var p := off + 8 + (count + 1) * 4
	var entry_size := d.decode_u16(p)
	p += 4
	var names := p + count * entry_size
	for i in count:
		var raw := d.slice(names + i * 16, names + i * 16 + 16)
		out.append({
			"name": raw.get_string_from_ascii(),
			"entry": p + i * entry_size,
		})
	return out
