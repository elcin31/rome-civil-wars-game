extends Control
## Bounded rendering: two frame textures and 28 lightweight particles at most.

signal completed
signal pause_requested
signal journal_requested
const UI = preload("res://scripts/roman_ui.gd")
const Model = preload("res://scripts/gameplay/cutscene_model.gd")
var beat: Dictionary
var model: RefCounted
var layer: Control
var texture: Texture2D
var next_texture: Texture2D
var previous: Texture2D
var shown: int = -1
var clock: float = 0.0
var fade: float = 1.0
var challenge_clock: float = 0.0
var caption: RichTextLabel


func setup(value: Dictionary) -> void:
	beat = value
	model = Model.new()
	model.setup(beat, StoryRuntime.state.gameplay, int(StoryRuntime.state.bond))
	model.configure({"seed": StoryRuntime.state.get("seed", 1), "flags": StoryRuntime.state.flags})
	var saved: Dictionary = StoryRuntime.state.gameplay.get("encounter", {})
	if saved.get("beat") == beat.id:
		model.restore(saved.get("state", {}))


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_rebuild()


func _rebuild() -> void:
	if is_instance_valid(layer):
		layer.hide()
		layer.process_mode = Node.PROCESS_MODE_DISABLED
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	var touch: float = UI.touch_height(self)
	UI.panel(layer, Rect2(12, 12, size.x - 24, touch + 16))
	UI.button(layer, "Пауза", Rect2(20, 20, 120, touch), pause_requested.emit)
	UI.heading(layer, model.data.title, Rect2(156, 20, size.x - 470, touch), 26, Color("d9a441"))
	UI.button(layer, "Пропустить", Rect2(size.x - 300, 20, 144, touch), _skip)
	UI.button(layer, "Повтор", Rect2(size.x - 144, 20, 124, touch), _replay)
	if model.state.won:
		_result(touch)
	elif model.waiting_choice():
		_choice(touch)
	elif model.waiting_challenge():
		_challenge(touch)
	else:
		var top: float = size.y - touch - 162
		UI.panel(layer, Rect2(16, top, size.x - 32, 134), "parchment")
		caption = RichTextLabel.new()
		caption.position = Vector2(34, top + 12)
		caption.size = Vector2(size.x - 68, 110)
		caption.text = model.data.frames[int(model.state.frame)].caption.ru
		caption.add_theme_font_size_override("normal_font_size", 24)
		caption.set_meta("scroll_document", true)
		layer.add_child(caption)
		UI.button(
			layer, "Следующий кадр", Rect2(size.x - 252, size.y - touch - 16, 236, touch), _next
		)
	_load_frame()
	persist()


func _choice(touch: float) -> void:
	var options: Array = model.data.choice.options
	var top: float = maxf(touch + 48, size.y - (touch + 12) * (options.size() + 1) - 32)
	UI.panel(layer, Rect2(16, top, size.x - 32, size.y - top - 16))
	UI.label(layer, model.data.choice.prompt, Rect2(36, top + 10, size.x - 72, touch), 24)
	for i in range(options.size()):
		UI.button(
			layer,
			options[i].text.ru,
			Rect2(36, top + touch + 22 + i * (touch + 8), size.x - 72, touch),
			_choose.bind(i)
		)


func _challenge(touch: float) -> void:
	if GameServices.settings.get("skip_minigames", false):
		model.challenge(0)
		call_deferred("_rebuild")
		return
	var top: float = size.y - touch * 2 - 138
	UI.panel(layer, Rect2(16, top, size.x - 32, size.y - top - 16))
	var game: Dictionary = model.data.minigame
	UI.label(layer, game.prompt, Rect2(36, top + 12, size.x - 72, 64), 24)
	if game.type == "persuasion":
		UI.button(
			layer,
			game.get("argument", "Назвать свидетеля и показать запись"),
			Rect2(36, top + 88, size.x - 72, touch),
			_argument
		)
	else:
		UI.button(layer, "Действовать", Rect2(36, top + 88, size.x * 0.5 - 44, touch), _timing)
		UI.button(
			layer,
			"Спокойно / без риска",
			Rect2(size.x * 0.5 + 8, top + 88, size.x * 0.5 - 44, touch),
			_neutral
		)
	UI.button(
		layer, "Пропустить вставку", Rect2(36, size.y - touch - 24, size.x - 72, touch), _neutral
	)


func _result(touch: float) -> void:
	var card: Dictionary = model.result()
	UI.panel(layer, Rect2(24, touch + 52, size.x - 48, size.y - touch * 2 - 84), "parchment")
	var description = RichTextLabel.new()
	description.position = Vector2(48, touch + 70)
	description.size = Vector2(size.x - 96, size.y - touch * 2 - 120)
	description.text = (
		"ИТОГ · "
		+ {"win": "УСПЕХ", "costly": "ДОРОГОЙ УСПЕХ", "loss": "ПОТЕРЯ"}[model.state.outcome]
		+ "\n\n"
		+ card.text
		+ "\n\nПотери: "
		+ card.losses
		+ "\nМонеты: +%d · Связь: %+d\nРепутация: %s" % [card.reward, card.bond, str(card.rep)]
	)
	description.add_theme_font_size_override("normal_font_size", 24)
	description.set_meta("scroll_document", true)
	layer.add_child(description)
	UI.button(
		layer, "Принять последствия", Rect2(24, size.y - touch - 16, size.x - 48, touch), _finish
	)


