extends GutTest
const Lore = preload("res://scripts/lore_library.gd")
const Progression = preload("res://scripts/gameplay/progression.gd")


func test_chronicle_search_filters_and_progress_locks() -> void:
	var early: Dictionary = {"progress": {"chapter": 1, "visited": []}}
	var late: Dictionary = {"progress": {"chapter": 8, "visited": []}}
	assert_lt(Lore.entries(early).size(), 60)
	assert_eq(Lore.entries(late).size(), 60)
	assert_eq(Lore.entries(early, "Клеопатра").size(), 0)
	assert_gt(Lore.entries(late, "Клеопатра", "people").size(), 0)
	assert_eq(Lore.entries(late, "Клеопатра", "equipment").size(), 0)
	assert_eq(Lore.entries(late, "небывалый запрос").size(), 0)
	for category in ["people", "events", "places", "equipment"]:
		assert_gt(Lore.entries(late, "", category).size(), 0)


func test_gallery_unlocks_only_seen_scene_or_frame() -> void:
	var state: Dictionary = {
		"progress": {"chapter": 1, "visited": []}, "beats_completed": [], "art_seen": []
	}
	var painting: Dictionary = {
		"file": "assets/cs/cicero_01.png", "beat": "beat_ch01_s03", "chapter": 1
	}
	assert_false(Lore.unlocked(painting, state))
	state.art_seen.append(painting.file)
	assert_true(Lore.unlocked(painting, state))
	painting.file = "assets/cs/cicero_02.png"
	assert_false(Lore.unlocked(painting, state))
	state.beats_completed.append("beat_ch01_s03")
	assert_true(Lore.unlocked(painting, state))
	var scene: Dictionary = {"scene": "ch08_s05", "chapter": 8}
	assert_false(Lore.unlocked(scene, state))
	state.progress.visited.append("ch08_s05")
	assert_true(Lore.unlocked(scene, state))
	assert_gte(Lore.gallery(state).size(), 118)


func test_recap_is_bounded_and_derived_from_flags_without_mutation() -> void:
	var state: Dictionary = {
		"progress": {"chapter": 7, "visited": []},
		"bond": 41,
		"flags":
		{
			"friend_lost": true,
			"route_citizen": true,
			"warned_lucilla": true,
			"warned_serranus": true
		},
		"gameplay": Progression.fresh(),
		"decisions": [],
		"rep": {"citizens": 4}
	}
	var before: Dictionary = state.duplicate(true)
	var recap: Array = Lore.recap(state)
	assert_gte(recap.size(), 3)
	assert_lte(recap.size(), 5)
	assert_true("\n".join(recap).contains("Ворен погиб"))
	assert_true(Lore.fate(state).contains("Горожане: +4"))
	assert_eq(state, before)


func test_comfort_values_are_bounded_and_restore_in_memory() -> void:
	var remembered: Dictionary = GameServices.settings.duplicate(true)
	GameServices.set_preference("text_size", 99, false)
	assert_eq(GameServices.settings.text_size, 2)
	GameServices.set_preference("battery", true, false)
	assert_eq(Engine.max_fps, 30)
	GameServices.set_preference("hints", "false", false)
	assert_eq(GameServices.settings.hints, remembered.hints)
	for key in remembered:
		GameServices.set_preference(key, remembered[key], false)
