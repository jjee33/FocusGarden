extends TestCase
## PlantInstance placement: a plant is in exactly one place (§62).


func test_a_new_plant_starts_in_the_collection() -> void:
	var plant := PlantInstance.create(&"pothos")
	assert_eq(plant.location, PlantInstance.Location.INVENTORY, "and nowhere else")
	assert_eq(plant.shelf_slot, -1, "with no shelf slot")
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "and no garden cell")


func test_moving_to_the_shelf_clears_the_garden_cell() -> void:
	var plant := PlantInstance.create(&"pothos")
	plant.move_to_garden(Vector2i(2, 2))
	plant.move_to_shelf(4)

	assert_eq(plant.location, PlantInstance.Location.SHELF, "it is on the shelf")
	assert_eq(plant.shelf_slot, 4, "in the right slot")
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "and no longer in the garden")


func test_moving_to_the_garden_clears_the_shelf_slot() -> void:
	var plant := PlantInstance.create(&"pothos")
	plant.move_to_shelf(3)
	plant.move_to_garden(Vector2i(1, 1))

	assert_eq(plant.location, PlantInstance.Location.GARDEN, "it is in the garden")
	assert_eq(plant.garden_cell, Vector2i(1, 1), "in the right cell")
	assert_eq(plant.shelf_slot, -1, "and no longer on the shelf")


func test_returning_to_the_collection_clears_both() -> void:
	var plant := PlantInstance.create(&"pothos")
	plant.move_to_shelf(2)
	plant.move_to_inventory()

	assert_eq(plant.location, PlantInstance.Location.INVENTORY, "back in the collection")
	assert_eq(plant.shelf_slot, -1, "with no slot")
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "and no cell")


func test_a_save_claiming_two_places_is_repaired_on_load() -> void:
	# A hand-edited save, or one written by a buggy build, could carry both a
	# shelf slot and a garden cell. `location` is the authority and the rest is
	# reconciled to it, so the duplicate-placement bug cannot survive a load.
	var plant := PlantInstance.from_dict({
		"uid": "pl_test-00000000",
		"species_id": "pothos",
		"location": int(PlantInstance.Location.SHELF),
		"shelf_slot": 5,
		"garden_cell_x": 3,
		"garden_cell_y": 2,
	})

	assert_eq(plant.location, PlantInstance.Location.SHELF, "the stored location wins")
	assert_eq(plant.shelf_slot, 5, "its slot is kept")
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "and the contradictory cell is dropped")


func test_an_inventory_plant_with_stale_coordinates_is_repaired() -> void:
	var plant := PlantInstance.from_dict({
		"uid": "pl_test-00000001",
		"species_id": "aloe_vera",
		"location": int(PlantInstance.Location.INVENTORY),
		"shelf_slot": 7,
		"garden_cell_x": 1,
		"garden_cell_y": 1,
	})

	assert_eq(plant.shelf_slot, -1, "a plant in the collection holds no slot")
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "and no cell")


func test_placement_survives_a_serialization_round_trip() -> void:
	var plant := PlantInstance.create(&"monstera")
	plant.move_to_garden(Vector2i(4, 2))
	plant.pot_id = &"woven_basket"
	plant.favorite = true

	var restored := PlantInstance.from_dict(plant.to_dict())
	assert_eq(restored.location, PlantInstance.Location.GARDEN, "location survives")
	assert_eq(restored.garden_cell, Vector2i(4, 2), "cell survives")
	assert_eq(String(restored.pot_id), "woven_basket", "pot survives")
	assert_true(restored.favorite, "favourite survives")


# --- Facings ------------------------------------------------------------------
# A facing is cosmetic, like the pot, but it lives on the plant rather than on
# the layout — the plant carries where it stands AND which way it looks, so the
# two can never disagree.

func test_a_facing_wraps_rather_than_running_away() -> void:
	var plant := PlantInstance.create(&"monstera")
	plant.move_to_garden(Vector2i(1, 1))
	for _i in PlantInstance.GARDEN_ROTATIONS:
		plant.rotate_in_garden()
	assert_eq(plant.garden_rotation, 0, "four quarter turns is back where it started")

	plant.rotate_in_garden(-1)
	assert_eq(plant.garden_rotation, 3, "turning back from zero wraps to the last facing")


func test_returning_to_the_collection_forgets_the_facing() -> void:
	var plant := PlantInstance.create(&"monstera")
	plant.move_to_garden(Vector2i(2, 0), 2)
	assert_eq(plant.garden_rotation, 2, "a plant can be placed already turned")

	plant.move_to_inventory()
	assert_eq(plant.garden_rotation, 0, "a facing means nothing off the plot")


func test_a_facing_survives_a_serialization_round_trip() -> void:
	var plant := PlantInstance.create(&"monstera")
	plant.move_to_garden(Vector2i(3, 2), 3)
	var restored := PlantInstance.from_dict(plant.to_dict())
	assert_eq(restored.garden_rotation, 3, "the facing came back")
	assert_eq(restored.garden_cell, Vector2i(3, 2), "so did the cell")


func test_an_out_of_range_facing_in_a_save_is_repaired() -> void:
	var data := PlantInstance.create(&"monstera").to_dict()
	data["location"] = int(PlantInstance.Location.GARDEN)
	data["garden_cell_x"] = 1
	data["garden_cell_y"] = 1
	data["garden_rotation"] = 9
	assert_eq(
		PlantInstance.from_dict(data).garden_rotation, 1,
		"a hand-edited facing is wrapped into range rather than trusted"
	)


# --- Ornaments ----------------------------------------------------------------

func test_an_ornament_records_its_facing() -> void:
	var layout := GardenLayout.create()
	layout.set_decoration(Vector2i(1, 2), "stone_bench", 1)
	assert_eq(layout.get_decoration_id(Vector2i(1, 2)), "stone_bench", "the ornament is there")
	assert_eq(layout.get_decoration_rotation(Vector2i(1, 2)), 1, "and it is turned")

	assert_true(layout.rotate_decoration(Vector2i(1, 2)), "rotating an occupied cell reports success")
	assert_eq(layout.get_decoration_rotation(Vector2i(1, 2)), 2, "a quarter turn further")
	assert_false(layout.rotate_decoration(Vector2i(0, 0)), "rotating an empty cell does nothing")


func test_a_layout_reads_the_old_bare_string_shape() -> void:
	# Format 1 stored the id alone. The migration converts it, but the model still
	# accepts it so a save that skipped the migration is not a crash.
	var layout := GardenLayout.from_dict({"decorations": {"0,1": "garden_lantern"}})
	assert_eq(layout.get_decoration_id(Vector2i(0, 1)), "garden_lantern", "the id was read")
	assert_eq(layout.get_decoration_rotation(Vector2i(0, 1)), 0, "and defaults to unturned")


func test_an_ornament_survives_a_serialization_round_trip() -> void:
	var layout := GardenLayout.create()
	layout.set_decoration(Vector2i(2, 1), "stone_bench", 3)
	var restored := GardenLayout.from_dict(layout.to_dict())
	assert_eq(restored.get_decoration_rotation(Vector2i(2, 1)), 3, "the facing came back")
