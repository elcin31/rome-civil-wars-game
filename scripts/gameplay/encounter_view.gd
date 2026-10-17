extends Control
## One mobile presentation for the three independently tested gameplay models.

signal pause_requested
signal completed

const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")
const INK = Color("14151f")
const IVORY = Color("ede3cc")
const OCHRE = Color("d9a441")
const BRONZE = Color("a87b3d")
const GRID_ORIGIN = Vector2(7, 33)
const CELL = Vector2(26, 20)
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
	font = ThemeDB.fallback_font
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
	tiles = load("res://assets/tiles/" + str(beat.get("tiles", "camp_fields")) + ".png")
	_button("Пауза", Rect2(3, 1, 47, 26), _pause)
	_label(beat.title.ru, Rect2(55, 1, 208, 15), 10, OCHRE)
	objective = _label(beat.objective.ru, Rect2(55, 16, 260, 14), 8)
	status = _label("", Rect2(5, 132, 310, 13), 8, OCHRE)
	match beat.type:
		"tactical":
			_button("Щит", Rect2(246, 58, 70, 24), _guard)
			_button("Вместе", Rect2(246, 86, 70, 24), _cooperate)
			_button("Конец хода", Rect2(246, 114, 70, 24), _end_turn)
			GameServices.play_layer("battle")
		"rpg":
			_button("Дело", Rect2(180, 148, 42, 28), _interact)
			_button("Герой", Rect2(226, 148, 42, 28), _switch_hero)
			_button("Лавка", Rect2(272, 148, 44, 28), _shop)
			GameServices.play_layer("city")
		_:
			GameServices.play_layer("march")
	_update_status()
	persist()


