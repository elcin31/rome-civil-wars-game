extends Control
signal closed
signal resume_requested
const UI = preload("res://scripts/roman_ui.gd")
const Lore = preload("res://scripts/lore_library.gd")
var state: Dictionary
var tab: String = "gallery"
var layer: Control
var page: int = 0
var selected: int = 0
var query: String = ""
var category: String = "all"
var article: Dictionary = {}
var picture: TextureRect
var picture_clip: Control
var zoom_value: float = 1.0
var picture_file: String = ""
var offset: Vector2 = Vector2.ZERO
var drag_start: Vector2 = Vector2.ZERO
var clock: float = 0.0
var route_renderer: Control
var map_rect: Rect2
var route_points: Array[Vector2] = []
var search_field: LineEdit


func setup(mode: String, progress: Dictionary) -> void:
	tab = mode
	state = progress.duplicate(true)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# Keep the actual input node alive when the Android keyboard resizes the view.
	search_field = LineEdit.new()
	search_field.placeholder_text = "Поиск в Хронике"
	search_field.max_length = 120
	search_field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	search_field.text_submitted.connect(_search)
	add_child(search_field)
	build()


func build() -> void:
	if is_instance_valid(layer):
		layer.hide()
		layer.process_mode = Node.PROCESS_MODE_DISABLED
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	picture = null
	picture_clip = null
	map_rect = Rect2()
	route_renderer = null
	var touch: float = UI.touch_height(self)
	search_field.visible = tab == "chronicle" and article.is_empty() and picture_file.is_empty()
	UI.panel(layer, Rect2(Vector2.ZERO, size))
	UI.button(layer, "Назад", Rect2(16, 16, 132, touch), closed.emit)
	var names: Array = [
		["chronicle", "Хроника"],
		["gallery", "Галерея"],
		["fate", "Свиток судеб"],
		["campaign", "Карта"]
	]
	var width: float = (size.x - 180) / 4
	for i in range(4):
		UI.button(
			layer,
			names[i][1],
			Rect2(164 + i * width, 16, width - 8, touch),
			_tab.bind(names[i][0]),
			tab != names[i][0]
		)
	if not picture_file.is_empty():
		_fullscreen(touch)
	else:
		match tab:
			"chronicle":
				_chronicle(touch)
			"gallery":
				_gallery(touch)
			"fate":
				_document(Lore.fate(state), Rect2(24, touch + 48, size.x - 48, size.y - touch - 72))
			"campaign":
				_campaign(touch)
	move_child(search_field, get_child_count() - 1)
	queue_redraw()


func _tab(value: String) -> void:
	tab = value
	page = 0
	selected = 0
	picture_file = ""
	article = {}
	build()


func _document(text: String, rect: Rect2) -> RichTextLabel:
	var control = RichTextLabel.new()
	control.position = rect.position
	control.size = rect.size
	control.text = text
	control.add_theme_font_size_override(
		"normal_font_size",
		UI.accessible_font_size(self, [22, 26, 30][int(GameServices.settings.text_size)])
	)
	control.set_meta("scroll_document", true)
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(control)
	return control


func _pager(touch: float, count: int, per_page: int) -> void:
	var last: int = maxi(0, (count - 1) / per_page)
	page = clampi(page, 0, last)
	UI.button(
		layer, "Предыдущая", Rect2(16, size.y - touch - 16, 224, touch), _page.bind(-1), page > 0
	)
	UI.label(
		layer,
		"%d / %d" % [page + 1, last + 1],
		Rect2(256, size.y - touch - 16, size.x - 512, touch),
		24
	)
	UI.button(
		layer,
		"Следующая",
		Rect2(size.x - 240, size.y - touch - 16, 224, touch),
		_page.bind(1),
		page < last
	)


func _page(direction: int) -> void:
	page += direction
	selected = 0
	build()


