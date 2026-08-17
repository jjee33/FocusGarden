class_name JournalEntry
extends RefCounted
## One dated event in the player's history (§31). Player data — JSON.
##
## The journal is append-only and never rewritten: it is the narrative record of
## the player's productivity journey, and §3's "progress must feel permanent"
## depends on entries surviving every later change.
##
## Entries store a `body` string composed when the event happened rather than a
## template resolved at read time, so wording changes in a future version cannot
## retroactively alter what the player's history says.

enum Kind {
	SEED_PLANTED,
	STAGE_REACHED,
	PLANT_MATURED,
	MUTATION_DISCOVERED,
	ACHIEVEMENT_UNLOCKED,
	GARDEN_EXPANSION,
	MILESTONE_REACHED,
	LEVEL_UP,
	EXPEDITION_COMPLETED,
}

var id: String = ""
var kind: Kind = Kind.MILESTONE_REACHED
var created_at_utc: float = 0.0
var date_key: String = ""
var title: String = ""
var body: String = ""
## Optional back-reference (plant uid, achievement id, species id…) so clicking
## an entry can open the thing it describes.
var subject_id: String = ""


static func create(entry_kind: Kind, entry_title: String, entry_body: String, subject: String = "") -> JournalEntry:
	var entry := JournalEntry.new()
	entry.id = Uid.generate("j")
	entry.kind = entry_kind
	entry.title = entry_title
	entry.body = entry_body
	entry.subject_id = subject
	entry.created_at_utc = Time.get_unix_time_from_system()
	entry.date_key = TimeUtil.local_date_key(entry.created_at_utc)
	return entry


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": int(kind),
		"created_at_utc": created_at_utc,
		"date_key": date_key,
		"title": title,
		"body": body,
		"subject_id": subject_id,
	}


static func from_dict(data: Dictionary) -> JournalEntry:
	var entry := JournalEntry.new()
	entry.id = DictUtil.get_string(data, "id")
	var raw_kind := DictUtil.get_int(data, "kind", int(Kind.MILESTONE_REACHED))
	entry.kind = (
		raw_kind as Kind
		if raw_kind >= 0 and raw_kind <= int(Kind.EXPEDITION_COMPLETED)
		else Kind.MILESTONE_REACHED
	)
	entry.created_at_utc = DictUtil.get_float(data, "created_at_utc")
	entry.date_key = DictUtil.get_string(data, "date_key")
	entry.title = DictUtil.get_string(data, "title")
	entry.body = DictUtil.get_string(data, "body")
	entry.subject_id = DictUtil.get_string(data, "subject_id")
	return entry
