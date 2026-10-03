class_name SoundWaves
extends RefCounted
## A wave archive (SWAR): the recorded samples instruments are made of.
## Samples are decoded to Godot streams on first use and kept.

const STEP_TABLE := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80,
	88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
	598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749,
	3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635,
	13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]
const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8]

var _data := PackedByteArray()
var _offsets: Array[int] = []
var _cache := {}


func setup(swar: PackedByteArray) -> void:
	_data = swar
	if swar.size() < 0x40 or swar.slice(0, 4).get_string_from_ascii() != "SWAR":
		return
	for i in swar.decode_u32(0x38):
		_offsets.append(swar.decode_u32(0x3C + i * 4))


func count() -> int:
	return _offsets.size()


## The sample as a Godot stream (looping if the original loops), or null.
func get_stream(index: int) -> AudioStreamWAV:
	if _cache.has(index):
		return _cache[index]
	if index < 0 or index >= _offsets.size():
		return null
	var stream := _decode(_offsets[index])
	_cache[index] = stream
	return stream


func _decode(o: int) -> AudioStreamWAV:
	var kind := _data[o]
	var loops := _data[o + 1] != 0
	var rate := _data.decode_u16(o + 2)
	var loop_start := _data.decode_u16(o + 6)    # in 32-bit words
	var non_loop := _data.decode_u32(o + 8)      # in 32-bit words
	var body := o + 12
	var stream := AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.stereo = false
	var samples := 0
	var loop_begin := 0
	match kind:
		0:   # signed 8-bit PCM
			samples = (loop_start + non_loop) * 4
			stream.format = AudioStreamWAV.FORMAT_8_BITS
			stream.data = _data.slice(body, body + samples)
			loop_begin = loop_start * 4
		1:   # signed 16-bit PCM
			samples = (loop_start + non_loop) * 2
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.data = _data.slice(body, body + samples * 2)
			loop_begin = loop_start * 2
		_:   # IMA ADPCM with a 4-byte header
			samples = (loop_start + non_loop) * 8 - 8
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.data = _adpcm(body, samples)
			loop_begin = maxi(loop_start * 8 - 8, 0)
	if loops:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = samples
	return stream


func _adpcm(p: int, samples: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples * 2)
	var predictor := _data.decode_s16(p)
	var index := clampi(_data.decode_u16(p + 2), 0, 88)
	p += 4
	for i in samples:
		var byte := _data[p + (i >> 1)]
		var nibble := (byte >> 4) if i & 1 else (byte & 15)
		var step: int = STEP_TABLE[index]
		var diff := step >> 3
		if nibble & 1:
			diff += step >> 2
		if nibble & 2:
			diff += step >> 1
		if nibble & 4:
			diff += step
		if nibble & 8:
			diff = -diff
		predictor = clampi(predictor + diff, -32768, 32767)
		index = clampi(index + INDEX_TABLE[nibble & 7], 0, 88)
		out.encode_s16(i * 2, predictor)
	return out
