class_name SoundBank
extends RefCounted
## An instrument bank (SBNK): for each program number, which sample plays for which
## key, its base note and its volume envelope.

## Kinds of sound a region can make.
const SAMPLE := 1
const SQUARE := 2   # "PSG" square wave; `swav` holds the duty cycle
const NOISE := 3

var wave_archives: Array = []   # up to 4 SoundWaves (or null), as listed by the bank
var _data := PackedByteArray()
var _instruments: Array[Dictionary] = []


func setup(sbnk: PackedByteArray) -> void:
	_data = sbnk
	if sbnk.size() < 0x40 or sbnk.slice(0, 4).get_string_from_ascii() != "SBNK":
		return
	for i in sbnk.decode_u32(0x38):
		var e := 0x3C + i * 4
		_instruments.append({"type": sbnk[e], "offset": sbnk.decode_u16(e + 1)})


func program_count() -> int:
	return _instruments.size()


## The region that plays `key` for `program`: {kind, swav, swar, base, attack, decay,
## sustain, release, pan}, or an empty Dictionary if the program is empty.
func find_region(program: int, key: int) -> Dictionary:
	if program < 0 or program >= _instruments.size():
		return {}
	var inst := _instruments[program]
	var o: int = inst.offset
	match inst.type:
		1, 2, 3:
			return _region(inst.type, o + 0)
		16:   # drum set: one region per key
			var low := _data[o]
			var high := _data[o + 1]
			if key < low or key > high:
				return {}
			return _region_with_type(o + 2 + (key - low) * 12)
		17:   # key split: up to 8 regions, each valid up to a key limit
			var slot := 0
			while slot < 8 and key > _data[o + slot]:
				slot += 1
			if slot >= 8:
				return {}
			return _region_with_type(o + 8 + slot * 12)
	return {}


func _region_with_type(p: int) -> Dictionary:
	return _region(_data.decode_u16(p), p + 2)


func _region(kind: int, p: int) -> Dictionary:
	return {
		"kind": kind,
		"swav": _data.decode_u16(p), "swar": _data.decode_u16(p + 2),
		"base": _data[p + 4], "attack": _data[p + 5], "decay": _data[p + 6],
		"sustain": _data[p + 7], "release": _data[p + 8], "pan": _data[p + 9],
	}
