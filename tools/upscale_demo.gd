extends SceneTree
## Builds a side-by-side comparison of upscaling methods on Mario's textures.
## Usage: godot --headless --script tools/upscale_demo.gd -- <out.png>

const NitroLz := preload("res://scripts/formats/nitro_lz.gd")
const Nsbmd := preload("res://scripts/formats/nsbmd.gd")
const RotSprite := preload("res://scripts/formats/rotsprite.gd")


func _texture(file: String, tex_name: String) -> Image:
	var bytes := NitroLz.decompress(FileAccess.get_file_as_bytes(RomExtractor.RAW_DIR + file))
	var parsed := Nsbmd.new()
	parsed.parse(bytes)
	return parsed.tex.get_image(tex_name, tex_name)


func _init() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0]
	var rows := [
		_texture("player/mario_model_LZ.bin", "n_mario_body"),
		_texture("player/mario_head_cap_LZ.bin", "n_mario_head"),
	]
	var panel := 512
	var sheet := Image.create(panel * 3 + 40, panel * 2 + 30, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.25))
	for r in rows.size():
		var src: Image = rows[r]
		var variants: Array[Image] = []
		var t0 := Time.get_ticks_msec()
		var plain := src.duplicate() as Image
		plain.resize(src.get_width() * 8, src.get_height() * 8, Image.INTERPOLATE_NEAREST)
		variants.append(plain)
		variants.append(RotSprite.upscale(src, 3, 0))
		variants.append(RotSprite.upscale(src, 3, 48))
		print("row ", r, " ", src.get_size(), " upscaled in ", Time.get_ticks_msec() - t0, " ms")
		for v in variants.size():
			var img := variants[v]
			# Fit to the panel (shrinking uses smooth filtering, like the GPU would).
			var s := float(panel) / maxi(img.get_width(), img.get_height())
			if s != 1.0:
				img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(10 + v * (panel + 10), 10 + r * (panel + 10)))
	sheet.save_png(out_path)
	quit()
