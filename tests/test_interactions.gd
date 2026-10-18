extends "res://addons/gut/test.gd"

const Hub = preload("res://scripts/gameplay/hub_model.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")


func test_quest_supplies_win_over_the_closer_merchant() -> void:
	var hub = Hub.new()
	hub.setup({"variant": 0}, Progression.fresh(), 35)
	hub.state.quest = 1
	hub.state.x = 180.0
	hub.state.y = 106.0
	assert_eq(hub.nearest(), "supplies", "The merchant must not intercept the active quest")
	assert_eq(hub.interact(), "supplies")
	assert_eq(int(hub.state.quest), 2, "Taking the crate advances delivery")


func test_every_hub_recovers_from_every_initial_visit_order() -> void:
	var runtime: Node = get_node("/root/StoryRuntime")
	var orders: Array = _permutations(["scribe", "supplies", "merchant", "witness", "exit"])
	var count: int = 0
	for beat in runtime.beats.values():
		if beat.type != "rpg":
			continue
		count += 1
		for order in orders:
			var hub = Hub.new()
			hub.setup(beat, Progression.fresh(), 35)
			for ident in order:
				_move_to(hub, ident)
				var before: int = hub.state.quest
				hub.interact()
				assert_gte(int(hub.state.quest), before, "Repeated visits cannot reset progress")
			var steps: int = 0
			while not hub.state.won and steps < 1000:
				hub.bot_step(1.0 / 30.0)
				steps += 1
			assert_true(hub.state.won, "%s must complete after visits %s" % [beat.id, order])
	assert_eq(count, 9)


func test_overlapping_interaction_regions_use_the_quest_target() -> void:
	var hub = Hub.new()
	hub.setup({}, Progression.fresh(), 35)
	for stage in range(4):
		hub.state.quest = stage
		var target: Dictionary = hub.stations[[0, 1, 3, 4][stage]]
		for x in range(int(target.x) - 29, int(target.x) + 30, 4):
			for y in range(int(target.y) - 29, int(target.y) + 30, 4):
				hub.state.x = float(x)
				hub.state.y = float(y)
				if Vector2(x - target.x, y - target.y).length() < Hub.RADIUS:
					assert_eq(hub.nearest(), target.id)


func test_each_transition_survives_reload_and_repeated_actions() -> void:
	var hub = Hub.new()
	hub.setup({}, Progression.fresh(), 35)
	for stage in range(4):
		_move_to(hub, Hub.QUEST_TARGETS[stage])
		hub.interact()
		var saved: Dictionary = JSON.parse_string(JSON.stringify(hub.state))
		assert_true(hub.restore(saved))
		var reached: int = hub.state.quest
		for tap in range(140):
			hub.interact()
		assert_eq(int(hub.state.quest), reached)
		assert_lte(hub.state.interactions.size(), 5, "Repeated taps cannot bloat saves")
	assert_true(hub.state.won)
	var corrupt: Dictionary = hub.state.duplicate(true)
	corrupt.quest = 1.5
	assert_false(hub.restore(corrupt))
	corrupt.quest = 1
	assert_false(hub.restore(corrupt), "Cannot restore a won quest without delivery")


func _move_to(hub: RefCounted, ident: String) -> void:
	for station in hub.stations:
		if station.id == ident:
			hub.state.x = float(station.x)
			hub.state.y = float(station.y)


func _permutations(items: Array) -> Array:
	if items.is_empty():
		return [[]]
	var result: Array = []
	for index in range(items.size()):
		var rest: Array = items.duplicate()
		rest.remove_at(index)
		for tail in _permutations(rest):
			result.append([items[index]] + tail)
	return result
