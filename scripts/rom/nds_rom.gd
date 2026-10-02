class_name NdsRom
extends RefCounted
## Reads a Nintendo DS ROM image and its NitroFS file system.

var data := PackedByteArray()
var title := ""
var game_code := ""
var maker_code := ""
var version := 0

## Maps "path/inside/rom" -> Vector2i(start, end) offsets in `data`.
var files: Dictionary = {}


func open(path: String) -> Error:
	data = FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return FileAccess.get_open_error()
	if data.size() < 0x200:
		return ERR_FILE_CORRUPT

	title = data.slice(0x00, 0x0C).get_string_from_ascii().strip_edges()
	game_code = data.slice(0x0C, 0x10).get_string_from_ascii()
	maker_code = data.slice(0x10, 0x12).get_string_from_ascii()
	version = data[0x1E]

	var fnt_off := data.decode_u32(0x40)
	var fnt_size := data.decode_u32(0x44)
	var fat_off := data.decode_u32(0x48)
	var fat_size := data.decode_u32(0x4C)
	if fnt_off + fnt_size > data.size() or fat_off + fat_size > data.size():
		return ERR_FILE_CORRUPT

	files.clear()
	_read_dir(fnt_off, fat_off, 0xF000, "")
	return OK


func has_file(path: String) -> bool:
	return files.has(path)


func read_file(path: String) -> PackedByteArray:
	if not files.has(path):
		return PackedByteArray()
	var range: Vector2i = files[path]
	return data.slice(range.x, range.y)


func _read_dir(fnt_off: int, fat_off: int, dir_id: int, prefix: String) -> void:
	var entry := fnt_off + (dir_id & 0xFFF) * 8
	var pos := fnt_off + data.decode_u32(entry)
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
			var sub_id := data.decode_u16(pos)
			pos += 2
			_read_dir(fnt_off, fat_off, sub_id, prefix + entry_name + "/")
		else:
			var start := data.decode_u32(fat_off + file_id * 8)
			var end := data.decode_u32(fat_off + file_id * 8 + 4)
			if end >= start and end <= data.size():
				files[prefix + entry_name] = Vector2i(start, end)
			file_id += 1
