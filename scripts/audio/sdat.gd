class_name Sdat
extends RefCounted
## Reader for Nintendo DS sound archives (.sdat): sequences (music and sound effects
## written like MIDI), instrument banks, and the wave archives holding the samples.

const KINDS := ["seq", "seqarc", "bank", "wavearc", "player", "group", "strmplayer", "strm"]

var data := PackedByteArray()
var names := {}       # kind -> Array of names (index = id)
var sub_names := {}   # sequence archive id -> Array of names of the sequences inside
var infos := {}       # kind -> Array of Dictionary records
var _files: Array[Vector2i] = []   # (offset, size) per file id


func open(bytes: PackedByteArray) -> Error:
	data = bytes
	if data.size() < 0x40 or data.slice(0, 4).get_string_from_ascii() != "SDAT":
		return ERR_FILE_UNRECOGNIZED
	var symb := data.decode_u32(0x10)
	var info := data.decode_u32(0x18)
	var fat := data.decode_u32(0x20)
	_read_names(symb)
	_read_info(info)
	var count := data.decode_u32(fat + 8)
	for i in count:
		var e := fat + 12 + i * 16
		_files.append(Vector2i(data.decode_u32(e), data.decode_u32(e + 4)))
	return OK


func file_count() -> int:
	return _files.size()


func file(id: int) -> PackedByteArray:
	if id < 0 or id >= _files.size():
		return PackedByteArray()
	var f := _files[id]
	return data.slice(f.x, f.x + f.y)


## Name of an entry, or "kind#id" when the archive has no symbol for it.
func name_of(kind: String, id: int) -> String:
	var list: Array = names.get(kind, [])
	if id >= 0 and id < list.size() and list[id] != "":
		return list[id]
	return "%s#%d" % [kind, id]


## Finds an entry id by name, or -1.
func find(kind: String, entry_name: String) -> int:
	var list: Array = names.get(kind, [])
	return list.find(entry_name)


## The sequences of a sequence archive: [{name, offset, bank, volume, player}, ...].
## `offset` is where the sequence's events start inside the archive file.
func archive_entries(archive_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := file(infos["seqarc"][archive_id].file)
	if f.size() < 0x20 or f.slice(0, 4).get_string_from_ascii() != "SSAR":
		return out
	var data_offset := f.decode_u32(0x18)
	var subs: Array = sub_names.get(archive_id, [])
	for i in f.decode_u32(0x1C):
		var e := 0x20 + i * 12
		out.append({
			"name": subs[i] if i < subs.size() else "seq%d" % i,
			"offset": data_offset + f.decode_u32(e),
			"bank": f.decode_u16(e + 4),
			"volume": f[e + 6],
			"player": f[e + 9],
		})
	return out


func _read_names(symb: int) -> void:
	for k in KINDS.size():
		var list_off := data.decode_u32(symb + 8 + k * 4)
		var out: Array = []
		if list_off != 0:
			var p := symb + list_off
			var count := data.decode_u32(p)
			if KINDS[k] == "seqarc":
				# Each entry: name offset, then a list of names of the sequences inside.
				for i in count:
					var name_off := data.decode_u32(p + 4 + i * 8)
					var sub_off := data.decode_u32(p + 8 + i * 8)
					out.append(_cstring(symb + name_off) if name_off != 0 else "")
					var subs: Array = []
					if sub_off != 0:
						var sp := symb + sub_off
						for j in data.decode_u32(sp):
							var n := data.decode_u32(sp + 4 + j * 4)
							subs.append(_cstring(symb + n) if n != 0 else "")
					sub_names[i] = subs
			else:
				for i in count:
					var name_off := data.decode_u32(p + 4 + i * 4)
					out.append(_cstring(symb + name_off) if name_off != 0 else "")
		names[KINDS[k]] = out


func _read_info(info: int) -> void:
	for k in KINDS.size():
		var list_off := data.decode_u32(info + 8 + k * 4)
		var out: Array = []
		if list_off != 0:
			var p := info + list_off
			for i in data.decode_u32(p):
				var rec_off := data.decode_u32(p + 4 + i * 4)
				out.append(_record(KINDS[k], info + rec_off) if rec_off != 0 else {})
		infos[KINDS[k]] = out


func _record(kind: String, p: int) -> Dictionary:
	match kind:
		"seq":
			return {
				"file": data.decode_u32(p), "bank": data.decode_u16(p + 4),
				"volume": data[p + 6], "player": data[p + 9],
			}
		"bank":
			return {
				"file": data.decode_u32(p),
				"wave_archives": [data.decode_u16(p + 4), data.decode_u16(p + 6),
					data.decode_u16(p + 8), data.decode_u16(p + 10)],
			}
		_:
			return {"file": data.decode_u32(p)}


func _cstring(p: int) -> String:
	var end := p
	while end < data.size() and data[end] != 0:
		end += 1
	return data.slice(p, end).get_string_from_ascii()
