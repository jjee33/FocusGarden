class_name Requirement
extends Resource
## One condition, evaluated by one engine (§48).
##
## §48 is explicit that plant unlocks, achievements, expeditions, garden upgrades
## and cosmetic unlocks must NOT each grow their own condition engine. They all
## use this type, and RequirementEvaluator is the only thing that interprets it.
##
## Requirements return a RATIO, not just a boolean. Plant growth needs a
## continuous 0..1 progress value to pick a growth stage and drive a progress bar,
## and achievements need the same number for "7 of 10 plants matured". One
## evaluation path serves both, so a plant's maturity rule and an achievement's
## unlock rule are literally the same kind of object.
##
## Static content — authored as .tres in data/.

enum Type {
	TOTAL_FOCUS_MINUTES,     ## params: amount: float
	COMPLETED_SESSIONS,      ## params: count: int
	UNIQUE_FOCUS_DAYS,       ## params: count: int
	CONSECUTIVE_DAYS,        ## params: count: int
	SESSIONS_IN_TIME_WINDOW, ## params: count: int, start_hour: int, end_hour: int
	SESSION_LENGTH_AT_LEAST, ## params: minutes: float, count: int
	BREAK_SESSIONS,          ## params: count: int
	PLANTS_MATURED,          ## params: count: int
	SPECIES_DISCOVERED,      ## params: count: int
	PLAYER_LEVEL,            ## params: level: int
	CATALOGUE_COMPLETION,    ## params: ratio: float
	ACHIEVEMENT_UNLOCKED,    ## params: achievement_id: String
	EXPEDITION_COMPLETED,    ## params: expedition_id: String
}

## Whether the requirement measures the whole profile or just one plant's own
## contributing sessions. A Monstera needing 250 minutes means 250 minutes grown
## into THAT plant, while "Century Garden" means 100 hours across everything.
enum Scope { GLOBAL, ACTIVE_PLANT }

@export var type: Type = Type.TOTAL_FOCUS_MINUTES
@export var scope: Scope = Scope.GLOBAL
@export var params: Dictionary = {}
## Optional author-written text. When empty, RequirementEvaluator generates a
## description, so content authors only write copy where the default reads badly.
@export_multiline var description_override: String = ""


static func make(
	requirement_type: Type, requirement_params: Dictionary, requirement_scope: Scope = Scope.GLOBAL
) -> Requirement:
	var requirement := Requirement.new()
	requirement.type = requirement_type
	requirement.params = requirement_params
	requirement.scope = requirement_scope
	return requirement


func to_dict() -> Dictionary:
	return {
		"type": int(type),
		"scope": int(scope),
		"params": params.duplicate(true),
		"description_override": description_override,
	}


static func from_dict(data: Dictionary) -> Requirement:
	var requirement := Requirement.new()
	var raw_type := DictUtil.get_int(data, "type", int(Type.TOTAL_FOCUS_MINUTES))
	requirement.type = (
		raw_type as Type
		if raw_type >= 0 and raw_type <= int(Type.EXPEDITION_COMPLETED)
		else Type.TOTAL_FOCUS_MINUTES
	)
	var raw_scope := DictUtil.get_int(data, "scope", int(Scope.GLOBAL))
	requirement.scope = (
		raw_scope as Scope if raw_scope >= 0 and raw_scope <= int(Scope.ACTIVE_PLANT) else Scope.GLOBAL
	)
	requirement.params = DictUtil.get_dict(data, "params")
	requirement.description_override = DictUtil.get_string(data, "description_override")
	return requirement
