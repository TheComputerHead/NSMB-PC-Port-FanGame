class_name InputConfig
extends RefCounted
## The game's controls: one action per thing the player can do, each with a keyboard key
## and a gamepad button that the player can change. Saved with the other settings.

const ACTIONS := [
	{"id": "move_left", "label": "Move left", "key": KEY_LEFT, "pad": JOY_BUTTON_DPAD_LEFT},
	{"id": "move_right", "label": "Move right", "key": KEY_RIGHT, "pad": JOY_BUTTON_DPAD_RIGHT},
	{"id": "move_up", "label": "Up / enter door", "key": KEY_UP, "pad": JOY_BUTTON_DPAD_UP},
	{"id": "move_down", "label": "Crouch / enter pipe", "key": KEY_DOWN, "pad": JOY_BUTTON_DPAD_DOWN},
	{"id": "jump", "label": "Jump", "key": KEY_X, "pad": JOY_BUTTON_A},
	{"id": "run", "label": "Run / fireball", "key": KEY_Z, "pad": JOY_BUTTON_X},
	{"id": "pause", "label": "Pause", "key": KEY_P, "pad": JOY_BUTTON_START},
]

static var keys := {}   # action id -> physical keycode
static var pads := {}   # action id -> joypad button


## Registers the actions with their default bindings.
static func setup() -> void:
	for a: Dictionary in ACTIONS:
		keys[a.id] = a.key
		pads[a.id] = a.pad
		if not InputMap.has_action(a.id):
			InputMap.add_action(a.id)
		_apply(a.id)


static func reset_defaults() -> void:
	setup()


static func load_from(cfg: ConfigFile) -> void:
	for a: Dictionary in ACTIONS:
		keys[a.id] = cfg.get_value("controls", a.id + "_key", a.key)
		pads[a.id] = cfg.get_value("controls", a.id + "_pad", a.pad)
		_apply(a.id)


static func save_to(cfg: ConfigFile) -> void:
	for a: Dictionary in ACTIONS:
		cfg.set_value("controls", a.id + "_key", keys[a.id])
		cfg.set_value("controls", a.id + "_pad", pads[a.id])


static func set_key(id: String, keycode: int) -> void:
	keys[id] = keycode
	_apply(id)


static func set_pad(id: String, button: int) -> void:
	pads[id] = button
	_apply(id)


static func _apply(id: String) -> void:
	InputMap.action_erase_events(id)
	var key := InputEventKey.new()
	key.physical_keycode = keys[id]
	InputMap.action_add_event(id, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = pads[id]
	InputMap.action_add_event(id, pad)


static func key_name(id: String) -> String:
	return OS.get_keycode_string(keys[id])


## Gamepad button as text. The face buttons use the symbols of the game's own font.
static func pad_name(id: String) -> String:
	match pads[id]:
		JOY_BUTTON_A: return ""
		JOY_BUTTON_B: return ""
		JOY_BUTTON_X: return ""
		JOY_BUTTON_Y: return ""
		JOY_BUTTON_LEFT_SHOULDER: return ""
		JOY_BUTTON_RIGHT_SHOULDER: return ""
		JOY_BUTTON_DPAD_LEFT: return "←"
		JOY_BUTTON_DPAD_RIGHT: return "→"
		JOY_BUTTON_DPAD_UP: return "↑"
		JOY_BUTTON_DPAD_DOWN: return "↓"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Select"
	return "Btn %d" % pads[id]
