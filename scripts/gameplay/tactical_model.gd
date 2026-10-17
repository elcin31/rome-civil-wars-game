extends RefCounted

const Snapshot = preload("res://scripts/gameplay/snapshot.gd")
## Deterministic grid combat. Rendering and touch handling never change these rules.

const WIDTH = 9
const HEIGHT = 5
var state: Dictionary = {}
var config: Dictionary = {}
var bond: int = 0


func setup(beat: Dictionary, progress: Dictionary, trust: int, companion: bool = true) -> void:
	config = beat
	bond = trust if companion else 0
	var difficulty: int = int(beat.get("difficulty", 1))
	state = {
		"units": [],
		"round": 1,
		"selected": 0,
		"won": false,
		"failed": false,
		"message": "Выберите отряд, затем клетку или противника.",
		"cooperation": false
	}
	state.convoy = {"x": 0, "y": 4, "hp": 3}
	var strength: int = int(progress.skills.strength) + int(progress.equipment.sword)
	var defense: int = int(progress.skills.formation) + int(progress.equipment.shield)
	_add_unit(0, "legion", 1, 2, 8 + defense, 3 + strength)
	_add_unit(0, "archer", 1, 3, 5 + defense, 2 + strength)
	_add_unit(0, "cavalry", 1, 1, 7 + defense, 3 + strength)
	_add_unit(1, "legion", 6, 2, 4 + difficulty / 3, 2 + difficulty / 5)
	_add_unit(1, "archer", 7, 1, 3 + difficulty / 3, 1 + difficulty / 5)
	_add_unit(1, "cavalry", 7, 3, 4 + difficulty / 3, 2 + difficulty / 5)
	if difficulty >= 7:
		_add_unit(1, "legion", 6, 4, 4, 2)


func _add_unit(team: int, kind: String, x: int, y: int, health: int, damage: int) -> void:
	state.units.append(
		{
			"team": team,
			"kind": kind,
			"x": x,
			"y": y,
			"hp": health,
			"max_hp": health,
			"damage": damage,
			"ap": 2,
			"morale": 4 if team == 0 and bond >= 60 else 3,
			"guard": false,
			"charge": false
		}
	)


func restore(snapshot: Dictionary) -> bool:
	if not Snapshot.matches(snapshot, state) or snapshot.units.size() != state.units.size():
		return false
	if (
		snapshot.selected < 0
		or snapshot.selected >= snapshot.units.size()
		or snapshot.round < 1
		or snapshot.round > 31
	):
		return false
	for unit in snapshot.units:
		if not _valid_unit(unit):
			return false
	if (
		not inside(Vector2i(snapshot.convoy.x, snapshot.convoy.y))
		or snapshot.convoy.hp < 0
		or snapshot.convoy.hp > 3
	):
		return false
	state = snapshot.duplicate(true)
	for key in ["round", "selected"]:
		state[key] = int(state[key])
	for key in ["x", "y", "hp"]:
		state.convoy[key] = int(state.convoy[key])
	for unit in state.units:
		for key in ["team", "x", "y", "hp", "max_hp", "damage", "ap", "morale"]:
			unit[key] = int(unit[key])
	return true


func _valid_unit(unit: Dictionary) -> bool:
	return (
		inside(_cell(unit))
		and unit.kind in ["legion", "archer", "cavalry"]
		and int(unit.team) in [0, 1]
		and unit.hp >= 0
		and unit.hp <= unit.max_hp
		and unit.max_hp >= 1
		and unit.max_hp <= 100
		and unit.ap >= 0
		and unit.ap <= 2
		and unit.damage >= 1
		and unit.damage <= 30
		and unit.morale >= 0
		and unit.morale <= 5
	)


func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func terrain(cell: Vector2i) -> String:
	var variant: int = int(config.get("variant", 0))
	if cell == Vector2i(4, 2 if variant % 2 == 0 else 0):
		return "wall"
	if cell in [Vector2i(3, 1), Vector2i(5, 3), Vector2i(6, variant % 5)]:
		return "cover"
	if cell.y == (variant + 4) % 5 and cell.x in [3, 4, 5]:
		return "mud"
	return "plain"


func occupant(cell: Vector2i) -> int:
	for index in range(state.units.size()):
		var unit: Dictionary = state.units[index]
		if unit.hp > 0 and _cell(unit) == cell:
			return index
	return -1


func _cell(unit: Dictionary) -> Vector2i:
	return Vector2i(int(unit.x), int(unit.y))


func distance(a: Dictionary, b: Dictionary) -> int:
	return absi(int(a.x) - int(b.x)) + absi(int(a.y) - int(b.y))


func reachable(index: int) -> Dictionary:
	var unit: Dictionary = state.units[index]
	var start: Vector2i = _cell(unit)
	var budget: int = 3 if unit.kind == "cavalry" else 2
	var costs: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if not inside(next) or terrain(next) == "wall" or occupant(next) >= 0:
				continue
			var cost: int = int(costs[cell]) + (2 if terrain(next) == "mud" else 1)
			if cost <= budget and (not costs.has(next) or cost < costs[next]):
				costs[next] = cost
				frontier.append(next)
	return costs


func move_unit(index: int, destination: Vector2i) -> bool:
	if state.won or state.failed or index < 0 or index >= state.units.size():
		return false
	var unit: Dictionary = state.units[index]
	if unit.hp <= 0 or unit.ap <= 0 or occupant(destination) >= 0:
		return false
	var cells: Dictionary = reachable(index)
	if not cells.has(destination):
		return false
	unit.charge = int(cells[destination]) >= 2
	unit.x = destination.x
	unit.y = destination.y
	unit.ap -= 1
	_check_end()
	return true


