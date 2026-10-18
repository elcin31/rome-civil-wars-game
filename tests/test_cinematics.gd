extends GutTest
const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")


func test_all_cinematic_choices_outcomes_and_reload() -> void:
	var outcomes: Dictionary = {}
	for beat in StoryRuntime.beats.values():
		if beat.type != "cutscene":
			continue
		for option in range(2):
			for seed_number in range(1, 31):
				var model = Factory.create(beat, Progression.fresh(), 35)
				model.configure({"seed": seed_number, "flags": {}})
				while not model.waiting_choice():
					model.next_frame()
				assert_true(model.choose(option))
				assert_false(model.choose(option), "Decision cannot be repeated")
				var loaded = Factory.create(beat, Progression.fresh(), 35)
				loaded.configure({"seed": seed_number, "flags": {}})
				assert_true(loaded.restore(JSON.parse_string(JSON.stringify(model.state))))
				assert_gte(Factory.solve(model, "cutscene"), 0)
				assert_gte(Factory.solve(loaded, "cutscene"), 0)
				assert_eq(model.result(), loaded.result(), "Reload preserves roll and consequences")
				outcomes[model.state.outcome] = true
				var result: Dictionary = model.result().duplicate(true)
				model.replay()
				Factory.solve(model, "cutscene")
				assert_eq(model.result(), result, "Replay cannot reroll")
	assert_eq(outcomes.size(), 3, "Win, costly outcome and loss all advance")


func test_skip_waits_for_choice_and_soft_games_are_optional() -> void:
	for beat in StoryRuntime.beats.values():
		var model = Factory.create(beat, Progression.fresh(), 35)
		if beat.type == "cutscene":
			model.skip()
			assert_false(model.state.won)
			assert_true(model.waiting_choice())
			model.choose(1)
			model.skip()
			assert_true(model.state.won)
			assert_eq(model.state.challenge, 0)
		elif beat.type == "soft":
			assert_gte(Factory.solve(model, "soft"), 0)
			assert_false(model.state.failed)
			var skipped = Factory.create(beat, Progression.fresh(), 35)
			skipped.skip()
			assert_true(skipped.state.won)
			assert_true(skipped.state.neutral)


func test_reject_corrupt_cinematic_snapshot() -> void:
	for beat in StoryRuntime.beats.values():
		if beat.type != "cutscene":
			continue
		var model = Factory.create(beat, Progression.fresh(), 35)
		var corrupt: Dictionary = model.state.duplicate(true)
		corrupt.selected = 0.5
		assert_false(model.restore(corrupt))
		corrupt = model.state.duplicate(true)
		corrupt.won = true
		assert_false(model.restore(corrupt))
