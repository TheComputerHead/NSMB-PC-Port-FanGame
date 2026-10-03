class_name Narc
extends RefCounted
## Reader for NARC archives (Nitro file archives, .narc).

var data := PackedByteArray()
var files: Array[Vector2i] = []        # (start, end) of every file, in archive order
var names: Dictionary = {}             # file index -> path, when the archive has a name table


func open(bytes: PackedByteArray) -> Error:
	data = bytes
	if data.size() < 0x10 or data.slice(0, 4).get_string_from_ascii() != "NARC":
		return ERR_FILE_UNRECOGNIZED
	var p := data.decode_u16(0x0C)   # header size
	var fat := -1
	var fnt := -1
	var img := -1
	for i in data.decode_u16(0x0E):
		var tag := data.slice(p, p + 4).get_string_from_ascii()
		match tag:
			"BTAF": fat = p
			"BTNF": fnt = p
			"GMIF": img = p
		p += data.decode_u32(p + 4)
	if fat < 0 or img < 0:
		return ERR_FILE_CORRUPT
	var base := img + 8
	for i in data.decode_u16(fat + 8):
		var e := fat + 12 + i * 8
		files.append(Vector2i(base + data.decode_u32(e), base + data.decode_u32(e + 4)))
	if fnt >= 0:
		_read_names(fnt + 8, "", 0xF000)
	return OK


func get_file(index: int) -> PackedByteArray:
	var r := files[index]
	return data.slice(r.x, r.y)


func file_name(index: int) -> String:
	return names.get(index, "file_%03d" % index)


func _read_names(table: int, prefix: String, dir_id: int) -> void:
	var entry := table + (dir_id & 0xFFF) * 8
	var pos := table + data.decode_u32(entry)
	var file_id := data.decode_u16(entry + 4)
	while pos < data.size():
		var info := data[pos]
		pos += 1
		if info == 0:
			break
		var length := info & 0x7F
		var entry_name: String = data.slice(pos, pos + length).get_string_from_ascii()
		pos += length
		if info & 0x80:
			var sub := data.decode_u16(pos)
			pos += 2
			_read_names(table, prefix + entry_name + "/", sub)
		else:
			names[file_id] = prefix + entry_name
			file_id += 1
