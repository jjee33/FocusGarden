class_name BotanicalInfo
extends Resource
## Real-world plant facts shown in the catalogue (§17).
##
## Deliberately a separate resource from PlantSpecies so factual text can be
## corrected without touching anything gameplay reads (§17). Nothing in this file
## may ever influence growth, XP, or unlocks — it is presentation only.

@export var family: String = ""
@export var native_region: String = ""
@export var light_preference: String = ""
@export var watering_preference: String = ""
## Free text ("Easy", "Fussy about humidity") rather than a number: this is the
## real plant's care difficulty for flavor, NOT the game's focus difficulty.
@export var care_difficulty: String = ""
@export_multiline var interesting_fact: String = ""


func is_populated() -> bool:
	return not family.is_empty() or not interesting_fact.is_empty()
