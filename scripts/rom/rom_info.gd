class_name RomInfo
extends RefCounted
## Identifies which release of New Super Mario Bros. a ROM is.

const KNOWN := {
	"A2DE": "USA",
	"A2DP": "Europe",
	"A2DJ": "Japan",
	"A2DK": "Korea",
}


## Returns the region name, or "" if the ROM is not New Super Mario Bros.
static func region_of(rom: NdsRom) -> String:
	return KNOWN.get(rom.game_code, "")
