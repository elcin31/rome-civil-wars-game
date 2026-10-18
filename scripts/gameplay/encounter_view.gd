extends Control
## One mobile presentation for the three independently tested gameplay models.

signal pause_requested
signal completed

const UI = preload("res://scripts/roman_ui.gd")
const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
const INK = Color("14151f")
const IVORY = Color("ede3cc")
const OCHRE = Color("d9a441")
const BRONZE = Color("a87b3d")
const GRID_ORIGIN = Vector2(7, 44)
const CELL = Vector2(26, 24)
var beat: Dictionary = {}
var model: RefCounted
var sprites: Dictionary = {}
var scene_background: Texture2D
var tiles: Texture2D
var controls: Dictionary = {"jump": false, "strike": false, "block": false}
var touch_actions: Dictionary = {}
var joy_pointer: int = -99
var joy_axis: Vector2 = Vector2.ZERO
var save_clock: float = 0.0
var status: Label
var objective: Label
var overlay: Control
var result_shown: bool = false
var font: Font
var camera: float = 0.0
var action_buttons: Array[Button] = []
var nearby_button: Button
var world_transform: Transform2D
var panel_hidden: Array[Control] = []


func setup(value: Dictionary) -> void:
	beat = value
	model = Factory.create(
		beat,
		StoryRuntime.state.gameplay,
		int(StoryRuntime.state.bond),
		not StoryRuntime.state.flags.get("friend_lost", false)
	)
	var saved: Dictionary = StoryRuntime.state.gameplay.get("encounter", {})
	if saved.get("beat") == beat.id and saved.get("state") is Dictionary:
		model.restore(saved.state)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = UI.theme_resource()
	font = theme.default_font
	for ident in [
		"titus_pullo",
		"lucius_vorenus",
		"caesar_legionary",
		"gallic_warrior",
		"pompeian_soldier",
		"roman_citizen",
		"craftsman"
	]:
		sprites[ident] = load("res://assets/characters/" + ident + ".png")
	var path: String = "res://assets/locations/" + str(beat.get("location", "roman_camp")) + ".png"
	if ResourceLoader.exists(path):
		scene_background = load(path)
	if beat.type == "tactical":
		for ident in ["caesar_legionary", "pompeian_soldier", "roman_citizen"]:
			sprites[ident + "_tactical"] = load(
				"res://assets/characters/" + ident + "_tactical.png"
			)
	if beat.type == "rpg":
		var chapter: int = int(StoryRuntime.state.progress.chapter)
		var place: String = [
			"camp_day",
			"command_tent",
			"ship_deck",
			"atrium_house",
			"forest_night",
			"camp_rain",
			"ship_deck",
			"villa_garden"
		][clampi(chapter - 1, 0, 7)]
		scene_background = load("res://assets/interiors/" + place + ".png")
		for ident in ["scribe", "merchant", "healer", "servant"]:
			sprites["npc_" + ident] = load("res://assets/npcs/" + ident + ".png")
	tiles = load("res://assets/tiles/" + str(beat.get("tiles", "camp_fields")) + ".png")
	var physical_scale: float = get_viewport().get_screen_transform().get_scale().y
	var factor: float = (
		maxf(
			2,
			(
				floorf(
					(
						minf(size.x / 320.0, (size.y - maxf(0, UI.touch_height(self) - 58)) / 180.0)
						* physical_scale
						/ 2.0
					)
				)
				* 2
			)
		)
		/ physical_scale
	)
	world_transform = Transform2D(
		0,
		Vector2.ONE * factor,
		0,
		Vector2((size.x - 320 * factor) / 2, (size.y - 180 * factor) / 2 - 30)
	)
	if beat.type == "tactical":
		var board_top: float = maxf(90, UI.touch_height(self) + 28)
		var fit: float = minf(
			(size.x - 196) / (CELL.x * 9), (size.y - 80 - board_top) / (CELL.y * 5)
		)
		var board_scale: float = maxf(2, floorf(fit * physical_scale / 2) * 2) / physical_scale
		world_transform = Transform2D(
			0,
			Vector2.ONE * board_scale,
			0,
			Vector2(
				(size.x - 196 - CELL.x * 9 * board_scale) / 2 - GRID_ORIGIN.x * board_scale,
				board_top - GRID_ORIGIN.y * board_scale
			)
		)
	UI.panel(
		self,
		Rect2(
			8,
			8,
			size.x - 16,
			maxf(76, UI.touch_height(self) + 16) if beat.type == "tactical" else 112
		)
	)
	_button("Пауза", Rect2(16, 16, 120, UI.touch_height(self)), _pause)
	_label(
		beat.title.ru,
		Rect2(
			156,
			10 if beat.type == "tactical" else 14,
			size.x - 180,
			28 if beat.type == "tactical" else 38
		),
		24 if beat.type == "tactical" else 30,
		OCHRE
	)
	objective = _label(
		beat.objective.ru,
		Rect2(
			156,
			40 if beat.type == "tactical" else 54,
			size.x - 184,
			42 if beat.type == "tactical" else 60
		),
		18 if beat.type == "tactical" else 22
	)
	if beat.type == "tactical":
		UI.panel(self, Rect2(16, size.y - 76, size.x - 32, 60))
		status = _label("", Rect2(32, size.y - 72, size.x - 64, 52), 22, OCHRE)
	else:
		UI.panel(self, Rect2(148, size.y - _action_rect(0).size.y - 108, size.x - 164, 76))
		status = _label(
			"", Rect2(164, size.y - _action_rect(0).size.y - 100, size.x - 196, 60), 22, OCHRE
		)
	match beat.type:
		"tactical":
			_button("Щит", _action_rect(0), _guard)
			_button("Вместе", _action_rect(1), _cooperate)
			_button("Конец хода", _action_rect(2), _end_turn)
			GameServices.play_layer("battle")
		"rpg":
			_button("Дело", _action_rect(0), _interact)
			_button("Герой", _action_rect(1), _switch_hero)
			_button("Лавка", _action_rect(2), _shop)
			nearby_button = _button(
				"Говорить", Rect2(200, 200, 156, UI.touch_height(self)), _interact
			)
			nearby_button.visible = false
			GameServices.play_layer("city")
		_:
			for index in range(3):
				var button: Button = _button(
					["Прыжок", "Удар", "Щит"][index], _action_rect(index), func(): pass
				)
				button.toggle_mode = true
				action_buttons.append(button)
			GameServices.play_layer("march")
	_update_status()
	persist()


