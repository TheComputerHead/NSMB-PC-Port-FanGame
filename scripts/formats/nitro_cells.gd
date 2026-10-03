class_name NitroCells
extends RefCounted
## Reader for the "JNCD" sprite-cell files of the DS menus. A cell is a small group of
## sprites (OAM objects) that together make one picture; the file carries its own 4bpp tiles.
##
## Layout: header 28 bytes (cell count at 6, then the offsets of the cell table, the object
## table and the tile data). Cell = 6 bytes (width, height, first object, object count).
## Object = 12 bytes: attr0, attr1 (DS OAM: y, x, shape, size), palette (high nibble),
## padding, first tile, tile count. Tiles are laid out in "1D" order.

const SIZES := [
	[Vector2i(8, 8), Vector2i(16, 16), Vector2i(32, 32), Vector2i(64, 64)],   # square
	[Vector2i(16, 8), Vector2i(32, 8), Vector2i(32, 16), Vector2i(64, 32)],   # wide
	[Vector2i(8, 16), Vector2i(8, 32), Vector2i(16, 32), Vector2i(32, 64)],   # tall
]

var data: PackedByteArray
var palette: PackedColorArray
var cell_count := 0
var _cells_at := 0
var _objects_at := 0
var _tiles_at := 0


## `palette_data` is the raw BGR555 object palette (16 banks of 16 colours).
static func load_cells(rel: String, palette_rel: String) -> NitroCells:
	var cells := NitroCells.new()
	cells.data = FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + rel)
	cells.palette = Nitro2D.palette(FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + palette_rel))
	cells.cell_count = cells.data.decode_u16(6)
	cells._cells_at = cells.data.decode_u32(8)
	cells._objects_at = cells.data.decode_u32(12)
	cells._tiles_at = cells.data.decode_u32(16)
	return cells


func cell_size(index: int) -> Vector2i:
	var at := _cells_at + index * 6
	return Vector2i(data[at], data[at + 1])


## Draws one cell at its natural size (1 pixel per DS pixel).
func render(index: int) -> Image:
	var at := _cells_at + index * 6
	var size := Vector2i(data[at], data[at + 1])
	var first := data.decode_u16(at + 2)
	var count := data.decode_u16(at + 4)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for k in count:
		var o := _objects_at + (first + k) * 12
		var attr0 := data.decode_u16(o)
		var attr1 := data.decode_u16(o + 2)
		var bank := data.decode_u16(o + 4) >> 12
		var tile := data.decode_u16(o + 8)
		var shape := attr0 >> 14
		var obj_size := attr1 >> 14
		var dims: Vector2i = SIZES[shape][obj_size]
		var x := attr1 & 0x1FF
		if x >= 256:
			x -= 512
		var y := attr0 & 0xFF
		if y >= 128:
			y -= 256
		var tiles_wide := dims.x / 8
		for ty in dims.y / 8:
			for tx in tiles_wide:
				_draw_tile(img, tile + ty * tiles_wide + tx, bank, x + tx * 8, y + ty * 8,
					(attr1 >> 12) & 1 == 1, (attr1 >> 13) & 1 == 1, dims)
	return img


func _draw_tile(img: Image, tile: int, bank: int, x0: int, y0: int, _hflip: bool, _vflip: bool, _dims: Vector2i) -> void:
	var base := _tiles_at + tile * 32
	if base + 32 > data.size():
		return
	for p in 64:
		var b := data[base + (p >> 1)]
		var idx := (b >> 4) if p & 1 else (b & 15)
		if idx == 0:
			continue
		var x := x0 + (p & 7)
		var y := y0 + (p >> 3)
		if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
			continue
		var ci := bank * 16 + idx
		if ci < palette.size():
			img.set_pixel(x, y, palette[ci])
