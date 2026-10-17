extends Control
## Part 1 art viewer. All art is shown at its native pixel size in fullscreen.
## Animation here is explicitly procedural; each named pose has one painted key.

const UI = preload("res://scripts/roman_ui.gd")
const GROUPS = ["characters", "locations", "tiles", "ui", "illustrations"]
const GROUP_NAMES = ["Герои", "Локации", "Тайлы", "Интерфейс", "Хроника"]
const POSES = ["Анфас", "Профиль", "Спина", "Покой", "Шаг", "Бег", "Удар", "Блок", "Урон"]
const INK = Color("14151f")
const IVORY = Color("ede3cc")
const BRONZE = Color("a87b3d")
const OCHRE = Color("d9a441")

var assets: Array = []
var filtered: Array = []
var group_index: int = 0
var asset_index: int = 0
var pose_index: int = 3
var clock: float = 0.0
var moving: bool = true
var fullscreen: bool = false
var touch_start: Vector2 = Vector2.ZERO
var current: Dictionary = {}
var texture: Texture2D
var portrait: Texture2D
var layers: Array[Texture2D] = []
var backdrop: Texture2D
var button_art: Texture2D
var arrow_art: Texture2D
var chrome: Control
var name_label: Label
var detail_label: Label
var action_button: Button
var tabs: Array[Button] = []
var font: Font


func _ready() -> void:
	theme = UI.theme_resource()
	font = theme.default_font
	get_viewport().size_changed.connect(_resize)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/manifest.json"))
	if data is Dictionary:
		assets = data.get("assets", [])
	var additions: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tools/refresh_art_manifest.json")
	)
	assets.append_array(additions.get("assets", []))
	var previous: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tools/story_art_manifest.json")
	)
	for asset in previous.get("assets", []):
		if asset.category != "emotions":
			var copy: Dictionary = asset.duplicate()
			copy.category = "illustrations"
			assets.append(copy)
	if ResourceLoader.exists("res://assets/locations/gaul_forest.png"):
		backdrop = load("res://assets/locations/gaul_forest.png")
	if ResourceLoader.exists("res://assets/ui/buttons.png"):
		button_art = load("res://assets/ui/buttons.png")
	if ResourceLoader.exists("res://assets/ui/arrows.png"):
		arrow_art = load("res://assets/ui/arrows.png")
	_build_ui()

	_select_group(0)
	# Automation uses this same real scene; no fake screenshot renderer.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gallery-group="):
			_select_group(int(arg.get_slice("=", 1)))
		elif arg.begins_with("--gallery-asset="):
			_select_asset(int(arg.get_slice("=", 1)))
		elif arg == "--gallery-fullscreen":
			_toggle_fullscreen()


func _button(text_value: String, box: Rect2, callback: Callable) -> Button:
	return UI.button(chrome, text_value, box, callback)


func _label(text_value: String, pos: Vector2, color: Color = IVORY) -> Label:
	return UI.label(
		chrome, text_value, Rect2(pos, Vector2(chrome.size.x - pos.x - 24, 40)), 24, color
	)


func _build_ui() -> void:
	chrome = Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe: Rect2 = UI.safe_rect(self)
	chrome.position = safe.position
	chrome.size = safe.size
	add_child(chrome)
	var width: float = chrome.size.x
	var height: float = chrome.size.y
	UI.panel(chrome, Rect2(8, 8, width - 16, 66))
	_label("CINIS LAURI", Vector2(24, 20), OCHRE).size.x = 212
	name_label = _label("", Vector2(252, 20))
	name_label.size.x = width - 420
	_button(
		"Меню",
		Rect2(width - 148, 12, 132, UI.touch_height(self)),
		func(): get_tree().change_scene_to_file("res://scenes/StoryMain.tscn")
	)
	var column: float = (width - 64) / 5
	tabs.clear()
	for index in range(5):
		tabs.append(
			_button(
				GROUP_NAMES[index],
				Rect2(
					16 + index * (column + 8),
					maxf(82, UI.touch_height(self) + 32),
					column,
					UI.touch_height(self)
				),
				_select_group.bind(index)
			)
		)
	detail_label = _label("", Vector2(24, height - UI.touch_height(self) - 52), BRONZE)
	_button(
		"←",
		Rect2(
			16,
			height - UI.touch_height(self) - 16,
			maxf(88, UI.touch_height(self)),
			UI.touch_height(self)
		),
		_navigate.bind(-1)
	)
	_button(
		"→",
		Rect2(
			width - 104,
			height - UI.touch_height(self) - 16,
			maxf(88, UI.touch_height(self)),
			UI.touch_height(self)
		),
		_navigate.bind(1)
	)
	var half: float = (width - 256) / 2
	action_button = _button(
		"", Rect2(116, height - UI.touch_height(self) - 16, half, UI.touch_height(self)), _action
	)
	_button(
		"Чистый вид",
		Rect2(128 + half, height - UI.touch_height(self) - 16, half, UI.touch_height(self)),
		_toggle_fullscreen
	)


func _resize() -> void:
	if is_instance_valid(chrome):
		remove_child(chrome)
		chrome.queue_free()
		_build_ui()
		_select_group(group_index)
		chrome.visible = not fullscreen


func _select_group(index: int) -> void:
	group_index = posmod(index, GROUPS.size())
	filtered = assets.filter(func(item): return item.get("category", "") == GROUPS[group_index])
	for i in range(tabs.size()):
		tabs[i].modulate = OCHRE if i == group_index else Color.WHITE
	_select_asset(0)


func _navigate(direction: int) -> void:
	_select_asset(asset_index + direction)


