extends SceneTree
## Rasterises the app icon into the formats the installers need.
##
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tools/render_icons.gd
##
## The exported executables get their icon from assets/ui/app_icon.svg directly,
## but neither installer can: Inno Setup wants a Windows .ico, and appimagetool
## wants a PNG. Rather than keep hand-exported rasters that quietly drift from
## the SVG, this regenerates both from the one source.
##
## The .ico itself is assembled by tools/pack_ico.py, because Godot cannot write
## that container. This script produces the pixels it needs: raw RGBA8, one file
## per size, which pack_ico.py stores as uncompressed DIBs.
##
## Every size is a DIB, including 256, rather than the more usual PNG entry at
## the large sizes. PNG entries are smaller and Explorer reads them, but GDI+
## cannot — System.Drawing throws on them — and an installer icon is worth more
## as universally readable than as 40 KB smaller.
##
## Outputs are committed build artifacts. Re-run this after editing the SVG.

const SOURCE := "res://assets/ui/app_icon.svg"
const SOURCE_SIZE := 256.0

const ICO_SIZES: Array[int] = [16, 32, 48, 64, 128, 256]

const WINDOWS_DIR := "res://packaging/windows/icons"
const LINUX_ICON := "res://packaging/linux/focus-garden.png"
const LINUX_SIZE: int = 256


func _init() -> void:
	var svg := FileAccess.get_file_as_string(SOURCE)
	if svg.is_empty():
		printerr("Could not read %s" % SOURCE)
		quit(1)
		return

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(WINDOWS_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WINDOWS_DIR))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LINUX_ICON).get_base_dir()
	)

	for size: int in ICO_SIZES:
		var image := _render(svg, size)
		if image == null:
			quit(1)
			return
		var path := "%s/icon_%d.rgba" % [WINDOWS_DIR, size]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("Failed to write %s" % path)
			quit(1)
			return
		file.store_buffer(image.get_data())
		file.close()
		print("  %dx%d -> %s" % [size, size, path])

	var linux_icon := _render(svg, LINUX_SIZE)
	if linux_icon == null:
		quit(1)
		return
	var linux_error := linux_icon.save_png(LINUX_ICON)
	if linux_error != OK:
		printerr("Failed to write %s (error %d)" % [LINUX_ICON, linux_error])
		quit(1)
		return
	print("  %dx%d -> %s" % [LINUX_SIZE, LINUX_SIZE, LINUX_ICON])

	print("Icons rendered. Run tools/pack_ico.py to assemble the .ico.")
	quit(0)


## Renders the SVG at a pixel size, always as RGBA8 so the raw buffers written
## for the .ico have a known layout.
func _render(svg: String, size: int) -> Image:
	var image := Image.new()
	var error := image.load_svg_from_string(svg, float(size) / SOURCE_SIZE)
	if error != OK:
		printerr("SVG rasterisation failed at %dpx (error %d)" % [size, error])
		return null
	# ThorVG rounds, and a one-pixel difference would corrupt a raw DIB.
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image
