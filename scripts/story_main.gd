extends Control

const INK = Color("14151f")
const IVORY = Color("ede3cc")
const BRONZE = Color("a87b3d")
const OCHRE = Color("d9a441")
const UI = preload("res://scripts/roman_ui.gd")
const LibraryView = preload("res://scripts/library_view.gd")
const Lore = preload("res://scripts/lore_library.gd")
const SoftView = preload("res://scripts/gameplay/soft_view.gd")
const CutsceneView = preload("res://scripts/gameplay/cutscene_view.gd")
const EncounterView = preload("res://scripts/gameplay/encounter_view.gd")
var layer: Control
var mode: String = "menu"
var background: Texture2D
var background_layers: Array[Texture2D] = []
var face: Texture2D
var body: RichTextLabel
var pages: Array[String] = []
var page_index: int = 0
var letters: float = 0.0
var font: Font
var test_route: String = "legion"
var settings_return: Callable
var encounter: Control
var transition_serial: int = 0
var resizing: bool = false
var portrait_rect: Rect2
var text_size: int = 24
var ambience_clock: float = 0.0
var probe_clock: float = 0.0
var previous_button: Button
var library_tab: String = "gallery"
var library_view: Control
var last_shown_chapter: int = 1
var auto_clock: float = 0
var reveal_button: Button


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = UI.theme_resource()
	font = theme.default_font
	_set_background("res://assets/locations/roman_camp.png")
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	menu()


func _clear(new_mode: String) -> void:
	transition_serial += 1
	GameServices.set_dialogue(false)
	if is_instance_valid(encounter):
		encounter.persist()
		encounter = null
	mode = new_mode
	library_view = null
	body = null
	face = null
	previous_button = null
	reveal_button = null
	if is_instance_valid(layer):
		# A button callback may still be on the GUI dispatch stack. Keep its nodes
		# inside the tree until deferred deletion, but hide and stop them immediately.
		layer.hide()
		layer.process_mode = Node.PROCESS_MODE_DISABLED
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	var safe: Rect2 = UI.safe_rect(self)
	layer.position = safe.position
	layer.size = safe.size
	add_child(layer)
	queue_redraw()


func _width() -> float:
	return layer.size.x


func _height() -> float:
	return layer.size.y


func _touch() -> float:
	return UI.touch_height(self)


func _footer_y() -> float:
	return _height() - _touch() - 16


func _content_top() -> float:
	return maxf(96, _touch() + 32)


func _heading(title: String, back: Callable, back_text: String = "Назад") -> void:
	_button(back_text, Rect2(16, 14, 132, _touch()), back)
	UI.heading(layer, title, Rect2(168, 14, _width() - 188, _touch()), 30, OCHRE)


func _reading_panel(value: String, top: float, bottom: float, font_size: int = 24) -> RichTextLabel:
	UI.panel(layer, Rect2(16, top, _width() - 32, _height() - top - bottom))
	var text = RichTextLabel.new()
	text.position = Vector2(36, top + 16)
	text.size = Vector2(_width() - 72, _height() - top - bottom - 32)
	text.text = value
	text.bbcode_enabled = false
	text.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	text.add_theme_font_size_override("normal_font_size", font_size)
	text.set_meta("scroll_document", true)
	layer.add_child(text)
	return text


func _set_background(path: String) -> void:
	if ResourceLoader.exists(path):
		background = load(path)
		background_layers.clear()
		if path.begins_with("res://assets/locations/"):
			for suffix in ["far", "mid", "near"]:
				var layer_path: String = path.trim_suffix(".png") + "_" + suffix + ".png"
				if ResourceLoader.exists(layer_path):
					background_layers.append(load(layer_path))


func _label(value: String, rect: Rect2, size_value: int = 24, color: Color = IVORY) -> Label:
	return UI.label(layer, value, rect, size_value, color)


func _button(value: String, rect: Rect2, callback: Callable, enabled: bool = true) -> Button:
	return UI.button(layer, value, rect, callback, enabled)


