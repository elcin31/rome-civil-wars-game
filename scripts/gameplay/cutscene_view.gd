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
var rhythm_hits: Array[int] = []
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
	for hit in model.state.rhythm:
		rhythm_hits.append(int(hit))


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
		caption.add_theme_font_size_override("normal_font_size", UI.accessible_font_size(self, 24))
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
	UI.label(
		layer,
		game.prompt + (" · Удары %d/3" % rhythm_hits.size() if game.type == "rowing" else ""),
		Rect2(36, top + 12, size.x - 72, 64),
		24
	)
	if game.type == "persuasion":
		UI.button(
			layer,
			"Показать проверяемую запись",
			Rect2(36, top + 88, size.x * 0.5 - 44, touch),
			_argument.bind(1)
		)
		UI.button(
			layer,
			"Надавить авторитетом",
			Rect2(size.x * 0.5 + 8, top + 88, size.x * 0.5 - 44, touch),
			_argument.bind(-1)
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
		+ (
			"\nМонеты: +%d · 45 опыта · Связь: %+d\n%s"
			% [int(card.reward) + 8, card.bond, _rep_text(card.rep)]
		)
		+ "\nПотери: "
		+ card.losses
		+ "\n\nРешение: "
		+ card.get("decision", "")
		+ "\n\n"
		+ card.text
	)

	description.add_theme_font_size_override("normal_font_size", UI.accessible_font_size(self, 24))
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
	if not StoryRuntime.state.has("art_seen"):
		StoryRuntime.state.art_seen = []
	if model.data.frames[index].image not in StoryRuntime.state.art_seen:
		StoryRuntime.state.art_seen.append(model.data.frames[index].image)
	shown = index
	fade = 0.0
	challenge_clock = 0.0
	# A single next frame is preloaded, so chapter-sized textures never accumulate.
	var upcoming: int = mini(index + 1, model.data.frames.size() - 1)
	var upcoming_path: String = "res://" + model.data.frames[upcoming].image
	next_texture = load(upcoming_path) if ResourceLoader.exists(upcoming_path) else texture
	GameServices.play_layer(model.data.get("music", "battle"))
	GameServices.set_ambience(
		"sea" if model.data.id == "actium" else "forest" if model.data.id == "forest" else "camp"
	)
	GameServices.set_dialogue(true)
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
	var physical_scale: float = get_viewport().get_screen_transform().get_scale().y
	var offset: Vector2 = (
		Vector2(lerpf(start[0], end[0], progress), lerpf(start[1], end[1], progress)) * size
	)
	if "shake" in frame.get("fx", []) and progress < 0.2:
		offset += Vector2(sin(clock * 65), cos(clock * 53)) * 3
	if previous and fade < 1.0:
		draw_texture_rect(previous, UI.cover_rect(previous.get_size(), size, physical_scale), false)
	draw_texture_rect(
		texture,
		UI.cover_rect(texture.get_size(), size, physical_scale, zoom, offset),
		false,
		Color(1, 1, 1, fade)
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
	if model.waiting_challenge():
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
	if model.state.frame == model.data.frames.size() - 1 and model.state.played:
		model.resolve()
	_rebuild()


func _timing() -> void:
	var phase: float = sin(challenge_clock * 1.7) * 0.5 + 0.5
	var quality: int = 1 if phase >= 0.25 and phase <= 0.75 else -1
	if model.data.minigame.type == "rowing":
		rhythm_hits.append(quality)
		model.state.rhythm = rhythm_hits.duplicate()
		if rhythm_hits.size() < 3:
			_rebuild()
			return
		quality = 1 if rhythm_hits.reduce(func(total, item): return total + item, 0) > 0 else -1
	model.challenge(quality)
	_rebuild()


func _argument(quality: int) -> void:
	model.challenge(quality)
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
	if StoryRuntime.current().get("beat") != beat.id or not model.state.won:
		return
	if StoryRuntime.complete_beat(model.result()):
		completed.emit()


func _rep_text(reputation: Dictionary) -> String:
	var parts: Array[String] = []
	for faction in reputation:
		parts.append(
			(
				"%s %+d"
				% [
					preload("res://scripts/lore_library.gd").FACTIONS.get(faction, faction),
					reputation[faction]
				]
			)
		)
	return ", ".join(parts)
