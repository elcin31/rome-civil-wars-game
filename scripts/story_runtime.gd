extends Node
## Data-only narrative graph. Conditions are a small DNF language, never eval().

const SAVE_PATH = "user://cinis_story_v2.json"
var save_path: String = SAVE_PATH
var chapters: Array = []
var nodes: Dictionary = {}
var scenes: Dictionary = {}
var characters: Dictionary = {}
var portraits: Dictionary = {}
var beats: Dictionary = {}
var definitions: Dictionary = {}
var ui: Dictionary = {}
var state: Dictionary = {}
var last_error: String = ""
var suppress_save: bool = false


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	return parser.data if parser.data is Dictionary else {}


func _ready() -> void:
	ui = read_json("res://story/ui_ru.json")
	definitions = read_json("res://story/flags.json")
	characters = read_json("res://story/characters.json").get("characters", {})
	portraits = read_json("res://story/portraits.json").get("portraits", {})
	for beat in read_json("res://story/beats.json").get("beats", []):
		beats[beat.id] = beat
	for i in range(1, 9):
		var chapter = read_json("res://story/chapters/ch%02d.json" % i)
		chapters.append(chapter)
		for scene in chapter.get("scenes", []):
			scenes[scene.id] = scene
		for node in chapter.get("nodes", []):
			nodes[node.id] = node


func tr_ui(key: String) -> String:
	return str(ui.get(key, key))


func current() -> Dictionary:
	return nodes.get(state.get("node", ""), {})


func current_scene() -> Dictionary:
	return scenes.get(current().get("scene", ""), {})


func start_new(chapter: int = 1, route: String = "legion") -> void:
	var flags: Dictionary = {}
	for flag in definitions.get("flags", {}):
		flags[flag] = definitions.flags[flag].default
	state = {"schema_version": 2, "node": "ch01_s01_n01", "bond": definitions.get("initial_bond", 35),
		"flags": flags, "rep": definitions.get("reputation", {}).duplicate(true),
		"progress": {"chapter": 1, "visited": []}, "history": [], "applied": [],
		"decisions": [], "beats_completed": []}
	suppress_save = true
	_settle()
	# Chapter testing uses an actual canonical traversal, never invented state snapshots.
	for step in range(3000):
		if int(state.progress.chapter) >= chapter or current().get("kind") == "ending":
			break
		if current().has("choices"):
			var selected: int = first_choice()
			for i in range(current().choices.size()):
				if current().choices[i].id == "ch02_s08_" + ("citizen" if route == "citizen" else "legion"):
					selected = i
			choose(selected)
		elif current().get("kind") == "beat":
			complete_beat()
		else:
			advance()
	suppress_save = false
	save_game()


func condition(expression: String) -> bool:
	if expression.strip_edges().is_empty():
		return true
	for alternative in expression.replace(" ", "").split("|"):
		var accepted: bool = true
		for atom in alternative.split("&"):
			if not _atom(atom):
				accepted = false
		if accepted:
			return true
	return false


func _atom(atom: String) -> bool:
	if atom.begins_with("!"):
		return not bool(state.flags.get(atom.substr(1), false))
	var regex = RegEx.new()
	regex.compile("^(bond|rep\\.[a-z_]+)(>=|<=|==|!=|>|<)(-?[0-9]+)$")
	var match_value = regex.search(atom)
	if match_value:
		var key: String = match_value.get_string(1)
		var lhs: int = int(state.bond) if key == "bond" else int(state.rep.get(key.substr(4), 0))
		var rhs: int = int(match_value.get_string(3))
		match match_value.get_string(2):
			">=": return lhs >= rhs
			"<=": return lhs <= rhs
			"==": return lhs == rhs
			"!=": return lhs != rhs
			">": return lhs > rhs
			"<": return lhs < rhs
	return bool(state.flags.get(atom, false))


