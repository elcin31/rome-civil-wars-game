extends RefCounted
## Shared pixel font, Roman nine-slice chrome and safe-area geometry.

const INK = Color("14151f")
const IVORY = Color("ede3cc")
const GOLD = Color("d9a441")
static var shared_theme: Theme
static var density_override: float = 0.0


static func theme_resource() -> Theme:
	if shared_theme:
		return shared_theme
	shared_theme = Theme.new()
	var pixel_font: FontFile = load("res://assets/fonts/Tiny5.ttf")
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	shared_theme.default_font = pixel_font
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
	shared_theme.set_constant("line_separation", "Label", 2)
	shared_theme.set_constant("line_separation", "RichTextLabel", 3)
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
	var density: float = (
		maxf(1.0, DisplayServer.screen_get_dpi() / 160.0) if OS.has_feature("android") else 1.0
	)
	if density_override > 0:
		density = density_override
	return maxf(58.0, ceilf(48.0 * density / maxf(physical_scale, 0.1)))


static func label(
	parent: Node, value: String, rect: Rect2, font_size: int = 24, color: Color = IVORY
) -> Label:
	var control = Label.new()
	control.text = value
	control.position = rect.position
	control.size = rect.size
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	return control


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
		Rect2(Vector2(12, 6), rect.size - Vector2(24, 12)),
		24,
		IVORY if enabled else Color("8a8577")
	)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_size: int = 24
	while caption.get_minimum_size().y > rect.size.y - 12 and font_size > 18:
		font_size -= 2
		caption.add_theme_font_size_override("font_size", font_size)
		caption.size = rect.size - Vector2(24, 12)
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
