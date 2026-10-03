extends Node
## The game's audio: plays the ROM's music and sound effects (an autoload called
## "GameAudio"). Sequences are played by our own sequencer; each note is a Godot player,
## so Godot does the mixing.
##
##   GameAudio.play_music("BGM_SELECT")
##   GameAudio.play_sound("SAR_VS_COMMON_MENU", "SE_SYS_DECIDE")

const VOICE_COUNT := 32
const SDAT_PATH := "sound_data.sdat"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var available := false

var _sdat: Sdat
var _banks := {}            # bank id -> SoundBank
var _wave_archives := {}    # wave archive id -> SoundWaves
var _players: Array[AudioStreamPlayer] = []
var _buses: Array[int] = []              # bus index of each player
var _voice_of := {}                      # player -> Voice
var _sequencers: Array[Sequencer] = []
var _music: Sequencer
var _music_name := ""
var _square_streams := {}
var _noise_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus(MUSIC_BUS)
	_make_bus(SFX_BUS)
	for i in VOICE_COUNT:
		var bus_name := "Voice%d" % i
		_make_bus(bus_name, MUSIC_BUS)
		var index := AudioServer.get_bus_index(bus_name)
		AudioServer.add_bus_effect(index, AudioEffectPanner.new(), 0)
		var player := AudioStreamPlayer.new()
		player.bus = bus_name
		add_child(player)
		_players.append(player)
		_buses.append(index)
	apply_volumes()


func _make_bus(bus_name: String, send := "Master") -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)


## Applies the music and effects volume sliders of the options.
func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(maxf(Settings.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))


## Loads the sound archive once. Returns false if the ROM's audio is not available.
func ensure_loaded() -> bool:
	if _sdat != null:
		return available
	var sdat := Sdat.new()
	var path := RomExtractor.RAW_DIR + SDAT_PATH
	if FileAccess.file_exists(path) and sdat.open(FileAccess.get_file_as_bytes(path)) == OK:
		available = true
	_sdat = sdat   # remember the attempt either way
	return available


func play_music(sequence_name: String, restart := false) -> void:
	if not ensure_loaded():
		return
	if sequence_name == _music_name and _music and _music.is_playing() and not restart:
		return
	stop_music()
	var id := _sdat.find("seq", sequence_name)
	if id < 0:
		push_warning("Unknown music " + sequence_name)
		return
	var info: Dictionary = _sdat.infos["seq"][id]
	var file := _sdat.file(info.file)
	_music = _make_sequencer(file, file.decode_u32(0x18), info.bank, info.volume, "music")
	_music_name = sequence_name


func stop_music() -> void:
	if _music:
		_music.stop(true)
	_music = null
	_music_name = ""


func play_sound(archive_name: String, sound_name: String) -> void:
	if not ensure_loaded():
		return
	var archive := _sdat.find("seqarc", archive_name)
	if archive < 0:
		return
	for entry in _sdat.archive_entries(archive):
		if entry.name == sound_name:
			var file := _sdat.file(_sdat.infos["seqarc"][archive].file)
			_make_sequencer(file, entry.offset, entry.bank, entry.volume, "sfx")
			return
	push_warning("Unknown sound %s / %s" % [archive_name, sound_name])


var _ui_mute_until := 0.0


## Silences the cursor sound for a moment (when a screen grabs focus on its own).
func mute_ui_for(seconds: float) -> void:
	_ui_mute_until = Time.get_ticks_msec() / 1000.0 + seconds


func ui_cursor() -> void:
	if Time.get_ticks_msec() / 1000.0 < _ui_mute_until:
		return
	play_sound("SAR_VS_COMMON_MENU", "SE_SYS_CURSOR")


func ui_decide() -> void:
	play_sound("SAR_VS_COMMON_MENU", "SE_SYS_DECIDE")


func ui_back() -> void:
	play_sound("SAR_VS_COMMON_MENU", "SE_SYS_BACK")


func _make_sequencer(file: PackedByteArray, offset: int, bank_id: int, volume: int, group: String) -> Sequencer:
	var seq := Sequencer.new()
	seq.engine = self
	seq.data = file
	seq.base = offset
	seq.bank = _get_bank(bank_id)
	seq.sequence_volume = volume
	seq.group = group
	seq.start()
	_sequencers.append(seq)
	return seq


