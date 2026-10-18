extends RefCounted
## Readable Cyrillic typography, Roman nine-slice chrome and safe-area geometry.

const INK = Color("14151f")
const IVORY = Color("ede3cc")
const GOLD = Color("d9a441")
static var shared_theme: Theme
static var strong_face: FontFile
static var title_face: FontFile
static var density_override: float = 0.0


static func theme_resource() -> Theme:
	if shared_theme:
		return shared_theme
	shared_theme = Theme.new()
	var reading_face: FontFile = load("res://assets/fonts/GolosText-Reading.ttf")
	strong_face = load("res://assets/fonts/GolosText-Semibold.ttf")
	title_face = load("res://assets/fonts/PTSerif-Bold.ttf")
	for face in [reading_face, strong_face, title_face]:
		face.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		face.hinting = TextServer.HINTING_LIGHT
		face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		face.oversampling = 2.0
	shared_theme.default_font = reading_face
	shared_theme.default_font_size = 24
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var style = StyleBoxTexture.new()
		style.texture = load("res://assets/ui/roman_" + state + ".png")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, 12)
			style.set_content_margin(side, 10)
		shared_theme.set_stylebox(state, "Button", style)
	shared_theme.set_color("font_color", "Label", IVORY)
	shared_theme.set_color("default_color", "RichTextLabel", IVORY)
	shared_theme.set_constant("line_separation", "Label", 4)
	shared_theme.set_constant("line_separation", "RichTextLabel", 6)
	return shared_theme


static func safe_rect(view: Control) -> Rect2:
	var rect = view.get_viewport_rect()
	if OS.has_feature("android"):
		var inverse = view.get_viewport().get_screen_transform().affine_inverse()
		var available: Rect2 = inverse * Rect2(DisplayServer.get_display_safe_area())
		if available.size.x > 0 and available.size.y > 0:
			rect = rect.intersection(available)
	# The same path is used by the notch/gesture regression test.
	var inset: Vector4 = view.get_meta("safe_insets", Vector4.ZERO)
	return Rect2(
		rect.position + Vector2(inset.x, inset.y),
		rect.size - Vector2(inset.x + inset.z, inset.y + inset.w)
	)


static func touch_height(view: Control) -> float:
	var physical_scale: float = view.get_viewport().get_screen_transform().get_scale().y
	return maxf(58.0, ceilf(48.0 * _density() / maxf(physical_scale, 0.1)))


static func _density() -> float:
	return (
		density_override
		if density_override > 0
		else (
			maxf(1.0, DisplayServer.screen_get_dpi() / 160.0) if OS.has_feature("android") else 1.0
		)
	)


static func accessible_font_size(view: Control, baseline: int, sp: float = 16.0) -> int:
	var physical_scale: float = view.get_viewport().get_screen_transform().get_scale().y
	return maxi(baseline, ceili(sp * _density() / maxf(physical_scale, 0.1)))


static func label(
	parent: Node,
	value: String,
	rect: Rect2,
	font_size: int = 24,
	color: Color = IVORY,
	custom_font: Font = null
) -> Label:
	theme_resource()
	var control = Label.new()
	control.text = value
	control.position = rect.position
	control.size = rect.size
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if custom_font != null or font_size >= 26:
		control.add_theme_font_override("font", custom_font if custom_font != null else strong_face)
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_meta("text_budget", rect.size)
	parent.add_child(control)
	fit_label(control, font_size)
	return control


static func fit_label(control: Label, font_size: int, minimum: int = 18) -> void:
	var budget: Vector2 = control.get_meta("text_budget", control.size)
	control.add_theme_font_size_override("font_size", font_size)
	control.size = budget
	while (
		(
			control.get_minimum_size().y > budget.y
			or control.get_minimum_size().x > budget.x
			or (
				control.autowrap_mode == TextServer.AUTOWRAP_WORD
				and _word_width(control, font_size) > budget.x
			)
		)
		and font_size > minimum
	):
		font_size -= 1
		control.add_theme_font_size_override("font_size", font_size)
		control.size = budget
	# Reapply after the final minimum-size calculation; wrapping can enlarge a Label.
	control.size = budget


static func _word_width(control: Label, font_size: int) -> float:
	var width: float = 0.0
	var face: Font = control.get_theme_font("font")
	for word in control.text.replace("\n", " ").split(" ", false):
		width = maxf(width, face.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return width


static func heading(
	parent: Node, value: String, rect: Rect2, font_size: int = 30, color: Color = GOLD
) -> Label:
	theme_resource()
	return label(parent, value, rect, font_size, color, title_face)


static func button(
	parent: Node, value: String, rect: Rect2, callback: Callable, enabled: bool = true
) -> Button:
	var control = Button.new()
	control.position = rect.position
	control.size = rect.size
	control.custom_minimum_size = rect.size
	control.disabled = not enabled
	control.set_meta("caption", value)
	control.pressed.connect(
		func():
			parent.get_node("/root/GameServices").effect("choice")
			callback.call()
	)
	parent.add_child(control)
	var caption = label(
		control,
		value,
		Rect2(Vector2(12, 4), rect.size - Vector2(24, 8)),
		accessible_font_size(control, 24, 14.0),
		IVORY if enabled else Color("a39b8c"),
		strong_face
	)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fit_label(caption, accessible_font_size(control, 24, 14.0))
	return control


static func panel(parent: Node, rect: Rect2, kind: String = "stone") -> Panel:
	var control = Panel.new()
	var style = StyleBoxTexture.new()
	style.texture = load("res://assets/ui/roman_" + kind + ".png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 12)
	control.add_theme_stylebox_override("panel", style)
	control.position = rect.position
	control.size = rect.size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	return control


static func enable_button(button: Button, enabled: bool) -> void:
	if not is_instance_valid(button):
		return
	button.disabled = not enabled
	for child in button.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", IVORY if enabled else Color("a39b8c"))


static func set_button_text(button: Button, value: String) -> void:
	button.text = ""
	button.set_meta("caption", value)
	for child in button.get_children():
		if child is Label:
			child.text = value
			fit_label(child, accessible_font_size(button, 24, 14.0))
