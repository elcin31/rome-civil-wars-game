extends RefCounted
## Walkable hub: receive a request, collect supplies, deliver, then leave.

var state: Dictionary = {}
var config: Dictionary = {}
var stations: Array = []


func setup(beat: Dictionary, _progress: Dictionary, _bond: int, _companion: bool = true) -> void:
	config = beat
	var offset: int = int(beat.get("variant", 0)) % 3 * 5
	stations = [
		{"id": "scribe", "x": 76 + offset, "y": 86, "name": "Писец"},
		{"id": "supplies", "x": 164, "y": 120, "name": "Запасы"},
		{"id": "merchant", "x": 184, "y": 76, "name": "Торговец"},
		{"id": "witness", "x": 264 - offset, "y": 92, "name": "Получатель"},
		{"id": "exit", "x": 303, "y": 122, "name": "Дорога"}
	]
	state = {
		"x": 26.0,
		"y": 114.0,
		"quest": 0,
		"won": false,
		"failed": false,
		"message": _line("intro", "Найдите писца у навеса."),
		"interactions": []
	}


func restore(snapshot: Dictionary) -> bool:
	for key in ["x", "y", "quest"]:
		if not (snapshot.get(key) is float or snapshot.get(key) is int):
			return false
	if snapshot.x < 12 or snapshot.x > 308 or snapshot.y < 66 or snapshot.y > 132:
		return false
	if (
		not snapshot.get("interactions") is Array
		or not snapshot.get("won") is bool
		or not snapshot.get("message") is String
	):
		return false
	state = snapshot.duplicate(true)
	return true


func tick(delta: float, axis: Vector2) -> void:
	if state.won:
		return
	var movement: Vector2 = axis.limit_length(1.0) * 78.0 * clampf(delta, 0.0, 1.0 / 30.0)
	state.x = clampf(float(state.x) + movement.x, 12.0, 308.0)
	state.y = clampf(float(state.y) + movement.y, 66.0, 132.0)


func nearest() -> String:
	var best: float = 30.0
	var result: String = ""
	for station in stations:
		var distance: float = Vector2(station.x - state.x, station.y - state.y).length()
		if distance < best:
			best = distance
			result = station.id
	return result


func interact() -> String:
	var ident: String = nearest()
	if ident.is_empty() or state.won:
		return ""
	state.interactions.append(ident)
	match ident:
		"scribe":
			if state.quest == 0:
				state.quest = 1
			state.message = _line("request", "Заберите отмеченный припас и передайте получателю.")
		"supplies":
			if state.quest == 1:
				state.quest = 2
				state.message = _line("collected", "Припас найден. Получатель ждёт у дороги.")
			elif state.quest == 0:
				state.message = _line(
					"unassigned", "Сначала узнайте у писца, кому принадлежит припас."
				)
		"witness":
			if state.quest == 2:
				state.quest = 3
				state.message = _line("delivered", "Передача подтверждена. Можно идти к дороге.")
			elif state.quest < 2:
				state.message = _line("waiting", "Получатель ждёт припас со склада.")
		"merchant":
			state.message = "Лавка открыта."
		"exit":
			if state.quest == 3:
				state.won = true
			else:
				state.message = "Сначала завершите поручение."
	return ident


func _line(key: String, fallback: String) -> String:
	return config.get("hub_dialogue", {}).get(key, {}).get("ru", fallback)


func bot_axis() -> Vector2:
	var ident: String = ["scribe", "supplies", "witness", "exit"][clampi(int(state.quest), 0, 3)]
	for station in stations:
		if station.id == ident:
			return Vector2(station.x - state.x, station.y - state.y).normalized()
	return Vector2.ZERO


func bot_step(delta: float) -> void:
	var target: String = ["scribe", "supplies", "witness", "exit"][clampi(int(state.quest), 0, 3)]
	if nearest() == target:
		interact()
	else:
		tick(delta, bot_axis())
