extends Control
## First-launch screen: the player picks their own NSMB ROM, we extract assets.

@onready var status: Label = %Status
@onready var bar: ProgressBar = %Bar
@onready var pick_button: Button = %PickButton
@onready var dialog: FileDialog = %Dialog

var _thread: Thread


func _ready() -> void:
	pick_button.pressed.connect(dialog.popup_centered_ratio.bind(0.7))
	dialog.file_selected.connect(_on_rom_chosen)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			_on_rom_chosen.call_deferred(arg.trim_prefix("--rom="))
			return
	if RomExtractor.is_extracted():
		_go_to_menu.call_deferred()


func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()


func _on_rom_chosen(path: String) -> void:
	var rom := NdsRom.new()
	var err := rom.open(path)
	if err != OK:
		status.text = "Could not read this file (%s)." % error_string(err)
		return
	var region := RomInfo.region_of(rom)
	if region == "":
		status.text = "This ROM is '%s' (%s), not New Super Mario Bros." % [rom.title, rom.game_code]
		return
	status.text = "New Super Mario Bros. (%s), %d files. Extracting..." % [region, rom.files.size()]
	pick_button.disabled = true
	_thread = Thread.new()
	_thread.start(_extract.bind(rom))


func _extract(rom: NdsRom) -> void:
	var err := RomExtractor.extract_all(rom, _report_progress)
	_finished.call_deferred(err, rom.files.size())


func _report_progress(done: int, total: int) -> void:
	_set_progress.call_deferred(done, total)


func _set_progress(done: int, total: int) -> void:
	bar.max_value = total
	bar.value = done


func _finished(err: Error, count: int) -> void:
	_thread.wait_to_finish()
	_thread = null
	pick_button.disabled = false
	if err == OK:
		status.text = "Done: %d files extracted to %s" % [count, ProjectSettings.globalize_path("user://assets/")]
		print("EXTRACT_OK ", count)
		get_tree().create_timer(1.0).timeout.connect(_go_to_menu)
	else:
		status.text = "Extraction failed (%s)." % error_string(err)
		print("EXTRACT_FAIL ", err)


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