func apply_effects(effect: Dictionary) -> void:
	for flag in effect.get("set_flags", []):
		state.flags[flag] = true
	for flag in effect.get("clear_flags", []):
		state.flags[flag] = false
	state.bond = clampi(int(state.bond) + int(effect.get("bond", 0)), 0, 100)
	for faction in effect.get("rep", {}):
		state.rep[faction] = clampi(int(state.rep.get(faction, 0)) + int(effect.rep[faction]), -100, 100)


func go(target: String) -> bool:
	if not nodes.has(target):
		last_error = "Unknown node: " + target
		push_error(last_error)
		return false
	state.node = target
	_settle()
	if not suppress_save:
		save_game()
	return true


func _settle() -> void:
	for step in range(100):
		var node = current()
		if node.is_empty():
			return
		if not condition(node.get("condition", "")):
			state.node = node.get("next", "")
			continue
		if node.get("kind") == "branch":
			var target: String = node.get("next", "")
			for branch in node.get("branches", []):
				if condition(branch.get("condition", "")):
					target = branch.goto
					break
			state.node = target
			continue
		if node.id not in state.applied:
			apply_effects(node)
			state.applied.append(node.id)
			var text: String = node.get("text", {}).get("ru", "")
			if not text.is_empty():
				state.history.append({"node": node.id, "speaker": node.get("speaker", "narrator"), "text": text})
		var scene = current_scene()
		state.progress.chapter = int(str(scene.get("id", "ch01")).substr(2, 2))
		if scene.get("id", "") not in state.progress.visited:
			state.progress.visited.append(scene.get("id", ""))
		return
	push_error("Narrative branch cycle")


func first_choice() -> int:
	var options: Array = current().get("choices", [])
	for i in range(options.size()):
		if condition(options[i].get("condition", "")):
			return i
	return -1


func choose(index: int) -> bool:
	var options: Array = current().get("choices", [])
	if index < 0 or index >= options.size() or not condition(options[index].get("condition", "")):
		return false
	var option: Dictionary = options[index]
	apply_effects(option)
	state.decisions.append({"node": state.node, "choice": option.id})
	state.history.append({"node": state.node, "speaker": "narrator", "text": tr_ui("choice_log") + option.text.ru})
	return go(option.goto)


func advance() -> bool:
	var node = current()
	if node.has("choices") or node.get("kind") in ["beat", "ending"]:
		return false
	return go(node.get("next", ""))


func complete_beat() -> bool:
	if current().get("kind") != "beat":
		return false
	if current().beat not in state.beats_completed:
		state.beats_completed.append(current().beat)
	return go(current().get("next", ""))


func skip_scene() -> void:
	var original: String = current().get("scene", "")
	for step in range(300):
		if current().get("scene") != original or current().get("kind") == "ending":
			break
		if current().has("choices"):
			if not choose(first_choice()): break
		elif current().get("kind") == "beat":
			complete_beat()
		elif not advance():
			break


func save_game() -> bool:
	var temp_path: String = save_path + ".tmp"
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = tr_ui("save_error")
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	file.close()
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path))
	last_error = "" if error == OK else tr_ui("save_error")
	return error == OK


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data = read_json(save_path)
	if data.get("schema_version") != 2 or not nodes.has(data.get("node", "")):
		return false
	if not data.get("flags") is Dictionary or not data.get("rep") is Dictionary:
		return false
	if not data.get("bond") is float and not data.get("bond") is int:
		return false
	if data.bond < 0 or data.bond > 100:
		return false
	for key in definitions.flags:
		if not data.flags.get(key) is bool:
			return false
	for key in definitions.reputation:
		if not data.rep.get(key) is float and not data.rep.get(key) is int:
			return false
	for key in ["history", "applied", "decisions", "beats_completed"]:
		if not data.get(key) is Array:
			return false
	if not data.get("progress") is Dictionary or not data.progress.get("visited") is Array:
		return false
	state = data
	_settle()
	return true
