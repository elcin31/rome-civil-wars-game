extends RefCounted
## Hub drawing and collision-free context prompt; coordinates stay in world space.

const INK = Color("14151f")
const OCHRE = Color("d9a441")
const BRONZE = Color("a87b3d")


static func object_rect(station: Dictionary) -> Rect2:
	var dimensions: Vector2 = (
		Vector2(22, 18)
		if station.id == "supplies"
		else (Vector2(20, 32) if station.id == "exit" else Vector2(28, 46))
	)
	return Rect2(Vector2(station.x - dimensions.x / 2, station.y - dimensions.y), dimensions)


static func place_prompt(view: Control) -> void:
	if not view.nearby_button.visible:
		return
	var cache_key: Array = [
		Vector2(roundf(view.model.state.x), roundf(view.model.state.y)),
		view.model.nearest(),
		view.size
	]
	if view.get_meta("prompt_cache", []) == cache_key:
		return
	view.set_meta("prompt_cache", cache_key)
	var obstacles: Array[Rect2] = []
	for station in view.model.stations:
		obstacles.append(view.world_transform * object_rect(station))
		if station.id == view.model.nearest():
			var caption: Rect2 = view.world_transform * caption_rect(view, station)
			view.nearby_button.set_meta("avoid_rect", caption)
			obstacles.append(caption)
	var hero: Vector2 = Vector2(view.model.state.x, view.model.state.y)
	for offset in [Vector2.ZERO, Vector2(-30, 12)]:
		obstacles.append(
			view.world_transform * Rect2(hero + offset - Vector2(14, 46), Vector2(28, 46))
		)
	var available: Rect2 = Rect2(16, 132, view.size.x - 32, view.status.position.y - 152)
	var dimensions: Vector2 = view.nearby_button.size
	var origin: Vector2 = view.world_transform * hero
	var best: Vector2 = available.position
	var distance: float = INF
	for y in range(ceilf(available.position.y), floorf(available.end.y - dimensions.y) + 1, 12):
		for x in range(16, floorf(available.end.x - dimensions.x) + 1, 20):
			var candidate: Rect2 = Rect2(Vector2(x, y), dimensions)
			var clear: bool = true
			for obstacle in obstacles:
				if candidate.grow(6).intersects(obstacle):
					clear = false
					break
			var score: float = candidate.get_center().distance_squared_to(origin)
			if clear and score < distance:
				best = candidate.position
				distance = score
	view.nearby_button.position = best
	view.nearby_button.set_meta("avoid_rects", obstacles)


static func debug_tap(view: Control, point: Vector2) -> void:
	if not Rect2(156, 8, view.size.x - 180, 104).has_point(point):
		return
	var now: int = Time.get_ticks_msec()
	var count: int = int(view.get_meta("debug_taps", 0)) + 1
	if now - int(view.get_meta("debug_tap_time", 0)) > 1800:
		count = 1
	view.set_meta("debug_tap_time", now)
	view.set_meta("debug_taps", count % 5)
	if count == 5:
		view.debug_interactions = not view.debug_interactions
		view.queue_redraw()


