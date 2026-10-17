extends SceneTree
## Desktop renderer measurements; physical Android budgets stay explicitly unverified.

var view: Control
var game: Node


func _initialize() -> void:
	call_deferred("_profile")


func _profile() -> void:
	game = root.get_node("StoryRuntime")
	game.save_path = "user://profiling_%s.json" % OS.get_process_id()
	view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	game.start_new()
	game.state.bond = 65
	var results: Array = []
	for pair in [
		["ch01_s03_n80", "tactical"], ["ch01_s06_n80", "platformer"], ["ch01_s01_n75", "rpg"]
	]:
		game.go(pair[0])
		view.refresh()
		var samples: Array = []
		var cpu_max: float = 0.0
		var memory_max: float = 0.0
		for frame in range(300):
			var encounter: Control = view.encounter
			if encounter.model.state.won or encounter.model.state.failed:
				encounter._retry()
			if pair[1] == "platformer":
				var action: Dictionary = encounter.model.bot_input()
				encounter.joy_axis = Vector2(action.axis, 0)
				encounter.controls.jump = action.jump
				encounter.controls.strike = action.strike
			elif pair[1] == "tactical" and frame % 30 == 0:
				encounter.model.bot_turn()
				encounter.queue_redraw()
			elif pair[1] == "rpg":
				encounter.model.bot_step(1.0 / 60.0)
			await process_frame
			if frame >= 180:
				samples.append(Performance.get_monitor(Performance.TIME_FPS))
				cpu_max = maxf(cpu_max, Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
				memory_max = maxf(
					memory_max, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576
				)
		results.append(
			{
				"layer": pair[1],
				"fps_min": samples.min(),
				"fps_max": samples.max(),
				"cpu_frame_max_ms": snappedf(cpu_max, 0.01),
				"static_memory_max_mib": snappedf(memory_max, 0.01)
			}
		)
	for presentation in ["menu", "dialogue", "gallery"]:
		var gallery: Control
		if presentation == "menu":
			view.menu()
		elif presentation == "dialogue":
			game.start_new()
			view.refresh()
			view._reveal()
		else:
			view.menu()
			view.hide()
			gallery = load("res://scenes/AssetGallery.tscn").instantiate()
			root.add_child(gallery)
		var samples: Array = []
		var cpu_max: float = 0.0
		var memory_max: float = 0.0
		for frame in range(300):
			await process_frame
			if frame >= 180:
				samples.append(Performance.get_monitor(Performance.TIME_FPS))
				cpu_max = maxf(cpu_max, Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
				memory_max = maxf(
					memory_max, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576
				)
		results.append(
			{
				"layer": presentation,
				"fps_min": samples.min(),
				"fps_max": samples.max(),
				"cpu_frame_max_ms": snappedf(cpu_max, 0.01),
				"static_memory_max_mib": snappedf(memory_max, 0.01)
			}
		)
		if is_instance_valid(gallery):
			gallery.queue_free()
			await process_frame
			view.show()
	game.go("ch01_s06_n80")
	view.refresh()
	await process_frame
	await process_frame
	var before: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var memory_before: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576
	for cycle in range(20):
		view._pause()
		view.refresh()
		await process_frame
		await process_frame
	var after: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var memory_after: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576
	var aspect_results: Array = []
	for dimensions in [Vector2i(1280, 720), Vector2i(1680, 720)]:
		DisplayServer.window_set_size(dimensions)
		await process_frame
		await process_frame
		aspect_results.append(
			{"window": [dimensions.x, dimensions.y], "viewport": [root.size.x, root.size.y]}
		)
	var report: Dictionary = {
		"device": "Linux desktop, Xorg dummy, Mesa llvmpipe software OpenGL",
		"godot": Engine.get_version_info().string,
		"physical_android": false,
		"samples_per_layer": 120,
		"layers": results,
		"nodes_before_pause_cycles": before,
		"nodes_after_pause_cycles": after,
		"static_memory_before_pause_mib": snappedf(memory_before, 0.01),
		"static_memory_after_pause_mib": snappedf(memory_after, 0.01),
		"pause_cycles": 20,
		"aspects": aspect_results
	}
	var file = FileAccess.open("res://docs/desktop_performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	assert(after <= before, "Pause/resume leaked nodes")
	var audio = root.get_node("GameServices")
	audio.music.stop()
	for voice in audio.voices:
		voice.stop()
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	print("DESKTOP PROFILE PASS ", JSON.stringify(report))
	quit(0)
