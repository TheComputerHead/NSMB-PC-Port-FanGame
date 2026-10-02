extends SceneTree
# Usage: godot --headless --script tools/dump.gd -- <file> [out]
const NitroLz := preload("res://scripts/formats/nitro_lz.gd")
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var d := FileAccess.get_file_as_bytes(args[0])
	if NitroLz.is_compressed(d):
		d = NitroLz.decompress(d)
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_buffer(d)
	f = null
	print("size ", d.size(), " magic ", d.slice(0, 4).get_string_from_ascii())
	quit()
