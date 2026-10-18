extends SceneTree
## Real-renderer layout and touch regression matrix. Uses an isolated save.

const Lore = preload("res://scripts/lore_library.gd")
const UI = preload("res://scripts/roman_ui.gd")

var game: Node
var view: Control
var failures: Array[String] = []
var frames: Array = []
var output: String = "res://build/ui/1280x720"
var checks: int = 0
var touches: int = 0
var capture: bool = true
var quick: bool = false
var last_shot: String
var density: float = 1.0


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures.append(last_shot + ": " + message)


func _controls(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			result.append(child)
		result.append_array(_controls(child))
	return result


func _check_layout() -> Array[Button]:
	var buttons: Array[Button] = []
	var safe: Rect2 = UI.safe_rect(view)
	for control in _controls(view):
		var bounds: Rect2 = control.get_global_rect()
		var ancestor: Node = control.get_parent()
		while ancestor is Control:
			if ancestor.clip_contents:
				bounds = bounds.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		if control is ScrollBar or control.get_parent() is ScrollBar:
			continue
		checks += 1
		if not safe.grow(1).encloses(bounds):
			_fail("outside safe area: %s %s / %s" % [control.get_class(), bounds, safe])
		if control is Label and not control.text.is_empty():
			var minimum: Vector2 = control.get_minimum_size()
			if control.autowrap_mode == TextServer.AUTOWRAP_WORD:
				var face: Font = control.get_theme_font("font")
				var font_size: int = control.get_theme_font_size("font_size")
				for word in control.text.replace("\n", " ").split(" ", false):
					if (
						face.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
						> control.size.x + 1
					):
						_fail("button word crosses its text area: " + word)
			if control.has_meta("text_budget"):
				var budget: Vector2 = control.get_meta("text_budget")
				if minimum.y > budget.y + 1:
					_fail("status text crosses its frame: " + control.text.left(70))
			if minimum.x > control.size.x + 1 or minimum.y > control.size.y + 1:
				_fail(
					(
						"clipped label: %s min=%s size=%s"
						% [control.text.left(70), minimum, control.size]
					)
				)
			if (
				control.get_parent() is Button
				and not control.get_parent().get_global_rect().grow(-1).encloses(bounds)
			):
				_fail("caption crosses its button frame: " + control.text.left(70))
		if control is RichTextLabel and not control.scroll_active:
			if control.get_content_height() > control.size.y + 1:
				_fail("clipped dialogue page")
		if control is Button:
			buttons.append(control)
			for obstacle in control.get_meta("avoid_rects", []):
				var actor: Rect2 = (
					control.get_parent().get_global_transform_with_canvas() * obstacle
				)
				if bounds.intersects(actor):
					_fail("context button obscures an actor or object")
			if control.has_meta("avoid_rect"):
				var caption: Rect2 = (
					control.get_parent().get_global_transform_with_canvas()
					* control.get_meta("avoid_rect")
				)
				if bounds.grow(1).intersects(caption):
					_fail("context button obscures NPC caption")
			var pixels: Vector2 = get_root().get_screen_transform().get_scale() * bounds.size
			if minf(pixels.x, pixels.y) < 48.0 * density - 0.1:
				_fail("touch area below 48 pixels at density 1: " + str(pixels))
			if control.pressed.get_connections().is_empty():
				_fail("unwired button")
	# One pixel padding rejects touching targets while tolerating fractional rounding.
	for index in range(buttons.size()):
		for other in range(index):
			if buttons[index].get_global_rect().grow(1).intersects(
				buttons[other].get_global_rect().grow(1)
			):
				_fail(
					(
						"overlapping buttons: %s / %s"
						% [
							buttons[index].get_meta("caption", "?"),
							buttons[other].get_meta("caption", "?")
						]
					)
				)
	return buttons


func _tap_buttons(buttons: Array[Button]) -> void:
	# Isolate navigation callbacks while testing actual input dispatch. Business outcomes
	# are verified separately by GUT and the full campaign bot.
	var saved_links: Dictionary = {}
	for button in buttons:
		saved_links[button] = button.pressed.get_connections()
		for link in saved_links[button]:
			button.pressed.disconnect(link.callable)
	view.set_process_unhandled_input(false)
	for button in buttons:
		var received: Array = [0]
		var probe: Callable = func(): received[0] += 1
		button.pressed.connect(probe)
		var point: Vector2 = button.get_global_rect().get_center()
		for pressed in [true, false]:
			var touch = InputEventScreenTouch.new()
			touch.index = 7
			touch.position = root.get_screen_transform() * point
			touch.pressed = pressed
			Input.parse_input_event(touch)
			await process_frame
		var expected: int = 0 if button.disabled else 1
		if received[0] != expected:
			_fail(
				(
					"touch not delivered: %s received=%d"
					% [button.get_meta("caption", "?"), received[0]]
				)
			)
		button.pressed.disconnect(probe)
		touches += 1
	for button in buttons:
		for link in saved_links[button]:
			button.pressed.connect(link.callable, link.flags)
	view.set_process_unhandled_input(true)


func _shot(caption: String, tap: bool = false) -> void:
	last_shot = caption
	await process_frame
	await process_frame
	var buttons: Array[Button] = _check_layout()
	if is_instance_valid(view.get("body")):
		var text_pixels: float = (
			view.body.get_theme_font_size("normal_font_size")
			* root.get_screen_transform().get_scale().y
		)
		if text_pixels < 16.0 * density - 0.1:
			_fail("reading text below 16 sp")
		for page in view.pages:
			view.body.text = page
			if view.body.get_content_height() > view.body.size.y + 1:
				_fail("long dialogue page overflows")
		view.body.text = view.pages[view.page_index]
		view._reveal()
	if capture:
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		if picture == null or picture.is_empty():
			_fail("renderer returned an empty image")
		else:
			picture.save_png(output + "/" + caption + ".png")
	if tap:
		if is_instance_valid(view.get("body")):
			view._show_page()
		await _tap_buttons(buttons)
	frames.append(caption)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--no-capture":
			capture = false
		elif arg == "--quick":
			quick = true
		elif arg.begins_with("--density="):
			density = float(arg.trim_prefix("--density="))
			UI.density_override = density
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = root.get_node("StoryRuntime")
	game.save_path = "user://ui_matrix_%s.json" % OS.get_process_id()
	game.slot_prefix = "user://ui_matrix_slot_%s_" % OS.get_process_id()
	view = load("res://scenes/StoryMain.tscn").instantiate()
	root.add_child(view)
	await _shot("menu", true)
	view._new_game()
	await _shot("dialogue", true)
	view._pause()
	await _shot("pause", true)
	view._slots()
	await _shot("saves", true)
	view._open_settings(view.menu)
	await _shot("settings", true)
	view._comfort()
	await _shot("comfort", true)
	view._recap()
	await _shot("recap", true)
	view._library("chronicle")
	await _shot("chronicle", true)
	var chronicle_view: Control = view.layer.get_child(0)
	chronicle_view._open_article(Lore.entries(game.state)[0])
	await _shot("chronicle_article", true)
	view._library("fate")
	await _shot("fate", true)
	view._gallery()
	await _shot("locked_gallery", true)
	var library: Control = view.layer.get_child(0)
	for painting in Lore.gallery(game.state):
		if painting.unlocked:
			library._open_picture(painting.file)
			break
	await _shot("gallery_fullscreen", true)
	library._zoom(1.0)
	await _shot("gallery_zoom", true)
	view._credits()
	await _shot("credits", true)
	view._licenses()
	await _shot("licenses", true)
	view._chapters()
	await _shot("campaign", true)
	view._log()
	await _shot("log", true)
	for pair in [["ch01_s01_n75", "hub"], ["ch01_s03_n80", "cinematic"], ["ch01_s06_n80", "soft"]]:
		game.start_new()
		game.go(pair[0])
		view.refresh()
		await _shot(pair[1], true)
		preload("res://scripts/gameplay/encounter_factory.gd").solve(
			view.encounter.model, game.beats[game.current().beat].type
		)
		if game.beats[game.current().beat].type == "rpg":
			view.encounter._result()
		elif game.beats[game.current().beat].type == "cutscene":
			view.encounter._rebuild()
		else:
			view.encounter._build()
		await _shot(pair[1] + "_result", true)
	game.start_new()
	game.go("ch01_s01_n75")
	view.refresh()
	var merchant: Dictionary = view.encounter.model.stations[2]
	view.encounter.model.state.x = merchant.x
	view.encounter.model.state.y = merchant.y
	view.encounter._shop()
	await _shot("shop", true)
	view.encounter._close_panel()
	# The hidden diagnostic switch must also work without a hardware keyboard.
	for index in range(5):
		for pressed in [true, false]:
			var touch = InputEventScreenTouch.new()
			touch.index = 9
			touch.position = (
				root.get_screen_transform() * (view.layer.global_position + Vector2(300, 44))
			)
			touch.pressed = pressed
			Input.parse_input_event(touch)
			await process_frame
	if not view.encounter.debug_interactions:
		_fail("five header touches did not enable interaction debug")
	await _shot("hub_debug", true)
	view.encounter.debug_interactions = false
	# Reproduce the player's overlap position, then tap the real contextual action.
	view.encounter.model.state.quest = 1
	view.encounter.model.state.x = 180.0
	view.encounter.model.state.y = 106.0
	view.encounter._update_status()
	await _shot("hub_supplies_overlap", true)
	if view.encounter.nearby_button.get_meta("caption") != "Взять":
		_fail("supplies prompt does not say Take")
	var take_point: Vector2 = view.encounter.nearby_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch = InputEventScreenTouch.new()
		touch.index = 8
		touch.position = root.get_screen_transform() * take_point
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await process_frame
	if int(view.encounter.model.state.quest) != 2:
		_fail("real touch failed to take quest supplies")
	for index in range(4):
		var station: Dictionary = view.encounter.model.stations[[0, 1, 3, 4][index]]
		view.encounter.model.state.x = station.x
		view.encounter.model.state.y = station.y
		view.encounter.model.state.quest = index
		if index < 3:
			view.encounter.model.interact()
		view.encounter._update_status()
		await _shot("hub_step_%d" % index, true)
	# Real quest messages can wrap farther than the initial hub introduction.
	for encounter in game.read_json("res://story/beats.json").beats:
		for key in encounter.get("hub_dialogue", {}):
			view.encounter.model.state.quest = (
				{"intro": 0, "request": 1, "collected": 2, "delivered": 3}.get(key, 1)
			)
			view.encounter.model.state.message = encounter.hub_dialogue[key].ru
			view.encounter._update_status()
			await process_frame
			_check_layout()
	var services: Node = root.get_node("GameServices")
	services.settings.button_scale = 1.3
	services.settings.button_offset = 8.0
	game.start_new()
	game.go("ch01_s06_n80")
	view.refresh()
	await _shot("large_controls", true)
	services.settings.button_scale = 1.0
	services.settings.button_offset = 0.0
	services.settings.left_handed = true
	game.go("ch01_s01_n75")
	view.refresh()
	await _shot("left_handed_hub", true)
	game.go("ch01_s06_n80")
	view.refresh()
	await _shot("left_handed_soft", true)
	services.settings.left_handed = false
	view.set_meta("safe_insets", Vector4(32, 16, 48, 28))
	view.menu()
	await _shot("notch_menu", true)
	view.remove_meta("safe_insets")
	if not quick:
		for chapter in range(1, 9):
			game.start_new(chapter)
			var data: Dictionary = game.read_json("res://story/chapters/ch%02d.json" % chapter)
			for scene in data.scenes:
				game.go(scene.entry)
				view.refresh()
				await _shot(scene.id)
			for node in data.nodes:
				if node.has("choices") or node.get("kind") in ["beat", "ending"]:
					game.go(node.id)
					view.refresh()
					await _shot(node.id, true)
				elif node.get("text", {}).get("ru", "") != "":
					for page in view._paginate(node.text.ru):
						for line in page.split("\n"):
							if (
								(
									view
									. font
									. get_string_size(
										line, HORIZONTAL_ALIGNMENT_LEFT, -1, view.text_size
									)
									. x
								)
								> view._width() - 224
							):
								_fail("text exceeds page width in " + node.id)
		for beat in game.beats.values():
			if beat.type != "cutscene":
				continue
			game.go(beat.node)
			game.state.gameplay.encounter = {}
			view.refresh()
			var cinematic: Control = view.encounter
			for step in range(12):
				cinematic._rebuild()
				await _shot(beat.cutscene + "_frame_%02d" % step, true)
				if cinematic.model.state.won:
					break
				cinematic.model.bot_step(0)

	view.queue_free()
	await process_frame
	view = load("res://scenes/AssetGallery.tscn").instantiate()
	root.add_child(view)
	await process_frame
	for group in range(5):
		view._select_group(group)
		await _shot("gallery_%d" % group, true)
	var report: Dictionary = {
		"resolution": [root.size.x, root.size.y],
		"frames": frames,
		"checks": checks,
		"touches": touches,
		"errors": failures
	}
	var report_file = FileAccess.open(output + "/report.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	for failure in failures.slice(0, 30):
		printerr(failure)
	print(
		(
			"UI MATRIX: %d frames, %d checks, %d touches, %d failures"
			% [frames.size(), checks, touches, failures.size()]
		)
	)
	view.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	quit(0 if failures.is_empty() else 1)
