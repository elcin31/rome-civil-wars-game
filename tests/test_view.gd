extends "res://addons/gut/test.gd"

const UI = preload("res://scripts/roman_ui.gd")

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


func test_art_keeps_aspect_and_covers_all_screens_during_pan_and_zoom() -> void:
	var image: Vector2 = Vector2(480, 270)
	for area in [
		Vector2(1280, 720),
		Vector2(1920, 1080),
		Vector2(2160, 1080),
		Vector2(2340, 1080),
		Vector2(2400, 1080),
		Vector2(2560, 1080),
		Vector2(800, 480)
	]:
		for density in [1.0, 2.625]:
			for zoom in [1.0, 1.15]:
				for offset in [Vector2.ZERO, Vector2(-5000, 5000), Vector2(5000, -5000)]:
					var rect: Rect2 = UI.cover_rect(image, area, density, zoom, offset)
					assert_almost_eq(rect.size.x / image.x, rect.size.y / image.y, 0.0001)
					assert_lte(rect.position.x, 0.001)
					assert_lte(rect.position.y, 0.001)
					assert_gte(rect.end.x, area.x - 0.001)
					assert_gte(rect.end.y, area.y - 0.001)
					if zoom == 1.0:
						var pixel_scale: float = rect.size.x / image.x * density
						assert_almost_eq(pixel_scale, roundf(pixel_scale), 0.0001)


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


func test_library_reflow_preserves_draft_query_filter_and_input_focus() -> void:
	view._library("chronicle")
	var library: Control = view.layer.get_child(0)
	library.query = "Цицерон"
	library.category = "people"
	var search: LineEdit = library.find_children("*", "LineEdit", true, false)[0]
	search.text = "54"
	search.grab_focus()
	assert_true(search.has_focus())
	view._reflow()
	var resumed: Control = view.layer.get_child(0)
	var input: LineEdit = resumed.find_children("*", "LineEdit", true, false)[0]
	assert_eq(resumed, library, "Viewport/keyboard resize must retain the active library")
	assert_eq(resumed.query, "Цицерон")
	assert_eq(resumed.category, "people")
	assert_eq(input.text, "54", "Unsubmitted text survives a viewport resize")
	assert_true(input.has_focus(), "Resizing must not dismiss the focused search field")


func test_library_reflow_keeps_gallery_tab_picture_zoom_and_pan() -> void:
	view._library("chronicle")
	var library: Control = view.layer.get_child(0)
	library._tab("gallery")
	library._open_picture("assets/cs/cicero_01.png")
	library._zoom(1.0)
	library.offset = Vector2(12, 0)
	view._reflow()
	var resumed: Control = view.layer.get_child(0)
	assert_eq(resumed.tab, "gallery")
	assert_eq(resumed.picture_file, "assets/cs/cicero_01.png")
	assert_eq(resumed.zoom_value, 2.0)
	assert_eq(resumed.offset, Vector2(12, 0))


func test_menu_library_ignores_corrupt_progress_without_loading_a_story() -> void:
	var corrupt: Dictionary = game.state.duplicate(true)
	corrupt.progress = "broken"
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + ".bak"))
	game.state = {}
	view.menu()
	view._library("gallery")
	assert_eq(game.state, {})
	assert_eq(view.layer.get_child(0).state, {})
	view.layer.get_child(0)._tab("fate")
	assert_eq(game.state, {})


func test_short_chronicle_keeps_search_without_overlapping_result_navigation() -> void:
	view._library("chronicle")
	var library: Control = view.layer.get_child(0)
	library.size = Vector2(960, UI.touch_height(library) * 2 + 100)
	library.build()
	assert_true(library.search_field.is_visible_in_tree())
	for button in library.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree():
			continue
		assert_ne(button.get_meta("caption", button.text), "Следующая")
		assert_lte(button.get_global_rect().end.y, library.get_global_rect().end.y)


func test_auto_advance_keeps_counting_after_text_is_fully_revealed() -> void:
	var previous: bool = GameServices.settings.auto_advance
	GameServices.set_preference("auto_advance", true, false)
	view._new_game()
	view._reveal()
	view.auto_clock = maxf(3.0, view.body.text.length() / 18.0) - 0.2
	for frame in range(3):
		view._process(0.1)
	assert_eq(view.page_index, 1)
	game.go("ch01_s01_n90")
	view.refresh()
	var before: Array = game.state.decisions.duplicate(true)
	view._process(100.0)
	assert_eq(game.state.node, "ch01_s01_n90", "Automatic reading never picks a decision")
	assert_eq(game.state.decisions, before)
	GameServices.set_preference("auto_advance", previous, false)


func test_skip_read_advances_remembered_pages_but_waits_on_new_text() -> void:
	var previous: bool = GameServices.settings.skip_read
	var remembered: Dictionary = GameServices.read_nodes.duplicate(true)
	GameServices.set_preference("skip_read", true, false)
	view._new_game()
	GameServices.read_nodes[game.current().id] = true
	for frame in range(3):
		view._process(0.2)
	assert_eq(view.page_index, 1)
	GameServices.read_nodes.erase(game.current().id)
	for frame in range(5):
		view._process(0.2)
	assert_eq(view.page_index, 1)
	GameServices.read_nodes = remembered
	GameServices.set_preference("skip_read", previous, false)


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
