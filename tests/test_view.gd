extends "res://addons/gut/test.gd"

var view: Control
var game: Node


func before_each() -> void:
	game = get_tree().root.get_node("StoryRuntime")
	game.save_path = "user://gut_view_%s.json" % OS.get_process_id()
	game.start_new()
	view = load("res://scenes/StoryMain.tscn").instantiate()
	add_child_autofree(view)


func after_each() -> void:
	view._clear("menu")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))


func _touch(index: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	return event


func test_two_finger_controls_pause_and_in_episode_reload() -> void:
	game.go("ch01_s06_n80")
	view.refresh()
	var encounter: Control = view.encounter
	assert_not_null(encounter)
	encounter._input(_touch(0, Vector2(56, 152), true))
	encounter._input(_touch(1, Vector2(199, 152), true))
	assert_gt(encounter.joy_axis.x, 0.9)
	assert_true(encounter.controls.jump)
	var start_x: float = encounter.model.state.x
	encounter._physics_process(1.0 / 60.0)
	assert_gt(float(encounter.model.state.x), start_x)
	assert_lt(float(encounter.model.state.vy), 0)
	encounter._input(_touch(0, Vector2(56, 152), false))
	assert_eq(encounter.joy_axis, Vector2.ZERO)
	assert_true(encounter.controls.jump)
	encounter._input(_touch(1, Vector2(199, 152), false))
	assert_false(encounter.controls.jump)
	var saved_x: float = encounter.model.state.x
	encounter._pause()
	assert_eq(view.mode, "pause")
	assert_true(game.load_game())
	view.refresh()
	assert_almost_eq(float(view.encounter.model.state.x), saved_x, 0.001)
	assert_eq(view.encounter.joy_axis, Vector2.ZERO)


func test_gameplay_cannot_finish_before_objective_is_won() -> void:
	game.go("ch01_s03_n80")
	view.refresh()
	var original: String = game.state.node
	view._complete_beat()
	assert_eq(game.state.node, original)
	var factory = load("res://scripts/gameplay/encounter_factory.gd")
	assert_gte(factory.solve(view.encounter.model, "tactical"), 0)
	view._complete_beat()
	assert_ne(game.state.node, original)
	assert_true("beat_ch01_s03" in game.state.beats_completed)