func attack(index: int, target: int) -> bool:
	if state.won or state.failed or index < 0 or target < 0:
		return false
	if index >= state.units.size() or target >= state.units.size():
		return false
	var unit: Dictionary = state.units[index]
	var enemy: Dictionary = state.units[target]
	var reach: int = 3 if unit.kind == "archer" else 1
	if (
		unit.hp <= 0
		or enemy.hp <= 0
		or unit.ap <= 0
		or unit.team == enemy.team
		or distance(unit, enemy) > reach
	):
		return false
	var damage: int = int(unit.damage) + (1 if unit.kind == "cavalry" and unit.charge else 0)
	damage -= (1 if enemy.guard else 0) + (1 if terrain(_cell(enemy)) == "cover" else 0)
	enemy.hp = maxi(0, int(enemy.hp) - maxi(1, damage))
	unit.ap -= 1
	unit.charge = false
	state.message = "Попадание: %d. Боевой дух: %d." % [maxi(1, damage), int(enemy.morale)]
	if enemy.hp == 0:
		for other in state.units:
			if other.team == enemy.team and other.hp > 0:
				other.morale -= 1
				if other.morale <= 0:
					other.hp = 0
	_check_end()
	return true


func guard(index: int) -> bool:
	if index < 0 or index >= state.units.size() or state.won or state.failed:
		return false
	var unit: Dictionary = state.units[index]
	if unit.team != 0 or unit.hp <= 0 or unit.ap <= 0:
		return false
	unit.guard = true
	unit.ap -= 1
	state.message = "Отряд прикрылся щитами."
	return true


func cooperate() -> bool:
	if bond < 55 or state.cooperation or state.won or state.failed:
		return false
	state.cooperation = true
	for unit in state.units:
		if unit.team == 0 and unit.hp > 0:
			unit.guard = true
			unit.hp = mini(int(unit.max_hp), int(unit.hp) + 1)
	state.message = "Взаимное прикрытие: щиты и помощь раненым."
	return true


func click(cell: Vector2i) -> bool:
	if not inside(cell) or state.won or state.failed:
		return false
	var index: int = occupant(cell)
	if index >= 0 and state.units[index].team == 0:
		state.selected = index
		return true
	if index >= 0:
		return attack(int(state.selected), index)
	return move_unit(int(state.selected), cell)


func end_turn() -> void:
	if state.won or state.failed:
		return
	for index in range(state.units.size()):
		if state.units[index].team == 1:
			state.units[index].ap = 2
			state.units[index].guard = false
			_ai_unit(index)
	state.round += 1
	if config.get("goal") == "escort":
		var next_cell = Vector2i(mini(8, int(state.convoy.x) + 1), int(state.convoy.y))
		var blocking: int = occupant(next_cell)
		if blocking < 0 or state.units[blocking].team == 0:
			state.convoy.x = next_cell.x
		for unit in state.units:
			if (
				unit.team == 1
				and unit.hp > 0
				and (
					(
						absi(int(unit.x) - int(state.convoy.x))
						+ absi(int(unit.y) - int(state.convoy.y))
					)
					<= 1
				)
			):
				state.convoy.hp = maxi(0, int(state.convoy.hp) - 1)
				break
	state.cooperation = false
	for unit in state.units:
		if unit.team == 0:
			unit.ap = 2
			unit.guard = false
	_check_end()


func _ai_unit(index: int) -> void:
	var unit: Dictionary = state.units[index]
	for action in range(2):
		if unit.hp <= 0 or state.won or state.failed:
			return
		var target: int = -1
		var best: int = 10000
		for other in range(state.units.size()):
			var candidate: Dictionary = state.units[other]
			if candidate.team != unit.team and candidate.hp > 0:
				var score: int = distance(unit, candidate) * 10 + int(candidate.hp)
				if score < best:
					best = score
					target = other
		if target < 0 or attack(index, target):
			continue
		var destination: Vector2i = _cell(unit)
		var minimum: int = distance(unit, state.units[target])
		for cell in reachable(index):
			var remaining: int = (
				absi(cell.x - int(state.units[target].x))
				+ absi(cell.y - int(state.units[target].y))
			)
			if remaining < minimum:
				minimum = remaining
				destination = cell
		move_unit(index, destination)
		# Player bot stages its advance rather than spending both actions on a charge.
		if unit.team == 0 and unit.ap == 1:
			var reach: int = 3 if unit.kind == "archer" else 1
			if distance(unit, state.units[target]) > reach:
				guard(index)
				return


func bot_turn() -> void:
	if bond >= 55:
		cooperate()
	for index in range(state.units.size()):
		if state.units[index].team == 0:
			_ai_unit(index)
	end_turn()


func _check_end() -> void:
	var allies: int = 0
	var enemies: int = 0
	for unit in state.units:
		if unit.hp > 0:
			if unit.team == 0:
				allies += 1
			else:
				enemies += 1
	state.failed = allies == 0 or state.round > 30
	state.won = (
		allies > 0 and (enemies == 0 or (config.get("goal", "rout") == "hold" and state.round >= 5))
	)
	if config.get("goal") == "escort":
		state.failed = state.failed or state.convoy.hp <= 0
		state.won = allies > 0 and state.convoy.hp > 0 and state.convoy.x >= 8