func _select_asset(index: int) -> void:
	if filtered.is_empty():
		return
	asset_index = posmod(index, filtered.size())
	current = filtered[asset_index]
	texture = null
	portrait = null
	layers.clear()
	var path = "res://" + str(current.get("file", ""))
	if ResourceLoader.exists(path):
		texture = load(path)
	if current.has("portrait") and ResourceLoader.exists("res://" + current["portrait"]):
		portrait = load("res://" + current["portrait"])
	for layer_path in current.get("layers", []):
		if ResourceLoader.exists("res://" + layer_path):
			layers.append(load("res://" + layer_path))
	name_label.text = "%02d/%02d  %s" % [asset_index + 1, filtered.size(), current.get("title", "")]
	var dimensions = current.get("size", [0, 0])
	detail_label.text = "%s x %s px  /  48 цветов" % [dimensions[0], dimensions[1]]
	_update_action()
	queue_redraw()


func _update_action() -> void:
	if group_index == 0:
		action_button.text = "Поза: " + POSES[pose_index]
	else:
		action_button.text = "Движение: " + ("вкл" if moving else "выкл")


func _action() -> void:
	if group_index == 0:
		pose_index = (pose_index + 1) % 9
	else:
		moving = not moving
	_update_action()
	queue_redraw()


func _toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	chrome.visible = not fullscreen
	queue_redraw()


func _process(delta: float) -> void:
	if moving:
		clock += delta
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
		else:
			var swipe = event.position.x - touch_start.x
			if absf(swipe) > 40:
				_navigate(-1 if swipe > 0 else 1)
			elif fullscreen:
				_toggle_fullscreen()
	elif event is InputEventMouseButton and event.pressed and fullscreen:
		_toggle_fullscreen()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT:
				_navigate(1)
			KEY_LEFT:
				_navigate(-1)
			KEY_TAB:
				_select_group(group_index + 1)
			KEY_SPACE:
				_action()
			KEY_F, KEY_ESCAPE:
				_toggle_fullscreen()


func _draw() -> void:
	var bounds: Rect2 = get_viewport_rect()
	draw_rect(bounds, INK)
	if current.is_empty() or not texture:
		return
	var safe: Rect2 = UI.safe_rect(self)
	var preview: Rect2 = (
		safe
		if fullscreen
		else Rect2(safe.position + Vector2(16, 152), safe.size - Vector2(32, 272))
	)
	if group_index == 0:
		var cell: Vector2 = texture.get_size() / Vector2(3, 3)
		var factor: float = maxf(1, floorf(preview.size.y / cell.y))
		var point: Vector2 = preview.position + Vector2(preview.size.x * 0.32, preview.size.y)
		var bob: float = roundf(sin(clock * 3)) if moving else 0.0
		draw_set_transform(point + Vector2(0, bob))
		draw_texture_rect_region(
			texture,
			Rect2(-cell.x * factor / 2, -cell.y * factor, cell.x * factor, cell.y * factor),
			Rect2(Vector2(pose_index % 3, floori(pose_index / 3.0)) * cell, cell)
		)
		draw_set_transform(Vector2.ZERO)
		if portrait:
			var dimensions: Vector2 = portrait.get_size()
			draw_texture_rect(
				portrait,
				Rect2(
					(
						preview.position
						+ Vector2(preview.size.x * 0.62, (preview.size.y - dimensions.y) / 2)
					),
					dimensions
				),
				false
			)
	else:
		var physical: float = get_viewport().get_screen_transform().get_scale().y
		var fit: float = minf(
			preview.size.x / texture.get_width(), preview.size.y / texture.get_height()
		)
		var factor: float = maxf(1, floorf(fit * physical)) / physical
		var dimensions: Vector2 = texture.get_size() * factor
		var target = Rect2(preview.get_center() - dimensions / 2, dimensions)
		var visible: Rect2 = target.intersection(preview)
		draw_texture_rect_region(
			texture,
			visible,
			Rect2((visible.position - target.position) / factor, visible.size / factor)
		)


func _draw_checker() -> void:
	for y in range(12):
		for x in range(20):
			var color = Color("1e2a44") if (x + y) % 2 == 0 else Color("2d4855")
			draw_rect(Rect2(x * 16, y * 16, 16, 16), color)


func _draw_character() -> void:
	if backdrop:
		draw_texture(backdrop, Vector2.ZERO, Color(.42, .42, .42))
	if not texture:
		return
	var source = Rect2((pose_index % 3) * 48, (pose_index / 3) * 64, 48, 64)
	# Integer offsets retain readable clusters; no generated in-between frames are claimed.
	var bob = round(sin(clock * 3)) if moving and pose_index >= 3 else 0.0
	var lunge = round(maxf(0.0, sin(clock * 5)) * 3) if moving and pose_index == 6 else 0.0
	var recoil = sin(clock * 4) * .06 if moving and pose_index == 8 else 0.0
	draw_set_transform(Vector2(76 + lunge, 133 + bob), recoil)
	draw_texture_rect_region(texture, Rect2(-24, -64, 48, 64), source)
	draw_set_transform(Vector2.ZERO)
	# Companion portrait, also at native size. Both assets remain complete in clean view.
	if portrait:
		draw_rect(Rect2(187, 37, 100, 100), BRONZE)
		draw_rect(Rect2(188, 38, 98, 98), INK)
		draw_texture(portrait, Vector2(189, 39))
	draw_string(font, Vector2(51, 56), "48 x 64", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, IVORY)
	draw_string(font, Vector2(210, 29), "96 x 96", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, IVORY)
