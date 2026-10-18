extends SceneTree
## Real complete campaigns with alternate cinematic decisions and independent save seeds.
const Factory = preload("res://scripts/gameplay/encounter_factory.gd")
var game: Node
var outcomes: Dictionary = {}
var executions: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	game = root.get_node("StoryRuntime")
	game.save_path = "user://alternative_bot_%s.json" % OS.get_process_id()
	game.test_seed = 1
	for seed_number in range(1, 5):
		for civilian in [false, true]:
			for alternative in [false, true]:
				game.start_new()
				game.state.seed = seed_number
				game.suppress_save = true
				for step in range(4000):
					var node: Dictionary = game.current()
					if node.kind == "ending":
						break
					if node.has("choices"):
						var index: int = game.first_choice()
						if alternative:
							for i in range(node.choices.size()):
								if game.condition(node.choices[i].get("condition", "")):
									index = i
						if node.id == "ch02_s08_n90":
							for i in range(node.choices.size()):
								if node.choices[i].id.ends_with(
									"citizen" if civilian else "legion"
								):
									index = i
						assert(game.choose(index))
					elif node.kind == "beat":
						var beat: Dictionary = game.beats[node.beat]
						var model = Factory.create(beat, game.state.gameplay, int(game.state.bond))
						var result: Dictionary = {}
						if beat.type == "cutscene":
							model.configure({"seed": seed_number, "flags": game.state.flags})
							while not model.waiting_choice():
								model.next_frame()
							assert(model.choose(1 if alternative else 0))
						assert(Factory.solve(model, beat.type) >= 0, "Unfinished " + beat.id)
						if beat.type == "cutscene":
							result = model.result()
							outcomes[result.outcome] = true
						assert(game.complete_beat(result))
						executions += 1
					else:
						assert(game.advance())
				assert(game.current().kind == "ending", "Campaign did not terminate")
	if outcomes.size() != 3:
		push_error("Expected all three cinematic outcomes; found " + str(outcomes.keys()))
		quit(1)
		return
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path + suffix))
	print("ALTERNATIVE BOT PASS: 16 campaigns, ", executions, " encounters, ", outcomes.keys())
	quit(0)
