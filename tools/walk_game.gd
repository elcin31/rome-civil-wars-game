extends SceneTree
## Play narrative witnesses using real gameplay actions, without victory flag injection.

const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")
var game: Node
var chapter_filter: int = 0
var counts: Dictionary = {"tactical": 0, "platformer": 0, "rpg": 0}
var unique: Dictionary = {}
var total_steps: int = 0
var reload_checked: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	game = root.get_node("StoryRuntime")
	game.save_path = "user://gameplay_bot_%s.json" % OS.get_process_id()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--chapter="):
			chapter_filter = int(argument.get_slice("=", 1))
	var witnesses: Dictionary = game.read_json("res://story/test_routes.json")
	var routes: Array = witnesses.routes + witnesses.scenarios
	if chapter_filter == 0 and FileAccess.file_exists("res://story/gameplay_routes.json"):
		routes += game.read_json("res://story/gameplay_routes.json").get("routes", [])
	for route in routes:
		if not _walk(route):
			quit(1)
			return
	print(
		"GAMEPLAY BOT PASS: ",
		routes.size(),
		" routes; unique encounters ",
		unique.size(),
		"; executions ",
		counts,
		"; simulation actions ",
		total_steps,
		"; save/reload ",
		reload_checked
	)
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	quit(0)


func _walk(route: Dictionary) -> bool:
	game.start_new()
	game.suppress_save = true
	var decision: int = 0
	var reached_chapter: bool = false
	for step in range(4000):
		var node: Dictionary = game.current()
		var chapter: int = int(game.state.progress.chapter)
		if chapter_filter > 0 and chapter > chapter_filter:
			return reached_chapter
		if chapter_filter == chapter:
			reached_chapter = true
		if node.get("kind") == "ending":
			if node.get("ending") != route.ending:
				push_error("Unexpected ending in gameplay bot")
				return false
			print("PLAYED ", route.get("case", route.get("route", "coverage")), " / ", route.ending)
			return true
		if node.has("choices"):
			if decision >= route.decisions.size() or route.decisions[decision].node != node.id:
				push_error("Choice witness diverged at " + node.id)
				return false
			var index: int = -1
			for option in range(node.choices.size()):
				if node.choices[option].id == route.decisions[decision].choice:
					index = option
			if not game.choose(index):
				return false
			decision += 1
		elif node.get("kind") == "beat":
			if chapter_filter == 0 or chapter_filter == chapter:
				if not _play(node.beat):
					return false
			game.complete_beat()
		elif not game.advance():
			return false
	push_error("Narrative traversal limit")
	return false


func _play(ident: String) -> bool:
	var beat: Dictionary = game.beats[ident]
	var model: RefCounted = Factory.create(
		beat,
		game.state.gameplay,
		int(game.state.bond),
		not game.state.flags.get("friend_lost", false)
	)
	if beat.type == "rpg":
		_prepare_hub(model)
	if not reload_checked:
		game.state.gameplay.encounter = {"beat": ident, "state": model.state.duplicate(true)}
		if not game.save_game() or not game.load_game():
			return false
		model = Factory.create(
			beat,
			game.state.gameplay,
			int(game.state.bond),
			not game.state.flags.get("friend_lost", false)
		)
		if not model.restore(game.state.gameplay.encounter.state):
			return false
		reload_checked = true
	var steps: int = Factory.solve(model, beat.type)
	if steps < 0 or not model.state.won:
		push_error("Unfinished real encounter: " + ident + " / " + JSON.stringify(model.state))
		return false
	total_steps += steps
	counts[beat.type] += 1
	unique[ident] = true
	return true


func _prepare_hub(model: RefCounted) -> void:
	for step in range(1000):
		if model.nearest() == "merchant":
			model.interact()
			break
		model.tick(1.0 / 60.0, Vector2(184 - model.state.x, 76 - model.state.y).normalized())
	if model.nearest() != "merchant":
		return
	var progress: Dictionary = game.state.gameplay
	for skill in ["strength", "formation", "diplomacy"]:
		for rank in range(3):
			Progression.train(progress, skill)
	var discount: int = maxi(0, int(game.state.rep.citizens) / 5) + int(progress.skills.diplomacy)
	for item in ["sword", "shield"]:
		for rank in range(3):
			Progression.buy(progress, item, discount)
