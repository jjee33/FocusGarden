extends TestCase
## GardenService: expansion unlocks must be deterministic (§65).


func _expansions() -> Array[GardenExpansion]:
	var out: Array[GardenExpansion] = []
	out.append(GardenExpansion.make("plot_a", "A", "", Vector2i(4, 3), 0.0))
	out.append(GardenExpansion.make("plot_b", "B", "", Vector2i(6, 4), 10.0))
	out.append(GardenExpansion.make("plot_c", "C", "", Vector2i(8, 5), 50.0))
	return out


func _context(focus_hours: float) -> RequirementContext:
	var context := RequirementContext.new()
	context.total_focus_minutes = focus_hours * 60.0
	return context


func test_first_plot_is_granted_immediately() -> void:
	var layout := GardenLayout.create()
	var result := GardenService.reconcile(layout, _context(0.0), _expansions())
	assert_eq(result.newly_unlocked.size(), 1, "the zero-hour plot is granted at once")
	assert_true(layout.has_expansion("plot_a"), "and recorded on the layout")


func test_expansions_unlock_at_their_thresholds() -> void:
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(12.0), _expansions())
	assert_true(layout.has_expansion("plot_b"), "12 hours clears the 10 hour step")
	assert_false(layout.has_expansion("plot_c"), "but not the 50 hour one")
	assert_eq(layout.grid_size, Vector2i(6, 4), "the plot grew to match")


func test_reconcile_is_idempotent() -> void:
	# §65's "expansion unlocks are deterministic". Running it repeatedly must not
	# grant anything twice, or the celebration and journal entry would repeat.
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(60.0), _expansions())
	var second := GardenService.reconcile(layout, _context(60.0), _expansions())
	assert_eq(second.newly_unlocked.size(), 0, "a second pass grants nothing new")
	assert_eq(layout.unlocked_expansion_ids.size(), 3, "and does not duplicate ids")


func test_plot_never_shrinks() -> void:
	# A retuned threshold, or a context that momentarily reads lower, must not be
	# able to take ground away from a player who already had it.
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(60.0), _expansions())
	assert_eq(layout.grid_size, Vector2i(8, 5), "the largest plot was granted")

	GardenService.reconcile(layout, _context(0.0), _expansions())
	assert_eq(layout.grid_size, Vector2i(8, 5), "and it survives a zero-focus pass")


func test_next_expansion_reports_the_first_unearned() -> void:
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(12.0), _expansions())
	var next := GardenService.next_expansion(layout, _context(12.0), _expansions())
	assert_not_null(next, "there is another step to come")
	assert_eq(String(next.id), "plot_c", "and it is the 50 hour one")


func test_next_expansion_is_null_when_complete() -> void:
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(500.0), _expansions())
	assert_null(
		GardenService.next_expansion(layout, _context(500.0), _expansions()),
		"nothing is left once every step is earned"
	)


func test_progress_toward_next_expansion() -> void:
	var layout := GardenLayout.create()
	GardenService.reconcile(layout, _context(5.0), _expansions())
	var progress := GardenService.next_expansion_progress(layout, _context(5.0), _expansions())
	assert_almost_eq(progress, 0.5, "5 of the 10 hours needed")


func test_out_of_bounds_detection() -> void:
	var layout := GardenLayout.create()
	layout.grid_size = Vector2i(4, 3)

	var inside := PlantInstance.create(&"pothos")
	inside.move_to_garden(Vector2i(1, 1))
	var outside := PlantInstance.create(&"pothos")
	outside.move_to_garden(Vector2i(9, 9))

	var stranded := GardenService.find_out_of_bounds(layout, [inside, outside])
	assert_eq(stranded.size(), 1, "only the out-of-plot plant is reported")
	assert_eq(stranded[0].uid, outside.uid, "and it is the right one")
