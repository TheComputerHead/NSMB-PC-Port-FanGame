class_name Voice
extends RefCounted
## One sounding note: a Godot player plus the DS volume envelope (attack, decay,
## sustain, release), pitch (with bend and vibrato) and panning.
##
## The envelope works like the console's: an "amplitude" in 1/128 of a tenth of a dB (so the
## range is -72 dB to 0) that goes from -92544 (silence) to 0 (full volume), 192 updates a second.

enum { ATTACK, DECAY, SUSTAIN, RELEASE }

const SILENCE := -92544.0
const STEP := 1.0 / 192.0
const ATTACK_TABLE := [
	0x00, 0x01, 0x05, 0x0E, 0x1A, 0x26, 0x33, 0x3F, 0x49, 0x54, 0x5C, 0x64, 0x6D, 0x74, 0x7B, 0x7F, 0x84, 0x89,
]

var player: AudioStreamPlayer
var engine: Node
var seq: Sequencer
var track: Sequencer.Track
var key := 60
var velocity := 100
var kind := SoundBank.SAMPLE
var base_key := 60
var region_pan := 64
var ticks_left := 0
var tied := false
var infinite := false      # length 0: plays until its sample ends
var loops := false         # the sample loops (so it never ends by itself)
var done := false
var priority := 64
var started_at := 0.0

var _state := ATTACK
var _amp := SILENCE
var _attack_rate := 0.0
var _decay_rate := 0.0
var _sustain_amp := 0.0
var _release_rate := 0.0
var _age := 0.0
var _accumulated := 0.0


func setup(region: Dictionary) -> void:
	kind = region.kind
	base_key = region.base
	region_pan = region.pan
	var a: int = track.attack if track.attack >= 0 else region.attack
	var d: int = track.decay if track.decay >= 0 else region.decay
	var s: int = track.sustain if track.sustain >= 0 else region.sustain
	var r: int = track.release if track.release >= 0 else region.release
	_attack_rate = _attack_factor(a)
	_decay_rate = _fall_rate(d)
	_release_rate = _fall_rate(r)
	_sustain_amp = SILENCE if s <= 0 else minf(0.0, 128.0 * 400.0 * log(minf(s, 127) / 127.0) / log(10.0))
	if _attack_rate <= 1.0:
		_amp = 0.0
		_state = DECAY


static func _attack_factor(a: int) -> float:
	if a >= 109:
		return float(ATTACK_TABLE[mini(127 - a, ATTACK_TABLE.size() - 1)])
	return float(255 - a)


## Units the envelope falls per step for a decay/release value.
static func _fall_rate(value: int) -> float:
	if value >= 127:
		return 65535.0
	if value == 126:
		return float(0x3C00)
	if value < 50:
		return value * 2.0 + 1.0
	return float(0x1E00) / (126.0 - value)


func retune(new_key: int) -> void:
	key = new_key


## Starts the release stage (the note ended). `quickly` makes it very short.
func release(quickly := false) -> void:
	if _state == RELEASE:
		return
	_state = RELEASE
	if quickly:
		_release_rate = maxf(_release_rate, 1500.0)


## Advances the envelope by `dt` seconds of sequence time (called once per sequence tick).
func advance(dt: float) -> void:
	if done:
		return
	_age += dt
	if _age > 90.0 and _state != RELEASE:
		release(true)   # safety net: nothing should sound this long
	_accumulated += dt
	while _accumulated >= STEP and not done:
		_accumulated -= STEP
		_step()


## Pushes the current volume, pitch and pan to the player (called every frame).
func update(_delta: float) -> void:
	if done:
		return
	if kind != SoundBank.NOISE and not player.playing:
		finish()
		return
	_apply()


func _step() -> void:
	match _state:
		ATTACK:
			_amp = _amp * _attack_rate / 256.0
			if _amp > -1.0:
				_amp = 0.0
				_state = DECAY
		DECAY:
			_amp -= _decay_rate
			if _amp <= _sustain_amp:
				_amp = _sustain_amp
				_state = SUSTAIN
				if _sustain_amp <= SILENCE:
					finish()
		RELEASE:
			_amp -= _release_rate
			if _amp <= SILENCE:
				finish()


func _apply() -> void:
	var level := pow(10.0, _amp / 25600.0)   # envelope units -> linear amplitude
	var amp := level \
		* pow(velocity / 127.0, 2.0) \
		* pow(track.volume / 127.0, 2.0) \
		* pow(track.expression / 127.0, 2.0) \
		* pow(seq.sequence_volume / 127.0, 2.0) \
		* pow(seq.master_volume / 127.0, 2.0) \
		* seq.gain
	player.volume_db = linear_to_db(maxf(amp, 0.00001))

	var semitones := float(key + track.transpose - base_key)
	semitones += track.bend / 127.0 * track.bend_range
	if track.mod_depth > 0 and _age >= track.mod_delay * 60.0 / (seq.tempo * 48.0):
		var hz := track.mod_speed * 0.35
		semitones += sin(_age * TAU * hz) * track.mod_depth / 127.0 * track.mod_range
	player.pitch_scale = pow(2.0, semitones / 12.0)
	engine.set_voice_pan(player, clampf(((region_pan - 64) + (track.pan - 64)) / 64.0, -1.0, 1.0))


func finish() -> void:
	if done:
		return
	done = true
	engine.free_voice(player)