func _label(
	text: String, rect: Rect2, font_size: int = 24, color: Color = IVORY, parent: Node = self
) -> Label:
	return UI.label(parent, text, rect, font_size, color)


func _button(text: String, rect: Rect2, callback: Callable, parent: Node = self) -> Button:
	return UI.button(parent, text, rect, callback)


func _physics_process(delta: float) -> void:
	if is_instance_valid(overlay):
		return
	var axis: Vector2 = joy_axis
	axis.x += (
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	)
	axis.y += (
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	match beat.type:
		"platformer":
			var jump: bool = controls.jump or Input.is_physical_key_pressed(KEY_SPACE)
			var attack: bool = controls.strike or Input.is_physical_key_pressed(KEY_J)
			var block: bool = controls.block or Input.is_physical_key_pressed(KEY_K)
			var dodge: bool = Input.is_physical_key_pressed(KEY_SHIFT) or (block and axis.y > 0.45)
			var health: int = model.state.hp
			var attack_before: float = model.state.attack
			model.tick(delta, axis.x, jump, attack, block, dodge)
			if model.state.hp < health:
				GameServices.effect("hit")
			elif model.state.attack > attack_before:
				GameServices.effect("sword")
			camera = clampf(float(model.state.x) - 85.0, 0.0, model.width - 320.0)
		"rpg":
			model.tick(delta, axis)
	save_clock += delta
	if save_clock >= 1.5:
		save_clock = 0.0
		persist()
	_update_status()
	if (model.state.won or model.state.failed) and not result_shown:
		_result()
	if beat.type != "tactical":
		queue_redraw()


func _update_status() -> void:
	if not is_instance_valid(status):
		return
	match beat.type:
		"tactical":
			status.text = "Ход %d · %s" % [int(model.state.round), model.state.message]
		"platformer":
			status.text = (
				"Жизнь %d/%d · Отметки %d/3\n%s"
				% [
					int(model.state.hp),
					int(model.state.max_hp),
					model.state.tokens.size(),
					model.state.message
				]
			)
		_:
			var next: String = [
				"Поговорите с писцом",
				"Заберите припасы",
				"Передайте припасы получателю",
				"Идите к дороге"
			][clampi(int(model.state.quest), 0, 3)]
			status.text = next + " · " + model.state.message
			if is_instance_valid(nearby_button):
				var station: String = model.nearest()
				nearby_button.visible = not station.is_empty()
				var point: Vector2 = world_transform * Vector2(model.state.x, model.state.y)
				nearby_button.position = Vector2(
					clampf(point.x + 32, 16, size.x - 180), clampf(point.y - 70, 132, size.y - 248)
				)
				for nearby in model.stations:
					if nearby.id != station:
						continue
					var caption: Rect2 = world_transform * _npc_caption_rect(nearby)
					nearby_button.set_meta("avoid_rect", caption)
					if nearby_button.get_rect().grow(8).intersects(caption):
						nearby_button.position.x = clampf(
							minf(point.x - 32, caption.position.x - 12) - nearby_button.size.x,
							16,
							size.x - nearby_button.size.x - 16
						)


func persist() -> void:
	if model == null or StoryRuntime.state.is_empty():
		return
	if StoryRuntime.current().get("beat") != beat.id:
		return
	StoryRuntime.state.gameplay.encounter = {"beat": beat.id, "state": model.state.duplicate(true)}
	StoryRuntime.save_game()


func _pause() -> void:
	_clear_input()
	persist()
	pause_requested.emit()


func _guard() -> void:
	model.guard(int(model.state.selected))
	persist()
	queue_redraw()


func _cooperate() -> void:
	if not model.cooperate():
		model.state.message = "Совместное прикрытие требует bond 55 и напарника."
	persist()
	queue_redraw()


func _end_turn() -> void:
	model.end_turn()
	GameServices.effect("turn")
	persist()
	queue_redraw()


func _interact() -> void:
	var station: String = model.interact()
	GameServices.effect("choice")
	if station == "merchant":
		_shop()
	persist()
	queue_redraw()


func _switch_hero() -> void:
	if StoryRuntime.state.flags.get("friend_lost", false):
		model.state.message = "Напарник погиб."
		return
	var progress: Dictionary = StoryRuntime.state.gameplay
	progress.hero = "vorenus" if progress.hero == "pullo" else "pullo"
	model.state.message = (
		"Впереди Ворен: щит и строй."
		if progress.hero == "vorenus"
		else "Впереди Пулон: сила и прыжок."
	)
	persist()
	queue_redraw()


func _panel() -> void:
	_clear_input()
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	else:
		panel_hidden.clear()
		for child in get_children():
			if child is Control and child.visible:
				panel_hidden.append(child)
				child.hide()
	overlay = Control.new()
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.size = size
	add_child(overlay)
	var shade = ColorRect.new()
	shade.color = Color(0.078, 0.082, 0.121, 0.97)
	shade.size = size
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	UI.panel(overlay, Rect2(8, 8, size.x - 16, size.y - 16))


func _close_panel() -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null
	for control in panel_hidden:
		control.show()
	panel_hidden.clear()


func _shop() -> void:
	if model.nearest() != "merchant":
		model.state.message = "Лавка у торговца. Подойдите к нему."
		return
	_panel()
	var progress: Dictionary = StoryRuntime.state.gameplay
	_label(
		"Лавка · %d монет · уровень %d" % [int(progress.coins), int(progress.level)],
		Rect2(28, 24, size.x - 56, 44),
		30,
		OCHRE,
		overlay
	)
	var discount: int = (
		maxi(0, int(StoryRuntime.state.rep.citizens) / 5) + int(progress.skills.diplomacy)
	)
	var half: float = (size.x - 80) / 2
	for index in range(3):
		var item: String = ["sword", "shield", "supplies"][index]
		var name_value: String = ["Гладиус", "Щит", "Припасы"][index]
		var rank: int = (
			int(progress.get(item, 0)) if item == "supplies" else int(progress.equipment[item])
		)
		var price: int = (
			maxi(2, 6 - discount) if item == "supplies" else maxi(4, 12 + rank * 6 - discount)
		)
		var top: float = (
			(84 if UI.touch_height(self) > 74 else 96)
			+ index * maxf(78, UI.touch_height(self) + 10)
		)
		_button(
			"%s %d · %d монет" % [name_value, rank, price],
			Rect2(28, top, half, UI.touch_height(self)),
			_buy.bind(item, discount),
			overlay
		)
		var skill: String = ["strength", "formation", "diplomacy"][index]
		_button(
			"%s %d → учить" % [["Сила", "Строй", "Дипломатия"][index], int(progress.skills[skill])],
			Rect2(52 + half, top, half, UI.touch_height(self)),
			_train.bind(skill),
			overlay
		)
	if UI.touch_height(self) <= 74:
		_label(
			"Одно очко навыка за уровень. Снаряжение общее.",
			Rect2(28, 336, size.x - 56, 36),
			24,
			IVORY,
			overlay
		)
	_label(
		model.state.message,
		Rect2(28, size.y - UI.touch_height(self) - 58, size.x - 56, 32),
		22,
		OCHRE,
		overlay
	)
	_button(
		"Назад",
		Rect2(28, size.y - UI.touch_height(self) - 16, size.x - 56, UI.touch_height(self)),
		_close_panel,
		overlay
	)


func _buy(item: String, discount: int) -> void:
	model.state.message = (
		"Куплено."
		if model.buy(StoryRuntime.state.gameplay, item, discount)
		else "Недостаточно монет или достигнут предел."
	)
	persist()
	_shop()


func _train(skill: String) -> void:
	model.state.message = (
		"Навык улучшен."
		if model.train(StoryRuntime.state.gameplay, skill)
		else "Нет свободных очков или достигнут предел."
	)
	persist()
	_shop()


func _result() -> void:
	result_shown = true
	_panel()
	var won: bool = model.state.won
	_label(
		"Поручение выполнено" if won else "Отряд отступил",
		Rect2(48, 80, size.x - 96, 64),
		40,
		OCHRE,
		overlay
	)
	_label(beat.objective.ru, Rect2(48, 164, size.x - 96, 120), 28, IVORY, overlay)
	_label(
		"+45 опыта · +8 монет" if won else "Повторите бой с другим построением.",
		Rect2(48, 316, size.x - 96, 76),
		28,
		OCHRE,
		overlay
	)
	_button(
		"Продолжить" if won else "Повторить",
		Rect2(48, size.y - 100, size.x - 96, UI.touch_height(self)),
		_finish if won else _retry,
		overlay
	)
	GameServices.effect("victory" if won else "hit")
	persist()


func _finish() -> void:
	if not model.state.won:
		return
	StoryRuntime.complete_beat()
	completed.emit()


func _retry() -> void:
	_close_panel()
	result_shown = false
	model = Factory.create(
		beat,
		StoryRuntime.state.gameplay,
		int(StoryRuntime.state.bond),
		not StoryRuntime.state.flags.get("friend_lost", false)
	)
	persist()


func _joy_center() -> Vector2:
	var radius: float = _joy_radius()
	return Vector2(24 + radius + float(GameServices.settings.button_offset), size.y - 16 - radius)


func _joy_radius() -> float:
	return maxf(
		UI.touch_height(self) / 2, clampf(42 * float(GameServices.settings.button_scale), 40, 64)
	)


func _action_rect(index: int) -> Rect2:
	if beat.type == "tactical":
		var height: float = UI.touch_height(self)
		return Rect2(size.x - 180, maxf(104, height + 46) + index * (height + 16), 164, height)
	var factor: float = float(GameServices.settings.button_scale)
	var dimensions: Vector2 = Vector2(
		clampf(132 * factor, 120, 180), maxf(UI.touch_height(self), 58 * factor)
	)
	var total: float = dimensions.x * 3 + 24
	var offset: float = clampf(float(GameServices.settings.button_offset), -12, 12)
	return Rect2(
		Vector2(
			size.x - 16 - total + index * (dimensions.x + 12) - maxf(0, offset),
			size.y - 16 - dimensions.y
		),
		dimensions
	)


func _local(event_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * event_position


func _clear_input() -> void:
	joy_pointer = -99
	joy_axis = Vector2.ZERO
	touch_actions.clear()
	for key in controls:
		controls[key] = false
	for button in action_buttons:
		button.set_pressed_no_signal(false)


func _pointer_down(pointer: int, point: Vector2) -> bool:
	if point.distance_to(_joy_center()) <= _joy_radius() + 10 and beat.type != "tactical":
		joy_pointer = pointer
		joy_axis = ((point - _joy_center()) / _joy_radius()).limit_length(1.0)
		return true
	if beat.type == "platformer":
		for index in range(3):
			if _action_rect(index).has_point(point):
				var action: String = ["jump", "strike", "block"][index]
				touch_actions[pointer] = action
				controls[action] = true
				action_buttons[index].set_pressed_no_signal(true)
				action_buttons[index].pressed.emit()
				return true
	return false


func _pointer_up(pointer: int) -> void:
	if pointer == joy_pointer:
		joy_pointer = -99
		joy_axis = Vector2.ZERO
	if touch_actions.has(pointer):
		var action: String = touch_actions[pointer]
		touch_actions.erase(pointer)
		controls[action] = action in touch_actions.values()
		var index: int = ["jump", "strike", "block"].find(action)
		action_buttons[index].set_pressed_no_signal(controls[action])


func _input(event: InputEvent) -> void:
	if is_instance_valid(overlay):
		return
	if (
		event is InputEventMouseButton
		and event.device == InputEvent.DEVICE_ID_EMULATION
		and beat.type == "platformer"
	):
		var point: Vector2 = _local(event.position)
		for index in range(3):
			if _action_rect(index).has_point(point):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_down(event.index, _local(event.position)):
				get_viewport().set_input_as_handled()
		else:
			_pointer_up(event.index)
	elif event is InputEventScreenDrag and event.index == joy_pointer:
		joy_axis = ((_local(event.position) - _joy_center()) / _joy_radius()).limit_length(1.0)
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.device != InputEvent.DEVICE_ID_EMULATION
	):
		if event.pressed:
			if _pointer_down(-1, _local(event.position)):
				get_viewport().set_input_as_handled()
		else:
			_pointer_up(-1)
	elif event is InputEventMouseMotion and joy_pointer == -1:
		joy_axis = ((_local(event.position) - _joy_center()) / _joy_radius()).limit_length(1.0)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(overlay):
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and beat.type == "tactical"
	):
		var point: Vector2 = world_transform.affine_inverse() * _local(event.position) - GRID_ORIGIN
		if Rect2(Vector2.ZERO, CELL * Vector2(9, 5)).has_point(point):
			model.click(Vector2i(int(point.x / CELL.x), int(point.y / CELL.y)))
			persist()
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and beat.type == "rpg":
			_interact()
		elif event.keycode == KEY_ENTER and beat.type == "tactical":
			_end_turn()


