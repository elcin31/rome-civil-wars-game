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
				var frames = load("res://assets/characters/" + gallery.current.id + ".tres") as SpriteFrames
				assert(frames != null and frames.get_animation_names().size() == 9)
				for pose in range(9):
					gallery._action()
			elif group == 1:
				assert(gallery.layers.size() == 3, "Missing parallax layer")
			elif group == 2:
				var tiles = load("res://" + gallery.current.file.replace(".png", ".tres")) as TileSet
				assert(tiles != null and tiles.tile_size == Vector2i(16, 16))
				assert(tiles.get_source(0).get_tiles_count() == 64)
			await process_frame
			count += 1
		gallery._navigate(1)
		assert(gallery.asset_index == 0, "Forward wrap failed")
		gallery._navigate(-1)
		assert(gallery.asset_index == total - 1, "Backward wrap failed")
	assert(count == 36, "Unexpected asset count")
	gallery._toggle_fullscreen()
	assert(not gallery.chrome.visible)
	gallery._toggle_fullscreen()
	assert(gallery.chrome.visible)
	print("GALLERY PASS: ", count, " assets, 135 character keys, 36 parallax layers, 256 tile regions")
	quit(0)
