extends SceneTree


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var game = root.get_node("StoryRuntime")
	game.test_seed = 1
	game.save_path = "user://story_verification_%s.json" % OS.get_process_id()
	var witnesses = game.read_json("res://story/test_routes.json")
	var routes = witnesses.get("routes", [])
	assert(routes.size() == 8, "Expected four endings through both paths")
	var scenarios = witnesses.get("scenarios", [])
	assert(scenarios.size() == 16, "Expected targeted major-decision cases")
	routes += scenarios
	for route in routes:
		game.start_new()
		# Canonical routes exercise autosaves; extra cases avoid redundant disk writes.
		game.suppress_save = route.has("case")
		var decision: int = 0
		for step in range(3000):
			var node = game.current()
			if node.get("kind") == "ending":
				break
			if node.has("choices"):
				for i in range(node.choices.size()):
					if not game.condition(node.choices[i].get("condition", "")):
						var unchanged = game.state.duplicate(true)
						assert(not game.choose(i), "Locked choice accepted")
						assert(game.state == unchanged, "Locked choice changed state")
				assert(decision < route.decisions.size())
				assert(route.decisions[decision].node == node.id, "Choice sequence diverged")
				var index: int = -1
				for i in range(node.choices.size()):
					if node.choices[i].id == route.decisions[decision].choice:
						index = i
				assert(index >= 0 and game.choose(index), "Choice unavailable in Godot")
				decision += 1
			elif node.get("kind") == "beat":
				assert(game.complete_beat())
			else:
				assert(game.advance())
		assert(game.current().get("ending") == route.ending, "Wrong ending")
		assert(int(game.state.bond) == int(route.state.bond))
		assert(game.state.flags == route.state.flags, "Flag interpreter diverged")
		for faction in route.state.rep:
			assert(int(game.state.rep[faction]) == int(route.state.rep[faction]))
		var actual_history: Array[String] = []
		for item in game.state.history:
			if game.nodes.has(item.node) and item.text == game.nodes[item.node].text.ru:
				actual_history.append(item.node)
			if game.state.flags.friend_lost and str(item.node) >= "ch07_s04":
				assert(item.speaker != "vorenus", "Lost friend speaks after Actium")
		var expected_history: Array[String] = []
		for ident in route.nodes:
			if not game.nodes[ident].text.ru.is_empty():
				expected_history.append(ident)
		assert(actual_history == expected_history, "Conditional dialogue history diverged")
		if route.has("case"):
			print("SCENARIO PASS ", route["case"], " / ", route.ending)
		else:
			print("ROUTE PASS ", route.route, " / ", route.ending, " / bond ", game.state.bond)
	game.start_new(3, "citizen")
	assert(game.current().id == "ch03_s10_n01" and game.state.flags.route_citizen)
	var saved = game.state.duplicate(true)
	assert(game.save_game())
	game.state.bond = 0
	game.state.flags.neria_trust = not saved.flags.neria_trust
	assert(game.load_game())
	assert(game.state.node == saved.node and int(game.state.bond) == int(saved.bond))
	assert(game.state.flags == saved.flags and game.state.history.size() == saved.history.size())
	# Loading twice must never reapply bond/flags or duplicate dialogue history.
	assert(game.load_game())
	assert(game.state.history.size() == saved.history.size())
	# Recover newly added warning flags from decisions in a real older save.
	game.start_new(6, "legion")
	var before_migration = game.state.flags.duplicate(true)
	var legacy = game.state.duplicate(true)
	legacy.flags.erase("warned_serranus")
	legacy.flags.erase("warned_lucilla")
	var legacy_file = FileAccess.open(game.save_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	assert(game.load_game())
	assert(game.state.flags == before_migration, "Saved warning decisions not recovered")
	legacy.flags.erase("ledger_survives")
	legacy_file = FileAccess.open(game.save_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	assert(not game.load_game(), "Missing original flag should be rejected")
	game.start_new(7, "citizen")
	for step in range(300):
		if game.current().id == "ch07_s03_n90":
			break
		if game.current().has("choices"):
			game.choose(game.first_choice())
		elif game.current().get("kind") == "beat":
			game.complete_beat()
		else:
			game.advance()
	assert(game.current().id == "ch07_s03_n90")
	assert(game.choose(1) and game.current().get("kind") == "beat")
	var beat_bond: int = int(game.state.bond)
	assert(game.load_game(), "Autosave before gameplay slot was not readable")
	assert(game.current().id == "ch07_s03_n80" and game.state.flags.friend_lost)
	assert(int(game.state.bond) == beat_bond, "Choice effect repeated on reload")
	assert(game.complete_beat() and game.current().id == "ch07_s03_n92")
	var view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	await process_frame
	view._new_game()
	var original: String = game.current().text.ru
	var reconstructed: String = " ".join(view.pages).replace("\n", " ")
	assert(
		(
			" ".join(reconstructed.split(" ", false))
			== " ".join(original.replace("\n", " ").split(" ", false))
		),
		"Pagination lost words"
	)
	for node in game.nodes.values():
		var text: String = node.text.ru
		var pages = view._paginate(text)
		var joined: String = " ".join(pages).replace("\n", " ")
		assert(
			(
				" ".join(joined.split(" ", false))
				== " ".join(text.replace("\n", " ").split(" ", false))
			),
			"Long dialogue pagination lost words"
		)
		for page in pages:
			assert(page.count("\n") < 4, "Page exceeds four visible lines")
	var node_before: String = game.state.node
	view._next()
	assert(
		game.state.node == node_before and view.body.visible_characters == -1,
		"Reveal should not advance"
	)
	game.skip_scene()
	assert(game.current().scene != "ch01_s01", "Scene skip did not progress")
	# Invalid save must fail cleanly rather than accepting a corrupted current node.
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert(not game.load_game())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print(
		(
			"STORY PASS: 24 routes, history, choices, chapter entry, migration, "
			+ "mid-beat reload, pagination, reveal, skip, corrupt save"
		)
	)
	quit(0)