func _chronicle(touch: float) -> void:
	if not article.is_empty():
		_article(touch)
		return
	var top: float = touch + 48
	search_field.position = Vector2(16, top)
	search_field.size = Vector2(size.x * 0.5 - 32, touch)
	search_field.add_theme_font_size_override("font_size", UI.accessible_font_size(self, 24))
	UI.button(
		layer, "Найти", Rect2(size.x * 0.5, top, 152, touch), func(): _search(search_field.text)
	)
	var labels: Dictionary = {
		"all": "Все",
		"people": "Люди",
		"events": "События",
		"places": "Места",
		"equipment": "Снаряжение"
	}
	UI.button(
		layer,
		"Фильтр: " + labels[category],
		Rect2(size.x * 0.5 + 168, top, size.x * 0.5 - 184, touch),
		_filter
	)
	var available: float = size.y - top - touch * 2 - 56
	# The keyboard can leave room only for navigation and the search row.
	if available < touch + 12:
		return
	var entries: Array = Lore.entries(state, query, category)
	var per_page: int = clampi(int(available / (touch + 12)), 1, 3)
	_pager(touch, entries.size(), per_page)
	top += touch + 20
	var width: float = size.x * 0.31
	for i in range(per_page):
		var index: int = page * per_page + i
		if index >= entries.size():
			break
		UI.button(
			layer,
			entries[index].title,
			Rect2(16, top + i * (touch + 12), width - 24, touch),
			_open_article.bind(entries[index])
		)
	UI.label(
		layer,
		"Открыто: %d / 60" % Lore.entries(state).size(),
		Rect2(20, size.y - touch - 56, width - 24, 32),
		22
	)
	if entries.is_empty():
		_document(
			"Записей по этому запросу пока нет. Новые сведения откроются по ходу истории.",
			Rect2(width + 20, top, size.x - width - 40, size.y - top - touch - 40)
		)
		return
	var entry: Dictionary = entries[mini(page * per_page + selected, entries.size() - 1)]
	var image_height: float = minf(170, (size.y - top - touch - 48) * 0.4)
	if (
		size.y - top - touch > 260
		and not entry.image.is_empty()
		and ResourceLoader.exists("res://" + entry.image)
	):
		_image(entry.image, Rect2(width + 20, top, size.x - width - 40, image_height))
		top += image_height + 12
	_document(
		entry.text + "\n\nИсточник: " + entry.source,
		Rect2(width + 20, top, size.x - width - 40, size.y - top - touch - 36)
	)


func _search(value: String) -> void:
	query = value.strip_edges().left(120)
	search_field.text = query
	search_field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	page = 0
	selected = 0
	build()


func _filter() -> void:
	var categories: Array = ["all", "people", "events", "places", "equipment"]
	category = categories[(categories.find(category) + 1) % categories.size()]
	page = 0
	selected = 0
	build()


func _select(index: int) -> void:
	selected = index
	build()


func _gallery(touch: float) -> void:
	var art: Array = Lore.gallery(state)
	var opened: int = 0
	for entry in art:
		opened += int(entry.unlocked)
	UI.label(
		layer,
		"Открыто %d из %d · Иллюстрации и кадры катсцен" % [opened, art.size()],
		Rect2(20, touch + 32, size.x - 40, 44),
		24
	)
	_pager(touch, art.size(), 8)
	var top: float = touch + 92
	var cell = Vector2((size.x - 56) / 4, (size.y - top - touch - 48) / 2)
	for i in range(8):
		var index: int = page * 8 + i
		if index >= art.size():
			break
		var item: Dictionary = art[index]
		var rect = Rect2(Vector2(16 + (i % 4) * (cell.x + 8), top + (i / 4) * (cell.y + 8)), cell)
		var button: Button = UI.button(
			layer,
			item.title if item.unlocked else "Закрыто · глава %d" % int(item.chapter),
			rect,
			_open_picture.bind(item.file),
			item.unlocked
		)
		if item.unlocked:
			var texture = TextureRect.new()
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.texture = load("res://" + item.file)
			texture.position = Vector2(8, 8)
			texture.size = cell - Vector2(16, 16)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.size = cell - Vector2(16, 16)
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.modulate.a = 0.42
			texture.mouse_filter = MOUSE_FILTER_IGNORE
			button.add_child(texture)
			button.move_child(texture, 0)
		else:
			var silhouette = Polygon2D.new()
			var center = Vector2(cell.x * 0.5, cell.y * 0.52)
			var radius: float = minf(cell.x, cell.y) * 0.18
			var outline = PackedVector2Array()
			for point in range(18):
				outline.append(
					center + Vector2(cos(point * TAU / 18), sin(point * TAU / 18)) * radius
				)
			silhouette.polygon = outline
			silhouette.color = Color(0.03, 0.03, 0.05, 0.65)
			var torso = Polygon2D.new()
			torso.polygon = PackedVector2Array(
				[
					center + Vector2(-radius * 1.7, radius * 2.1),
					center + Vector2(-radius, radius),
					center + Vector2(radius, radius),
					center + Vector2(radius * 1.7, radius * 2.1)
				]
			)
			torso.color = silhouette.color
			button.add_child(torso)
			button.move_child(torso, 0)
			button.add_child(silhouette)
			button.move_child(silhouette, 0)


func _image(path: String, rect: Rect2) -> void:
	var texture = TextureRect.new()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture = load("res://" + path)
	texture.position = rect.position
	texture.size = rect.size
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.size = rect.size
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(texture)


func _open_picture(path: String) -> void:
	picture_file = path
	zoom_value = 1
	offset = Vector2.ZERO
	build()