func _label(
	text: String, rect: Rect2, font_size: int = 9, color: Color = IVORY, parent: Node = self
) -> Label:
	var label = Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.clip_text = true
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(text: String, rect: Rect2, callback: Callable, parent: Node = self) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 8)
	for key in ["normal", "pressed", "hover", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = INK if key == "normal" else Color("4a3026")
		style.border_color = BRONZE
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(key, style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


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
	queue_redraw()


func _update_status() -> void:
	if not is_instance_valid(status):
		return
	match beat.type:
		"tactical":
			status.text = "Ход %d · %s" % [int(model.state.round), model.state.message]
		"platformer":
			status.text = (
				"Жизнь %d/%d · Отметки %d/3 · %s"
				% [
					int(model.state.hp),
					int(model.state.max_hp),
					model.state.tokens.size(),
					model.state.message
				]
			)
		_:
			status.text = model.state.message


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
	overlay = Control.new()
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.size = Vector2(320, 180)
	add_child(overlay)
	var shade = ColorRect.new()
	shade.color = Color(0.078, 0.082, 0.121, 0.97)
	shade.size = Vector2(320, 180)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.add_child(shade)


func _close_panel() -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null


func _shop() -> void:
	if model.nearest() != "merchant":
		model.state.message = "Лавка у торговца. Подойдите к нему."
		return
	_panel()
	var progress: Dictionary = StoryRuntime.state.gameplay
	_label(
		"Лавка · %d монет · уровень %d" % [int(progress.coins), int(progress.level)],
		Rect2(6, 3, 300, 22),
		12,
		OCHRE,
		overlay
	)
	var discount: int = (
		maxi(0, int(StoryRuntime.state.rep.citizens) / 5) + int(progress.skills.diplomacy)
	)
	for index in range(3):
		var item: String = ["sword", "shield", "supplies"][index]
		var name_value: String = ["Гладиус", "Щит", "Припасы"][index]
		var rank: int = (
			int(progress.get(item, 0)) if item == "supplies" else int(progress.equipment[item])
		)
		var price: int = (
			maxi(2, 6 - discount) if item == "supplies" else maxi(4, 12 + rank * 6 - discount)
		)
		_button(
			"%s %d · %d монет" % [name_value, rank, price],
			Rect2(6, 30 + index * 29, 149, 26),
			_buy.bind(item, discount),
			overlay
		)
	for index in range(3):
		var skill: String = ["strength", "formation", "diplomacy"][index]
		var name_value: String = ["Сила", "Строй", "Дипломатия"][index]
		_button(
			"%s %d → учить" % [name_value, int(progress.skills[skill])],
			Rect2(163, 30 + index * 29, 151, 26),
			_train.bind(skill),
			overlay
		)
	_label(
		"Одно очко навыка за уровень. Снаряжение общее.", Rect2(8, 119, 304, 18), 8, IVORY, overlay
	)
	_label(model.state.message, Rect2(8, 137, 304, 15), 8, OCHRE, overlay)
	_button("Назад", Rect2(100, 153, 120, 26), _close_panel, overlay)


func _buy(item: String, discount: int) -> void:
	model.state.message = (
		"Куплено."
		if Progression.buy(StoryRuntime.state.gameplay, item, discount)
		else "Недостаточно монет или достигнут предел."
	)
	persist()
	_shop()


func _train(skill: String) -> void:
	model.state.message = (
		"Навык улучшен."
		if Progression.train(StoryRuntime.state.gameplay, skill)
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
		Rect2(20, 27, 290, 28),
		16,
		OCHRE,
		overlay
	)
	var text: Label = _label(beat.objective.ru, Rect2(24, 63, 272, 45), 11, IVORY, overlay)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(
		"+45 опыта · +8 монет" if won else "Повторите бой с другим построением.",
		Rect2(24, 111, 272, 20),
		10,
		BRONZE,
		overlay
	)
	_button(
		"Продолжить" if won else "Повторить",
		Rect2(75, 146, 170, 28),
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
	return Vector2(34 + float(GameServices.settings.button_offset), 152)


func _action_rect(index: int) -> Rect2:
	var factor: float = GameServices.settings.button_scale
	var center = Vector2(
		clampf(199 + index * 47 - float(GameServices.settings.button_offset), 22, 297), 152
	)
	var dimensions = Vector2(32, 28) * factor
	return Rect2(center - dimensions * 0.5, dimensions)


func _local(event_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * event_position


func _clear_input() -> void:
	joy_pointer = -99
	joy_axis = Vector2.ZERO
	touch_actions.clear()
	for key in controls:
		controls[key] = false


func _pointer_down(pointer: int, point: Vector2) -> bool:
	if Rect2(0, 117, 103, 63).has_point(point) and beat.type != "tactical":
		joy_pointer = pointer
		joy_axis = ((point - _joy_center()) / 22.0).limit_length(1.0)
		return true
	if beat.type == "platformer":
		for index in range(3):
			if _action_rect(index).has_point(point):
				var action: String = ["jump", "strike", "block"][index]
				touch_actions[pointer] = action
				controls[action] = true
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


func _input(event: InputEvent) -> void:
	if is_instance_valid(overlay):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_down(event.index, _local(event.position)):
				get_viewport().set_input_as_handled()
		else:
			_pointer_up(event.index)
	elif event is InputEventScreenDrag and event.index == joy_pointer:
		joy_axis = ((_local(event.position) - _joy_center()) / 22.0).limit_length(1.0)
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
		joy_axis = ((_local(event.position) - _joy_center()) / 22.0).limit_length(1.0)
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
		var point: Vector2 = _local(event.position) - GRID_ORIGIN
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
	draw_rect(Rect2(0, 0, 320, 180), INK)
	if scene_background:
		draw_texture_rect(scene_background, Rect2(0, 26, 320, 112), false)
		draw_rect(Rect2(0, 26, 320, 106), Color(0.078, 0.082, 0.121, 0.3))
	match beat.type:
		"tactical":
			_draw_tactics()
		"platformer":
			_draw_platformer()
		_:
			_draw_hub()
	draw_rect(Rect2(0, 0, 320, 31), INK)
	draw_rect(Rect2(0, 132, 320, 13), INK)
	if beat.type != "tactical":
		var radius: float = 20.0 * float(GameServices.settings.button_scale)
		draw_circle(_joy_center(), radius, Color("2b1b14"))
		draw_arc(_joy_center(), radius, 0, TAU, 24, BRONZE)
		draw_circle(_joy_center() + joy_axis * 13.0, 7.0, OCHRE)
		if beat.type == "platformer":
			for index in range(3):
				var rect: Rect2 = _action_rect(index)
				draw_rect(
					rect, Color("4a3026") if controls[["jump", "strike", "block"][index]] else INK
				)
				draw_rect(rect, BRONZE, false)
				draw_string(
					font,
					rect.position + Vector2(3, 17),
					["Прыжок", "Удар", "Щит"][index],
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					7,
					IVORY
				)
			draw_string(
				font,
				Vector2(104, 176),
				"↓ + щит: уклонение",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				7,
				BRONZE
			)


func _sprite(
	ident: String,
	point: Vector2,
	pose: int = 3,
	facing: int = 1,
	dimensions: Vector2 = Vector2(24, 32)
) -> void:
	if not sprites.has(ident):
		return
	var target = Rect2(point - Vector2(dimensions.x * 0.5, dimensions.y), dimensions)
	if facing < 0:
		target.position.x += dimensions.x
		target.size.x = -dimensions.x
	draw_texture_rect_region(
		sprites[ident], target, Rect2((pose % 3) * 48, (pose / 3) * 64, 48, 64)
	)


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
		var point: Vector2 = GRID_ORIGIN + Vector2(unit.x + 0.5, unit.y + 0.9) * CELL
		draw_circle(
			point - Vector2(0, 4), 8, Color("2d4855") if unit.team == 0 else Color("7a1f1f")
		)
		var ident: String = "caesar_legionary" if unit.team == 0 else "pompeian_soldier"
		_sprite(ident, point, 7 if unit.guard else 3, 1 if unit.team == 0 else -1, Vector2(17, 23))
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
			draw_arc(point - Vector2(0, 4), 10, 0, TAU, 20, OCHRE)
	if beat.get("goal") == "escort":
		var convoy: Dictionary = model.state.convoy
		var point: Vector2 = GRID_ORIGIN + Vector2(convoy.x + 0.5, convoy.y + 0.9) * CELL
		_sprite("roman_citizen", point, 4, 1, Vector2(19, 25))
		draw_string(
			font,
			point - Vector2(8, 22),
			"С:%d" % int(convoy.hp),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			OCHRE
		)
	var selected: Dictionary = model.state.units[model.state.selected]
	draw_string(
		font,
		Vector2(246, 44),
		"ОД %d · дух %d" % [int(selected.ap), int(selected.morale)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		IVORY
	)
	draw_string(
		font,
		Vector2(9, 158),
		"Л — легион · Лк — лучники · К — конница",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		IVORY
	)
	draw_string(
		font,
		Vector2(9, 173),
		"Мышь / касание: отряд → клетка или цель",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		BRONZE
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
				Vector2(32, 42)
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
			Vector2(32, 42)
		)
	var pose: int = (
		7
		if model.state.block
		else (6 if model.state.attack > 0.18 else (4 if absf(model.state.vx) > 1 else 3))
	)
	_sprite(
		_hero_sprite(),
		Vector2(model.state.x - camera, model.state.y - 14),
		pose,
		int(model.state.facing),
		Vector2(32, 42)
	)
	var exit_point = Vector2(model.width - 20 - camera, 118)
	draw_line(exit_point, exit_point - Vector2(0, 36), OCHRE, 2)
	draw_rect(Rect2(exit_point - Vector2(0, 36), Vector2(14, 9)), Color("7a1f1f"))


func _draw_hub() -> void:
	draw_rect(Rect2(0, 125, 320, 7), Color("76503b"))
	for station in model.stations:
		if station.id == "supplies":
			draw_texture_rect_region(
				tiles, Rect2(station.x - 8, station.y - 16, 16, 16), Rect2(16, 0, 16, 16)
			)
		elif station.id == "exit":
			draw_line(Vector2(station.x, station.y), Vector2(station.x, station.y - 30), OCHRE, 2)
		else:
			_sprite(
				"craftsman" if station.id == "merchant" else "roman_citizen",
				Vector2(station.x, station.y)
			)
		draw_string(
			font,
			Vector2(station.x - 20, station.y - 34),
			station.name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			7,
			OCHRE
		)
	if not StoryRuntime.state.flags.get("friend_lost", false):
		_sprite(
			"lucius_vorenus" if _hero_sprite() == "titus_pullo" else "titus_pullo",
			Vector2(model.state.x - 18, model.state.y + 2),
			4
		)
	_sprite(
		_hero_sprite(), Vector2(model.state.x, model.state.y), 4 if joy_axis.length() > 0.1 else 3
	)
	draw_string(
		font, Vector2(98, 171), "Подойдите: Дело / E", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, BRONZE
	)
