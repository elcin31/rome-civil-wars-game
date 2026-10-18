extends RefCounted

## Walkable hub: receive a request, collect supplies, deliver, then leave.

enum QuestStage { REQUEST, COLLECT, DELIVER, COMPLETE }

const Snapshot = preload("res://scripts/gameplay/snapshot.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")
const RADIUS = 30.0
const QUEST_TARGETS = ["scribe", "supplies", "witness", "exit"]
const TRANSITIONS = {
	QuestStage.REQUEST: {"object": "scribe", "next": QuestStage.COLLECT, "line": "request"},
	QuestStage.COLLECT: {"object": "supplies", "next": QuestStage.DELIVER, "line": "collected"},
	QuestStage.DELIVER: {"object": "witness", "next": QuestStage.COMPLETE, "line": "delivered"}
}
const OBJECTIVES = [
	"1/3 · Поговорите с писцом",
	"2/3 · Возьмите отмеченные запасы",
	"3/3 · Передайте припасы получателю",
	"Поручение выполнено · Идите к дороге"
]
const MESSAGES = {
	"request": "Заберите отмеченный припас и передайте получателю.",
	"collected": "Припас найден. Получатель ждёт у дороги.",
	"delivered": "Передача подтверждена. Можно идти к дороге."
}

var state: Dictionary = {}
var config: Dictionary = {}
var stations: Array = []


func setup(beat: Dictionary, _progress: Dictionary, _bond: int, _companion: bool = true) -> void:
	config = beat
	var offset: int = int(beat.get("variant", 0)) % 3 * 5
	stations = [
		{"id": "scribe", "x": 76 + offset, "y": 100, "name": "Писец"},
		{"id": "supplies", "x": 164, "y": 120, "name": "Запасы"},
		{"id": "merchant", "x": 184, "y": 96, "name": "Торговец"},
		{"id": "witness", "x": 264 - offset, "y": 108, "name": "Получатель"},
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
	if not Snapshot.matches(snapshot, state):
		return false
	if (
		snapshot.x < 12
		or snapshot.x > 308
		or snapshot.y < 66
		or snapshot.y > 132
		or snapshot.quest < 0
		or snapshot.quest > 3
		or float(snapshot.quest) != floorf(float(snapshot.quest))
		or snapshot.failed
		or (snapshot.won and snapshot.quest != QuestStage.COMPLETE)
	):
		return false
	for item in snapshot.interactions:
		if item not in ["scribe", "supplies", "witness", "merchant", "exit"]:
			return false
	state = snapshot.duplicate(true)
	state.quest = int(state.quest)
	return true


func tick(delta: float, axis: Vector2) -> void:
	if state.won:
		return
	var movement: Vector2 = axis.limit_length(1.0) * 78.0 * clampf(delta, 0.0, 1.0 / 30.0)
	state.x = clampf(float(state.x) + movement.x, 12.0, 308.0)
	state.y = clampf(float(state.y) + movement.y, 66.0, 132.0)
	# Interaction range leaves room to stand beside people, rather than inside them.
	for station in stations:
		if station.id not in ["scribe", "merchant", "witness"]:
			continue
		var away: Vector2 = Vector2(state.x - station.x, state.y - station.y)
		if away.length() < 18.0:
			away = Vector2.DOWN if away.is_zero_approx() else away.normalized()
			state.x = clampf(station.x + away.x * 18.0, 12.0, 308.0)
			state.y = clampf(station.y + away.y * 18.0, 66.0, 132.0)


func nearest() -> String:
	# The same resolver drives the prompt, highlight, keyboard and touch action.
	var target: String = quest_target()
	var best: float = RADIUS
	var result: String = ""
	for station in stations:
		var distance: float = Vector2(station.x - state.x, station.y - state.y).length()
		if station.id == target and distance < RADIUS:
			return target
		if distance < best:
			best = distance
			result = station.id
	return result


func quest_target() -> String:
	return QUEST_TARGETS[clampi(int(state.quest), 0, 3)]


func objective_text() -> String:
	return OBJECTIVES[clampi(int(state.quest), 0, 3)]


func action_text() -> String:
	match nearest():
		"supplies":
			return "Взять" if state.quest == QuestStage.COLLECT else "Осмотреть"
		"witness":
			return "Передать" if state.quest == QuestStage.DELIVER else "Говорить"
		"exit":
			return "В путь" if state.quest == QuestStage.COMPLETE else "Осмотреть"
	return "Говорить"


func hint_text() -> String:
	return [
		"Подойдите к писцу слева у навеса и нажмите «Говорить».",
		"Ящик «Запасы» стоит посреди лагеря. Подойдите и нажмите «Взять».",
		"Получатель ждёт справа от склада. Подойдите к нему и нажмите «Передать».",
		"Поручение выполнено. Дойдите до указателя справа и нажмите «В путь»."
	][clampi(int(state.quest), 0, 3)]


func interact() -> String:
	var ident: String = nearest()
	if ident.is_empty() or state.won:
		return ""
	if ident not in state.interactions:
		state.interactions.append(ident)
	var transition: Dictionary = TRANSITIONS.get(int(state.quest), {})
	if transition.get("object") == ident:
		state.quest = transition.next
		state.message = _line(transition.line, MESSAGES[transition.line])
		return ident
	match ident:
		"scribe":
			state.message = hint_text()
		"supplies":
			if state.quest == QuestStage.REQUEST:
				state.message = _line(
					"unassigned", "Сначала узнайте у писца, кому принадлежит припас."
				)
		"witness":
			if state.quest < QuestStage.DELIVER:
				state.message = _line("waiting", "Получатель ждёт припас со склада.")
		"merchant":
			state.message = "Лавка открыта."
		"exit":
			if state.quest == QuestStage.COMPLETE:
				state.won = true
			else:
				state.message = "Сначала завершите поручение."
	return ident


func _line(key: String, fallback: String) -> String:
	return config.get("hub_dialogue", {}).get(key, {}).get("ru", fallback)


func bot_axis() -> Vector2:
	var ident: String = quest_target()
	for station in stations:
		if station.id == ident:
			return Vector2(station.x - state.x, station.y - state.y).normalized()
	return Vector2.ZERO


func bot_step(delta: float) -> void:
	var target: String = quest_target()
	if nearest() == target:
		interact()
	else:
		tick(delta, bot_axis())


func buy(progress: Dictionary, item: String, discount: int) -> bool:
	return nearest() == "merchant" and Progression.buy(progress, item, discount)


func train(progress: Dictionary, skill: String) -> bool:
	return nearest() == "merchant" and Progression.train(progress, skill)
