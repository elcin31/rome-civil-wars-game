extends Node
## Data-only narrative graph. Conditions are a small DNF language, never eval().

const SAVE_PATH = "user://cinis_story_v2.json"
const Progression = preload("res://scripts/gameplay/progression.gd")
var save_path: String = SAVE_PATH
var slot_prefix: String = "user://cinis_slot_"
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
var test_seed: int = 0
var suppress_save: bool = false
var loaded_chapters: Dictionary = {}


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024:
		return {}
	var parser = JSON.new()
	var contents: String = file.get_as_text()
	file.close()
	if parser.parse(contents) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


func _ready() -> void:
	ui = read_json("res://story/ui_ru.json")
	definitions = read_json("res://story/flags.json")
	characters = read_json("res://story/characters.json").get("characters", {})
	portraits = read_json("res://story/portraits.json").get("portraits", {})
	for beat in read_json("res://story/beats.json").get("beats", []):
		beats[beat.id] = beat
	chapters = read_json("res://story/chapter_index.json").get("chapters", [])
	_load_chapter(1)


func _load_chapter(number: int) -> void:
	if loaded_chapters.has(number) or number < 1 or number > 8:
		return
	var chapter: Dictionary = read_json("res://story/chapters/ch%02d.json" % number)
	for scene in chapter.get("scenes", []):
		scenes[scene.id] = scene
	for node in chapter.get("nodes", []):
		nodes[node.id] = node
	loaded_chapters[number] = true


func _ensure_node(ident: String) -> bool:
	if not nodes.has(ident) and ident.begins_with("ch") and ident.length() > 4:
		_load_chapter(int(ident.substr(2, 2)))
	return nodes.has(ident)


func tr_ui(key: String) -> String:
	return str(ui.get(key, key))


func current() -> Dictionary:
	_ensure_node(state.get("node", ""))
	return nodes.get(state.get("node", ""), {})


func current_scene() -> Dictionary:
	return scenes.get(current().get("scene", ""), {})


func start_new(chapter: int = 1, route: String = "legion") -> void:
	var flags: Dictionary = {}
	for flag in definitions.get("flags", {}):
		flags[flag] = definitions.flags[flag].default
	state = {
		"schema_version": 2,
		"seed": test_seed if test_seed > 0 else randi_range(1, 2147483646),
		"cutscenes": {},
		"node": "ch01_s01_n01",
		"bond": definitions.get("initial_bond", 35),
		"flags": flags,
		"rep": definitions.get("reputation", {}).duplicate(true),
		"progress": {"chapter": 1, "visited": []},
		"history": [],
		"applied": [],
		"decisions": [],
		"beats_completed": [],
		"gameplay": Progression.fresh()
	}
	suppress_save = true
	_settle()
	# Chapter testing uses an actual canonical traversal, never invented state snapshots.
	for step in range(3000):
		if int(state.progress.chapter) >= chapter or current().get("kind") == "ending":
			break
		if current().has("choices"):
			var selected: int = first_choice()
			for i in range(current().choices.size()):
				if (
					current().choices[i].id
					== "ch02_s08_" + ("citizen" if route == "citizen" else "legion")
				):
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
		return {
			">=": lhs >= rhs,
			"<=": lhs <= rhs,
			"==": lhs == rhs,
			"!=": lhs != rhs,
			">": lhs > rhs,
			"<": lhs < rhs
		}[match_value.get_string(2)]
	return bool(state.flags.get(atom, false))


func apply_effects(effect: Dictionary) -> void:
	for flag in effect.get("set_flags", []):
		state.flags[flag] = true
	for flag in effect.get("clear_flags", []):
		state.flags[flag] = false
	state.bond = clampi(int(state.bond) + int(effect.get("bond", 0)), 0, 100)
	for faction in effect.get("rep", {}):
		state.rep[faction] = clampi(
			int(state.rep.get(faction, 0)) + int(effect.rep[faction]), -100, 100
		)
	_synchronize_hero()


func _synchronize_hero() -> void:
	if state.flags.get("friend_lost", false) and state.has("gameplay"):
		state.gameplay.hero = "pullo"


func go(target: String) -> bool:
	if not _ensure_node(target):
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
				state.history.append(
					{"node": node.id, "speaker": node.get("speaker", "narrator"), "text": text}
				)
		var scene = current_scene()
		state.progress.chapter = int(str(scene.get("id", "ch01")).substr(2, 2))
		if scene.get("id", "") not in state.progress.visited:
			state.progress.visited.append(scene.get("id", ""))
		# Empty dialogue connectors carry effects but should not ask for a blank tap.
		if (
			node.get("kind") == "dialogue"
			and node.get("text", {}).get("ru", "").is_empty()
			and node.has("next")
		):
			state.node = node.next
			continue
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
	state.history.append(
		{"node": state.node, "speaker": "narrator", "text": tr_ui("choice_log") + option.text.ru}
	)
	return go(option.goto)


func advance() -> bool:
	var node = current()
	if node.has("choices") or node.get("kind") in ["beat", "ending"]:
		return false
	return go(node.get("next", ""))


