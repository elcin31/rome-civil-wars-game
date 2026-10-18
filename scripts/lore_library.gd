extends RefCounted
## Read-only views of progress. Opening a library never advances or rewrites the story.
const FACTIONS = {
	"legion": "Легион",
	"citizens": "Горожане",
	"octavian": "Октавиан",
	"antony": "Антоний",
	"republicans": "Республиканцы"
}


static func read(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file else {}
	return value if value is Dictionary else {}


static func chapter(state: Dictionary) -> int:
	return clampi(int(state.get("progress", {}).get("chapter", 1)), 1, 8)


static func entries(state: Dictionary, query: String = "", category: String = "all") -> Array:
	var result: Array = []
	for entry in read("res://story/chronicle.json").get("entries", []):
		if int(entry.chapter) > chapter(state) or category not in ["all", entry.category]:
			continue
		if (
			not query.is_empty()
			and not (entry.title + " " + entry.text).to_lower().contains(query.to_lower())
		):
			continue
		result.append(entry)
	return result


static func unlocked(art: Dictionary, state: Dictionary) -> bool:
	if art.get("always", false):
		return true
	if art.has("beat"):
		return art.beat in state.get("beats_completed", []) or art.file in state.get("art_seen", [])
	if art.has("scene"):
		return art.scene in state.get("progress", {}).get("visited", [])
	return int(art.get("chapter", 1)) <= chapter(state)


static func gallery(state: Dictionary) -> Array:
	var result: Array = []
	for art in read("res://story/library_art.json").get("assets", []):
		var item: Dictionary = art.duplicate(true)
		item["unlocked"] = unlocked(item, state)
		result.append(item)
	return result


static func fate(state: Dictionary) -> String:
	var result: String = "Связь Пулона и Ворена: %d / 100\n" % int(state.get("bond", 35))
	for faction in state.get("rep", {}):
		result += "%s: %+d\n" % [FACTIONS.get(faction, faction), state.rep[faction]]
	result += "\nРЕШЕНИЯ И ПОСЛЕДСТВИЯ\n"
	var cached: Dictionary = {}
	for decision in state.get("decisions", []):
		var number: int = int(str(decision.node).substr(2, 2))
		if not cached.has(number):
			cached[number] = read("res://story/chapters/ch%02d.json" % number).get("nodes", [])
		for node in cached[number]:
			if node.id != decision.node:
				continue
			for option in node.get("choices", []):
				if option.id != decision.choice:
					continue
				result += "\n• " + option.text.ru
				if int(option.get("bond", 0)) != 0:
					result += "\nСвязь: %+d" % int(option.bond)
				for faction in option.get("rep", {}):
					result += " · %s: %+d" % [FACTIONS.get(faction, faction), option.rep[faction]]
				for consequence in cached[number]:
					if consequence.id == option.goto and not consequence.text.ru.is_empty():
						result += "\n" + consequence.text.ru
				result += "\n"
	for card in state.get("cutscenes", {}).values():
		result += (
			"\n• "
			+ card.get("title", "Событие")
			+ "\n"
			+ card.text
			+ "\nПотери: "
			+ card.losses
			+ "\n"
		)
	return result


static func recap(state: Dictionary) -> Array[String]:
	var flags: Dictionary = state.get("flags", {})
	var points: Array[String] = []
	points.append("Дорога продолжается: глава %d из 8." % chapter(state))
	if flags.get("friend_lost", false):
		points.append("Ворен погиб у каната. Спасённые продолжают путь и сохраняют память о нём.")
	elif flags.get("aulus_safe", false):
		points.append("Авл выведен из опасности; последствия переправы остались в общей записи.")
	if flags.get("route_citizen", false):
		points.append("Вы выбрали гражданскую дорогу: мастерские, письма и помощь соседям.")
	elif flags.get("route_legion", false):
		points.append("Вы продолжили дорогу с легионом, отвечая и за людей вне строя.")
	if flags.get("warned_lucilla", false) and flags.get("warned_serranus", false):
		points.append("Луцилла и Серран получили предупреждения во время проскрипций.")
	elif flags.get("neria_trust", false):
		points.append("Нерия доверяет героям; помощь в ранних главах укрепила эту связь.")
	if points.size() < 4:
		points.append(
			(
				"Выполнено поручений: %d. Подробности доступны в журнале."
				% state.get("gameplay", {}).get("quests", {}).size()
			)
		)
	points.append(
		(
			"Связь героев сейчас: %d / 100. Ключевые решения сохранены в свитке судеб."
			% int(state.get("bond", 35))
		)
	)
	return points.slice(0, 5)
