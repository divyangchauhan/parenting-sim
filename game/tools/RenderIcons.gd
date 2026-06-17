extends SceneTree
## RenderIcons — rasterizes the Android launcher icons from SVG sources.
##
## One-off tooling, run headless:
##   godot --headless --path game --script tools/RenderIcons.gd
##
## Produces PNGs in res://assets/icons/ that export_presets.cfg points at.
## No SVG rasterizer (rsvg/inkscape/imagemagick) is required — Godot does it.


## Source SVG -> output PNG at a fixed pixel size.
class IconSpec:
	var src: String
	var dst: String
	var size: int

	func _init(p_src: String, p_dst: String, p_size: int) -> void:
		src = p_src
		dst = p_dst
		size = p_size


func _init() -> void:
	var specs: Array[IconSpec] = [
		IconSpec.new("res://assets/icons/icon_store.svg", "res://assets/icons/icon_store_512.png", 512),
		IconSpec.new("res://assets/icons/icon_fg.svg", "res://assets/icons/icon_foreground_432.png", 432),
		IconSpec.new("res://assets/icons/icon_bg.svg", "res://assets/icons/icon_background_432.png", 432),
	]

	var failures: int = 0
	for spec in specs:
		if not _render(spec):
			failures += 1

	if failures > 0:
		push_error("RenderIcons: %d icon(s) failed to render" % failures)
		quit(1)
		return

	print("RenderIcons: all icons rendered OK")
	quit(0)


## Rasterize a single SVG to PNG at the requested square size. Returns success.
func _render(spec: IconSpec) -> bool:
	var svg_text: String = FileAccess.get_file_as_string(spec.src)
	if svg_text.is_empty():
		push_error("RenderIcons: could not read %s" % spec.src)
		return false

	var img := Image.new()
	# The source viewBox is square; scale = target_px / native_px.
	var native: float = _native_width(svg_text)
	if native <= 0.0:
		push_error("RenderIcons: could not parse width of %s" % spec.src)
		return false

	var scale: float = float(spec.size) / native
	var err: int = img.load_svg_from_string(svg_text, scale)
	if err != OK:
		push_error("RenderIcons: load_svg_from_string failed for %s (err %d)" % [spec.src, err])
		return false

	# Guard against off-by-one rounding so the PNG is exactly the requested size.
	if img.get_width() != spec.size or img.get_height() != spec.size:
		img.resize(spec.size, spec.size, Image.INTERPOLATE_LANCZOS)

	var write_err: int = img.save_png(spec.dst)
	if write_err != OK:
		push_error("RenderIcons: save_png failed for %s (err %d)" % [spec.dst, write_err])
		return false

	print("  rendered %s (%dx%d)" % [spec.dst, img.get_width(), img.get_height()])
	return true


## Pull the `width="N"` attribute out of an SVG header.
func _native_width(svg_text: String) -> float:
	var regex := RegEx.new()
	regex.compile("width=\"([0-9.]+)\"")
	var m: RegExMatch = regex.search(svg_text)
	if m == null:
		return -1.0
	return m.get_string(1).to_float()
