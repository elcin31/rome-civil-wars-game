extends RefCounted
## Layout telemetry is enabled only in the separate AndroidSmoke export.


static func write(view: Control) -> void:
	var screen: Transform2D = view.get_viewport().get_screen_transform()
	var buttons: Array = []
	var pending: Array[Node] = [view]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Control and not node.is_visible_in_tree():
			continue
		if node is Button:
			var rect: Rect2 = screen * node.get_global_rect()
			buttons.append(
				{
					"text": node.get_meta("caption", node.text),
					"disabled": node.disabled,
					"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
				}
			)
		pending.append_array(node.get_children())
	var data: Dictionary = {
		"mode": view.mode,
		"dpi": DisplayServer.screen_get_dpi(),
		"buttons": buttons,
		"frame": Engine.get_process_frames(),
		"transition": view.transition_serial
	}
	var encounter: Control = view.encounter
	if is_instance_valid(encounter):
		data.encounter_type = encounter.beat.type
		var center: Vector2 = (
			screen * (encounter.get_global_transform_with_canvas() * encounter._joy_center())
		)
		data.joystick = [center.x, center.y, encounter._joy_radius() * screen.get_scale().y]
	var path: String = "user://cinis_ui_layout.json"
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)
		)
