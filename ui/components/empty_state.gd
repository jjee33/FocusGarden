class_name EmptyState
extends VBoxContainer
## A deliberate empty state (§74: "empty states look intentional").
##
## §74 makes empty states a quality gate rather than an afterthought, and §8's
## milestone screens are mostly empty by definition until later milestones fill
## them. This component is what keeps "nothing here yet" looking like a designed
## part of a cozy game instead of a blank rectangle someone forgot.
##
## Every empty state says three things: what this place is FOR, why it is empty
## RIGHT NOW, and what the player can do about it. A state that only says "No
## data" fails all three.

## Maximum line length for body copy, in pixels at the 1920x1080 design
## resolution. Roughly 70 characters — long enough not to feel cramped, short
## enough that the eye finds the next line.
const MEASURE_WIDTH: int = 560

var _glyph_label: Label
var _title_label: Label
var _body_label: Label
var _note_label: Label


## `glyph` is a short emoji or symbol used decoratively. It is never the only
## carrier of meaning — the title and body always say it in words (§50).
static func create(glyph: String, title: String, body: String, note: String = "") -> EmptyState:
	var state := EmptyState.new()
	state._configure(glyph, title, body, note)
	return state


func _configure(glyph: String, title: String, body: String, note: String) -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_glyph_label = Label.new()
	_glyph_label.text = glyph
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.add_theme_font_size_override("font_size", 52)
	# Decorative only: screen readers and keyboard users get the same information
	# from the title and body below.
	_glyph_label.modulate = Color(1, 1, 1, 0.55)
	add_child(_glyph_label)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.theme_type_variation = &"Title"
	add_child(_title_label)

	_body_label = _make_wrapped_label(body, &"Muted")
	add_child(_body_label)

	if note.is_empty():
		return

	# The milestone note is honest scaffolding: it tells the player (and us) that
	# this screen is unbuilt rather than broken. §72 forbids passing a placeholder
	# off as a finished feature, and saying so on the screen is the plainest way
	# to keep that promise.
	_note_label = _make_wrapped_label(note, &"Caption")
	add_child(_note_label)


## A centred label capped at a readable line length.
##
## SIZE_SHRINK_CENTER is what does the work: inside a VBoxContainer a Label
## defaults to filling the full width, so on a 1920-wide window a sentence
## stretches into one enormously long line that technically "fits" and is
## miserable to read. Shrinking to the minimum width instead makes autowrap
## break at MEASURE_WIDTH, which is the readable line length §74 is asking for.
func _make_wrapped_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = MEASURE_WIDTH
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label
