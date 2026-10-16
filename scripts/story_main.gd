extends Control

const INK = Color("14151f")
const IVORY = Color("ede3cc")
const BRONZE = Color("a87b3d")
const OCHRE = Color("d9a441")
var layer: Control
var mode: String = "menu"
var background: Texture2D
var face: Texture2D
var body: RichTextLabel
var pages: Array[String] = []
var page_index: int = 0
var letters: float = 0.0
var font: Font
var test_route: String = "legion"


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_set_background("res://assets/locations/roman_camp.png")
	menu()


func _clear(new_mode: String) -> void:
	mode = new_mode
	body = null
	face = null
	if is_instance_valid(layer):
		remove_child(layer)
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	queue_redraw()


func _set_background(path: String) -> void:
	if ResourceLoader.exists(path):
		background = load(path)


func _label(value: String, rect: Rect2, size_value: int = 9, color: Color = IVORY) -> Label:
	var label = Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.clip_text = true
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(label)
	return label


func _button(value: String, rect: Rect2, callback: Callable, enabled: bool = true) -> Button:
	var button = Button.new()
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 9)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("4a3026") if state == "pressed" else INK
		style.border_color = OCHRE if state in ["focus", "hover"] else BRONZE
		style.set_border_width_all(1)
		style.set_content_margin_all(1)
		button.add_theme_stylebox_override(state, style)
	button.position = rect.position
	button.pressed.connect(callback)
	layer.add_child(button)
	button.size = rect.size
	button.set_deferred("size", rect.size)
	var label = Label.new()
	label.text = value
	label.position = Vector2(3, 1)
	label.size = rect.size - Vector2(6, 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", IVORY if enabled else BRONZE)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button


func menu(message: String = "") -> void:
	_clear("menu")
	_label(StoryRuntime.tr_ui("title"), Rect2(77, 10, 200, 22), 19, OCHRE)
	_label(StoryRuntime.tr_ui("subtitle"), Rect2(115, 35, 180, 18), 11)
	_button(StoryRuntime.tr_ui("new_game"), Rect2(80, 64, 160, 22), _new_request)
	_button(StoryRuntime.tr_ui("continue"), Rect2(80, 90, 160, 22), _continue,
		FileAccess.file_exists(StoryRuntime.SAVE_PATH))
	_button(StoryRuntime.tr_ui("chapters"), Rect2(80, 116, 160, 22), _chapters)
	_button(StoryRuntime.tr_ui("gallery"), Rect2(80, 142, 160, 22), _gallery)
	if not message.is_empty():
		_label(message, Rect2(4, 166, 312, 14), 8, OCHRE)


func _new_request() -> void:
	if not FileAccess.file_exists(StoryRuntime.SAVE_PATH):
		_new_game()
		return
	_clear("confirm")
	var text = _label(StoryRuntime.tr_ui("confirm_new"), Rect2(30, 40, 260, 42), 11)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(StoryRuntime.tr_ui("yes"), Rect2(35, 103, 120, 30), _new_game)
	_button(StoryRuntime.tr_ui("no"), Rect2(165, 103, 120, 30), menu)


func _new_game(chapter: int = 1) -> void:
	StoryRuntime.start_new(chapter, test_route)
	refresh()


func _continue() -> void:
	if StoryRuntime.load_game():
		refresh()
	else:
		menu(StoryRuntime.tr_ui("bad_save"))


func _chapters() -> void:
	_clear("chapters")
	_label(StoryRuntime.tr_ui("chapter_test"), Rect2(40, 8, 260, 20), 12, OCHRE)
	for i in range(8):
		var chapter = StoryRuntime.chapters[i]
		_button(str(i + 1) + ". " + chapter.title.ru,
			Rect2(4 + i % 4 * 79, 35 + (i / 4) * 43, 75, 39), _new_game.bind(i + 1))
	_button(StoryRuntime.tr_ui("legion"), Rect2(24, 127, 126, 20), _set_route.bind("legion"))
	_button(StoryRuntime.tr_ui("citizen"), Rect2(170, 127, 126, 20), _set_route.bind("citizen"))
	_label(StoryRuntime.tr_ui(test_route), Rect2(136, 151, 100, 15), 8, OCHRE)
	_button(StoryRuntime.tr_ui("back"), Rect2(4, 158, 70, 20), menu)


func _set_route(value: String) -> void:
	test_route = value
	_chapters()


func _gallery() -> void:
	get_tree().change_scene_to_file("res://scenes/AssetGallery.tscn")


func refresh() -> void:
	_clear("play")
	var node = StoryRuntime.current()
	var scene = StoryRuntime.current_scene()
	var picture: String = scene.get("illustration", "assets/locations/roman_camp.png")
	for variant in scene.get("illustration_variants", []):
		if StoryRuntime.condition(variant.get("condition", "")):
			picture = variant.file
			break
	_set_background("res://" + picture)
	_button(StoryRuntime.tr_ui("menu"), Rect2(2, 1, 42, 16), _pause)
	_label(scene.get("title", {}).get("ru", ""), Rect2(49, 1, 120, 14), 8, OCHRE)
	_label(StoryRuntime.tr_ui("bond").format({"bond": int(StoryRuntime.state.bond)}), Rect2(174, 1, 80, 14), 8)
	_button(StoryRuntime.tr_ui("log"), Rect2(258, 1, 60, 16), _log)
	if node.get("kind") == "ending":
		_label(StoryRuntime.tr_ui("ending"), Rect2(8, 112, 305, 17), 10, OCHRE)
		_label(scene.title.ru, Rect2(8, 130, 305, 22), 14)
		_button(StoryRuntime.tr_ui("restart"), Rect2(80, 158, 160, 20), menu)
		return
	if node.has("choices"):
		var count: int = node.choices.size()
		var height_value: int = mini(39, 148 / maxi(1, count))
		for i in range(count):
			var option = node.choices[i]
			var available: bool = StoryRuntime.condition(option.get("condition", ""))
			var caption: String = option.text.ru
			if not available: caption += "\n" + option.get("requirement_text", {}).get("ru", StoryRuntime.tr_ui("locked_choice"))
			_button(caption, Rect2(12, 25 + i * height_value, 296, height_value - 2), _choose.bind(i), available)
		return
	if node.get("kind") == "beat":
		_show_beat(node)
		return
	var who: String = node.get("speaker", "narrator")
	var name_value: String = StoryRuntime.characters.get(who, {}).get("name", {}).get("ru", who)
	_label(name_value, Rect2(57, 85, 250, 14), 9, OCHRE)
	var portrait: String = node.get("portrait", "")
	if StoryRuntime.portraits.has(portrait):
		var path: String = "res://" + StoryRuntime.portraits[portrait].file
		if ResourceLoader.exists(path):
			face = load(path)
		_label(StoryRuntime.tr_ui(StoryRuntime.portraits[portrait].emotion), Rect2(3, 151, 52, 10), 7, BRONZE)
	body = RichTextLabel.new()
	body.position = Vector2(57, 100)
	body.size = Vector2(258, 61)
	body.scroll_active = false
	body.bbcode_enabled = false
	body.add_theme_font_override("normal_font", font)
	body.add_theme_font_size_override("normal_font_size", 9)
	body.add_theme_color_override("default_color", IVORY)
	body.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(body)
	pages = _paginate(node.get("text", {}).get("ru", ""))
	page_index = 0
	_show_page()
	_button(StoryRuntime.tr_ui("back"), Rect2(3, 164, 50, 15), _previous_page)
	_button(StoryRuntime.tr_ui("reveal"), Rect2(57, 164, 149, 15), _reveal)
	_button(StoryRuntime.tr_ui("next"), Rect2(211, 164, 106, 15), _next)


func _paginate(text: String) -> Array[String]:
	var output: Array[String] = []
	var line: String = ""
	var page: String = ""
	var rows: int = 0
	for word in text.replace("\n", " \n ").split(" ", false):
		var candidate: String = word if line.is_empty() else line + " " + word
		if word == "\n" or font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x > 254:
			page += ("" if page.is_empty() else "\n") + line
			rows += 1
			line = "" if word == "\n" else word
			if rows >= 4:
				output.append(page)
				page = ""
				rows = 0
		else:
			line = candidate
	if not line.is_empty():
		page += ("" if page.is_empty() else "\n") + line
	if not page.is_empty():
		output.append(page)
	if output.is_empty(): output.append("")
	return output


func _show_page() -> void:
	letters = 0
	body.text = pages[page_index]
	body.visible_characters = 0


func _process(delta: float) -> void:
	if mode == "play" and is_instance_valid(body):
		letters += delta * 36
		body.visible_characters = mini(int(letters), body.text.length())


func _reveal() -> void:
	if is_instance_valid(body):
		letters = body.text.length()
		body.visible_characters = -1


func _previous_page() -> void:
	if page_index > 0:
		page_index -= 1
		_show_page()


func _next() -> void:
	if mode != "play" or not is_instance_valid(body): return
	if letters < body.text.length():
		_reveal()
	elif page_index + 1 < pages.size():
		page_index += 1
		_show_page()
	else:
		StoryRuntime.advance()
		refresh()


func _choose(index: int) -> void:
	if StoryRuntime.choose(index): refresh()


func _show_beat(node: Dictionary) -> void:
	var beat = StoryRuntime.beats[node.beat]
	_label(beat.title.ru, Rect2(12, 28, 296, 24), 13, OCHRE)
	var description: String = StoryRuntime.tr_ui("objective") + ": " + beat.objective.ru + "\n"
	description += StoryRuntime.tr_ui("victory") + ":\n"
	for requirement in beat.victory: description += "• " + requirement.ru + "\n"
	var label = _label(description, Rect2(12, 57, 296, 90), 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(StoryRuntime.tr_ui("complete_plan"), Rect2(75, 151, 170, 25), _complete_beat)


func _complete_beat() -> void:
	StoryRuntime.complete_beat()
	refresh()


func _pause() -> void:
	_clear("pause")
	_label(StoryRuntime.tr_ui("pause"), Rect2(130, 8, 120, 20), 13, OCHRE)
	_button(StoryRuntime.tr_ui("resume"), Rect2(75, 38, 170, 23), refresh)
	_button(StoryRuntime.tr_ui("log"), Rect2(75, 64, 170, 23), _log)
	_button(StoryRuntime.tr_ui("skip"), Rect2(75, 90, 170, 23), _skip)
	_button(StoryRuntime.tr_ui("chapters"), Rect2(75, 116, 170, 23), _chapters)
	_button(StoryRuntime.tr_ui("menu"), Rect2(75, 142, 170, 23), menu)


func _skip() -> void:
	StoryRuntime.skip_scene()
	refresh()


func _log() -> void:
	_clear("log")
	_button(StoryRuntime.tr_ui("back"), Rect2(2, 1, 60, 20), refresh)
	var log_text: String = ""
	for item in StoryRuntime.state.get("history", []):
		log_text += StoryRuntime.characters.get(item.speaker, {}).get("name", {}).get("ru", item.speaker) + ": " + item.text + "\n\n"
	var log_view = RichTextLabel.new()
	log_view.position = Vector2(5, 26)
	log_view.size = Vector2(310, 150)
	log_view.bbcode_enabled = false
	log_view.text = log_text
	log_view.add_theme_font_size_override("normal_font_size", 9)
	log_view.add_theme_color_override("default_color", IVORY)
	layer.add_child(log_view)
	log_view.scroll_to_line(maxi(0, log_view.get_line_count() - 5))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if mode == "play": _pause()
			elif not StoryRuntime.state.is_empty(): refresh()
			else: menu()
		elif event.keycode in [KEY_SPACE, KEY_ENTER]: _next()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), INK)
	if background: draw_texture_rect(background, Rect2(0, 0, 320, 180), false)
	if mode == "play":
		draw_rect(Rect2(0, 0, 320, 18), INK)
		if StoryRuntime.current().get("kind") not in ["choice", "beat", "ending"]:
			draw_rect(Rect2(0, 82, 320, 98), INK)
			draw_line(Vector2(0, 82), Vector2(320, 82), BRONZE)
			if face: draw_texture_rect(face, Rect2(4, 100, 48, 48), false)
		else:
			draw_rect(Rect2(5, 22, 310, 156), Color(0.078, 0.082, 0.121, .86))
	else:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.078, 0.082, 0.121, .9))