func complete_beat(result: Dictionary = {}) -> bool:
	if current().get("kind") != "beat":
		return false
	if current().beat not in state.beats_completed:
		if beats[current().beat].type == "cutscene":
			if result.is_empty():
				var cinematic = preload("res://scripts/gameplay/cutscene_model.gd").new()
				cinematic.setup(beats[current().beat], state.gameplay, int(state.bond))
				cinematic.configure({"seed": state.get("seed", 1), "flags": state.flags})
				for step in range(20):
					cinematic.bot_step(0)
					if cinematic.state.won:
						break
				result = cinematic.result()
			apply_effects(result)
			state.gameplay.coins += int(result.get("reward", 0))
			if not state.has("cutscenes"):
				state.cutscenes = {}
			state.cutscenes[current().beat] = result.duplicate(true)
			state.history.append(
				{
					"node": state.node,
					"speaker": "narrator",
					"text": "Итог: " + str(result.get("text", ""))
				}
			)
		state.beats_completed.append(current().beat)
		Progression.reward(state.gameplay, current().beat)
		if beats[current().beat].type == "rpg":
			state.gameplay.quests[current().beat] = true
	state.gameplay.encounter = {}
	return go(current().get("next", ""))


func skip_scene() -> void:
	var original: String = current().get("scene", "")
	for step in range(300):
		if current().get("scene") != original or current().get("kind") == "ending":
			break
		if current().has("choices"):
			if not choose(first_choice()):
				break
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
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		last_error = tr_ui("save_error")
		return false
	# Keep the last parseable version; a damaged main file must not replace it.
	var previous = read_json(save_path)
	if (
		_valid_save_fields(previous)
		and _valid_save_records(previous)
		and _migrate_flags(previous)
		and (not previous.has("gameplay") or Progression.valid(previous.gameplay))
	):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path + ".bak")
		)
	var error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(save_path)
	)
	last_error = "" if error == OK else tr_ui("save_error")
	return error == OK


func load_game(use_backup: bool = false) -> bool:
	if _load_path(save_path):
		last_error = ""
		return true
	if use_backup and _load_path(save_path + ".bak"):
		last_error = "Восстановлена резервная копия сохранения."
		return true
	last_error = tr_ui("bad_save")
	return false


func _load_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Dictionary = read_json(path)
	if not _valid_save_fields(data) or not _valid_save_records(data):
		return false
	if not _migrate_flags(data):
		return false
	if not data.has("gameplay"):
		data.gameplay = Progression.fresh()
		for ident in data.beats_completed:
			if beats.has(ident):
				Progression.reward(data.gameplay, ident)
				if beats[ident].type == "rpg":
					data.gameplay.quests[ident] = true
	if not Progression.valid(data.gameplay):
		return false
	if not data.has("seed"):
		data.seed = absi(str(data.applied).hash())
	if not data.has("cutscenes"):
		data.cutscenes = {}
	state = data
	_synchronize_hero()
	_settle()
	return true


func _numeric(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _valid_save_fields(data: Dictionary) -> bool:
	if (
		data.get("schema_version") != 2
		or not data.get("node") is String
		or not _ensure_node(data.node)
	):
		return false
	if not data.get("flags") is Dictionary or not data.get("rep") is Dictionary:
		return false
	if not _numeric(data.get("bond")) or data.bond < 0 or data.bond > 100:
		return false
	for key in ["history", "applied", "decisions", "beats_completed"]:
		if not data.get(key) is Array:
			return false
	if not data.get("progress") is Dictionary or not data.progress.get("visited") is Array:
		return false
	return true


func _valid_save_records(data: Dictionary) -> bool:
	for decision in data.decisions:
		if (
			not decision is Dictionary
			or not decision.get("choice") is String
			or not decision.get("node") is String
		):
			return false
	for item in data.history:
		if not item is Dictionary:
			return false
		for key in ["node", "speaker", "text"]:
			if not item.get(key) is String:
				return false
	for key in ["applied", "beats_completed"]:
		for item in data[key]:
			if not item is String:
				return false
	return true


func _migrate_flags(data: Dictionary) -> bool:
	for key in definitions.flags:
		var definition: Dictionary = definitions.flags[key]
		if not data.flags.has(key) and definition.has("restore_from_choices"):
			data.flags[key] = definition.get("default", false)
			for decision in data.decisions:
				if decision.choice in definition.restore_from_choices:
					data.flags[key] = true
		if not data.flags.get(key) is bool:
			return false
	for key in definitions.reputation:
		if not _numeric(data.rep.get(key)) or absf(float(data.rep[key])) > 100:
			return false
	return true


func use_supply() -> bool:
	var progress: Dictionary = state.get("gameplay", {})
	var saved: Dictionary = progress.get("encounter", {})
	if int(progress.get("supplies", 0)) <= 0 or saved.get("beat") != current().get("beat"):
		return false
	if beats.get(saved.get("beat"), {}).get("type") != "platformer":
		return false
	var episode: Dictionary = saved.get("state", {})
	if not _numeric(episode.get("hp")) or not _numeric(episode.get("max_hp")):
		return false
	if episode.hp <= 0 or episode.hp >= episode.max_hp:
		return false
	progress.supplies -= 1
	episode.hp = mini(int(episode.max_hp), int(episode.hp) + 3)
	return save_game()


func save_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	var original: String = save_path
	save_path = slot_prefix + str(slot) + ".json"
	var result: bool = save_game()
	save_path = original
	return result


func load_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	var original: String = save_path
	save_path = slot_prefix + str(slot) + ".json"
	var result: bool = load_game(true)
	save_path = original
	return result