func _get_bank(bank_id: int) -> SoundBank:
	if _banks.has(bank_id):
		return _banks[bank_id]
	var info: Dictionary = _sdat.infos["bank"][bank_id]
	var bank := SoundBank.new()
	bank.setup(_sdat.file(info.file))
	for arc_id: int in info.wave_archives:
		if arc_id == 0xFFFF:
			bank.wave_archives.append(null)
		else:
			bank.wave_archives.append(_get_waves(arc_id))
	_banks[bank_id] = bank
	return bank


func _get_waves(arc_id: int) -> SoundWaves:
	if _wave_archives.has(arc_id):
		return _wave_archives[arc_id]
	var waves := SoundWaves.new()
	waves.setup(_sdat.file(_sdat.infos["wavearc"][arc_id].file))
	_wave_archives[arc_id] = waves
	return waves


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)   # a long frame (loading) must not make the music jump ahead
	for seq in _sequencers.duplicate():
		seq.update(delta)
		if not seq.is_playing():
			_sequencers.erase(seq)


# --- voices -----------------------------------------------------------------

## Called by sequencers when a note starts. Returns the voice, or null if nothing plays.
func start_voice(seq: Sequencer, track: Sequencer.Track, key: int, velocity: int, ticks: int) -> Voice:
	var region := seq.bank.find_region(track.program, key)
	if region.is_empty():
		return null
	var stream := _stream_for(seq.bank, region)
	if stream == null:
		return null
	var player := _take_player(seq.group, track.priority)
	if player == null:
		return null
	var voice := Voice.new()
	voice.engine = self
	voice.seq = seq
	voice.track = track
	voice.key = key
	voice.velocity = velocity
	voice.ticks_left = ticks
	voice.priority = track.priority
	voice.started_at = Time.get_ticks_msec() / 1000.0
	voice.loops = stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	voice.setup(region)
	_voice_of[player] = voice
	voice.player = player
	var index := _players.find(player)
	AudioServer.set_bus_send(_buses[index], MUSIC_BUS if seq.group == "music" else SFX_BUS)
	player.stream = stream
	player.pitch_scale = 1.0
	player.volume_db = -80.0
	player.play()
	voice.update(0.0)
	return voice


func free_voice(player: AudioStreamPlayer) -> void:
	player.stop()
	_voice_of.erase(player)


func set_voice_pan(player: AudioStreamPlayer, pan: float) -> void:
	var index := _players.find(player)
	if index >= 0:
		var panner := AudioServer.get_bus_effect(_buses[index], 0) as AudioEffectPanner
		if panner:
			panner.pan = pan


## A free player, or the one whose voice is the best candidate to cut off.
func _take_player(group: String, priority: int) -> AudioStreamPlayer:
	for p in _players:
		if not _voice_of.has(p):
			return p
	var victim: Voice
	for v: Voice in _voice_of.values():
		if v.seq.group != group and group == "music":
			continue   # music never cuts sound effects
		if victim == null or v.priority < victim.priority or \
				(v.priority == victim.priority and v.started_at < victim.started_at):
			victim = v
	if victim and victim.priority <= priority:
		var player := victim.player
		victim.done = true
		victim.seq.voices.erase(victim)
		_voice_of.erase(player)
		return player
	return null


func _stream_for(bank: SoundBank, region: Dictionary) -> AudioStreamWAV:
	match region.kind:
		SoundBank.SAMPLE:
			if region.swar >= bank.wave_archives.size() or bank.wave_archives[region.swar] == null:
				return null
			return (bank.wave_archives[region.swar] as SoundWaves).get_stream(region.swav)
		SoundBank.SQUARE:
			return _square(region.swav)
		SoundBank.NOISE:
			return _noise()
	return null


## Square wave of the given duty cycle (0 = 12.5% ... 6 = 87.5%), one 8-sample period
## that plays middle C (key 60) at its natural speed.
func _square(duty: int) -> AudioStreamWAV:
	var d := clampi(duty, 0, 6)
	if _square_streams.has(d):
		return _square_streams[d]
	var data := PackedByteArray()
	data.resize(8)
	for i in 8:
		data[i] = 100 if i <= d else 256 - 100   # signed 8-bit
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = int(261.63 * 8)
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = 8
	_square_streams[d] = s
	return s


func _noise() -> AudioStreamWAV:
	if _noise_stream:
		return _noise_stream
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var data := PackedByteArray()
	data.resize(4096)
	for i in 4096:
		data[i] = 90 if rng.randi() & 1 else 256 - 90
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = 16384
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = 4096
	_noise_stream = s
	return s