func _draw() -> void:
	if scene_background:
		var physical: float = get_viewport().get_screen_transform().get_scale().y
		var ratio: float = maxf(
			size.x / scene_background.get_width(), size.y / scene_background.get_height()
		)
		ratio = ceilf(ratio * physical) / physical
		var dimensions: Vector2 = scene_background.get_size() * ratio
		draw_texture_rect(
			scene_background,
			Rect2((size - dimensions) / 2, dimensions),
			false,
			Color(0.82, 0.82, 0.85)
		)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), INK)
	draw_set_transform_matrix(world_transform)
	match beat.type:
		"tactical":
			_draw_tactics()
		"platformer":
			_draw_platformer()
		_:
			_draw_hub()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if beat.type != "tactical":
		var radius: float = _joy_radius()
		draw_circle(_joy_center(), radius + 4, INK)
		draw_circle(_joy_center(), radius, Color("2b1b14"))
		draw_arc(_joy_center(), radius, 0, TAU, 32, BRONZE, 3)
		draw_circle(_joy_center() + joy_axis * radius * 0.55, radius * 0.38, OCHRE)


func _sprite(
	ident: String,
	point: Vector2,
	pose: int = 3,
	facing: int = 1,
	dimensions: Vector2 = Vector2(32, 48)
) -> void:
	if not sprites.has(ident):
		return
	# Feet, rather than the image centre, anchor every figure to the same ground plane.
	draw_set_transform_matrix(
		world_transform * Transform2D(0, Vector2(1.8, 0.5), 0, point - Vector2(0, 1))
	)
	draw_circle(Vector2.ZERO, dimensions.x * 0.20, Color(0.05, 0.06, 0.08, 0.6))
	var cell: Vector2 = sprites[ident].get_size() / Vector2(3, 3)
	var bob: float = roundf(sin(Time.get_ticks_msec() * 0.006)) if pose == 4 else 0.0
	var breathing: float = 1.0 + sin(Time.get_ticks_msec() * 0.002) * 0.012 if pose == 3 else 1.0
	var tilt: float = 0.06 if pose == 8 else (-0.06 if pose == 6 else 0.0)
	draw_set_transform_matrix(
		(
			world_transform
			* Transform2D(
				tilt, Vector2(-1 if facing < 0 else 1, breathing), 0, point + Vector2(0, bob)
			)
		)
	)
	draw_texture_rect_region(
		sprites[ident],
		Rect2(Vector2(-dimensions.x * 0.5, -dimensions.y), dimensions),
		Rect2(Vector2(pose % 3, floori(pose / 3.0)) * cell, cell)
	)
	draw_set_transform_matrix(world_transform)


