extends RefCounted
## Shared persistent progression. Narrative bond/reputation remain in StoryRuntime.


static func fresh() -> Dictionary:
	return {
		"xp": 0,
		"level": 1,
		"coins": 24,
		"hero": "pullo",
		"skills": {"strength": 0, "formation": 0, "diplomacy": 0},
		"equipment": {"sword": 0, "shield": 0},
		"supplies": 2,
		"quests": {},
		"encounter": {},
		"rewards": []
	}


static func valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["xp", "level", "coins", "supplies"]:
		if not (data.get(key) is float or data.get(key) is int):
			return false
		if (
			not is_finite(float(data[key]))
			or data[key] != int(data[key])
			or data[key] < 0
			or data[key] > 1000000
		):
			return false
	if data.get("hero") not in ["pullo", "vorenus"]:
		return false
	for key in ["skills", "equipment", "quests", "encounter"]:
		if not data.get(key) is Dictionary:
			return false
	for key in ["strength", "formation", "diplomacy"]:
		if not _rank(data.skills.get(key)):
			return false
	for key in ["sword", "shield"]:
		if not _rank(data.equipment.get(key)):
			return false
	return data.get("rewards") is Array and data.level >= 1


static func _rank(value: Variant) -> bool:
	return (value is float or value is int) and value >= 0 and value <= 3 and value == int(value)


static func reward(data: Dictionary, ident: String, xp: int = 45) -> bool:
	if ident in data.rewards:
		return false
	data.rewards.append(ident)
	data.xp += xp
	data.coins += 8
	data.level = 1 + int(data.xp) / 100
	return true


static func train(data: Dictionary, skill: String) -> bool:
	if not data.skills.has(skill) or data.skills[skill] >= 3:
		return false
	var spent: int = 0
	for rank in data.skills.values():
		spent += int(rank)
	if spent >= int(data.level):
		return false
	data.skills[skill] += 1
	return true


static func buy(data: Dictionary, item: String, discount: int = 0) -> bool:
	if item == "supplies":
		if data.coins < maxi(2, 6 - discount):
			return false
		data.coins -= maxi(2, 6 - discount)
		data.supplies += 1
		return true
	if not data.equipment.has(item) or data.equipment[item] >= 3:
		return false
	var price: int = maxi(4, 12 + int(data.equipment[item]) * 6 - discount)
	if data.coins < price:
		return false
	data.coins -= price
	data.equipment[item] += 1
	return true
