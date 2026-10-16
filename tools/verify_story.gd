extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var game = root.get_node("StoryRuntime")
	game.save_path = "user://story_verification_%s.json" % OS.get_process_id()
	var routes = game.read_json("res://story/test_routes.json").get("routes", [])
	assert(routes.size() == 8, "Expected four endings through both paths")
	for route in routes:
		game.start_new()
		var decision: int = 0
		for step in range(3000):
			var node = game.current()
			if node.get("kind") == "ending": break
			if node.has("choices"):
				assert(decision < route.decisions.size())
				assert(route.decisions[decision].node == node.id, "Choice sequence diverged")
				var index: int = -1
				for i in range(node.choices.size()):
					if node.choices[i].id == route.decisions[decision].choice: index = i
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
	var view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	await process_frame
	view._new_game()
	var original: String = game.current().text.ru
	var reconstructed: String = " ".join(view.pages).replace("\n", " ")
	assert(" ".join(reconstructed.split(" ", false)) == " ".join(original.replace("\n", " ").split(" ", false)), "Pagination lost words")
	var node_before: String = game.state.node
	view._next()
	assert(game.state.node == node_before and view.body.visible_characters == -1, "Reveal should not advance")
	game.skip_scene()
	assert(game.current().scene != "ch01_s01", "Scene skip did not progress")
	# Invalid save must fail cleanly rather than accepting a corrupted current node.
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert(not game.load_game())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("STORY PASS: 8 ending routes, chapter entry, save round-trip, pagination, reveal, skip, corrupt save")
	quit(0)
