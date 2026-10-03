class_name HudIcons
extends RefCounted
## Small pictures of the original game's world-map screen (the Mario / Luigi emblems, the
## "World" lettering, the Star Coin), cut from its sprite cells and enlarged with RotSprite.

const CELLS := "uiStudio/UI_O_1P_course_select_d.nce.bncd"
const PALETTE := "uiStudio/UI_O_1P_course_select_o_ud_ncl.bin"

# name -> [cell index, region to keep (Rect2i, or empty for the whole cell)]
const PICTURES := {
	"mario": [21, Rect2i()],
	"luigi": [22, Rect2i()],
	"world": [18, Rect2i(0, 0, 66, 17)],
	"star_coin": [47, Rect2i(0, 0, 17, 16)],
	"coin": [-1, Rect2i()],   # not a cell: drawn from the level tileset
}

const COIN_OBJECT := 21   # a lone coin in the common tileset's object list

static var _cells: NitroCells
static var _cache := {}


## The coin as the levels draw it: one 16x16 block of the common tileset.
static func _level_coin() -> Image:
	var tileset := Tilesets.grassland().companion
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for t: Dictionary in tileset.expand(COIN_OBJECT, 3, 3):
		if t.x == 0 and t.y == 0:
			img.blend_rect(tileset.block_image(t.block), Rect2i(0, 0, 16, 16), Vector2i.ZERO)
	return img


## The picture as a texture, or null when the ROM has not been extracted.
static func texture(picture: String) -> Texture2D:
	if _cache.has(picture):
		return _cache[picture]
	if not PICTURES.has(picture) or not RomExtractor.is_extracted():
		return null
	var img: Image
	if picture == "coin":
		img = _level_coin()
	else:
		if _cells == null:
			_cells = NitroCells.load_cells(CELLS, PALETTE)
		var params: Array = PICTURES[picture]
		img = _cells.render(params[0])
		var region: Rect2i = params[1]
		if region.size != Vector2i.ZERO:
			img = img.get_region(region)
	img = RotSprite.upscale(img, 2, Settings.SMOOTHING_TOLERANCE) if Settings.texture_smoothing else img
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[picture] = tex
	return tex