func menu(message: String = "") -> void:
	_clear("menu")
	_set_background("res://assets/new_story/menu.png")
	GameServices.play_layer("city")
	var panel_width: float = minf(456, _width() * 0.49)
	UI.panel(layer, Rect2(24, 18, panel_width, _height() - 36))
	UI.heading(layer, "CINIS LAURI", Rect2(48, 34, panel_width - 48, 50), 42, OCHRE)
	_label("ПЕПЕЛ ЛАВРА", Rect2(48, 86, panel_width - 48, 34), 26)
	var captions: Array = [
		"Новая игра", "Продолжить", "Карта кампании", "Галерея", "Хроника", "Настройки"
	]
	var actions: Array[Callable] = [
		_new_request, _continue, _chapters, _gallery, _chronicle, _open_settings.bind(menu)
	]
	var dense: bool = (_height() - 156) / 6.0 < _touch() + 6
	var row: float = (_height() - 156) / (3.0 if dense else 6.0)
	var columns: int = 2 if dense else 1
	var cell: float = (panel_width - 40 - (12 if dense else 0)) / columns
	for index in range(6):
		_button(
			captions[index],
			Rect2(
				44 + (index % columns) * (cell + 12), 132 + row * (index / columns), cell, _touch()
			),
			actions[index],
			index != 1 or FileAccess.file_exists(StoryRuntime.save_path)
		)
	if not message.is_empty():
		UI.panel(layer, Rect2(panel_width + 48, _height() - 112, _width() - panel_width - 72, 88))
		_label(
			message,
			Rect2(panel_width + 64, _height() - 100, _width() - panel_width - 104, 64),
			24,
			OCHRE
		)


func _new_request() -> void:
	if not FileAccess.file_exists(StoryRuntime.save_path):
		_new_game()
		return
	_clear("confirm")
	UI.panel(layer, Rect2(48, 96, _width() - 96, _height() - 192))
	_label(StoryRuntime.tr_ui("confirm_new"), Rect2(80, 132, _width() - 160, 100), 30)
	var half: float = (_width() - 176) / 2
	_button("Начать заново", Rect2(80, _height() - 184, half, _touch()), _new_game)
	_button("Отмена", Rect2(96 + half, _height() - 184, half, _touch()), menu)


func _new_game(chapter: int = 1) -> void:
	StoryRuntime.start_new(chapter, test_route)
	refresh()


func _continue() -> void:
	if StoryRuntime.load_game(true):
		_recap()
	else:
		menu(StoryRuntime.tr_ui("bad_save"))


func _chapters() -> void:
	_library("campaign", "chapters")


func _campaign_resume() -> void:
	if not StoryRuntime.state.is_empty():
		refresh()
	elif FileAccess.file_exists(StoryRuntime.save_path):
		_continue()
	else:
		_new_game()


func _gallery() -> void:
	_library("gallery")


func _chronicle() -> void:
	_library("chronicle")


func _library(tab: String, screen_mode: String = "library") -> void:
	library_tab = tab
	var back: Callable = _log if mode == "log" else menu
	var snapshot: Dictionary = StoryRuntime.progress_snapshot()
	_clear(screen_mode)
	library_view = LibraryView.new()
	library_view.size = layer.size
	library_view.setup(tab, snapshot)
	library_view.closed.connect(back)
	library_view.resume_requested.connect(_campaign_resume)
	layer.add_child(library_view)


func _recap() -> void:
	last_shown_chapter = int(StoryRuntime.state.progress.chapter)
	_clear("recap")
	_heading("Ранее в игре", _pause)
	_reading_panel(
		"• " + "\n\n• ".join(Lore.recap(StoryRuntime.state)), _content_top(), _touch() + 40
	)
	_button("К истории", Rect2(16, _footer_y(), _width() - 32, _touch()), refresh)


