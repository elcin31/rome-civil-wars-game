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
	await get_tree().process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))


func _touch(index: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	return event


func test_soft_controls_pause_and_in_episode_reload() -> void:
	game.go("ch01_s06_n80")
	view.refresh()
	var encounter: Control = view.encounter
	assert_not_null(encounter)
	var start_x: float = encounter.model.state.x
	encounter._move(1.0)
	encounter._cover(true)
	encounter._process(0.1)
	assert_gt(float(encounter.model.state.x), start_x)
	assert_true(encounter.model.state.cover)
	var saved_x: float = encounter.model.state.x
	encounter.persist()
	view._pause()
	assert_eq(view.mode, "pause")
	assert_true(game.load_game())
	view.refresh()
	assert_almost_eq(float(view.encounter.model.state.x), saved_x, 0.001)
	assert_eq(view.encounter.axis, 0.0)


func test_gameplay_cannot_finish_before_objective_is_won() -> void:
	game.go("ch01_s03_n80")
	view.refresh()
	var original: String = game.state.node
	view._complete_beat()
	assert_eq(game.state.node, original)
	var factory = load("res://scripts/gameplay/encounter_factory.gd")
	assert_gte(factory.solve(view.encounter.model, "cutscene"), 0)
	view._complete_beat()
	assert_ne(game.state.node, original)
	assert_true("beat_ch01_s03" in game.state.beats_completed)


func test_dialogue_buttons_follow_page_and_reveal_state() -> void:
	view._new_game()
	assert_gt(view.pages.size(), 1)
	assert_true(view.previous_button.disabled)
	assert_false(view.reveal_button.disabled)
	view._reveal()
	assert_true(view.reveal_button.disabled)
	view._next()
	assert_eq(view.page_index, 1)
	assert_false(view.previous_button.disabled)
	view._previous_page()
	assert_eq(view.page_index, 0)
	assert_true(view.previous_button.disabled)


func test_campaign_map_preserves_current_story_decisions() -> void:
	for step in range(200):
		if game.current().has("choices"):
			break
		if game.current().get("kind") == "beat":
			game.complete_beat()
		else:
			game.advance()
	game.choose(game.first_choice())
	var node: String = game.state.node
	var decisions: Array = game.state.decisions.duplicate(true)
	view._chapters()
	view._campaign_resume()
	assert_eq(game.state.node, node)
	assert_eq(game.state.decisions, decisions)


func test_hints_obey_preference_and_manual_help_remains_available() -> void:
	game.go("ch01_s01_n75")
	view.refresh()
	var services: Node = get_node("/root/GameServices")
	var previous: bool = services.settings.hints
	services.set_preference("hints", false, false)
	var initial: String = view.encounter.model.state.message
	view.encounter._physics_process(20.1)
	assert_eq(view.encounter.model.state.message, initial)
	services.set_preference("hints", true, false)
	view.encounter._physics_process(0.1)
	assert_eq(view.encounter.model.state.message, view.encounter.model.hint_text())
	view.encounter.model.state.quest = 1
	view.encounter._hint()
	assert_true(view.encounter.model.state.message.contains("Взять"))
	assert_eq(game.state.gameplay.encounter.state.quest, 1)
	services.set_preference("hints", previous, false)


func test_journal_opens_at_the_current_quest_step() -> void:
	game.go("ch01_s01_n75")
	view.refresh()
	view.encounter.model.state.quest = 2
	view.encounter._journal()
	assert_eq(view.mode, "log")
	var text: String = ""
	for child in view.layer.get_children():
		if child is RichTextLabel:
			text += child.text
	assert_true(text.contains("3/3"))
	assert_true(text.contains("Передать"))
