extends SceneTree
## Synthesises the game's sound effects as .wav files.
##
##     ... --headless --path . --script res://tools/generate_audio.gd
##
## §33 asks for tasteful sound feedback and §42 forbids using copyrighted audio.
## With no sound library available, the honest option is to synthesise the cues
## from scratch — which for the small set this game needs (a chime, a soft click,
## a two-note completion, a level-up arpeggio) is entirely achievable and gives
## sounds that are consistent with each other by construction.
##
## Everything is a sine with a gentle attack and an exponential decay. No square
## waves, no noise, no sharp transients: §3 rules out anything that reads as a
## mobile-game reward jingle, and a soft sine is the sonic equivalent of the
## rounded, warm visual language.
##
## Output is committed. Re-run only when the cues change.

const OUTPUT_DIR: String = "res://assets/audio"
const SAMPLE_RATE: int = 44100

## Frequencies of a pentatonic scale in A. Pentatonic because every combination
## of its notes is consonant — there is no way for these cues to clash with each
## other or with themselves.
const A4: float = 440.0
const C5: float = 523.25
const D5: float = 587.33
const E5: float = 659.25
const G5: float = 783.99
const A5: float = 880.0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	# A single warm note. Used for a stage change and general positive feedback.
	_write("chime_soft", _tone(E5, 0.55, 0.35))

	# Session complete: a rising third, which resolves rather than just stopping.
	_write("session_complete", _sequence([
		{"freq": C5, "start": 0.0, "length": 0.5, "gain": 0.32},
		{"freq": G5, "start": 0.16, "length": 0.7, "gain": 0.28},
	]))

	# Break over: the same shape inverted, so it reads as a counterpart rather
	# than as a second, competing announcement.
	_write("break_complete", _sequence([
		{"freq": G5, "start": 0.0, "length": 0.45, "gain": 0.26},
		{"freq": D5, "start": 0.14, "length": 0.6, "gain": 0.24},
	]))

	# Level up: a four-note pentatonic run. The one cue allowed to feel like an
	# event, and still under a second.
	_write("level_up", _sequence([
		{"freq": A4, "start": 0.00, "length": 0.34, "gain": 0.26},
		{"freq": C5, "start": 0.09, "length": 0.34, "gain": 0.26},
		{"freq": E5, "start": 0.18, "length": 0.40, "gain": 0.26},
		{"freq": A5, "start": 0.27, "length": 0.60, "gain": 0.24},
	]))

	# A plant maturing: the fullest cue, but still soft.
	_write("plant_matured", _sequence([
		{"freq": C5, "start": 0.00, "length": 0.45, "gain": 0.24},
		{"freq": E5, "start": 0.10, "length": 0.50, "gain": 0.24},
		{"freq": G5, "start": 0.20, "length": 0.75, "gain": 0.22},
	]))

	# UI click: very short, very quiet, high enough to sit out of the way of
	# whatever ambient audio is playing.
	_write("ui_click", _tone(A5, 0.07, 0.10, 0.004))

	# Session start: one low note, so beginning feels like settling rather than
	# like a starting pistol.
	_write("session_start", _tone(A4, 0.42, 0.22))

	print("Generated 7 audio cues in %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


## One note with a soft attack and exponential decay.
func _tone(frequency: float, length: float, gain: float, attack: float = 0.02) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := int(length * float(SAMPLE_RATE))
	samples.resize(count)

	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := _envelope(t, length, attack)
		# A touch of the octave above adds warmth without making it a new note.
		var value := sin(TAU * frequency * t) + 0.18 * sin(TAU * frequency * 2.0 * t)
		samples[i] = value * envelope * gain
	return samples


## Mixes several notes into one buffer, so a cue is a chord or a run rather than
## separate streams the audio bus would have to schedule.
func _sequence(notes: Array) -> PackedFloat32Array:
	var total_length := 0.0
	for note: Dictionary in notes:
		total_length = maxf(total_length, float(note["start"]) + float(note["length"]))

	var count := int(total_length * float(SAMPLE_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)

	for note: Dictionary in notes:
		var start_sample := int(float(note["start"]) * float(SAMPLE_RATE))
		var note_samples := _tone(
			float(note["freq"]), float(note["length"]), float(note["gain"])
		)
		for i in note_samples.size():
			var index := start_sample + i
			if index >= count:
				break
			samples[index] += note_samples[i]

	# Guard against the sum clipping. Notes overlap by design, so the peak is
	# not knowable in advance.
	var peak := 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	if peak > 0.95:
		var scale := 0.95 / peak
		for i in samples.size():
			samples[i] *= scale
	return samples


## Attack-decay envelope. The attack removes the click a raw sine start makes;
## the exponential decay is what makes it sound struck rather than switched on.
func _envelope(t: float, length: float, attack: float) -> float:
	if t < attack:
		return t / attack
	var decay_progress := (t - attack) / maxf(0.0001, length - attack)
	return exp(-4.5 * decay_progress)


## Writes 16-bit mono PCM as a .wav.
##
## Written by hand rather than through AudioStreamWAV.save_to_wav, which does not
## exist in this engine version — and a 44-byte header is less risk than a
## dependency on an API that might not be there.
func _write(name: String, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		var clamped := clampf(samples[i], -1.0, 1.0)
		var value := int(clamped * 32767.0)
		pcm.encode_s16(i * 2, value)

	var file := FileAccess.open("%s/%s.wav" % [OUTPUT_DIR, name], FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s" % name)
		return

	var data_size := pcm.size()
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)               # Subchunk size for PCM.
	file.store_16(1)                # Format 1 = uncompressed PCM.
	file.store_16(1)                # Mono.
	file.store_32(SAMPLE_RATE)
	file.store_32(SAMPLE_RATE * 2)  # Byte rate: rate * channels * bytes/sample.
	file.store_16(2)                # Block align.
	file.store_16(16)               # Bits per sample.
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	file.store_buffer(pcm)
	file.close()
