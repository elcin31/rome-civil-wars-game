extends "res://addons/gut/test.gd"

const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")


func _beat(kind: String, difficulty: int = 1) -> Dictionary:
	return {"id": "test", "type": kind, "difficulty": difficulty, "variant": difficulty}


func test_tactics_reject_illegal_moves_and_exhausted_actions() -> void:
	var model = Factory.create(_beat("tactical"), Progression.fresh(), 35)
	var original: Dictionary = model.state.duplicate(true)
	assert_false(model.move_unit(0, Vector2i(-1, 2)))
	assert_false(model.move_unit(0, Vector2i(4, 0)))
	assert_false(model.attack(0, 3))
	assert_eq(model.state, original)
	assert_true(model.guard(0))
	assert_true(model.guard(0))
	assert_false(model.move_unit(0, Vector2i(2, 2)))
	assert_false(model.cooperate())


func test_all_tactical_difficulties_have_a_winning_action_path() -> void:
	for difficulty in range(1, 11):
		var progress: Dictionary = Progression.fresh()
		if difficulty == 10:
			# The final battle follows nine previous missions and access to a hub shop.
			for mission in range(9):
				Progression.reward(progress, "earlier_%d" % mission)
			for upgrade in range(3):
				Progression.train(progress, "strength")
				Progression.buy(progress, "sword")
			for upgrade in range(2):
				Progression.train(progress, "formation")
				Progression.buy(progress, "shield")
		var model = Factory.create(_beat("tactical", difficulty), progress, 35)
		assert_gt(Factory.solve(model, "tactical"), 0, "Tactical difficulty %d" % difficulty)
		assert_true(model.state.won)


func test_platformer_real_physics_collects_items_and_reaches_exit() -> void:
	for difficulty in [1, 5, 10]:
		var model = Factory.create(_beat("platformer", difficulty), Progression.fresh(), 35)
		assert_gt(Factory.solve(model, "platformer"), 0, "Platform difficulty %d" % difficulty)
		assert_eq(model.state.tokens.size(), 3)
		assert_eq(
			int(model.state.retries), 0, "A successful traversal must not rely on repeated respawns"
		)


func test_fall_restores_checkpoint_and_not_the_whole_episode() -> void:
	var model = Factory.create(_beat("platformer"), Progression.fresh(), 60)
	model.state.checkpoint = 250.0
	model.state.x = 405.0
	model.state.y = 210.0
	model.tick(1.0 / 60.0, 0, false, false, false, false)
	assert_eq(float(model.state.x), 250.0)
	assert_eq(int(model.state.retries), 1)
	assert_eq(int(model.state.hp), int(model.state.max_hp))


func test_hub_requires_walking_and_delivery_before_exit() -> void:
	var model = Factory.create(_beat("rpg"), Progression.fresh(), 35)
	assert_eq(model.interact(), "")
	assert_false(model.state.won)
	model.state.x = 303.0
	model.state.y = 122.0
	assert_eq(model.interact(), "exit")
	assert_false(model.state.won)
	assert_gt(Factory.solve(model, "rpg"), 0)
	assert_eq(int(model.state.quest), 3)


func test_snapshot_roundtrip_and_corrupt_snapshot_rejection() -> void:
	for kind in ["tactical", "platformer", "rpg"]:
		var model = Factory.create(_beat(kind), Progression.fresh(), 60)
		if kind == "tactical":
			model.bot_turn()
		elif kind == "platformer":
			for step in range(120):
				var action: Dictionary = model.bot_input()
				model.tick(
					1.0 / 60.0, action.axis, action.jump, action.strike, action.block, action.dodge
				)
		else:
			for step in range(120):
				model.bot_step(1.0 / 60.0)
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(model.state))
		var resumed = Factory.create(_beat(kind), Progression.fresh(), 60)
		assert_true(resumed.restore(snapshot), kind)
		assert_gt(Factory.solve(resumed, kind), 0, kind)
		assert_false(resumed.restore({"x": "invalid"}))


func test_shop_requires_reaching_the_merchant() -> void:
	var progress: Dictionary = Progression.fresh()
	var model = Factory.create(_beat("rpg"), progress, 35)
	assert_false(model.buy(progress, "sword", 0))
	assert_false(model.train(progress, "strength"))
	assert_eq(int(progress.coins), 24)
	model.state.x = 184.0
	model.state.y = 76.0
	assert_true(model.buy(progress, "sword", 0))
	assert_true(model.train(progress, "strength"))


func test_heroes_and_bond_change_platforming_defense() -> void:
	var pullo = Factory.create(_beat("platformer"), Progression.fresh(), 35, false)
	var advancement: Dictionary = Progression.fresh()
	advancement.hero = "vorenus"
	var vorenus = Factory.create(_beat("platformer"), advancement, 35, false)
	pullo.state.block = true
	vorenus.state.block = true
	pullo._damage(2)
	vorenus._damage(2)
	assert_eq(int(pullo.state.max_hp) - int(pullo.state.hp), 1)
	assert_eq(int(vorenus.state.max_hp) - int(vorenus.state.hp), 0)
	var supported = Factory.create(_beat("platformer"), Progression.fresh(), 65, true)
	var solitary = Factory.create(_beat("platformer"), Progression.fresh(), 35, false)
	supported.tick(1.0 / 60.0, 0, true, false, false, false)
	solitary.tick(1.0 / 60.0, 0, true, false, false, false)
	assert_lt(float(supported.state.vy), float(solitary.state.vy))
