class_name NitroAnim
extends RefCounted
## Reader for joint animations (.nsbca, "BCA0"): for every joint of a model, how its
## translation, rotation and scale change from frame to frame.
##
## A pack holds several animations by name. Joint i of an animation drives node i of the
## model it was made for. Each joint starts with a 16-bit flag word (the upper half is its
## index) that says which of translation x/y/z, rotation and scale are absent, constant
## or animated; the values follow. Rotation values are indices into two tables: pivot
## rotations (a flag word and a cosine/sine pair) and full matrices (five numbers, the
## rest is recomputed).

const FX := 1.0 / 4096.0

var animations := {}   # name -> {frames, joints}
var _d := PackedByteArray()


## `data` is the decompressed file. Returns OK or an error.
func parse(data: PackedByteArray) -> Error:
	_d = data
	if _d.size() < 0x14 or _d.slice(0, 4).get_string_from_ascii() != "BCA0":
		return ERR_FILE_UNRECOGNIZED
	var block := _d.decode_u32(0x10)
	if _d.slice(block, block + 4).get_string_from_ascii() != "JNT0":
		return ERR_FILE_CORRUPT
	for e in NitroDict.read(_d, block + 8):
		animations[e.name] = _parse_animation(block + _d.decode_u32(e.entry))
	return OK


func has_animation(animation_name: String) -> bool:
	return animations.has(animation_name)


func frame_count(animation_name: String) -> int:
	return animations[animation_name].frames


func _parse_animation(a: int) -> Dictionary:
	var frames := _d.decode_u16(a + 4)
	var count := _d.decode_u16(a + 6)
	var pivots := a + _d.decode_u32(a + 12)
	var matrices := a + _d.decode_u32(a + 16)
	var joints := []
	for i in count:
		joints.append(_parse_joint(a, a + _d.decode_u16(a + 20 + i * 2)))
	_measure_samples(joints)
	return {"frames": frames, "joints": joints, "pivots": pivots, "matrices": matrices}


## Works out how many samples each animated value really has: its data ends where the
## next one begins. (Some animations store one more key, at their very end; short ones
## do not, and reading it would take numbers from the neighbouring value.)
func _measure_samples(joints: Array) -> void:
	var values: Array[Dictionary] = []
	for joint: Dictionary in joints:
		if joint.r != null and not joint.r.constant:
			joint.r["bytes"] = 2
			values.append(joint.r)
		for c in 3:
			for v in [joint.t[c], joint.s[c]]:
				if v != null and not v.constant:
					v["bytes"] = 4 if v.wide else 2
					values.append(v)
	var starts: Array[int] = []
	for v in values:
		starts.append(v.data)
	starts.sort()
	for v in values:
		var end := -1
		for s in starts:
			if s > v.data:
				end = s
				break
		v["avail"] = (end - v.data) / v.bytes if end > 0 else 1 << 20


## Reads the flag word of a joint and what follows it.
func _parse_joint(anim: int, p: int) -> Dictionary:
	var flags := _d.decode_u16(p)
	p += 4
	var joint := {"t": [null, null, null], "r": null, "s": [null, null, null]}
	if not flags & 0x01:
		for c in 3:
			var r := _read_value(anim, p, flags & (0x08 << c) != 0)
			joint.t[c] = r[0]
			p = r[1]
	if not flags & 0x02:
		var r := _read_value(anim, p, flags & 0x100 != 0)
		joint.r = r[0]
		p = r[1]
	if not flags & 0x200:
		for c in 3:
			var r := _read_value(anim, p, flags & (0x800 << c) != 0)
			joint.s[c] = r[0]
			p = r[1]
	return joint


## A constant is one 32-bit word; an animated value is a header (first frame, last frame
## with mode bits) and an offset to the samples. Returns [value, next position].
func _read_value(anim: int, p: int, is_constant: bool) -> Array:
	if is_constant:
		return [{"constant": true, "raw": _d.decode_s32(p), "index": _d.decode_u16(p)}, p + 4]
	var info := _d.decode_u32(p)
	var mode := (info >> 28) & 0xF
	return [{
		"constant": false,
		"first": info & 0xFFFF,
		"last": (info >> 16) & 0xFFF,
		"step": 1 << ((mode >> 2) & 3) if (mode >> 2) & 3 < 3 else 4,
		"wide": (mode & 2) == 0,   # translation / scale samples: 32-bit unless bit 13 is set
		"data": anim + _d.decode_u32(p + 4),
	}, p + 8]


# --- evaluation -----------------------------------------------------------

## The local transforms of all joints at `frame` (a float; it is looped by the caller).
func pose(animation_name: String, frame: float) -> Array[Transform3D]:
	var anim: Dictionary = animations[animation_name]
	var out: Array[Transform3D] = []
	for joint: Dictionary in anim.joints:
		var origin := Vector3.ZERO
		for c in 3:
			if joint.t[c] != null:
				origin[c] = _scalar(joint.t[c], frame)
		var basis := Basis.IDENTITY
		if joint.r != null:
			basis = _rotation(anim, joint.r, frame)
		var scale := Vector3.ONE
		for c in 3:
			if joint.s[c] != null:
				scale[c] = _scalar(joint.s[c], frame)
		# A few joints use a layout that is not understood yet (the "scale_up" animation's
		# root): their numbers are nonsense, so they stay at rest rather than wreck the model.
		var biggest := maxf(absf(scale.x), maxf(absf(scale.y), absf(scale.z)))
		var smallest := minf(absf(scale.x), minf(absf(scale.y), absf(scale.z)))
		if biggest > 50.0 or smallest < 0.001:
			scale = Vector3.ONE
		if origin.length() > 1000.0:
			origin = Vector3.ZERO
		out.append(Transform3D(basis * Basis.from_scale(scale), origin))
	return out


