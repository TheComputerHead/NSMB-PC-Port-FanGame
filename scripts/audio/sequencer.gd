class_name Sequencer
extends RefCounted
## Plays one DS sequence: a set of tracks of commands (notes, rests, volume, tempo,
## jumps...) read like a MIDI file. It decides what plays when; the actual sound is made
## by Voice objects mixed by Godot.

const TICKS_PER_BEAT := 48
const MAX_COMMANDS_PER_TICK := 400   # guards against broken loops

class Track extends RefCounted:
	var pos := 0
	var wait := 0
	var active := true
	var program := 0
	var volume := 127
	var expression := 127
	var pan := 64
	var bend := 0
	var bend_range := 2
	var transpose := 0
	var priority := 64
	var note_wait := true
	var tie := false
	var tied_voice: Voice
	var attack := -1
	var decay := -1
	var sustain := -1
	var release := -1
	var mod_depth := 0
	var mod_speed := 16
	var mod_range := 1
	var mod_delay := 0
	var call_stack: Array[int] = []
	var loop_stack: Array = []   # [return position, remaining count]

var engine: Node            # GameAudio: gives voices and banks
var data := PackedByteArray()
var base := 0               # where the commands start in `data`
var bank: SoundBank
var group := "music"        # "music" or "sfx"
var sequence_volume := 127
var master_volume := 127
var tempo := 120
var gain := 1.0             # extra volume (fades)
var tracks: Array[Track] = []
var voices: Array[Voice] = []
var finished := false
var loop_count := 0         # how many times the music looped (jumps backwards)

var _tick_carry := 0.0
var _vars := PackedInt32Array()
var _rng := RandomNumberGenerator.new()


func start() -> void:
	_vars.resize(32)
	var track := Track.new()
	track.pos = base
	tracks.append(track)


## Advances the sequence by `delta` seconds and updates every sounding voice.
func update(delta: float) -> void:
	if not finished:
		_tick_carry += delta * tempo * TICKS_PER_BEAT / 60.0
		while _tick_carry >= 1.0:
			_tick_carry -= 1.0
			_tick()
	else:
		# The sequence is over but notes may still be fading out: keep their envelopes running
		# (otherwise they would stay stuck at their last level forever).
		for v in voices:
			if not (v.infinite and not v.loops):
				v.release()
			v.advance(delta)
	for v in voices.duplicate():
		v.update(delta)
		if v.done:
			voices.erase(v)


func is_playing() -> bool:
	return not finished or not voices.is_empty()


## Lets every note die out and stops the sequence.
func stop(release_now := true) -> void:
	finished = true
	for v in voices:
		v.release(release_now)


func _tick() -> void:
	var tick_seconds := 60.0 / (tempo * TICKS_PER_BEAT)
	for v in voices:
		v.advance(tick_seconds)
		if v.ticks_left > 0:
			v.ticks_left -= 1
			if v.ticks_left == 0 and not v.tied:
				v.release()
	var any_active := false
	var index := 0
	while index < tracks.size():   # tracks opened during this tick also run now
		var t := tracks[index]
		index += 1
		if not t.active:
			continue
		any_active = true
		if t.wait > 0:
			t.wait -= 1
		var guard := 0
		while t.wait == 0 and t.active and guard < MAX_COMMANDS_PER_TICK:
			_execute(t)
			guard += 1
		if guard >= MAX_COMMANDS_PER_TICK:
			t.active = false
	if not any_active:
		finished = true


func _u8(t: Track) -> int:
	var v := data[t.pos]
	t.pos += 1
	return v


func _s8(t: Track) -> int:
	var v := _u8(t)
	return v - 256 if v >= 128 else v


func _u16(t: Track) -> int:
	var v := data.decode_u16(t.pos)
	t.pos += 2
	return v


func _s16(t: Track) -> int:
	var v := data.decode_s16(t.pos)
	t.pos += 2
	return v


func _u24(t: Track) -> int:
	var v := data[t.pos] | (data[t.pos + 1] << 8) | (data[t.pos + 2] << 16)
	t.pos += 3
	return v


func _varlen(t: Track) -> int:
	var value := 0
	for i in 4:
		var b := _u8(t)
		value = (value << 7) | (b & 0x7F)
		if b & 0x80 == 0:
			break
	return value


## Reads the "value" argument of a command, which can be replaced by a random number
## (0xA0) or a variable (0xA1) written in front of the command.
func _arg(t: Track, kind: String, override: Variant) -> int:
	if override != null:
		return override
	match kind:
		"u8": return _u8(t)
		"s8": return _s8(t)
		"u16": return _u16(t)
		"s16": return _s16(t)
		_: return _varlen(t)


