class_name Nitro2D
extends RefCounted
## Decoders for the DS 2D graphics NSMB stores as raw LZ77 files:
## palettes (*_ncl.bin), tile graphics (*_ncg.bin) and tile maps (*_nsc.bin).


## Reads a file from the extracted ROM, decompressing it if needed.
static func load_raw(rel: String) -> PackedByteArray:
	var path := rel if rel.begins_with("user://") else RomExtractor.RAW_DIR + rel
	var bytes := FileAccess.get_file_as_bytes(path)
	return NitroLz.decompress(bytes) if NitroLz.is_compressed(bytes) else bytes


## BGR555 palette -> colours. Index 0 of every 16/256 colour set is the transparent one.
static func palette(data: PackedByteArray) -> PackedColorArray:
	var out := PackedColorArray()
	for i in data.size() / 2:
		var c := data.decode_u16(i * 2)
		out.append(Color((c & 31) / 31.0, ((c >> 5) & 31) / 31.0, ((c >> 10) & 31) / 31.0))
	return out


## Splits raw tile data into 8x8 tiles of palette indices (bpp is 4 or 8).
static func tiles(data: PackedByteArray, bpp: int) -> Array[PackedByteArray]:
	var size := 32 if bpp == 4 else 64
	var out: Array[PackedByteArray] = []
	for t in data.size() / size:
		var px := PackedByteArray()
		px.resize(64)
		for i in 64:
			if bpp == 8:
				px[i] = data[t * size + i]
			else:
				var b := data[t * size + (i >> 1)]
				px[i] = (b >> 4) if i & 1 else (b & 15)
		out.append(px)
	return out


## Tile map entries: [{tile, hflip, vflip, bank}, ...] (16-bit "text" background format).
static func tile_map(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in data.size() / 2:
		var e := data.decode_u16(i * 2)
		out.append({
			"tile": e & 0x3FF,
			"hflip": (e >> 10) & 1 == 1,
			"vflip": (e >> 11) & 1 == 1,
			"bank": e >> 12,
		})
	return out


## Draws a tile map into an image. `map_w` is the width in tiles.
static func render_map(map: Array[Dictionary], map_w: int, tile_set: Array[PackedByteArray],
		pal: PackedColorArray, bpp: int, bank_override := -1, tile_base := 0, bank_base := 0) -> Image:
	var map_h := map.size() / map_w
	var img := Image.create(map_w * 8, map_h * 8, false, Image.FORMAT_RGBA8)
	for i in map.size():
		var e: Dictionary = map[i]
		var tile_no: int = e.tile - tile_base
		if tile_no < 0 or tile_no >= tile_set.size():
			continue
		var px := tile_set[tile_no]
		var base: int = (e.bank - bank_base) * 256 if bpp == 8 else (e.bank if bank_override < 0 else bank_override) * 16
		for p in 64:
			var idx := px[p]
			if idx == 0:
				continue
			var x := p & 7
			var y := p >> 3
			if e.hflip:
				x = 7 - x
			if e.vflip:
				y = 7 - y
			var ci: int = base + idx
			if ci < pal.size():
				img.set_pixel((i % map_w) * 8 + x, (i / map_w) * 8 + y, pal[ci])
	return img


## Lays all tiles out in a grid (for inspecting a tile sheet).
static func render_sheet(tile_set: Array[PackedByteArray], pal: PackedColorArray, bank: int,
		bpp: int, columns := 16) -> Image:
	var rows := (tile_set.size() + columns - 1) / columns
	var img := Image.create(columns * 8, maxi(rows, 1) * 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1))
	var base: int = 0 if bpp == 8 else bank * 16
	for t in tile_set.size():
		for p in 64:
			var idx := tile_set[t][p]
			var ci: int = base + idx
			var c := Color(0, 0, 0, 0) if idx == 0 else (pal[ci] if ci < pal.size() else Color.RED)
			if idx != 0 or true:
				img.set_pixel((t % columns) * 8 + (p & 7), (t / columns) * 8 + (p >> 3), c if idx != 0 else Color(0.8, 0.8, 0.8))
	return img


## DS backgrounds larger than 256x256 are stored as 32x32 "screen blocks" one after
## another. Returns {map, width} with the blocks rearranged into one row-major map.
static func arrange_blocks(map: Array[Dictionary]) -> Dictionary:
	var count := map.size() / 1024
	if count <= 1:
		return {"map": map, "width": 32}
	var cols := 2 if count >= 2 else 1
	var rows := (count + cols - 1) / cols
	var out: Array[Dictionary] = []
	out.resize(cols * 32 * rows * 32)
	for b in count:
		var bx := (b % cols) * 32
		var by := (b / cols) * 32
		for i in 1024:
			out[(by + i / 32) * cols * 32 + bx + i % 32] = map[b * 1024 + i]
	return {"map": out, "width": cols * 32}
