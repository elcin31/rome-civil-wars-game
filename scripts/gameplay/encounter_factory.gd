extends RefCounted

const Soft = preload("res://scripts/gameplay/soft_model.gd")
const Cinematic = preload("res://scripts/gameplay/cutscene_model.gd")
const Tactical = preload("res://scripts/gameplay/tactical_model.gd")
const Platformer = preload("res://scripts/gameplay/platform_model.gd")
const Hub = preload("res://scripts/gameplay/hub_model.gd")


static func create(
	beat: Dictionary, progress: Dictionary, bond: int, companion: bool = true
) -> RefCounted:
	var model: RefCounted
	match beat.type:
		"soft":
			model = Soft.new()
		"cutscene":
			model = Cinematic.new()
		"tactical":
			model = Tactical.new()
		"platformer":
			model = Platformer.new()
		_:
			model = Hub.new()
	model.setup(beat, progress, bond, companion)
	return model


static func solve(model: RefCounted, kind: String, maximum_steps: int = 24000) -> int:
	for step in range(maximum_steps):
		if model.state.won:
			return step
		if model.state.failed:
			return -1
		match kind:
			"tactical":
				model.bot_turn()
			"platformer":
				var input: Dictionary = model.bot_input()
				model.tick(
					1.0 / 60.0, input.axis, input.jump, input.strike, input.block, input.dodge
				)
			_:
				model.bot_step(1.0 / 60.0)
	return -1