func _hero_sprite() -> String:
	return "titus_pullo" if StoryRuntime.state.gameplay.hero == "pullo" else "lucius_vorenus"


func _draw_tactics() -> void:
	var reachable: Dictionary = (
		model.reachable(int(model.state.selected))
		if model.state.units[model.state.selected].hp > 0
		else {}
	)
	for y in range(5):
		for x in range(9):
			var cell = Vector2i(x, y)
			var rect = Rect2(GRID_ORIGIN + Vector2(cell) * CELL, CELL - Vector2.ONE)
			var color: Color = {
				"plain": Color("6b7a3a"),
				"cover": Color("4a3026"),
				"mud": Color("76503b"),
				"wall": Color("8a8577")
			}[model.terrain(cell)]
			draw_rect(rect, color.darkened(0.3))
			draw_rect(rect, BRONZE.darkened(0.5), false)
			if reachable.has(cell):
				draw_rect(rect.grow(-2), Color(0.85, 0.64, 0.26, 0.22))
			if model.terrain(cell) == "cover":
				draw_line(rect.position + Vector2(4, 5), rect.end - Vector2(4, 5), BRONZE, 2)
	for index in range(model.state.units.size()):
		var unit: Dictionary = model.state.units[index]
		if unit.hp <= 0:
			continue
		var point: Vector2 = GRID_ORIGIN + Vector2(unit.x + 0.5, unit.y + 0.98) * CELL
		draw_circle(
			point - Vector2(0, 4), 8, Color("2d4855") if unit.team == 0 else Color("7a1f1f")
		)
		var ident: String = (
			"caesar_legionary_tactical" if unit.team == 0 else "pompeian_soldier_tactical"
		)
		_sprite(ident, point, 7 if unit.guard else 3, 1 if unit.team == 0 else -1, Vector2(16, 24))
		draw_rect(Rect2(point + Vector2(-9, 0), Vector2(18, 2)), INK)
		draw_rect(Rect2(point + Vector2(-9, 0), Vector2(18.0 * unit.hp / unit.max_hp, 2)), OCHRE)
		draw_string(
			font,
			point + Vector2(-8, -20),
			{"legion": "Л", "archer": "Лк", "cavalry": "К"}[unit.kind],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			IVORY
		)
		if index == int(model.state.selected):
			draw_arc(point - Vector2(0, 12), 10, 0, TAU, 20, OCHRE)
	if beat.get("goal") == "escort":
		var convoy: Dictionary = model.state.convoy
		var point: Vector2 = GRID_ORIGIN + Vector2(convoy.x + 0.5, convoy.y + 0.9) * CELL
		_sprite("roman_citizen_tactical", point, 4, 1, Vector2(16, 24))
		draw_string(
			font,
			point - Vector2(8, 22),
			"С:%d" % int(convoy.hp),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			OCHRE
		)


