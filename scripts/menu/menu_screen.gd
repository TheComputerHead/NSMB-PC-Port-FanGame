class_name MenuScreen
extends Control
## Base class of the menu screens. The root keeps the background, logo and
## characters; a screen only provides its own widgets.

## Which layout the root uses while this screen is shown: "title", "main" or "other".
var mode := "other"
## Set by MenuRoot before the screen enters the tree.
var root: Control


## Screen to return to when the player presses Back/Escape ("" = none).
func back_target() -> String:
	return ""


## What the help line at the bottom shows on this screen: [{kind, text}, ...] where kind is
## accept, back, move or left_right.
func help_items() -> Array:
	return [
		{"kind": "move", "text": "Move"},
		{"kind": "accept", "text": "Select"},
		{"kind": "back", "text": "Back"},
	]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_PASS
	GameAudio.mute_ui_for(0.3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and back_target() != "":
		get_viewport().set_input_as_handled()
		GameAudio.ui_back()
		root.go(back_target())
	elif event is InputEventJoypadButton and event.pressed \
			and (event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER):
		# The shoulder buttons page through the choices: previous / next.
		var focus := get_viewport().gui_get_focus_owner()
		if focus:
			var target := focus.find_prev_valid_focus() if event.button_index == JOY_BUTTON_LEFT_SHOULDER \
				else focus.find_next_valid_focus()
			if target and target != focus and is_ancestor_of(target):
				get_viewport().set_input_as_handled()
				target.grab_focus()


## A column of widgets centred in the space below the logo.
func column(top_fraction := 0.3, spacing := 14) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(margin)
	var update := func() -> void:
		margin.add_theme_constant_override("margin_top", int(size.y * top_fraction))
	resized.connect(update)
	update.call()
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	center.add_child(box)
	return box
