extends RefCounted
## Short noncombat journey. Detection costs time only; skip always advances neutrally.
var beat: Dictionary
var state: Dictionary
var seed_value: int = 1


func setup(value: Dictionary, _progress: Dictionary, _bond: int, _companion: bool = true) -> void:
	beat = value
	state = {
		"x": 24.0,
		"elapsed": 0.0,
		"cover": false,
		"marks": [],
		"alerts": 0,
		"won": false,
		"failed": false,
		"played": false,
		"roll": 0,
		"neutral": false
	}


func restore(value: Dictionary) -> bool:
	if (
		not (value.get("x") is float or value.get("x") is int)
		or not is_finite(value.x)
		or value.x < 16
		or value.x > 456
		or not (value.get("elapsed") is float or value.get("elapsed") is int)
		or not is_finite(value.elapsed)
		or value.elapsed < 0
		or value.elapsed > 86400
		or not value.get("marks") is Array
		or value.marks.size() > 3
	):
		return false
	for key in ["cover", "won", "failed", "played", "neutral"]:
		if not value.get(key) is bool:
			return false
	for key in ["alerts", "roll"]:
		if not (value.get(key) is float or value.get(key) is int) or value[key] != int(value[key]):
			return false
	var invalid: bool = value.failed or value.alerts < 0 or value.roll < 0 or value.roll > 6
	var unique: Array = []
	for mark in value.marks:
		invalid = invalid or mark not in [0, 1, 2] or mark in unique
		unique.append(mark)
	if (
		invalid
		or value.won and not value.neutral and beat.get("minigame") != "dice" and unique.size() < 3
	):
		return false
	state = value.duplicate(true)
	return true


func tick(delta: float, axis: float = 0.0, hiding: bool = false) -> void:
	if state.won:
		return
	state.elapsed = minf(86400, state.elapsed + clampf(delta, 0, 0.1))
	state.cover = hiding
	if beat.get("minigame") == "dice":
		return
	var lit: bool = fmod(state.elapsed, 5.0) < 1.8
	var speed: float = 38 if not hiding else 16
	if beat.get("minigame") == "stealth" and lit and not hiding and absf(axis) > 0.1:
		speed = 8  # No death, reset, or lost quest objects.
		state.alerts = maxi(int(state.alerts), 1)
	state.x = clampf(state.x + axis * speed * delta, 16, 456)
	for i in range(3):
		if absf(state.x - (120 + i * 125)) < 20 and i not in state.marks:
			state.marks.append(i)
	if state.x > 434 and state.marks.size() == 3:
		state.won = true


func dice(seed_number: int, risk: bool) -> void:
	if state.played or state.won:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_number ^ int(beat.id.hash())
	state.roll = rng.randi_range(1, 6)
	state.played = true
	state.neutral = not risk
	state.won = true


func skip() -> void:
	state.neutral = true
	state.won = true


func bot_step(delta: float) -> void:
	if beat.get("minigame") == "dice":
		dice(1, false)
	else:
		tick(delta, 1.0, beat.get("minigame") == "stealth")
