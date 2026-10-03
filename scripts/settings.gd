class_name Settings
extends RefCounted
## Player options, saved to user://settings.cfg.

const PATH := "user://settings.cfg"
const MSAA_LEVELS := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const SMOOTHING_TOLERANCE := 40   # RotSprite colour tolerance used when smoothing is on

## Display modes, in the order of the options list.
const DISPLAY_NAMES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const DISPLAY_MODES := [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

const FPS_NAMES := ["Unlimited", "30", "60", "120", "144", "240"]
const FPS_VALUES := [0, 30, 60, 120, 144, 240]
const VSYNC_NAMES := ["Off", "On", "Adaptive"]
const VSYNC_MODES := [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE]
const UI_SCALE_NAMES := ["75%", "100%", "125%", "150%"]
const UI_SCALES := [0.75, 1.0, 1.25, 1.5]

static var display_mode := 0   # index into DISPLAY_MODES
static var msaa := 2           # index into MSAA_LEVELS
static var fps_limit := 0      # index into FPS_VALUES
static var vsync := 1          # index into VSYNC_MODES
static var ui_scale := 1       # index into UI_SCALES
static var master_volume := 1.0
static var music_volume := 1.0
static var sfx_volume := 1.0
static var texture_smoothing := true
static var last_slot := 1        # the save file used last, selected when the file screen opens
static var intro_seen := false     # the welcome message of the first launch has been shown


static func load_and_apply(viewport: Viewport) -> void:
	var cfg := ConfigFile.new()
	InputConfig.setup()
	if cfg.load(PATH) == OK:
		if cfg.has_section_key("video", "display_mode"):
			display_mode = clampi(cfg.get_value("video", "display_mode"), 0, DISPLAY_MODES.size() - 1)
		elif cfg.get_value("video", "fullscreen", false):
			display_mode = 1   # old setting: any fullscreen becomes borderless
		msaa = clampi(cfg.get_value("video", "msaa", msaa), 0, MSAA_LEVELS.size() - 1)
		fps_limit = clampi(cfg.get_value("video", "fps_limit", fps_limit), 0, FPS_VALUES.size() - 1)
		vsync = clampi(cfg.get_value("video", "vsync", vsync), 0, VSYNC_MODES.size() - 1)
		ui_scale = clampi(cfg.get_value("video", "ui_scale", ui_scale), 0, UI_SCALES.size() - 1)
		texture_smoothing = cfg.get_value("video", "texture_smoothing", texture_smoothing)
		master_volume = cfg.get_value("audio", "master", master_volume)
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		last_slot = clampi(cfg.get_value("misc", "last_slot", last_slot), 1, SaveData.SLOT_COUNT)
		intro_seen = cfg.get_value("misc", "intro_seen", intro_seen)
		InputConfig.load_from(cfg)
	apply_display(viewport)
	apply_performance()
	apply_ui_scale(viewport)
	apply(viewport)


## Window mode only. Kept apart from apply() so that changing another option never
## touches the window the player has set up.
static func apply_display(viewport: Viewport) -> void:
	viewport.get_window().mode = DISPLAY_MODES[display_mode]


static func apply_performance() -> void:
	Engine.max_fps = FPS_VALUES[fps_limit]
	DisplayServer.window_set_vsync_mode(VSYNC_MODES[vsync])


static func apply_ui_scale(viewport: Viewport) -> void:
	viewport.get_window().content_scale_factor = UI_SCALES[ui_scale]


static func apply(viewport: Viewport) -> void:
	viewport.msaa_3d = MSAA_LEVELS[msaa]
	AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	Nsbmd.rotsprite_tolerance = SMOOTHING_TOLERANCE if texture_smoothing else -1
	var audio := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameAudio")
	if audio:
		audio.apply_volumes()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("video", "msaa", msaa)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("video", "texture_smoothing", texture_smoothing)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("misc", "last_slot", last_slot)
	cfg.set_value("misc", "intro_seen", intro_seen)
	InputConfig.save_to(cfg)
	cfg.save(PATH)