func refresh() -> void:
	_clear("play")
	text_size = UI.accessible_font_size(self, [22, 26, 30][int(GameServices.settings.text_size)])
	var node = StoryRuntime.current()
	var scene = StoryRuntime.current_scene()
	var picture: String = scene.get("illustration", "assets/locations/roman_camp.png")
	for variant in scene.get("illustration_variants", []):
		if StoryRuntime.condition(variant.get("condition", "")):
			picture = variant.file
			break
	_set_background("res://" + picture)
	if node.get("kind") == "beat":
		_show_beat(node)
		return
	GameServices.set_dialogue(true)
	GameServices.play_layer("city")
	GameServices.set_ambience("forum" if int(StoryRuntime.state.progress.chapter) > 1 else "camp")
	UI.panel(layer, Rect2(8, 8, _width() - 16, maxf(76, _touch() + 16)))
	_button("Пауза", Rect2(16, 16, 120, _touch()), _pause)
	_label(scene.get("title", {}).get("ru", ""), Rect2(152, 14, _width() - 422, 64), 26, OCHRE)
	_label("Связь\n%d / 100" % int(StoryRuntime.state.bond), Rect2(_width() - 254, 16, 108, 60), 24)
	_button("Журнал", Rect2(_width() - 136, 16, 120, _touch()), _log)
	if node.get("kind") == "ending":
		UI.panel(layer, Rect2(24, _height() - _touch() - 154, _width() - 48, _touch() + 138))
		_label("КОНЕЦ ИСТОРИИ", Rect2(48, _height() - _touch() - 140, _width() - 96, 34), 26, OCHRE)
		_label(scene.title.ru, Rect2(48, _height() - _touch() - 98, _width() - 96, 60), 32)
		_button("В главное меню", Rect2(48, _footer_y(), _width() - 96, _touch()), menu)
		return
	if node.has("choices"):
		var count: int = node.choices.size()
		var row: float = (_height() - _content_top() - 16) / maxi(1, count)
		for index in range(count):
			var option = node.choices[index]
			var available: bool = StoryRuntime.condition(option.get("condition", ""))
			var caption: String = option.text.ru
			if not available:
				caption += (
					"\n"
					+ option.get("requirement_text", {}).get(
						"ru", StoryRuntime.tr_ui("locked_choice")
					)
				)
			_button(
				caption,
				Rect2(24, _content_top() + index * row, _width() - 48, row - 4),
				_choose.bind(index),
				available
			)
		return
	var who: String = node.get("speaker", "narrator")
	var actor: Dictionary = StoryRuntime.characters.get(who, {})
	var portrait: String = node.get("portrait", "")
	if portrait.is_empty():
		portrait = actor.get("default_portrait", "")
	assert(StoryRuntime.portraits.has(portrait), "Missing portrait for " + who)
	if StoryRuntime.portraits.has(portrait):
		face = load("res://" + StoryRuntime.portraits[portrait].file)
	var panel_top: float = _height() - 312 - maxf(0, _touch() - 58)
	UI.panel(layer, Rect2(16, panel_top, _width() - 32, 224), "parchment")
	portrait_rect = Rect2(32, panel_top + 24, 128, 128)
	var portrait_view = TextureRect.new()
	portrait_view.texture = face
	portrait_view.position = portrait_rect.position
	var physical_scale: float = get_viewport().get_screen_transform().get_scale().y
	var portrait_factor: float = (
		maxf(1, floorf(128 * physical_scale / face.get_width())) / physical_scale
	)
	portrait_view.size = face.get_size() * portrait_factor
	portrait_view.position += (portrait_rect.size - portrait_view.size) / 2
	portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_view.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(portrait_view)
	_label(
		actor.get("name", {}).get("ru", who),
		Rect2(184, panel_top + 12, _width() - 224, 36),
		28,
		OCHRE
	)
	body = RichTextLabel.new()
	body.position = Vector2(184, panel_top + 54)
	body.size = Vector2(_width() - 224, 152)
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.bbcode_enabled = false
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.add_theme_font_size_override("normal_font_size", text_size)
	body.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(body)
	pages = _paginate(node.get("text", {}).get("ru", ""))
	page_index = 0
	_show_page()
	previous_button = _button("Назад", Rect2(16, _footer_y(), 144, _touch()), _previous_page, false)
	reveal_button = _button(
		"Показать текст", Rect2(172, _footer_y(), _width() - 392, _touch()), _reveal
	)
	_button("Дальше", Rect2(_width() - 208, _footer_y(), 192, _touch()), _next)


func _paginate(text: String) -> Array[String]:
	var output: Array[String] = []
	var line: String = ""
	var page: String = ""
	var rows: int = 0
	var available_width: float = (
		body.size.x - 8 if is_instance_valid(body) else maxf(400, _width() - 232)
	)
	var available_height: float = body.size.y if is_instance_valid(body) else 152.0
	var line_height: float = ceilf(font.get_height(text_size)) + 6.0
	var line_limit: int = clampi(int((available_height + 6.0) / line_height), 1, 4)
	for word in text.replace("\n", " \n ").split(" ", false):
		var candidate: String = word if line.is_empty() else line + " " + word
		if (
			word == "\n"
			or (
				font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
				> available_width
			)
		):
			page += ("" if page.is_empty() else "\n") + line
			rows += 1
			line = "" if word == "\n" else word
			if rows >= line_limit:
				output.append(page)
				page = ""
				rows = 0
		else:
			line = candidate
	if not line.is_empty():
		page += ("" if page.is_empty() else "\n") + line
	if not page.is_empty():
		output.append(page)
	if output.is_empty():
		output.append("")
	return output


