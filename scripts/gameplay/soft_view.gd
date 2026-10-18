extends Control
signal completed
signal pause_requested
signal journal_requested
const UI = preload("res://scripts/roman_ui.gd")
const Model = preload("res://scripts/gameplay/soft_model.gd")
var beat: Dictionary
var model: RefCounted
var axis: float = 0
var hiding: bool = false
var layer: Control
var status: Label
var background: Texture2D
var reported: bool = false


func setup(value: Dictionary) -> void:
	beat = value
	model = Model.new()
	model.setup(beat, StoryRuntime.state.gameplay, int(StoryRuntime.state.bond))
	var saved: Dictionary = StoryRuntime.state.gameplay.encounter
	if saved.get("beat") == beat.id:
		model.restore(saved.get("state", {}))


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	GameServices.play_layer("march")
	GameServices.set_ambience("sea" if beat.location in ["alexandria", "actium"] else "forest")
	background = load("res://assets/locations/" + beat.location + ".png")
	if GameServices.settings.get("skip_minigames", false):
		model.skip()
	_build()


func _build() -> void:
	if is_instance_valid(layer):
		layer.hide()
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	var touch: float = UI.touch_height(self)
	UI.panel(layer, Rect2(12, 12, size.x - 24, touch * 2 + 46))
	UI.button(layer, "Пауза", Rect2(20, 20, 120, touch), pause_requested.emit)
	UI.heading(layer, beat.title.ru, Rect2(156, 20, size.x - 390, touch), 26, Color("d9a441"))
	UI.button(layer, "Пропустить", Rect2(size.x - 216, 20, 196, touch), _skip)
	status = UI.label(layer, "", Rect2(32, touch + 32, size.x - 64, touch + 12), 24)
	if model.state.won:
		status.text = (
			"Путь завершён. "
			+ ("Спокойный исход." if model.state.neutral else "Все три отметки найдены.")
		)
		if beat.minigame == "dice" and model.state.played:
			status.text = "Alea: выпало %d. Одна партия; её результат сохранён." % model.state.roll
		UI.button(
			layer, "Продолжить путь", Rect2(24, size.y - touch - 24, size.x - 48, touch), _finish
		)
	elif beat.minigame == "dice":
		status.text = "Лагерные кости. Можно сыграть на две монеты или просто посидеть у огня."
		UI.button(
			layer,
			"Ставка: 2 монеты",
			Rect2(24, size.y - touch - 24, size.x * 0.5 - 32, touch),
			_dice.bind(true),
			int(StoryRuntime.state.gameplay.coins) >= 2
		)
		UI.button(
			layer,
			"Без ставки",
			Rect2(size.x * 0.5 + 8, size.y - touch - 24, size.x * 0.5 - 32, touch),
			_dice.bind(false)
		)
	else:
		var left: bool = GameServices.settings.get("left_handed", false)
		var origin: float = size.x - 340 if left else 24
		for i in range(2):
			var button: Button = UI.button(
				layer,
				"Влево" if i == 0 else "Вправо",
				Rect2(origin + i * 156, size.y - touch - 24, 144, touch),
				func(): pass
			)
			button.button_down.connect(_move.bind(-1.0 if i == 0 else 1.0))
			button.button_up.connect(_move.bind(0.0))
		var cover_x: float = 24 if left else size.x - 216
		var cover_button: Button = UI.button(
			layer, "Тихий шаг", Rect2(cover_x, size.y - touch - 24, 192, touch), func(): pass
		)
		cover_button.button_down.connect(_cover.bind(true))
		cover_button.button_up.connect(_cover.bind(false))
	persist()


func _process(delta: float) -> void:
	model.tick(delta, axis, hiding)
	if model.state.won and not reported:
		reported = true
		_build()
	elif not model.state.won and beat.minigame != "dice":
		status.text = (
			"Отметки: %d/3. %s"
			% [
				model.state.marks.size(),
				(
					"Патруль смотрит: идите тихо."
					if beat.minigame == "stealth" and fmod(model.state.elapsed, 5.0) < 1.8
					else "Двигайтесь к выходу справа. Опасного боя нет."
				)
			]
		)
	queue_redraw()


func _draw() -> void:
	if background:
		draw_texture_rect(background, Rect2(Vector2.ZERO, size), false, Color(0.6, 0.6, 0.7))
	var floor_y: float = size.y * 0.73
	draw_rect(Rect2(0, floor_y, size.x, 18), Color("7d6949"))
	for i in range(3):
		var point = Vector2((120 + i * 125) / 480.0 * size.x, floor_y - 24)
		if i not in model.state.marks:
			draw_rect(Rect2(point, Vector2(14, 20)), Color("d9a441"))
		draw_rect(Rect2(point + Vector2(-30, -28), Vector2(22, 52)), Color("454d4a"))
	if beat.minigame == "stealth":
		var guard = Vector2(size.x * (0.5 + sin(model.state.elapsed * 0.6) * 0.28), floor_y - 26)
		draw_rect(Rect2(guard + Vector2(-8, -44), Vector2(16, 44)), Color("454d4a"))
		draw_circle(guard + Vector2(0, -54), 9, Color("b69268"))
		if fmod(model.state.elapsed, 5.0) < 1.8:
			draw_colored_polygon(
				PackedVector2Array([guard, guard + Vector2(150, -18), guard + Vector2(150, 26)]),
				Color(0.9, 0.7, 0.3, 0.12)
			)
	var hero = Vector2(model.state.x / 480.0 * size.x, floor_y)
	draw_ellipse_shadow(hero)
	draw_rect(
		Rect2(hero + Vector2(-12, -42 if hiding else -64), Vector2(24, 42 if hiding else 64)),
		Color("963f38")
	)
	draw_circle(hero + Vector2(0, -52 if hiding else -74), 11, Color("d4ad7b"))


func draw_ellipse_shadow(point: Vector2) -> void:
	draw_set_transform(point, 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 20, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)


func _move(value: float) -> void:
	axis = value


func _cover(value: bool) -> void:
	hiding = value


func _skip() -> void:
	model.skip()
	_build()


func _dice(risk: bool) -> void:
	model.dice(int(StoryRuntime.state.get("seed", 1)), risk)
	_build()


func persist() -> void:
	if StoryRuntime.current().get("beat") == beat.id:
		StoryRuntime.state.gameplay.encounter = {
			"beat": beat.id, "state": model.state.duplicate(true)
		}
		StoryRuntime.save_game()


func _finish() -> void:
	if StoryRuntime.current().get("beat") != beat.id or not model.state.won:
		return
	if (
		beat.minigame == "dice"
		and not model.state.neutral
		and beat.id not in StoryRuntime.state.beats_completed
	):
		StoryRuntime.state.gameplay.coins = maxi(
			0, int(StoryRuntime.state.gameplay.coins) + (2 if model.state.roll >= 4 else -2)
		)
		StoryRuntime.apply_effects({"rep": {"legion": 1 if model.state.roll >= 4 else -1}})
	if StoryRuntime.complete_beat():
		completed.emit()