func _load_frame() -> void:
	var index: int = int(model.state.frame)
	if index == shown:
		return
	previous = texture
	var path: String = "res://" + model.data.frames[index].image
	texture = (
		load(path) if ResourceLoader.exists(path) else load("res://assets/locations/roman_camp.png")
	)
	shown = index
	fade = 0.0
	challenge_clock = 0.0
	# A single next frame is preloaded, so chapter-sized textures never accumulate.
	var upcoming: int = mini(index + 1, model.data.frames.size() - 1)
	var upcoming_path: String = "res://" + model.data.frames[upcoming].image
	next_texture = load(upcoming_path) if ResourceLoader.exists(upcoming_path) else texture
	GameServices.play_layer(model.data.get("music", "battle"))
	GameServices.effect(model.data.frames[index].get("sfx", "choice"))


func _process(delta: float) -> void:
	clock += delta
	challenge_clock += delta
	fade = minf(1.0, fade + delta * 2.8)
	var before: Array = [
		model.state.frame, model.waiting_choice(), model.waiting_challenge(), model.state.won
	]
	model.tick(delta)
	var after: Array = [
		model.state.frame, model.waiting_choice(), model.waiting_challenge(), model.state.won
	]
	if before != after:
		_rebuild()
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var frame: Dictionary = model.data.frames[int(model.state.frame)]
	var camera: Dictionary = frame.get("camera", {"from": [0, 0, 1], "to": [0, 0, 1.05]})
	var progress: float = clampf(float(model.state.elapsed) / float(frame.duration), 0, 1)
	var start: Array = camera.from
	var end: Array = camera.to
	var zoom: float = lerpf(start[2], end[2], progress)
	var extent: Vector2 = size * zoom
	var offset: Vector2 = (
		Vector2(lerpf(start[0], end[0], progress), lerpf(start[1], end[1], progress)) * size
	)
	if "shake" in frame.get("fx", []) and progress < 0.2:
		offset += Vector2(sin(clock * 65), cos(clock * 53)) * 3
	if previous:
		draw_texture_rect(previous, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(
		texture, Rect2((size - extent) * 0.5 + offset, extent), false, Color(1, 1, 1, fade)
	)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.05, 0.1, 0.12))
	for i in range(8):
		var alpha: float = 0.018 * (8 - i)
		draw_rect(Rect2(0, i * 5, size.x, 5), Color(0, 0, 0, alpha))
		draw_rect(Rect2(0, size.y - (i + 1) * 5, size.x, 5), Color(0, 0, 0, alpha))
	if "flash" in frame.get("fx", []) and progress < 0.08:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.6, 0.22 * (1 - progress / 0.08)))
	for i in range(28):
		var point = Vector2(
			fmod(i * 83.0 + clock * 9, size.x), fmod(i * 47.0 - clock * 14 + 5000, size.y)
		)
		if "rain" in frame.get("fx", []):
			draw_line(point, point + Vector2(-3, 12), Color(0.7, 0.8, 0.9, 0.25))
		elif "embers" in frame.get("fx", []) or "dust" in frame.get("fx", []):
			draw_rect(Rect2(point, Vector2(3, 3)), Color(0.9, 0.7, 0.35, 0.3))
	if model.waiting_challenge() and model.data.minigame.type != "persuasion":
		var bar = Rect2(size.x * 0.3, size.y * 0.45, size.x * 0.4, 18)
		draw_rect(bar, Color("14151f"))
		draw_rect(
			Rect2(bar.position + Vector2(bar.size.x * 0.25, 0), Vector2(bar.size.x * 0.5, 18)),
			Color("587052")
		)
		draw_rect(
			Rect2(
				bar.position + Vector2((sin(challenge_clock * 1.7) * 0.5 + 0.5) * bar.size.x, -4),
				Vector2(4, 26)
			),
			Color("ede3cc")
		)


func persist() -> void:
	if not model or StoryRuntime.current().get("beat") != beat.id:
		return
	StoryRuntime.state.gameplay.encounter = {"beat": beat.id, "state": model.state.duplicate(true)}
	StoryRuntime.save_game()


func _next() -> void:
	model.next_frame()
	_rebuild()


func _choose(index: int) -> void:
	model.choose(index)
	_rebuild()


func _timing() -> void:
	var phase: float = sin(challenge_clock * 1.7) * 0.5 + 0.5
	model.challenge(1 if phase >= 0.25 and phase <= 0.75 else -1)
	_rebuild()


func _argument() -> void:
	model.challenge(1)
	_rebuild()


func _neutral() -> void:
	model.challenge(0)
	_rebuild()


func _skip() -> void:
	model.skip()
	_rebuild()


func _replay() -> void:
	model.replay()
	_rebuild()


func _finish() -> void:
	if StoryRuntime.complete_beat(model.result()):
		completed.emit()
