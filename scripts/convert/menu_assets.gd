class_name MenuAssets
extends RefCounted
## Builds the menu background images from the ROM's World 1-1 background layers
## (the same sky, clouds, domes and castle as the original title screen), then
## enlarges them with RotSprite. Run once; the PNGs are kept in user://assets/ui/.

const DIR := "user://assets/ui/"
const BACK := DIR + "menu_back.png"
const FREE := DIR + "menu_free.png"
const GROUND := DIR + "menu_ground.png"

## Rows of the 512x512 layers kept (the top is plain sky, which the menu fills itself).
const CROP_TOP := 296
const UPSCALE_PASSES := 2

# layer name -> [first tile number, first palette bank]
const LAYERS := {
	"back": [576, 10],
	"free": [256, 8],
}


static func ready() -> bool:
	return FileAccess.file_exists(BACK) and FileAccess.file_exists(FREE) and FileAccess.file_exists(GROUND)


## Builds the images if they do not exist yet. Returns true when they are available.
static func ensure() -> bool:
	if ready():
		return true
	if not RomExtractor.is_extracted():
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	for layer: String in LAYERS:
		var img := _render_layer(layer)
		if img == null:
			return false
		var crop := img.get_region(Rect2i(0, CROP_TOP, img.get_width(), img.get_height() - CROP_TOP))
		var big := RotSprite.upscale(crop, UPSCALE_PASSES, 40)
		big.save_png(DIR + "menu_%s.png" % layer)
	var ground := _render_ground()
	if ground == null:
		return false
	RotSprite.upscale(ground, UPSCALE_PASSES, 40).save_png(GROUND)
	return ready()


## Scenery for the worlds other than the first: world -> [graphics name, tile map name].
## The mapping is a best guess from the look of each set of layers.
const THEMES := {
	2: ["sabaku", "sabaku_UR"],               # desert, pyramid
	3: ["setsugen", "setsugen_UR"],           # snowy pines
	4: ["nohara2", "nohara2_UR"],             # giant spotted mushrooms
	5: ["dokan_W4", "dokan_W4_UR"],           # forest and clouds
	6: ["kinoko3", "kinoko3_UR"],             # above the clouds
	7: ["dokan_W5", "dokan_W5_UR"],           # frozen night
	8: ["koopa_iwa", "koopa_iwa_UR"],         # Bowser's land
}


## The first world uses the original menu pictures; the others are built on demand.
static func theme_path(world: int, layer: String) -> String:
	if world == 1 or not THEMES.has(world):
		return BACK if layer == "back" else FREE
	return DIR + "menu_%s_w%d.png" % [layer, world]


static func theme_ready(world: int) -> bool:
	return FileAccess.file_exists(theme_path(world, "back")) and FileAccess.file_exists(theme_path(world, "free"))


## Builds the pictures of a world's scenery if needed. Returns true when they exist.
static func ensure_theme(world: int) -> bool:
	if world == 1 or not THEMES.has(world):
		return ensure()
	if theme_ready(world):
		return true
	if not RomExtractor.is_extracted():
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	var names: Array = THEMES[world]
	for layer: String in LAYERS:
		var img := _render_layer(layer, "d_2d_I_M_%s_%s" % [layer, names[0]], "d_2d_I_M_%s_%s" % [layer, names[1]])
		if img == null:
			return false
		var crop := img.get_region(Rect2i(0, CROP_TOP, img.get_width(), img.get_height() - CROP_TOP))
		RotSprite.upscale(crop, UPSCALE_PASSES, 40).save_png(theme_path(world, layer))
	return theme_ready(world)


static func _render_layer(layer: String, graphics := "", map_name := "") -> Image:
	var base := "d_2d_I_M_%s_nohara_W1_1" % layer
	if graphics == "":
		graphics = base
		map_name = base
	var ncg := Nitro2D.load_raw("BG_ncg/%s_ncg.bin" % graphics)
	var ncl := Nitro2D.load_raw("BG_ncl/%s_ncl.bin" % graphics)
	var nsc := Nitro2D.load_raw("BG_nsc/%s_nsc.bin" % map_name)
	if ncg.is_empty() or ncl.is_empty() or nsc.is_empty():
		return null
	var params: Array = LAYERS[layer]
	var map := Nitro2D.tile_map(nsc)
	return Nitro2D.render_map(map, 64, Nitro2D.tiles(ncg, 8), Nitro2D.palette(ncl), 8,
		-1, params[0], params[1])


## Number of 16px rows above the grass reserved for flowers, bushes and the fence.
const DECOR_ROWS := 4
## Ground strip size in 16x16 blocks.
const GROUND_BLOCKS := Vector2i(32, 3)

# [object id, x in blocks]: scenery standing on the grass, from the grassland tileset.
const DECOR := [
	[33, 1],    # big bush
	[59, 8],    # blue flower
	[62, 12],   # patch of blue flowers
	[34, 17],   # small bush
	[60, 22],   # pink flowers
	[47, 26],   # wooden fence
]


## Grass on top, dirt below, and the flowers/bushes/fence standing on it. 512 px wide
## so it repeats seamlessly like the other layers.
static func _render_ground() -> Image:
	var tileset := Tilesets.grassland()
	if tileset.object_count() == 0:
		return null
	var rows := DECOR_ROWS + GROUND_BLOCKS.y
	var img := Image.create(GROUND_BLOCKS.x * 16, rows * 16, false, Image.FORMAT_RGBA8)
	_stamp(img, tileset, 0, Vector2i(0, DECOR_ROWS + 1), Vector2i(GROUND_BLOCKS.x, GROUND_BLOCKS.y - 1))
	_stamp(img, tileset, 10, Vector2i(0, DECOR_ROWS), Vector2i(GROUND_BLOCKS.x, 1))
	for d: Array in DECOR:
		var natural := tileset.object_size(d[0])
		_stamp(img, tileset, d[0], Vector2i(d[1], DECOR_ROWS - natural.y), natural)
	return img


static func _stamp(img: Image, tileset: NsmbTileset, object_id: int, at: Vector2i, size: Vector2i) -> void:
	for t: Dictionary in tileset.expand(object_id, size.x, size.y):
		img.blend_rect(tileset.block_image(t.block), Rect2i(0, 0, 16, 16),
			Vector2i((at.x + t.x) * 16, (at.y + t.y) * 16))