func _show_page() -> void:
	auto_clock = 0
	letters = 0
	body.text = pages[page_index]
	body.visible_characters = 0
	UI.enable_button(previous_button, page_index > 0)
	UI.enable_button(reveal_button, true)


func _process(delta: float) -> void:
	if OS.has_feature("android_smoke"):
		probe_clock += delta
		if probe_clock >= 0.25:
			probe_clock = 0.0
			preload("res://scripts/mobile_test_probe.gd").write(self)
	ambience_clock += delta
	if mode in ["menu", "loading"] or (mode == "play" and not is_instance_valid(encounter)):
		queue_redraw()
	if mode != "play" or not is_instance_valid(body):
		return
	if body.visible_characters >= 0:
		letters += delta * float(GameServices.settings.text_speed)
		body.visible_characters = -1 if letters >= body.text.length() else int(letters)
		if body.visible_characters == -1:
			UI.enable_button(reveal_button, false)
	if GameServices.settings.skip_read and GameServices.read_nodes.has(StoryRuntime.current().id):
		if body.visible_characters >= 0:
			_reveal()
		auto_clock += delta
		if auto_clock >= 0.45:
			_next()
	elif GameServices.settings.auto_advance and body.visible_characters == -1:
		auto_clock += delta
		if auto_clock >= maxf(3.0, body.text.length() / 18.0):
			_next()


func _reveal() -> void:
	if is_instance_valid(body):
		letters = body.text.length()
		body.visible_characters = -1
		UI.enable_button(reveal_button, false)


func _previous_page() -> void:
	if page_index > 0:
		page_index -= 1
		_show_page()


func _next() -> void:
	if mode != "play" or not is_instance_valid(body):
		return
	if letters < body.text.length():
		_reveal()
	elif page_index + 1 < pages.size():
		page_index += 1
		_show_page()
	else:
		GameServices.mark_read(StoryRuntime.current().id)
		StoryRuntime.advance()
		_enter_current()


func _choose(index: int) -> void:
	GameServices.effect("choice")
	if StoryRuntime.choose(index):
		_enter_current()


func _enter_current() -> void:
	if int(StoryRuntime.state.progress.chapter) != last_shown_chapter:
		_recap()
		return
	var node: Dictionary = StoryRuntime.current()
	if node.get("kind") != "beat":
		refresh()
		return
	var beat: Dictionary = StoryRuntime.beats[node.beat]
	var art: String = {
		"tactical": "loading_battle",
		"platformer": "loading_march",
		"rpg": "loading_city",
		"cutscene": "loading_battle",
		"soft": "loading_march"
	}[beat.type]
	_clear("loading")
	_set_background("res://assets/final/" + art + ".png")
	UI.panel(layer, Rect2(24, _height() - 112, _width() - 48, 88))
	_label(beat.title.ru, Rect2(44, _height() - 100, _width() - 88, 64), 32, OCHRE)
	var serial: int = transition_serial
	await get_tree().create_timer(0.3).timeout
	if is_inside_tree() and mode == "loading" and serial == transition_serial:
		refresh()


func _show_beat(node: Dictionary) -> void:
	match StoryRuntime.beats[node.beat].type:
		"cutscene":
			encounter = CutsceneView.new()
		"soft":
			encounter = SoftView.new()
		_:
			encounter = EncounterView.new()
	encounter.size = layer.size
	encounter.setup(StoryRuntime.beats[node.beat])
	encounter.pause_requested.connect(_pause)
	encounter.journal_requested.connect(_log)
	encounter.completed.connect(_after_encounter)
	layer.add_child(encounter)


func _after_encounter() -> void:
	# The model has already committed its result. Do not save an old encounter into the next node.
	encounter = null
	refresh()


func _complete_beat() -> void:
	if is_instance_valid(encounter) and encounter.model.state.won:
		encounter._finish()


