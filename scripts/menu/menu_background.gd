class_name MenuBackground
extends Control
## Menu background: the ROM's World 1-1 scenery (sky, clouds, pastel domes, Peach's
## castle on its hill), drawn in parallax. The clouds and the domes drift at different
## speeds and the flowers in the grass sway in the wind.

const SKY_COLOR := Color("1890ff")
const NATIVE_HEIGHT := 216.0     # rows of the original layers that are shown
const NATIVE_WIDTH := 512.0      # width of one layer before enlarging
const SPLIT_ROW := 80.0          # row where the clouds end and the domes begin
const CLOUD_SPEED := 10.0        # native pixels per second
const DOME_SPEED := 3.0
const FREE_OFFSET := 312.0       # puts the castle on the right of the screen
const FREE_OFFSET_MENU := 24.0   # ...and on the left when the menu is open
const FADE_TIME := 0.8           # seconds to change from one world's scenery to another

## Wind for the flowers and bushes: moves the picture sideways, more the higher the pixel.
const SWAY_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
uniform float decor = 0.57;
void fragment() {
	float h = clamp((decor - UV.y) / decor, 0.0, 1.0);
	float sway = sin(time * 1.7 + UV.x * 6.28318 * 5.0) * 0.0035 * h;
	COLOR = texture(TEXTURE, vec2(UV.x + sway, UV.y));
}
"""

var target_free_offset := FREE_OFFSET

var _free_offset := FREE_OFFSET
var _back: Texture2D
var _free: Texture2D
var _world := 1
var _old_back: Texture2D       # the previous world's scenery, fading out
var _old_free: Texture2D
var _old_world := 1
var _fade := 1.0               # 0..1, how far the new scenery has faded in
var _themes := {}              # world -> [back, free] textures
var _ground: GroundLayer
var _time := 0.0


## The strip of grass and flowers, with the wind effect.
class GroundLayer extends Control:
	var texture: Texture2D
	var native_scale := 1.0
	var _material: ShaderMaterial

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var shader := Shader.new()
		shader.code = MenuBackground.SWAY_SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("decor", MenuAssets.DECOR_ROWS / float(MenuAssets.DECOR_ROWS + MenuAssets.GROUND_BLOCKS.y))
		material = _material

	func set_time(t: float) -> void:
		_material.set_shader_parameter("time", t)

	func _draw() -> void:
		if texture == null:
			return
		var w := MenuBackground.NATIVE_WIDTH * native_scale
		var x := 0.0
		while x < size.x:
			draw_texture_rect(texture, Rect2(x, 0, w, size.y), false)
			x += w


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if MenuAssets.ensure():
		_back = _load(MenuAssets.BACK)
		_free = _load(MenuAssets.FREE)
		_ground = GroundLayer.new()
		_ground.texture = _load(MenuAssets.GROUND)
		add_child(_ground)
	resized.connect(_layout)
	_layout()


## Shows the scenery of a world (1-8), fading from the previous one. The pictures of a
## world are built the first time it is shown (a short pause), then kept on disk.
func set_world(world: int) -> void:
	world = clampi(world, 1, 8)
	if world == _world or _back == null:
		return
	if not _themes.has(world):
		if not MenuAssets.ensure_theme(world):
			return
		_themes[world] = [_load(MenuAssets.theme_path(world, "back")), _load(MenuAssets.theme_path(world, "free"))]
	_old_back = _back
	_old_free = _free
	_old_world = _world
	_world = world
	_back = _themes[world][0]
	_free = _themes[world][1]
	_fade = 0.0
	if Time.get_ticks_msec() > 3000:   # not while the menu is starting
		GameAudio.play_sound("SAR_MENU", "SE_SYS_WORLD_CHG")


## Ends a running change of scenery at once.
func finish_fade() -> void:
	_fade = 1.0



static func _load(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _layout() -> void:
	if _ground == null:
		return
	var scale := size.y / NATIVE_HEIGHT
	var strip_h := (MenuAssets.DECOR_ROWS + MenuAssets.GROUND_BLOCKS.y) * 16.0 * scale
	_ground.native_scale = scale
	_ground.position = Vector2(0, size.y - strip_h)
	_ground.size = Vector2(size.x, strip_h)
	_ground.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_free_offset = lerpf(_free_offset, target_free_offset, 1.0 - exp(-delta * 2.2))
	_fade = minf(_fade + delta / FADE_TIME, 1.0)
	if _ground:
		_ground.set_time(_time)
		# The grass strip belongs to the first world only.
		var grass := (_fade if _world == 1 else 0.0) + ((1.0 - _fade) if _old_world == 1 else 0.0)
		_ground.modulate.a = clampf(grass, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SKY_COLOR)
	if _back == null:
		return
	var scale := size.y / NATIVE_HEIGHT
	if _fade < 1.0 and _old_back != null:
		_draw_scenery(_old_back, _old_free, _old_world, scale, 1.0)
	_draw_scenery(_back, _free, _world, scale, _fade)


## One world's layers. The first world keeps its clouds / domes split and its castle;
## the others are a single drifting back layer and a front layer.
func _draw_scenery(back: Texture2D, free: Texture2D, world: int, scale: float, alpha: float) -> void:
	if world == 1:
		_draw_band(back, scale, -_time * CLOUD_SPEED * scale, 0.0, SPLIT_ROW, alpha)
		_draw_band(back, scale, -_time * DOME_SPEED * scale, SPLIT_ROW, NATIVE_HEIGHT, alpha)
		_draw_band(free, scale, -_free_offset * scale, 0.0, NATIVE_HEIGHT, alpha)
	else:
		_draw_band(back, scale, -_time * DOME_SPEED * scale, 0.0, NATIVE_HEIGHT, alpha)
		_draw_band(free, scale, -_free_offset * scale, 0.0, NATIVE_HEIGHT, alpha)


## Draws rows [row_from, row_to) of a layer repeated horizontally, starting `offset`
## pixels from the left edge.
func _draw_band(tex: Texture2D, scale: float, offset: float, row_from: float, row_to: float, alpha := 1.0) -> void:
	var w := NATIVE_WIDTH * scale
	var x := fposmod(offset, w) - w
	var factor := tex.get_height() / NATIVE_HEIGHT
	var source := Rect2(0, row_from * factor, tex.get_width(), (row_to - row_from) * factor)
	var tint := Color(1, 1, 1, alpha)
	while x < size.x:
		draw_texture_rect_region(tex, Rect2(x, row_from * scale, w, (row_to - row_from) * scale), source, tint)
		x += w