func _fullscreen(touch: float) -> void:
	picture_clip = Control.new()
	picture_clip.position = Vector2(16, touch + 36)
	picture_clip.size = Vector2(size.x - 32, size.y - touch * 2 - 68)
	picture_clip.clip_contents = true
	picture_clip.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(picture_clip)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture = load("res://" + picture_file)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	picture_clip.add_child(picture)
	_position_picture()
	UI.button(layer, "−", Rect2(16, size.y - touch - 16, 120, touch), _zoom.bind(-0.5))
	UI.button(layer, "+", Rect2(148, size.y - touch - 16, 120, touch), _zoom.bind(0.5))
	UI.button(
		layer, "К списку", Rect2(size.x - 240, size.y - touch - 16, 224, touch), _close_picture
	)


func _position_picture() -> void:
	if not is_instance_valid(picture):
		return
	picture.size = picture_clip.size * zoom_value
	var limit: Vector2 = (picture.size - picture_clip.size) * 0.5
	offset = offset.clamp(-limit, limit)
	picture.position = (picture_clip.size - picture.size) * 0.5 + offset


func _zoom(amount: float) -> void:
	zoom_value = clampf(zoom_value + amount, 1, 4)
	_position_picture()


func _close_picture() -> void:
	picture_file = ""
	build()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(picture_clip):
		return
	if (
		event is InputEventScreenDrag
		or (event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT)
	):
		if picture_clip.get_global_rect().has_point(event.position):
			offset += event.relative
			_position_picture()
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_zoom(event.factor - 1.0)


func _campaign(touch: float) -> void:
	var chapters: Array = Lore.read("res://story/chapter_index.json").get("chapters", [])
	map_rect = Rect2(20, touch + 44, size.x * 0.56 - 28, size.y - touch * 2 - 76)
	_image("assets/new_story/mediterranean.png", map_rect)
	route_renderer = Control.new()
	route_renderer.mouse_filter = MOUSE_FILTER_IGNORE
	route_renderer.draw.connect(_draw_route)
	layer.add_child(route_renderer)
	var locations: Array = [
		[0.31, 0.19],
		[0.45, 0.29],
		[0.66, 0.52],
		[0.46, 0.4],
		[0.46, 0.4],
		[0.67, 0.34],
		[0.62, 0.52],
		[0.46, 0.4]
	]
	route_points.clear()
	for loc in locations:
		route_points.append(map_rect.position + Vector2(loc[0], loc[1]) * map_rect.size)
	var x: float = size.x * 0.56 + 8
	var width: float = size.x - x - 20
	var top: float = touch + 44
	var row: float = (size.y - touch * 2 - 84) / 2
	for i in range(2):
		var index: int = page * 2 + i
		if index >= chapters.size():
			break
		var item: Dictionary = chapters[index]
		var caption: String = (
			"%d. %s\n%s\n%s"
			% [
				index + 1,
				item.title.ru,
				item.years,
				item.get("epigraph", "У каждого пути остаётся свидетель.")
			]
		)
		var card: Button = UI.button(
			layer,
			caption,
			Rect2(x, top + i * row, width, row - 12),
			resume_requested.emit,
			index + 1 <= Lore.chapter(state)
		)
		var image = TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.texture = load("res://assets/chapter_cards/ch%02d.png" % (index + 1))
		image.position = Vector2(8, 8)
		image.size = card.size - Vector2(16, 16)
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.modulate.a = 0.22
		image.mouse_filter = MOUSE_FILTER_IGNORE
		card.clip_contents = true
		card.add_child(image)
		card.move_child(image, 0)
	_pager(touch, 8, 2)


func _process(delta: float) -> void:
	clock += delta
	if is_instance_valid(route_renderer) and clock < 5.0:
		route_renderer.queue_redraw()


func _draw_route() -> void:
	if tab != "campaign" or map_rect.size == Vector2.ZERO:
		return
	var extent: int = Lore.chapter(state)
	for i in range(mini(extent - 1, route_points.size() - 1)):
		var fraction: float = clampf(clock * 0.7 - i * 0.3, 0, 1)
		route_renderer.draw_line(
			route_points[i], route_points[i].lerp(route_points[i + 1], fraction), Color("d9a441"), 4
		)
	for i in range(mini(extent, route_points.size())):
		route_renderer.draw_circle(route_points[i], 6, Color("963f38"))


func _open_article(entry: Dictionary) -> void:
	article = entry
	build()


func _article(touch: float) -> void:
	_document(
		article.title + "\n\n" + article.text + "\n\nИсточник: " + article.source,
		Rect2(24, touch + 44, size.x - 48, size.y - touch * 2 - 80)
	)
	UI.button(layer, "К списку", Rect2(24, size.y - touch - 16, 224, touch), _close_article)
	if not article.image.is_empty():
		UI.button(
			layer,
			"Иллюстрация",
			Rect2(size.x - 264, size.y - touch - 16, 240, touch),
			_open_picture.bind(article.image)
		)


func _close_article() -> void:
	article = {}
	build()