func _draw_platformer() -> void:
	for platform in model.ground:
		var left: float = maxf(platform[0], camera - 16)
		var right: float = minf(platform[1], camera + 336)
		for x in range(int(floor(left / 16.0)) * 16, int(right), 16):
			draw_texture_rect_region(
				tiles, Rect2(x - camera, platform[2] - 14, 16, 16), Rect2(0, 0, 16, 16)
			)
			draw_rect(Rect2(x - camera, platform[2] + 2, 16, 28), Color("4a3026"))
	for index in range(model.tokens.size()):
		if index not in model.state.tokens:
			var point = Vector2(model.tokens[index] - camera, 98)
			draw_rect(Rect2(point, Vector2(7, 9)), OCHRE)
			draw_line(point + Vector2(2, 2), point + Vector2(5, 6), INK)
	for enemy in model.state.enemies:
		if enemy.hp > 0 and absf(enemy.x - camera - 160) < 190:
			_sprite(
				(
					"gallic_warrior"
					if (
						str(beat.get("location", "roman_camp"))
						in ["gaul_forest", "alesia", "gallic_fort"]
					)
					else "pompeian_soldier"
				),
				Vector2(enemy.x - camera, enemy.y - 14),
				6 if enemy.charge > 0 else 3,
				-1,
				Vector2(32, 48)
			)
			if enemy.charge > 0:
				draw_string(
					font,
					Vector2(enemy.x - camera - 2, enemy.y - 52),
					"!",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					12,
					Color("ed803e")
				)
	if model.companion:
		_sprite(
			"lucius_vorenus" if _hero_sprite() == "titus_pullo" else "titus_pullo",
			Vector2(model.state.ally_x - camera, model.state.ally_y - 14),
			7 if model.bond >= 55 else 4,
			1,
			Vector2(32, 48)
		)
	var pose: int = (
		7
		if model.state.block
		else (6 if model.state.attack > 0.18 else (4 if absf(model.state.vx) > 1 else 3))
	)
	if float(model.state.invincible) > 0.5:
		pose = 8
	var hero_point = Vector2(model.state.x - camera, model.state.y - 14)
	draw_circle(hero_point - Vector2(0, 14), 10, Color("1e2a44"))
	draw_string(font, hero_point - Vector2(5, 31), "Вы", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, OCHRE)
	_sprite(
		_hero_sprite(),
		Vector2(model.state.x - camera, model.state.y - 14),
		pose,
		int(model.state.facing),
		Vector2(32, 48)
	)
	var exit_point = Vector2(model.width - 20 - camera, 118)
	draw_line(exit_point, exit_point - Vector2(0, 36), OCHRE, 2)
	draw_rect(Rect2(exit_point - Vector2(0, 36), Vector2(14, 9)), Color("7a1f1f"))