func _execute(t: Track) -> void:
	if t.pos >= data.size():
		t.active = false
		return
	var cmd := _u8(t)
	var override: Variant = null
	var conditional := false
	# Modifier prefixes: 0xA0 random, 0xA1 variable, 0xA2 only if the last comparison held.
	while cmd == 0xA0 or cmd == 0xA1 or cmd == 0xA2:
		if cmd == 0xA0:
			var low := _s16(t)
			var high := _s16(t)
			override = _rng.randi_range(low, high)
		elif cmd == 0xA1:
			override = _vars[_u8(t) & 31]
		else:
			conditional = true
		cmd = _u8(t)
	if conditional and not _flag:
		_skip_arguments(t, cmd, override != null)
		return

	if cmd < 0x80:
		_note(t, cmd, override)
		return
	match cmd:
		0x80:
			t.wait = _arg(t, "var", override)
		0x81:
			t.program = _arg(t, "var", override)
		0x93:   # open track
			var number := _u8(t)
			var offset := _u24(t)
			var nt := Track.new()
			nt.pos = base + offset
			nt.program = t.program
			tracks.append(nt)
		0x94:   # jump
			var target := base + _u24(t)
			if target < t.pos:
				loop_count += 1
			t.pos = target
		0x95:   # call
			var target := base + _u24(t)
			t.call_stack.append(t.pos)
			t.pos = target
		0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD:
			_variable_op(t, cmd, override)
		0xC0: t.pan = _arg(t, "u8", override)
		0xC1: t.volume = _arg(t, "u8", override)
		0xC2: master_volume = _arg(t, "u8", override)
		0xC3: t.transpose = _arg(t, "s8", override)
		0xC4: t.bend = _arg(t, "s8", override)
		0xC5: t.bend_range = _arg(t, "u8", override)
		0xC6: t.priority = _arg(t, "u8", override)
		0xC7: t.note_wait = _arg(t, "u8", override) != 0
		0xC8:
			t.tie = _arg(t, "u8", override) != 0
			if not t.tie and t.tied_voice:
				t.tied_voice.release()
				t.tied_voice = null
		0xC9: _arg(t, "u8", override)        # portamento key (ignored)
		0xCA: t.mod_depth = _arg(t, "u8", override)
		0xCB: t.mod_speed = _arg(t, "u8", override)
		0xCC: _arg(t, "u8", override)        # modulation type (always pitch here)
		0xCD: t.mod_range = _arg(t, "u8", override)
		0xCE: _arg(t, "u8", override)        # portamento on/off (ignored)
		0xCF: _arg(t, "u8", override)        # portamento time (ignored)
		0xD0: t.attack = _arg(t, "u8", override)
		0xD1: t.decay = _arg(t, "u8", override)
		0xD2: t.sustain = _arg(t, "u8", override)
		0xD3: t.release = _arg(t, "u8", override)
		0xD4:   # loop start
			var count := _arg(t, "u8", override)
			t.loop_stack.append([t.pos, count])
		0xD5: t.expression = _arg(t, "u8", override)
		0xD6: _arg(t, "u8", override)        # print variable (debug)
		0xE0: t.mod_delay = _arg(t, "u16", override)
		0xE1: tempo = maxi(_arg(t, "u16", override), 1)
		0xE3: _arg(t, "s16", override)       # sweep pitch (ignored)
		0xFC:   # loop end
			if not t.loop_stack.is_empty():
				var top: Array = t.loop_stack[t.loop_stack.size() - 1]
				if top[1] == 0:
					t.pos = top[0]
					loop_count += 1
				else:
					top[1] -= 1
					if top[1] > 0:
						t.pos = top[0]
					else:
						t.loop_stack.pop_back()
		0xFD:   # return from call
			if not t.call_stack.is_empty():
				t.pos = t.call_stack.pop_back()
		0xFE:   # allocate tracks (informational)
			_u16(t)
		0xFF:
			t.active = false
			if t.tied_voice:
				t.tied_voice.release()
				t.tied_voice = null
		_:
			push_warning("Unknown sequence command 0x%02X" % cmd)
			t.active = false


var _flag := true   # result of the last variable comparison


func _skip_arguments(t: Track, cmd: int, replaced: bool) -> void:
	if cmd < 0x80:
		if not replaced:
			_u8(t)
			_varlen(t)
		return
	match cmd:
		0x80, 0x81:
			if not replaced:
				_varlen(t)
		0x93:
			t.pos += 4
		0x94, 0x95:
			t.pos += 3
		0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD:
			t.pos += 3
		0xE0, 0xE1, 0xE3, 0xFE:
			if not replaced:
				t.pos += 2
		0xFC, 0xFD, 0xFF:
			pass
		_:
			if not replaced:
				t.pos += 1


func _variable_op(t: Track, cmd: int, override: Variant) -> void:
	var variable := _u8(t) & 31
	var value := _arg(t, "s16", override)
	match cmd:
		0xB0: _vars[variable] = value
		0xB1: _vars[variable] += value
		0xB2: _vars[variable] -= value
		0xB3: _vars[variable] *= value
		0xB4: if value != 0: _vars[variable] /= value
		0xB5: _vars[variable] = _vars[variable] << value if value >= 0 else _vars[variable] >> -value
		0xB6: _vars[variable] = _rng.randi_range(mini(0, value), maxi(0, value))
		0xB8: _flag = _vars[variable] == value
		0xB9: _flag = _vars[variable] >= value
		0xBA: _flag = _vars[variable] > value
		0xBB: _flag = _vars[variable] <= value
		0xBC: _flag = _vars[variable] < value
		0xBD: _flag = _vars[variable] != value


func _note(t: Track, key: int, override: Variant) -> void:
	var velocity: int = (_u8(t) & 0x7F) if override == null else override
	var duration := _varlen(t)
	if t.tie and t.tied_voice and not t.tied_voice.done:
		t.tied_voice.retune(key)
		t.tied_voice.ticks_left = duration
	else:
		var voice: Voice = engine.start_voice(self, t, key, velocity, duration)
		if voice:
			voices.append(voice)
			# Length 0 means "play the whole sample" (voices, one-shot sounds).
			voice.infinite = duration == 0
			if t.tie:
				voice.tied = true
				t.tied_voice = voice
	if t.note_wait:
		t.wait = duration
