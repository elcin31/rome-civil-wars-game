extends SceneTree
## Headless integration check: load every resource, traverse every gallery item and pose.


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var scene = load("res://scenes/AssetGallery.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var gallery = scene.instantiate()
	root.add_child(gallery)
	await process_frame
	var count: int = 0
	for group in range(4):
		gallery._select_group(group)
		var total: int = gallery.filtered.size()
		for index in range(total):
			gallery._select_asset(index)
			assert(gallery.texture != null, "Missing texture")
			if group == 0:
				assert(gallery.portrait != null, "Missing portrait")
				var frames = (
					load("res://assets/characters/" + gallery.current.id + ".tres") as SpriteFrames
				)
				assert(frames != null and frames.get_animation_names().size() == 9)
				for pose in range(9):
					gallery._action()
			elif group == 1:
				assert(gallery.layers.size() == 3, "Missing parallax layer")
			elif group == 2:
				var tiles = (
					load("res://" + gallery.current.file.replace(".png", ".tres")) as TileSet
				)
				assert(tiles != null and tiles.tile_size == Vector2i(16, 16))
				assert(tiles.get_source(0).get_tiles_count() == 64)
			await process_frame
			count += 1
		gallery._navigate(1)
		assert(gallery.asset_index == 0, "Forward wrap failed")
		gallery._navigate(-1)
		assert(gallery.asset_index == total - 1, "Backward wrap failed")
	assert(count == 36, "Unexpected asset count")
	# Exercise input events and real button signal bindings, including cyclic navigation.
	gallery._select_group(0)
	gallery._select_asset(0)
	var down = InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(250, 90)
	gallery._unhandled_input(down)
	var up = InputEventScreenTouch.new()
	up.pressed = false
	up.position = Vector2(70, 90)
	gallery._unhandled_input(up)
	assert(gallery.asset_index == 1, "Touch swipe failed")
	var key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_RIGHT
	gallery._unhandled_input(key)
	assert(gallery.asset_index == 2, "Keyboard navigation failed")
	gallery.tabs[2].pressed.emit()
	assert(gallery.group_index == 2, "Category button binding failed")
	var previous_motion: bool = gallery.moving
	gallery.action_button.pressed.emit()
	assert(gallery.moving != previous_motion, "Action button binding failed")
	await process_frame
	for button in gallery.tabs:
		assert(button.size.y <= 18, "Category exceeds allocated height")
	assert(
		gallery.action_button.position.y + gallery.action_button.size.y <= 180,
		"Footer button exceeds viewport"
	)
	gallery._toggle_fullscreen()
	assert(not gallery.chrome.visible)
	gallery._toggle_fullscreen()
	assert(gallery.chrome.visible)
	print(
		"GALLERY PASS: ", count, " assets, 135 character keys, 36 parallax layers, 256 tile regions"
	)
	quit(0)
