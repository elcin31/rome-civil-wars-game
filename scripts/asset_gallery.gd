extends Control
## Part 1 art viewer. All art is shown at its native pixel size in fullscreen.
## Animation here is explicitly procedural; each named pose has one painted key.

const GROUPS = ["characters", "locations", "tiles", "ui"]
const GROUP_NAMES = ["Герои", "Локации", "Тайлы", "Интерфейс"]
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
	font = ThemeDB.fallback_font
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/manifest.json"))
	if data is Dictionary:
		assets = data.get("assets", [])
	if ResourceLoader.exists("res://assets/locations/gaul_forest.png"):
		backdrop = load("res://assets/locations/gaul_forest.png")
	if ResourceLoader.exists("res://assets/ui/buttons.png"):
		button_art = load("res://assets/ui/buttons.png")
	if ResourceLoader.exists("res://assets/ui/arrows.png"):
		arrow_art = load("res://assets/ui/arrows.png")
	_build_ui()
	if ResourceLoader.exists("res://scenes/StoryMain.tscn"):
		var words = JSON.parse_string(FileAccess.get_file_as_string("res://story/ui_ru.json"))
		_button(words.get("return_gallery", "Menu"), Rect2(276, 0, 44, 15),
			func(): get_tree().change_scene_to_file("res://scenes/StoryMain.tscn"))
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
	var button = Button.new()
	button.text = text_value
	button.position = box.position
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", OCHRE)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("4a3026") if state == "pressed" else Color("2b1b14")
		style.border_color = OCHRE if state == "focus" or state == "hover" else BRONZE
		style.set_border_width_all(1)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	chrome.add_child(button)
	button.size = box.size
	button.set_deferred("size", box.size)
	return button


func _label(text_value: String, pos: Vector2, color: Color = IVORY) -> Label:
	var label = Label.new()
	label.text = text_value
	label.position = pos
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.add_child(label)
	return label


func _build_ui() -> void:
	chrome = Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chrome)
	_label("C I N I S   L A U R I", Vector2(5, 1), OCHRE)
	_label("ПЕПЕЛ ЛАВРА  /  ART I", Vector2(207, 1), BRONZE)
	for i in range(4):
		tabs.append(_button(GROUP_NAMES[i], Rect2(i * 80, 16, 80, 18), _select_group.bind(i)))
	_button("<", Rect2(3, 143, 32, 32), _navigate.bind(-1))
	_button(">", Rect2(285, 143, 32, 32), _navigate.bind(1))
	name_label = _label("", Vector2(40, 141))
	detail_label = _label("", Vector2(40, 151), BRONZE)
	action_button = _button("", Rect2(40, 163, 117, 14), _action)
	_button("Чистый вид 1:1", Rect2(163, 163, 117, 14), _toggle_fullscreen)


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
	detail_label.text = "%s x %s px  /  24 цвета" % [dimensions[0], dimensions[1]]
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
			KEY_RIGHT: _navigate(1)
			KEY_LEFT: _navigate(-1)
			KEY_TAB: _select_group(group_index + 1)
			KEY_SPACE: _action()
			KEY_F, KEY_ESCAPE: _toggle_fullscreen()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), INK)
	if current.is_empty():
		return
	if group_index == 1 and not layers.is_empty():
		for i in range(layers.size()):
			var displacement = round(sin(clock * .3) * i * 2) if moving else 0.0
			draw_texture(layers[i], Vector2(displacement, 0))
	elif group_index == 0:
		_draw_character()
	else:
		_draw_checker()
		if texture:
			draw_texture(texture, (Vector2(320, 180) - texture.get_size()) / 2)
			if current.get("id", "") == "dialogue" and button_art:
				for state in range(4):
					draw_texture_rect_region(button_art, Rect2(14 + state * 76, 117, 64, 20), Rect2(0, state * 20, 64, 20))
				if arrow_art:
					draw_texture(arrow_art, Vector2(144, 142))
	if not fullscreen:
		draw_rect(Rect2(0, 0, 320, 16), INK)
		draw_line(Vector2(0, 15), Vector2(320, 15), BRONZE)
		draw_rect(Rect2(0, 140, 320, 40), INK)
		draw_line(Vector2(0, 140), Vector2(320, 140), BRONZE)
		if not texture:
			draw_string(font, Vector2(88, 90), "Исходник в работе", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, IVORY)


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