func _pause() -> void:
	var had_encounter: bool = is_instance_valid(encounter)
	_clear("pause")
	_heading("Пауза", refresh, "В игру")
	if not had_encounter:
		StoryRuntime.save_game()
	GameServices.music.stream_paused = true
	GameServices.ambient.stream_paused = true
	var progress: Dictionary = StoryRuntime.state.gameplay
	_label(
		"Уровень %d · %d монет" % [int(progress.level), int(progress.coins)],
		Rect2(_width() - 344, 24, 320, 40),
		24,
		OCHRE
	)
	var episode: Dictionary = progress.encounter.get("state", {})
	var captions: Array = ["Продолжить", "Сохранения", "Настройки", "Журнал", "Главное меню"]
	var actions: Array[Callable] = [refresh, _slots, _open_settings.bind(_pause), _log, menu]
	var top: float = _content_top()
	var row: float = (_height() - top - 24) / 3
	var width: float = (_width() - 64) / 2
	for index in range(5):
		_button(
			captions[index],
			Rect2(24 + (index % 2) * (width + 16), top + (index / 2) * row, width, _touch()),
			actions[index]
		)
	_button(
		"Припас · %d" % int(progress.supplies),
		Rect2(40 + width, top + 2 * row, width, _touch()),
		_use_supply,
		episode.has("max_hp") and episode.get("hp", 0) < episode.max_hp and progress.supplies > 0
	)


func _use_supply() -> void:
	StoryRuntime.use_supply()
	_pause()


func _slots(message: String = "") -> void:
	_clear("slots")
	_heading("Сохранения", _pause)
	var row: float = (_height() - 174) / 3
	for index in range(1, 4):
		var path: String = StoryRuntime.slot_prefix + str(index) + ".json"
		var data: Dictionary = StoryRuntime.read_json(path)
		var summary: Variant = data.get("progress")
		var chapter_text: String = (
			str(summary.get("chapter", "—")) if summary is Dictionary else "—"
		)
		var top: float = _content_top() + 8 + (index - 1) * row
		UI.panel(layer, Rect2(16, top - 8, _width() - 32, row - 12))
		_label(
			"Слот %d · глава %s" % [index, chapter_text],
			Rect2(36, top, _width() - 508, _touch()),
			28
		)
		_button("Записать", Rect2(_width() - 444, top, 204, _touch()), _save_slot.bind(index))
		_button(
			"Загрузить",
			Rect2(_width() - 224, top, 192, _touch()),
			_load_slot.bind(index),
			not data.is_empty() or FileAccess.file_exists(path + ".bak")
		)
	_label(message, Rect2(24, _height() - 60, _width() - 48, 40), 24, OCHRE)


func _save_slot(index: int) -> void:
	_slots("Сохранено." if StoryRuntime.save_slot(index) else "Не удалось сохранить.")


func _load_slot(index: int) -> void:
	if StoryRuntime.load_slot(index):
		refresh()
	else:
		_slots("Слот повреждён или пуст.")


func _open_settings(back: Callable) -> void:
	settings_return = back
	_settings()


func _settings() -> void:
	_clear("settings")
	_button("Назад", Rect2(16, 14, 132, _touch()), settings_return)
	_label("Настройки", Rect2(168, 14, _width() - 620, _touch()), 30, OCHRE)
	_button("Комфорт", Rect2(_width() - 400, 14, 188, _touch()), _comfort)
	_button("Об игре", Rect2(_width() - 196, 14, 180, _touch()), _credits)
	var rows: Array = [
		["music", "Музыка", 0.1],
		["effects", "Эффекты", 0.1],
		["button_scale", "Размер кнопок", 0.1],
		["button_offset", "Сдвиг кнопок", 2.0],
		["text_speed", "Скорость текста", 6.0],
		["text_size", "Размер текста: 0–2", 1.0]
	]
	var dense: bool = _touch() > 74
	var top: float = _content_top()
	var row_height: float = (_height() - top - 16) / (3.0 if dense else 6.0)
	var cell: float = (_width() - 64) / 2
	var button_width: float = maxf(88, _touch())
	for index in range(rows.size()):
		var row: Array = rows[index]
		var y: float = top + (index / 2 if dense else index) * row_height
		var x: float = 24 + (index % 2) * (cell + 16) if dense else 32
		var right: float = x + cell if dense else _width() - 24
		_label(
			row[1], Rect2(x, y, cell if dense else _width() - 428, 32 if dense else _touch()), 28
		)
		if dense:
			y += 34
		_button(
			"−",
			Rect2(right - 2 * button_width - 148, y, button_width, _touch()),
			_adjust.bind(row[0], -row[2])
		)
		_label(
			"%.1f" % float(GameServices.settings[row[0]]),
			Rect2(right - button_width - 128, y + 8, 112, 40),
			28,
			OCHRE
		)
		_button(
			"+",
			Rect2(right - button_width, y, button_width, _touch()),
			_adjust.bind(row[0], row[2])
		)


