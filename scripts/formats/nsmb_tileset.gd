class_name NsmbTileset
extends RefCounted
## A level tileset: 8x8 tile graphics, a palette, "Map16" blocks (16x16 pixels made of
## 2x2 tiles, 8 bits per pixel) and object definitions (how a level object like a ground strip or a pipe
## is made of Map16 blocks and how it stretches).

const NitroLz := preload("res://scripts/formats/nitro_lz.gd")
const Nitro2D := preload("res://scripts/formats/nitro_2d.gd")

var tiles: Array[PackedByteArray] = []
var palette := PackedColorArray()
var map16 := PackedInt32Array()      # 4 entries per block: TL, TR, BL, BR (u16 tile refs)
var _obj_index := PackedByteArray()
var _obj_data := PackedByteArray()
var tile_base := 0       # tile number of the first tile in this set (blocks use a tile space shared between sets)
var bank_base := 0       # palette bank of the first 256-colour set in the palette file
var companion: NsmbTileset   # the other set sharing the tile space (e.g. the common set)
var _block_cache := {}


## Each argument is the raw (still LZ-compressed, if it was) file content.
func setup(ncg: PackedByteArray, ncl: PackedByteArray, pa: PackedByteArray,
		objects: PackedByteArray, objects_hd: PackedByteArray) -> void:
	tiles = Nitro2D.tiles(_unpack(ncg), 8)
	palette = Nitro2D.palette(_unpack(ncl))
	var blocks := _unpack(pa)
	for i in blocks.size() / 2:
		map16.append(blocks.decode_u16(i * 2))
	_obj_data = _unpack(objects)
	_obj_index = _unpack(objects_hd)


static func _unpack(bytes: PackedByteArray) -> PackedByteArray:
	return NitroLz.decompress(bytes) if NitroLz.is_compressed(bytes) else bytes


func block_count() -> int:
	return map16.size() / 4


func object_count() -> int:
	return _obj_index.size() / 4


## Object definition as rows of tiles: [[{flags, block}, ...], ...].
func definition(id: int) -> Array:
	var rows: Array = []
	if id < 0 or id >= object_count():
		return rows
	var p := _obj_index.decode_u16(id * 4)
	var row: Array = []
	while p < _obj_data.size():
		var b := _obj_data[p]
		if b == 0xFF:
			break
		if b == 0xFE:
			rows.append(row)
			row = []
			p += 1
			continue
		if b & 0x80:
			# Slope data: not supported yet, skip the marker and its tile.
			p += 1
			continue
		row.append({"flags": b, "block": _obj_data[p + 1] + maxi(_obj_data[p + 2] - 1, 0) * 256})
		p += 3
	if not row.is_empty():
		rows.append(row)
	return rows


## Lays an object out over a width x height area of blocks.
## Returns [{x, y, block}, ...] in block units.
func expand(id: int, width: int, height: int) -> Array:
	var rows := definition(id)
	var out: Array = []
	if rows.is_empty():
		return out

	# Vertical: rows flagged "repeat Y" form the stretchable middle section.
	var row_ids: Array = []
	for r in rows.size():
		row_ids.append(r)
	var rep_rows: Array = []
	for r in rows.size():
		for t: Dictionary in rows[r]:
			if t.flags & 2:
				rep_rows.append(r)
				break
	var final_rows: Array = _stretch(row_ids, rep_rows, height)

	for y in final_rows.size():
		var row: Array = rows[final_rows[y]]
		var col_ids: Array = []
		var rep_cols: Array = []
		for c in row.size():
			col_ids.append(c)
			if row[c].flags & 1:
				rep_cols.append(c)
		var final_cols: Array = _stretch(col_ids, rep_cols, width)
		for x in final_cols.size():
			out.append({"x": x, "y": y, "block": row[final_cols[x]].block})
	return out


## Returns `target` indices: the fixed ones around the repeatable section, with the
## repeatable section cycled to fill the space.
static func _stretch(all: Array, repeat: Array, target: int) -> Array:
	if repeat.is_empty():
		return all.slice(0, target) if all.size() > target else all
	var first: int = repeat[0]
	var last: int = repeat[repeat.size() - 1]
	var before: Array = all.slice(0, first)
	var after: Array = all.slice(last + 1)
	var middle: Array = all.slice(first, last + 1)
	var out: Array = before.duplicate()
	var fill := target - before.size() - after.size()
	for i in maxi(fill, 0):
		out.append(middle[i % middle.size()])
	out.append_array(after)
	return out


## 16x16 image of a Map16 block.
func block_image(index: int) -> Image:
	if _block_cache.has(index):
		return _block_cache[index]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	if index >= 0 and index < block_count():
		for q in 4:
			var ref := map16[index * 4 + q]
			var tile_no := ref & 0x3FF
			var bank_no := ref >> 12
			var hflip := (ref >> 10) & 1 == 1
			var vflip := (ref >> 11) & 1 == 1
			var src: NsmbTileset = self
			if not _owns(tile_no, bank_no):
				if companion and companion._owns(tile_no, bank_no):
					src = companion
				else:
					continue
			var px := src.tiles[tile_no - src.tile_base]
			var bank := bank_no - src.bank_base
			for p in 64:
				var idx := px[p]
				if idx == 0:
					continue
				var x := p & 7
				var y := p >> 3
				if hflip:
					x = 7 - x
				if vflip:
					y = 7 - y
				var ci := bank * 256 + idx
				if ci < src.palette.size():
					img.set_pixel((q & 1) * 8 + x, (q >> 1) * 8 + y, src.palette[ci])
	_block_cache[index] = img
	return img


## True if this set has the tile and the palette bank a block refers to.
func _owns(tile_no: int, bank_no: int) -> bool:
	var tile := tile_no - tile_base
	var bank := bank_no - bank_base
	return tile >= 0 and tile < tiles.size() and bank >= 0 and bank * 256 < palette.size()


## Natural size of an object in blocks (before it is stretched).
func object_size(id: int) -> Vector2i:
	if id < 0 or id >= object_count():
		return Vector2i.ZERO
	return Vector2i(_obj_index[id * 4 + 2], _obj_index[id * 4 + 3])
