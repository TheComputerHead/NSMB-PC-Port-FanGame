class_name RomExtractor
extends RefCounted
## Copies every file of the ROM's NitroFS into a folder, as raw data.
## Later steps convert these raw files into PNG / OGG / meshes.

const RAW_DIR := "user://assets/raw/"
const CODE_DIR := "user://assets/code/"


static func extract_all(rom: NdsRom, progress: Callable = Callable()) -> Error:
	var paths: Array = rom.files.keys()
	paths.sort()
	var done := 0
	for path: String in paths:
		var target := RAW_DIR + path
		var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if err != OK:
			return err
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(rom.read_file(path))
		file.close()
		done += 1
		if progress.is_valid():
			progress.call(done, paths.size())

	# The main program holds the game's fonts; keep it (decompressed) next to the files.
	DirAccess.make_dir_recursive_absolute(CODE_DIR)
	var arm9 := FileAccess.open(CODE_DIR + "arm9.bin", FileAccess.WRITE)
	if arm9:
		arm9.store_buffer(NitroBlz.decompress(rom.arm9()))
		arm9.close()

	var marker := FileAccess.open("user://assets/extracted.txt", FileAccess.WRITE)
	marker.store_string(rom.game_code)
	return OK


static func is_extracted() -> bool:
	return FileAccess.file_exists("user://assets/extracted.txt")