func _comfort() -> void:
	_clear("comfort")
	_heading("Комфорт", _settings)
	var options: Array = [
		["skip_read", "Пропуск прочитанного"],
		["auto_advance", "Автопродолжение"],
		["vibration", "Вибрация"],
		["battery", "Экономия: 30 FPS"],
		["left_handed", "Левая рука"],
		["hints", "Подсказки"],
		["skip_minigames", "Пропуск мягких вставок"]
	]
	var row: float = (_height() - _content_top() - 16) / 4
	var cell: float = (_width() - 48) / 2
	for i in range(options.size()):
		var key: String = options[i][0]
		_button(
			options[i][1] + (": вкл" if GameServices.settings[key] else ": выкл"),
			Rect2(16 + (i % 2) * (cell + 16), _content_top() + (i / 2) * row, cell, _touch()),
			_toggle_comfort.bind(key)
		)


func _toggle_comfort(key: String) -> void:
	GameServices.set_preference(key, not GameServices.settings[key])
	_comfort()


func _toggle_hints() -> void:
	GameServices.set_preference("hints", not GameServices.settings.hints)
	_settings()


func _credits() -> void:
	_clear("credits")
	_set_background("res://assets/final/banner.png")
	_heading("CINIS LAURI · Пепел лавра", _settings)
	_reading_panel(
		(
			"Оригинальная историческая игра о гражданских войнах Рима.\n\n"
			+ "История, персонажи и иллюстрации созданы для этого проекта. "
			+ "Дизайн не основан на кино и телесериалах. Музыка и эффекты — оригинальный синтез.\n\n"
			+ "Исторические источники: Цезарь, Плутарх, Аппиан, Светоний, Кассий Дион.\n\n"
			+ "Шрифты Golos Text и PT Serif — их авторы и ParaType, "
			+ "SIL Open Font License 1.1.\nПолный реестр материалов и лицензий: docs/CREDITS.md."
		),
		_content_top(),
		_touch() + 40
	)
	_button("Лицензии и компоненты", Rect2(24, _footer_y(), _width() - 48, _touch()), _licenses)


func _licenses() -> void:
	_clear("legal")
	_heading("Лицензии и компоненты", _credits)
	var notice: String = "Golos Text / PT Serif — SIL Open Font License 1.1\n\n"
	for path in ["GolosText-OFL.txt", "PTSerif-OFL.txt"]:
		notice += FileAccess.get_file_as_string("res://assets/fonts/" + path) + "\n\n"
	notice += Engine.get_license_text() + "\n\n"
	for item in Engine.get_copyright_info():
		notice += str(item.get("name", "")) + "\n"
		for part in item.get("parts", []):
			for copyright_line in part.get("copyright", []):
				notice += str(copyright_line) + "\n"
			notice += str(part.get("license", "")) + "\n"
	var licenses: Dictionary = Engine.get_license_info()
	for key in licenses:
		notice += "\n" + str(key) + "\n" + str(licenses[key]) + "\n"
	_reading_panel(notice, _content_top(), 20, 20)


func _adjust(key: String, amount: float) -> void:
	GameServices.set_preference(key, float(GameServices.settings[key]) + amount)
	_settings()


func _apply_safe_area() -> void:
	if not resizing and is_instance_valid(layer):
		resizing = true
		call_deferred("_reflow")


func _reflow() -> void:
	var old_page: int = page_index
	var revealed: bool = is_instance_valid(body) and body.visible_characters == -1
	match mode:
		"play":
			refresh()
		"menu":
			menu()
		"chapters", "library":
			var safe: Rect2 = UI.safe_rect(self)
			layer.position = safe.position
			layer.size = safe.size
			if is_instance_valid(library_view):
				library_view.size = layer.size
				library_view.build()
			queue_redraw()
		"recap":
			_recap()
		"pause":
			_pause()
		"slots":
			_slots()
		"settings":
			_settings()
		"comfort":
			_comfort()
		"credits":
			_credits()
		"legal":
			_licenses()
		"log":
			_log()
		"confirm":
			_new_request()
	if is_instance_valid(body):
		page_index = mini(old_page, pages.size() - 1)
		_show_page()
		if revealed:
			_reveal()
	resizing = false


