extends RefCounted
## A resumable cinematic: no lethal state, deterministic roll, idempotent resolution.

var beat: Dictionary
var data: Dictionary
var progress: Dictionary
var bond: int
var context: Dictionary = {}
var state: Dictionary = {}


func setup(
	value: Dictionary, persistent: Dictionary, relationship: int, _companion: bool = true
) -> void:
	beat = value
	progress = persistent
	bond = relationship
	var file = FileAccess.open("res://story/cutscenes/" + beat.cutscene + ".json", FileAccess.READ)
	data = JSON.parse_string(file.get_as_text()) if file else {}
	state = {
		"frame": 0,
		"elapsed": 0.0,
		"selected": -1,
		"challenge": 0,
		"played": false,
		"won": false,
		"failed": false,
		"outcome": "",
		"roll": 0
	}


func configure(value: Dictionary) -> void:
	context = value.duplicate(true)


func restore(value: Dictionary) -> bool:
	for key in state:
		if not value.has(key) or typeof(value[key]) != typeof(state[key]):
			# JSON numbers are floats; accept finite integral numeric values below.
			if key not in ["frame", "elapsed", "selected", "challenge", "roll"]:
				return false
	for key in ["frame", "elapsed", "selected", "challenge", "roll"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(value[key]):
			return false
	if (
		value.frame < 0
		or value.frame >= data.frames.size()
		or value.frame != int(value.frame)
		or value.selected < -1
		or value.selected >= data.choice.options.size()
		or value.selected != int(value.selected)
		or absf(value.challenge) > 1
		or value.challenge != int(value.challenge)
		or value.elapsed < 0
		or value.elapsed > 120
		or value.failed
		or value.outcome not in ["", "win", "costly", "loss"]
		or value.won != (value.outcome != "")
	):
		return false
	state = value.duplicate(true)
	return true


func waiting_choice() -> bool:
	return state.frame >= int(data.get("choice_after", 2)) and state.selected < 0


func waiting_challenge() -> bool:
	return state.frame >= int(data.get("challenge_after", 4)) and not state.played


func choose(index: int) -> bool:
	if state.won or not waiting_choice() or index < 0 or index >= data.choice.options.size():
		return false
	state.selected = index
	return true


func challenge(quality: int) -> void:
	if not waiting_challenge() or state.won:
		return
	state.challenge = clampi(quality, -1, 1)
	state.played = true


func next_frame() -> bool:
	if state.won or waiting_choice() or waiting_challenge():
		return false
	state.elapsed = 0.0
	if state.frame + 1 < data.frames.size():
		state.frame += 1
	else:
		resolve()
	return true


func tick(delta: float) -> void:
	if state.won or waiting_choice() or waiting_challenge():
		return
	state.elapsed += clampf(delta, 0, 0.1)
	if state.elapsed >= float(data.frames[int(state.frame)].get("duration", 4.0)):
		next_frame()


func skip() -> void:
	# Skipping visuals preserves the strategic decision; the optional game is neutral.
	state.frame = data.frames.size() - 1
	state.elapsed = 0.0
	if not state.played:
		challenge(0)
	if state.selected >= 0:
		resolve()


func replay() -> void:
	# Review only: keep the committed decision and challenge to prevent reroll farming.
	state.frame = 0
	state.elapsed = 0.0
	state.won = false
	state.outcome = ""


func resolve() -> void:
	if state.won or state.selected < 0:
		return
	var salt: int = 0
	for i in range(beat.id.length()):
		salt = (salt * 31 + beat.id.unicode_at(i)) % 2147483647
	state.roll = ((int(context.get("seed", 1)) % 2147483647) * 48271 + salt) % 5 - 2
	var score: int = int(data.choice.options[int(state.selected)].power) + state.roll
	for rank in progress.get("skills", {}).values():
		score += int(rank)
	score += int(bond) / 25 + int(state.challenge)
	for flag in data.get("helpful_flags", []):
		if context.get("flags", {}).get(flag, false):
			score += 1
	state.outcome = "win" if score >= 5 else "costly" if score >= 2 else "loss"
	state.won = true  # A loss is a completed story event, never a game-over.


func result() -> Dictionary:
	if not state.won:
		return {}
	var card: Dictionary = data.outcome.cards[state.outcome].duplicate(true)
	var option: Dictionary = data.choice.options[int(state.selected)]
	card["set_flags"] = option.get("set_flags", []).duplicate()
	card["bond"] = int(card.get("bond", 0)) + int(option.get("bond", 0))
	card["outcome"] = state.outcome
	card["choice"] = option.id
	card["title"] = data.title
	return card


func bot_step(_delta: float) -> void:
	if waiting_choice():
		choose(0)
	elif waiting_challenge():
		challenge(0)
	else:
		next_frame()