func _scalar(v: Dictionary, frame: float) -> float:
	if v.constant:
		return v.raw * FX
	var pos: float = clampf(frame - v.first, 0.0, float(_span(v))) / v.step
	var i := int(floor(pos))
	var t: float = pos - i
	var a: float = _sample(v, i)
	var b: float = _sample(v, i + 1)
	if v.step == 1 or t < 0.001:
		return lerpf(a, b, t)
	# Sparse keys: a smooth curve through them instead of straight lines, which would
	# make every key a visible change of speed.
	return cubic_interpolate(a, b, _sample(v, i - 1), _sample(v, i + 2), t)


## How far an animated value goes, in frames from its first one. When keys are spaced
## out, the header names the last key before the end, and one more key is stored at the
## end of the animation itself: it is the one that closes the loop.
static func _span(v: Dictionary) -> int:
	return maxi(v.last - v.first, 0) + (v.step if v.step > 1 else 0)


## How many samples an animated value stores.
static func _count(v: Dictionary) -> int:
	var wanted := maxi(v.last - v.first, 1)
	if v.step > 1:
		wanted = _span(v) / v.step + 1
	return mini(wanted, v.avail)


func _sample(v: Dictionary, i: int) -> float:
	var count := _count(v)
	i = clampi(i, 0, count - 1)
	if v.wide:
		return _d.decode_s32(v.data + i * 4) * FX
	return _d.decode_s16(v.data + i * 2) * FX


func _rotation(anim: Dictionary, v: Dictionary, frame: float) -> Basis:
	if v.constant:
		return _rotation_at(anim, v.index)
	var pos: float = clampf(frame - v.first, 0.0, float(_span(v))) / v.step
	var i := int(floor(pos))
	var t: float = pos - i
	var keys: Array = _keys(anim, v)
	var last: int = keys.size() - 1
	var a: Quaternion = keys[clampi(i, 0, last)]
	if t < 0.001:
		return Basis(a)
	var b: Quaternion = keys[clampi(i + 1, 0, last)]
	if v.step == 1:
		return Basis(a.slerp(b, t))
	return Basis(_smooth_rotation(a, b, keys[clampi(i - 1, 0, last)], keys[clampi(i + 2, 0, last)], t))


## The rotation of every key of an animated value, worked out once.
func _keys(anim: Dictionary, v: Dictionary) -> Array:
	if v.has("keys"):
		return v.keys
	var keys: Array[Quaternion] = []
	for k in _count(v):
		keys.append(_rotation_at(anim, _d.decode_u16(v.data + k * 2)).get_rotation_quaternion())
	v["keys"] = keys
	return keys


## A smooth path from key `a` to key `b` (Catmull-Rom on the quaternion components, with
## the neighbours turned to the same side so that no key sends it the long way round).
static func _smooth_rotation(a: Quaternion, b: Quaternion, before: Quaternion, after: Quaternion, t: float) -> Quaternion:
	if a.dot(b) < 0.0:
		b = -b
	if a.dot(before) < 0.0:
		before = -before
	if b.dot(after) < 0.0:
		after = -after
	var q := Quaternion(
		cubic_interpolate(a.x, b.x, before.x, after.x, t),
		cubic_interpolate(a.y, b.y, before.y, after.y, t),
		cubic_interpolate(a.z, b.z, before.z, after.z, t),
		cubic_interpolate(a.w, b.w, before.w, after.w, t))
	return q.normalized()


func _rotation_at(anim: Dictionary, index: int) -> Basis:
	if index & 0x8000:
		return _pivot(anim.pivots + (index & 0x7FFF) * 6)
	return _matrix(anim.matrices + index * 10)


## Pivot rotation: one matrix element is +-1, a 2x2 block holds cosine and sine.
func _pivot(p: int) -> Basis:
	var flags := _d.decode_u16(p)
	var a := _d.decode_s16(p + 2) * FX
	var b := _d.decode_s16(p + 4) * FX
	var sel := flags & 0xF
	var row := sel / 3
	var col := sel % 3
	var rows: Array[int] = []
	var cols: Array[int] = []
	for i in 3:
		if i != row:
			rows.append(i)
		if i != col:
			cols.append(i)
	var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	m[row][col] = -1.0 if flags & 0x10 else 1.0
	m[rows[0]][cols[0]] = a
	m[rows[0]][cols[1]] = b
	m[rows[1]][cols[0]] = -b if flags & 0x20 else b
	m[rows[1]][cols[1]] = -a if flags & 0x40 else a
	# The DS multiplies row vectors, so its rows are Godot's basis columns.
	return Basis(
		Vector3(m[0][0], m[0][1], m[0][2]),
		Vector3(m[1][0], m[1][1], m[1][2]),
		Vector3(m[2][0], m[2][1], m[2][2]))


## Full matrix from five numbers: the first row, and the first two entries of the second.
## The last entry of the second row follows from it being a unit vector; its sign is
## kept in the lowest bit of the fifth number (1 = negative), which is not part of the
## value. The third row is the cross product of the other two.
func _matrix(p: int) -> Basis:
	var s := 1.0 / 32768.0
	var r0 := Vector3(_d.decode_s16(p), _d.decode_s16(p + 2), _d.decode_s16(p + 4)) * s
	var d := _d.decode_s16(p + 6) * s
	var raw_e := _d.decode_s16(p + 8)
	var e := (raw_e & ~7) * s
	var f := sqrt(maxf(1.0 - d * d - e * e, 0.0))
	if raw_e & 1:
		f = -f
	var r1 := Vector3(d, e, f).normalized()
	return Basis(r0, r1, r0.cross(r1).normalized())