func _notification(what: int) -> void:
	if (
		what
		in [
			NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_WM_GO_BACK_REQUEST
		]
	):
		if not StoryRuntime.state.is_empty():
			if mode == "play":
				_pause()
			else:
				StoryRuntime.save_game()


func _skip() -> void:
	StoryRuntime.skip_scene()
	refresh()


func _log() -> void:
	_clear("log")
	_heading("Журнал", refresh)
	_button("Свиток судеб", Rect2(_width() - 240, 14, 224, _touch()), _library.bind("fate"))
	var log_text: String = ""
	var active: String = StoryRuntime.current().get("beat", "")
	if StoryRuntime.beats.has(active):
		log_text += "Текущее поручение: " + StoryRuntime.beats[active].objective.ru + "\n\n"
		if StoryRuntime.beats[active].type == "rpg":
			var hub = preload("res://scripts/gameplay/hub_model.gd").new()
			hub.setup(StoryRuntime.beats[active], StoryRuntime.state.gameplay, 0)
			var saved: Dictionary = StoryRuntime.state.gameplay.encounter.get("state", {})
			if not saved.is_empty():
				hub.restore(saved)
			log_text += hub.objective_text() + "\n" + hub.hint_text() + "\n\n"
	for ident in StoryRuntime.state.get("gameplay", {}).get("quests", {}):
		if StoryRuntime.beats.has(ident):
			log_text += "Выполнено: " + StoryRuntime.beats[ident].title.ru + "\n"
	for item in StoryRuntime.state.get("history", []):
		log_text += (
			"\n"
			+ StoryRuntime.characters.get(item.speaker, {}).get("name", {}).get("ru", item.speaker)
			+ ": "
			+ item.text
			+ "\n"
		)
	var log_view: RichTextLabel = _reading_panel(log_text, _content_top(), 20)
	log_view.scroll_to_line(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if mode == "play":
				_pause()
			elif not StoryRuntime.state.is_empty():
				refresh()
			else:
				menu()
		elif event.keycode in [KEY_SPACE, KEY_ENTER]:
			_next()
	elif (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	):
		_next()


func _draw() -> void:
	var bounds: Rect2 = get_viewport_rect()
	if mode in ["library", "chapters"]:
		draw_rect(bounds, INK)
		return
	if mode == "play" and is_instance_valid(encounter):
		# The encounter covers the safe area; do not render a second world underneath it.
		return
	var shade: float = 0.16 if mode in ["menu", "play", "loading"] else 0.82
	var tint = Color(1 - shade, 1 - shade, 1 - shade * 0.85)
	if background:
		# Cover the complete display, including the extra width of 20:9 phones.
		var physical: float = get_viewport().get_screen_transform().get_scale().y
		var ratio: float = maxf(
			bounds.size.x / background.get_width(), bounds.size.y / background.get_height()
		)
		ratio = ceilf(ratio * physical) / physical
		var dimensions: Vector2 = background.get_size() * ratio
		var drift: float = (
			roundf(sin(ambience_clock * 0.12) * 2) if dimensions.x > bounds.size.x + 4 else 0
		)
		var target = Rect2((bounds.size - dimensions) / 2 + Vector2(drift, 0), dimensions)
		if background_layers.size() == 3:
			for index in range(3):
				var shift: float = roundf(sin(ambience_clock * 0.17) * index * 2) / physical
				draw_texture_rect(
					background_layers[index],
					Rect2(target.position + Vector2(shift, 0), target.size),
					false,
					tint
				)
		else:
			draw_texture_rect(background, target, false, tint)
	else:
		draw_rect(bounds, INK)
	for step in range(3):
		var margin: float = 8 + step * 10
		var shadow = Color(0.03, 0.04, 0.06, 0.08)
		draw_rect(Rect2(0, 0, bounds.size.x, margin), shadow)
		draw_rect(Rect2(0, bounds.size.y - margin, bounds.size.x, margin), shadow)
