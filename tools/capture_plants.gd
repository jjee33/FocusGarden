extends SceneTree
## Renders every species as a contact sheet, for visual review of the painter.
##
##     ... --path . --script res://tools/capture_plants.gd
##
## Needs a real window (no --headless): the painter draws through the renderer,
## so there is nothing to capture without one.
##
## Written because §74 and §75 cannot be checked by a test runner. The only way
## to know whether a procedurally drawn plant actually looks like a plant is to
## look at it, and looking at sixteen of them one at a time in the running app is
## far slower than one sheet.

const OUTPUT_DIR: String = "user://captures"
const COLUMNS: int = 4
const CELL := Vector2i(300, 340)
const GROWTH_STEPS: Array[float] = [0.08, 0.35, 0.7, 1.0]


func _init() -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var content_db := root.get_node("/root/ContentDB")
	var species_list: Array = content_db.get_all_species()
	if species_list.is_empty():
		printerr("No species loaded. Run generate_content.gd first.")
		quit(1)
		return

	await _sheet_all_species(species_list, content_db)
	await _sheet_growth_stages(species_list, content_db)
	await _sheet_pots(content_db)

	print("Plant sheets written to %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


## Every species at full growth, in its default pot.
func _sheet_all_species(species_list: Array, content_db: Node) -> void:
	var rows := int(ceil(float(species_list.size()) / float(COLUMNS)))
	var canvas := _new_canvas(Vector2i(CELL.x * COLUMNS, CELL.y * rows))

	for i in species_list.size():
		var cell := Vector2(
			float(i % COLUMNS) * CELL.x, float(i / COLUMNS) * CELL.y
		)
		_add_plant(canvas, species_list[i], content_db.get_pot(&"terracotta_basic"), cell, 1.0, true)

	await _flush_and_save(canvas, "plants_all.png")


## One species per row, showing the four growth checkpoints side by side, so
## stage progression can be judged as a sequence rather than in isolation.
func _sheet_growth_stages(species_list: Array, content_db: Node) -> void:
	var shown: Array = species_list.slice(0, 8)
	var canvas := _new_canvas(
		Vector2i(CELL.x * GROWTH_STEPS.size(), CELL.y * shown.size())
	)

	for row in shown.size():
		for col in GROWTH_STEPS.size():
			var cell := Vector2(float(col) * CELL.x, float(row) * CELL.y)
			_add_plant(
				canvas, shown[row], content_db.get_pot(&"terracotta_basic"),
				cell, GROWTH_STEPS[col], col == 0
			)

	await _flush_and_save(canvas, "plants_growth.png")


## Every pot design, so the set can be compared for variety and consistency.
func _sheet_pots(content_db: Node) -> void:
	var pots: Array = content_db.get_all_pots()
	var canvas := _new_canvas(Vector2i(CELL.x * pots.size(), CELL.y))

	for i in pots.size():
		var holder := Control.new()
		holder.position = Vector2(float(i) * CELL.x, 0.0)
		holder.custom_minimum_size = Vector2(CELL)
		holder.size = Vector2(CELL)
		canvas.add_child(holder)

		var painter := PotPreview.new()
		painter.pot = pots[i]
		painter.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(painter)

		var label := Label.new()
		label.text = pots[i].display_name
		label.position = Vector2(0.0, CELL.y - 40)
		label.custom_minimum_size.x = CELL.x
		label.size.x = CELL.x
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(label)

	await _flush_and_save(canvas, "pots_all.png")


func _add_plant(
	canvas: Control, species: PlantSpecies, pot: PotStyle, cell: Vector2, growth: float, label: bool
) -> void:
	var holder := Control.new()
	holder.position = cell
	holder.custom_minimum_size = Vector2(CELL)
	holder.size = Vector2(CELL)
	canvas.add_child(holder)

	var view := PlantView.new()
	view.species = species
	view.pot = pot
	view.growth = growth
	view.plant_height = CELL.y - 90
	view.position = Vector2(0.0, 40.0)
	view.size = Vector2(CELL.x, CELL.y - 90)
	holder.add_child(view)

	var caption := Label.new()
	caption.text = species.display_name if label else "%d%%" % int(growth * 100.0)
	caption.position = Vector2(0.0, CELL.y - 44)
	caption.size.x = CELL.x
	caption.custom_minimum_size.x = CELL.x
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(caption)


func _new_canvas(size: Vector2i) -> Control:
	root.size = size
	DisplayServer.window_set_size(size)

	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.theme = load("res://ui/theme/focus_garden.tres")

	var background := ColorRect.new()
	background.color = Palette.bg_base()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)

	root.add_child(canvas)
	return canvas


func _flush_and_save(canvas: Control, file_name: String) -> void:
	# Two frames: one to lay out, one to draw the laid-out result.
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUTPUT_DIR.path_join(file_name))
	canvas.queue_free()
	await process_frame


## Draws a pot alone, for the pot sheet.
class PotPreview extends Control:
	var pot: PotStyle

	func _draw() -> void:
		if pot == null:
			return
		PlantPainter.draw_pot(self, pot, Vector2(size.x * 0.5, size.y * 0.78), size.y * 0.45)
