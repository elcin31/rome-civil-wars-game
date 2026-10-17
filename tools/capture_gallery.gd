extends SceneTree
## Run with a real display (e.g. DISPLAY=:99), not the headless dummy renderer.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var gallery = load("res://scenes/AssetGallery.tscn").instantiate()
	root.add_child(gallery)
	await process_frame
	gallery.moving = false
	var shots = [[0, 0, "hero"], [1, 2, "alesia"], [2, 0, "tiles"], [3, 2, "map"]]
	for shot in shots:
		gallery._select_group(shot[0])
		gallery._select_asset(shot[1])
		gallery.fullscreen = false
		gallery.chrome.visible = true
		await process_frame
		await RenderingServer.frame_post_draw
		var picture = root.get_texture().get_image()
		assert(picture != null and not picture.is_empty())
		picture.save_png("res://docs/gallery_" + shot[2] + ".png")
	print("Saved four real Godot gallery screenshots")
	quit(0)
