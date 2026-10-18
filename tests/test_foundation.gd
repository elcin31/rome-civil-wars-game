extends "res://addons/gut/test.gd"

const Runtime = preload("res://scripts/story_runtime.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")
var game: Node


func before_each() -> void:
	game = Runtime.new()
	game.save_path = "user://gut_auto_%s.json" % OS.get_process_id()
	game.slot_prefix = "user://gut_slot_%s_" % OS.get_process_id()
	add_child_autofree(game)
	game.start_new()


func after_each() -> void:
	var paths: Array = [game.save_path]
	for slot in range(1, 4):
		paths.append(game.slot_prefix + str(slot) + ".json")
	for path in paths:
		for suffix in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func test_decision_is_persistent_and_not_applied_twice() -> void:
	for step in range(200):
		if game.current().has("choices"):
			break
		if game.current().get("kind") == "beat":
			game.complete_beat()
		else:
			game.advance()
	assert_true(game.choose(game.first_choice()))
	var saved: Dictionary = game.state.duplicate(true)
	assert_true(game.load_game())
	assert_true(game.load_game())
	assert_eq(int(game.state.bond), int(saved.bond))
	assert_eq(game.state.flags, saved.flags)
	assert_eq(game.state.decisions, saved.decisions)
	assert_eq(game.state.history.size(), saved.history.size())
	assert_eq(int(game.state.gameplay.coins), int(saved.gameplay.coins))


func test_independent_slots_and_backup_recovery() -> void:
	assert_true(game.save_slot(1))
	game.state.gameplay.coins = 71
	assert_true(game.save_slot(2))
	assert_true(game.load_slot(1))
	assert_eq(int(game.state.gameplay.coins), 24)
	assert_true(game.load_slot(2))
	assert_eq(int(game.state.gameplay.coins), 71)
	game.state.gameplay.coins = 72
	assert_true(game.save_slot(2))
	var file = FileAccess.open(game.slot_prefix + "2.json", FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert_true(game.load_slot(2))
	assert_eq(int(game.state.gameplay.coins), 71)
	assert_false(game.save_slot(0))
	assert_false(game.load_slot(4))


func test_corrupt_progression_does_not_replace_live_state() -> void:
	var saved: Dictionary = game.state.duplicate(true)
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.gameplay.equipment = "bad"
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	assert_false(game.load_game())
	assert_eq(game.state, saved)


func test_reward_and_shop_cannot_duplicate_or_overspend() -> void:
	var data: Dictionary = Progression.fresh()
	assert_true(Progression.reward(data, "first", 100))
	assert_false(Progression.reward(data, "first", 100))
	assert_eq(int(data.level), 2)
	assert_eq(int(data.xp), 100)
	assert_true(Progression.train(data, "strength"))
	assert_true(Progression.train(data, "formation"))
	assert_false(Progression.train(data, "diplomacy"))
	assert_true(Progression.buy(data, "sword"))
	assert_true(Progression.buy(data, "shield"))
	assert_false(Progression.buy(data, "sword"))
	assert_gte(data.coins, 0)


func test_lost_companion_cannot_remain_the_controlled_hero() -> void:
	game.state.gameplay.hero = "vorenus"
	game.apply_effects({"set_flags": ["friend_lost"]})
	assert_eq(game.state.gameplay.hero, "pullo")
	assert_true(game.save_game())
	assert_true(game.load_game())
	assert_eq(game.state.gameplay.hero, "pullo")


func test_corrupt_records_do_not_overwrite_the_last_valid_backup() -> void:
	assert_true(game.save_game())
	var backup: String = FileAccess.get_file_as_string(game.save_path + ".bak")
	var corrupt: Dictionary = game.state.duplicate(true)
	corrupt.history = [{"node": "ch01_s01_n01", "speaker": 5, "text": {}}]
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	assert_false(game.load_game())
	assert_true(game.save_game())
	assert_eq(FileAccess.get_file_as_string(game.save_path + ".bak"), backup)


func test_supplies_cannot_be_spent_in_a_noncombat_episode() -> void:
	game.go("ch01_s06_n80")
	var factory = load("res://scripts/gameplay/encounter_factory.gd")
	var model = factory.create(game.beats[game.current().beat], game.state.gameplay, 35)
	game.state.gameplay.encounter = {"beat": game.current().beat, "state": model.state}
	var before: int = game.state.gameplay.supplies
	assert_false(game.use_supply())
	assert_eq(int(game.state.gameplay.supplies), before)


func test_legacy_story_save_recovers_completed_mission_progression_once() -> void:
	game.start_new(4)
	var legacy: Dictionary = game.state.duplicate(true)
	legacy.erase("gameplay")
	var expected_xp: int = legacy.beats_completed.size() * 45
	var file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	assert_true(game.load_game())
	assert_eq(int(game.state.gameplay.xp), expected_xp)
	assert_true(game.save_game())
	assert_true(game.load_game())
	assert_eq(int(game.state.gameplay.xp), expected_xp)