func _npc_caption_rect(station: Dictionary) -> Rect2:
	var width: float = font.get_string_size(station.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	return Rect2(clampf(station.x + 18, 4, 316 - width) - 3, station.y - 30, width + 6, 13)


func _draw_hub() -> void:
	# A continuous earth plane, a path, horizon and contact shadows make depth explicit.
	draw_rect(Rect2(0, 66, 320, 67), Color(0.29, 0.22, 0.15, 0.84))
	draw_line(Vector2(0, 66), Vector2(320, 66), Color("bfa87a"), 2)
	draw_colored_polygon(
		PackedVector2Array([Vector2(0, 114), Vector2(320, 97), Vector2(320, 128), Vector2(0, 132)]),
		Color("76503b")
	)
	# A small brazier has a recognisable bowl, feet and two flickering flame clusters.
	var flicker: float = float(int(Time.get_ticks_msec() / 180) % 2)
	draw_line(Vector2(32, 89), Vector2(32, 98), Color("737e82"), 2)
	draw_line(Vector2(26, 98), Vector2(38, 98), Color("737e82"), 2)
	draw_colored_polygon(
		PackedVector2Array([Vector2(26, 85), Vector2(38, 85), Vector2(36, 89), Vector2(28, 89)]),
		BRONZE
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(28, 85),
				Vector2(31, 77 + flicker),
				Vector2(33, 81),
				Vector2(35, 76 - flicker),
				Vector2(37, 85)
			]
		),
		Color("ed803e")
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(31, 85), Vector2(33, 80 + flicker), Vector2(35, 85)]), OCHRE
	)
	var actors: Array = []
	var target: String = ["scribe", "supplies", "witness", "exit"][clampi(
		int(model.state.quest), 0, 3
	)]
	for station in model.stations:
		actors.append({"kind": station.id, "x": station.x, "y": station.y})
		if station.id == target:
			var tip = Vector2(station.x + 18, station.y - 38)
			draw_colored_polygon(
				PackedVector2Array([tip, tip + Vector2(-4, -6), tip + Vector2(4, -6)]), OCHRE
			)
	actors.append({"kind": "hero", "x": model.state.x, "y": model.state.y})
	if not StoryRuntime.state.flags.get("friend_lost", false):
		actors.append(
			{"kind": "ally", "x": clampf(model.state.x - 18, 18, 302), "y": model.state.y + 2}
		)
	actors.sort_custom(func(a, b): return a.y < b.y)
	for actor in actors:
		var point = Vector2(actor.x, actor.y)
		match actor.kind:
			"supplies":
				draw_rect(Rect2(point - Vector2(9, 13), Vector2(18, 13)), Color("4a3026"))
				draw_rect(Rect2(point - Vector2(9, 13), Vector2(18, 13)), BRONZE, false)
				draw_line(point - Vector2(8, 12), point - Vector2(-8, 1), BRONZE)
				draw_line(point - Vector2(-8, 12), point - Vector2(8, 1), BRONZE)
			"exit":
				draw_line(point, point - Vector2(0, 28), Color("76503b"), 3)
				draw_colored_polygon(
					PackedVector2Array(
						[
							point + Vector2(-2, -28),
							point + Vector2(12, -28),
							point + Vector2(16, -24),
							point + Vector2(12, -20),
							point + Vector2(-2, -20)
						]
					),
					OCHRE
				)
			"hero":
				_sprite(_hero_sprite(), point, 4 if joy_axis.length() > 0.1 else 3)
			"ally":
				_sprite(
					"lucius_vorenus" if _hero_sprite() == "titus_pullo" else "titus_pullo", point, 4
				)
			_:
				_sprite(
					(
						"npc_merchant"
						if actor.kind == "merchant"
						else ("npc_scribe" if actor.kind == "scribe" else "npc_healer")
					),
					point
				)
	var near: String = model.nearest()
	for station in model.stations:
		if station.id == near:
			var caption: Rect2 = _npc_caption_rect(station)
			draw_rect(caption, INK)
			draw_string(
				font,
				caption.position + Vector2(3, 10),
				station.name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				9,
				OCHRE
			)
