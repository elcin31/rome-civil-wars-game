extends SceneTree
## Render review frames using an actual display, without touching the player's save.

var view: Control
var game: Node


func _initialize() -> void:
	call_deferred("_capture")


func _shot(name_value: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture = root.get_texture().get_image()
	assert(picture != null and not picture.is_empty())
	assert(picture.save_png("res://docs/story_" + name_value + ".png") == OK)


func _capture() -> void:
	game = root.get_node("StoryRuntime")
	game.save_path = "user://story_capture_%s.json" % OS.get_process_id()
	view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	await _shot("menu")
	view._new_game()
	game.go("ch01_s03_n03")
	view.refresh()
	view._reveal()
	await _shot("dialogue")
	game.state.bond = 40
	game.state.flags.aglaia_safe = false
	game.go("ch07_s03_n90")
	view.refresh()
	await _shot("choice")
	game.go("ch01_s03_n80")
	view.refresh()
	await _shot("beat")
	view._log()
	await _shot("log")
	game.go("ch08_s05_n90")
	view.refresh()
	await _shot("ending")
	game.go("ch05_s01_n90")
	view.refresh()
	await _shot("factions")
	view._new_game(8)
	game.go("ch08_s03_n04")
	view.refresh()
	view._reveal()
	await _shot("epilogue")
	game.state.flags.friend_lost = true
	game.go("ch08_s03_n07")
	view.refresh()
	view._reveal()
	await _shot("loss")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("Saved nine real Godot story screenshots")
	quit(0)
