class_name Settings
extends RefCounted
## Player options, saved to user://settings.cfg.

const PATH := "user://settings.cfg"
const MSAA_LEVELS := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]

static var fullscreen := false
static var msaa := 2   # index into MSAA_LEVELS
static var master_volume := 1.0


static func load_and_apply(viewport: Viewport) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		msaa = clampi(cfg.get_value("video", "msaa", msaa), 0, MSAA_LEVELS.size() - 1)
		master_volume = cfg.get_value("audio", "master", master_volume)
	apply(viewport)


static func apply(viewport: Viewport) -> void:
	var window := viewport.get_window()
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	viewport.msaa_3d = MSAA_LEVELS[msaa]
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "msaa", msaa)
	cfg.set_value("audio", "master", master_volume)
	cfg.save(PATH)
