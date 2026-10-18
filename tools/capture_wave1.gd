extends SceneTree
## Capture the real quest flow through connected touch controls, using an isolated save.

var view: Control
var game: Node
var output: String = "res://build/wave1"


func _initialize() -> void:
	call_deferred("_run")


func _tap(caption: String) -> void:
	await process_frame
	var buttons: Array[Button] = []
	var pending: Array[Node] = [view]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Button and node.is_visible_in_tree():
			buttons.append(node)
		pending.append_array(node.get_children())
	for button in buttons:
		if button.get_meta("caption", "") != caption:
			continue
		var point: Vector2 = root.get_screen_transform() * button.get_global_rect().get_center()
		for pressed in [true, false]:
			var touch = InputEventScreenTouch.new()
			touch.index = 6
			touch.position = point
			touch.pressed = pressed
			Input.parse_input_event(touch)
			await process_frame
		return
	assert(false, "Missing visible button: " + caption)


func _shot(caption: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output + "/" + caption + ".png") == OK)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = root.get_node("StoryRuntime")
	game.save_path = "user://wave1_capture_%s.json" % OS.get_process_id()
	game.start_new()
	game.go("ch01_s01_n75")
	view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	view.refresh()
	var scribe: Dictionary = view.encounter.model.stations[0]
	view.encounter.model.state.x = float(scribe.x - 22)
	view.encounter.model.state.y = float(scribe.y)
	view.encounter._update_status()
	await _tap("Говорить")
	assert(view.encounter.model.state.quest == 1)
	view.encounter.model.state.x = 180.0
	view.encounter.model.state.y = 106.0
	view.encounter._update_status()
	await _shot("take")
	view.encounter.debug_interactions = true
	await _shot("debug")
	view.encounter.debug_interactions = false
	await _tap("Взять")
	assert(view.encounter.model.state.quest == 2)
	await _shot("delivery")
	await _tap("Что дальше?")
	await _shot("hint")
	await _tap("Журнал")
	assert(view.mode == "log")
	await _shot("journal")
	view.refresh()
	var witness: Dictionary = view.encounter.model.stations[3]
	view.encounter.model.state.x = float(witness.x - 22)
	view.encounter.model.state.y = float(witness.y)
	view.encounter._update_status()
	await _tap("Передать")
	assert(view.encounter.model.state.quest == 3)
	await _shot("completed")
	view.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	print("WAVE ONE CAPTURES PASS: request, take, help, journal, delivery through real touches")
	quit(0)
