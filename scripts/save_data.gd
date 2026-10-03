class_name SaveData
extends RefCounted
## The three save slots, stored in user://saves/slot_N.cfg.

const SLOT_COUNT := 3
const WORLD_COUNT := 8
const NAME_MAX := 10

## Level names of each world, in the order they appear on the map.
const LEVELS := ["1", "2", "Tower", "3", "4", "5", "Castle"]


static func _path(slot: int) -> String:
	return "user://saves/slot_%d.cfg" % slot


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))


## Returns the slot's data, or an empty Dictionary if it is unused.
static func load_slot(slot: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_path(slot)) != OK:
		return {}
	var character: String = cfg.get_value("save", "character", "mario")
	return {
		"character": character,
		"name": cfg.get_value("save", "name", character.capitalize()),
		"world": cfg.get_value("save", "world", 1),
		"level": cfg.get_value("save", "level", 0),
		"unlocked_world": cfg.get_value("save", "unlocked_world", 1),
		"lives": cfg.get_value("save", "lives", 4),
		"coins": cfg.get_value("save", "coins", 0),
		"star_coins": cfg.get_value("save", "star_coins", 0),
		"play_time": cfg.get_value("save", "play_time", 0),       # seconds
		"last_played": cfg.get_value("save", "last_played", 0),   # unix time, 0 = never
	}


static func create(slot: int, character: String, player_name := "") -> Dictionary:
	var data := {
		"character": character,
		"name": player_name if player_name != "" else character.capitalize(),
		"world": 1, "level": 0, "unlocked_world": 1,
		"lives": 4, "coins": 0, "star_coins": 0,
		"play_time": 0, "last_played": 0,
	}
	save_slot(slot, data)
	return data


static func save_slot(slot: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var cfg := ConfigFile.new()
	for key: String in data:
		cfg.set_value("save", key, data[key])
	cfg.save(_path(slot))


static func erase(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(_path(slot))


## "World 3-Tower" style label.
static func level_label(world: int, level: int) -> String:
	return "%d-%s" % [world, LEVELS[clampi(level, 0, LEVELS.size() - 1)]]


## 3725 seconds -> "1:02:05".
static func time_label(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


## Unix time -> "2026-10-03", or "Never".
static func date_label(unix: int) -> String:
	if unix <= 0:
		return "Never"
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]
