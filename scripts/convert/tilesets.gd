class_name Tilesets
extends RefCounted
## Loads level tilesets straight from the ROM's NARC archives (no manual extraction).

static var _narcs := {}


## One file of an archive, found by its path inside the archive (e.g. "Dat/Field/J01_1.bin").
static func file(archive: String, path: String) -> PackedByteArray:
	var narc: Narc = _narcs.get(archive)
	if narc == null:
		narc = Narc.new()
		if narc.open(FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + "ARCHIVE/" + archive)) != OK:
			return PackedByteArray()
		_narcs[archive] = narc
	for i in narc.files.size():
		if narc.file_name(i) == path:
			return narc.get_file(i)
	return PackedByteArray()


## The grassland tileset (World 1) together with the common tileset it shares tiles with.
static func grassland() -> NsmbTileset:
	var main_set := NsmbTileset.new()
	main_set.setup(
		file("Dat_Field.narc", "Dat/Field/d_2d_I_M_tikei_nohara_ncg.bin"),
		file("Dat_Field.narc", "Dat/Field/d_2d_I_M_tikei_nohara_ncl.bin"),
		file("Dat_Field.narc", "Dat/Field/d_2d_PA_I_M_nohara.bin"),
		file("Dat_Field.narc", "Dat/Field/I_M_nohara.bin"),
		file("Dat_Field.narc", "Dat/Field/I_M_nohara_hd.bin"))
	main_set.tile_base = 192
	main_set.bank_base = 2
	var common := NsmbTileset.new()
	common.setup(
		file("Dat_Init.narc", "Dat/Init/d_2d_A_J_jyotyu_ncg.bin"),
		file("Dat_2D.narc", "Dat/2D/d_2d_A_J_jyotyu_ncl.bin"),
		file("Dat_Init.narc", "Dat/Init/d_2d_PA_A_J_jyotyu.bin"),
		file("Dat_2D.narc", "Dat/2D/A_J_jyotyu.bin"),
		file("Dat_2D.narc", "Dat/2D/A_J_jyotyu_hd.bin"))
	main_set.companion = common
	common.companion = main_set
	return main_set