static func caption_rect(view: Control, station: Dictionary) -> Rect2:
	var width: float = view.font.get_string_size(station.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	return Rect2(
		clampf(station.x + 18, 4, 316 - width) - 3,
		station.y - 34,
		width + 6,
		view.font.get_height(11) + 6
	)


static func draw(view: Control) -> void:
	# A continuous earth plane, a path, horizon and contact shadows make depth explicit.
	view.draw_rect(Rect2(0, 60, 320, 88), Color(0.29, 0.22, 0.15, 0.94))
	view.draw_line(Vector2(0, 66), Vector2(320, 66), Color("bfa87a"), 2)
	view.draw_colored_polygon(
		PackedVector2Array([Vector2(0, 114), Vector2(320, 97), Vector2(320, 128), Vector2(0, 132)]),
		Color("76503b")
	)
	# A small brazier has a recognisable bowl, feet and two flickering flame clusters.
	var flicker: float = float(int(Time.get_ticks_msec() / 180) % 2)
	view.draw_line(Vector2(32, 89), Vector2(32, 98), Color("737e82"), 2)
	view.draw_line(Vector2(26, 98), Vector2(38, 98), Color("737e82"), 2)
	view.draw_colored_polygon(
		PackedVector2Array([Vector2(26, 85), Vector2(38, 85), Vector2(36, 89), Vector2(28, 89)]),
		BRONZE
	)
	view.draw_colored_polygon(
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
	view.draw_colored_polygon(
		PackedVector2Array([Vector2(31, 85), Vector2(33, 80 + flicker), Vector2(35, 85)]), OCHRE
	)
	var actors: Array = []
	var target: String = view.model.quest_target()
	for station in view.model.stations:
		actors.append({"kind": station.id, "x": station.x, "y": station.y})
		if station.id == target:
			var tip = Vector2(station.x + 18, station.y - 38)
			view.draw_colored_polygon(
				PackedVector2Array([tip, tip + Vector2(-4, -6), tip + Vector2(4, -6)]), OCHRE
			)
	actors.append({"kind": "hero", "x": view.model.state.x, "y": view.model.state.y})
	if not view.get_node("/root/StoryRuntime").state.flags.get("friend_lost", false):
		actors.append(
			{
				"kind": "ally",
				"x": clampf(view.model.state.x - 30, 18, 302),
				"y": view.model.state.y + 12
			}
		)
	actors.sort_custom(func(a, b): return a.y < b.y)
	for actor in actors:
		var point = Vector2(actor.x, actor.y)
		match actor.kind:
			"supplies":
				view.draw_rect(Rect2(point - Vector2(9, 13), Vector2(18, 13)), Color("4a3026"))
				view.draw_rect(Rect2(point - Vector2(9, 13), Vector2(18, 13)), BRONZE, false)
				view.draw_line(point - Vector2(8, 12), point - Vector2(-8, 1), BRONZE)
				view.draw_line(point - Vector2(-8, 12), point - Vector2(8, 1), BRONZE)
			"exit":
				view.draw_line(point, point - Vector2(0, 28), Color("76503b"), 3)
				view.draw_colored_polygon(
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
				view._sprite(view._hero_sprite(), point, 4 if view.joy_axis.length() > 0.1 else 3)
			"ally":
				view._sprite(
					"lucius_vorenus" if view._hero_sprite() == "titus_pullo" else "titus_pullo",
					point,
					4
				)
			_:
				view._sprite(
					(
						"npc_merchant"
						if actor.kind == "merchant"
						else ("npc_scribe" if actor.kind == "scribe" else "npc_healer")
					),
					point
				)
	var near: String = view.model.nearest()
	for station in view.model.stations:
		if view.debug_interactions:
			view.draw_arc(Vector2(station.x, station.y), view.model.RADIUS, 0, TAU, 32, BRONZE, 1)
		if station.id == target:
			var start: Vector2 = Vector2(view.model.state.x, view.model.state.y - 6)
			var direction: Vector2 = (Vector2(station.x, station.y - 6) - start).normalized()
			if start.distance_to(Vector2(station.x, station.y)) > 32:
				var tip: Vector2 = start + direction * 20
				view.draw_line(start, tip, OCHRE, 1)
				view.draw_line(tip, tip - direction.rotated(0.55) * 5, OCHRE, 1)
				view.draw_line(tip, tip - direction.rotated(-0.55) * 5, OCHRE, 1)
		if station.id == near:
			view.draw_rect(object_rect(station).grow(2), INK, false, 3)
			view.draw_rect(object_rect(station).grow(2), OCHRE, false, 1)
			var caption: Rect2 = caption_rect(view, station)
			view.draw_rect(caption, INK)
			view.draw_string(
				view.font,
				caption.position + Vector2(3, 3 + view.font.get_ascent(11)),
				station.name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				OCHRE
			)
