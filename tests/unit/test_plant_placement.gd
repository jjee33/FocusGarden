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
