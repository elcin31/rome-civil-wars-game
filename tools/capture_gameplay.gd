extends SceneTree
## Actual renderer captures. Run on a display; never claims Android device profiling.

var view: Control
var game: Node


func _initialize() -> void:
	call_deferred("_capture")


func _shot(name_value: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	assert(picture.save_png("res://docs/gameplay_" + name_value + ".png") == OK)


func _capture() -> void:
	game = root.get_node("StoryRuntime")
	game.save_path = "user://gameplay_capture_%s.json" % OS.get_process_id()
	view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	game.start_new()
	game.state.bond = 60
	for pair in [
		["ch01_s01_n75", "hub"], ["ch01_s03_n80", "tactical"], ["ch01_s06_n80", "platformer"]
	]:
		game.go(pair[0])
		view.refresh()
		await _shot(pair[1])
	view._open_settings(view.menu)
	await _shot("settings")
	view._slots()
	await _shot("saves")
	view.menu()
	await _shot("menu")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	print("GAMEPLAY CAPTURES PASS")
	quit(0)
