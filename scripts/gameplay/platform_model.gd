extends RefCounted

const Snapshot = preload("res://scripts/gameplay/snapshot.gd")
## Fixed-step platform physics, checkpoints, melee, shielding and a following ally.

var state: Dictionary = {}
var config: Dictionary = {}
var progress: Dictionary = {}
var bond: int = 0
var companion: bool = true
var width: float = 960.0
var ground: Array = []
var tokens: Array[float] = [80.0, 350.0, 730.0]


func setup(
	beat: Dictionary, advancement: Dictionary, trust: int, has_companion: bool = true
) -> void:
	config = beat
	progress = advancement
	bond = trust
	companion = has_companion
	var difficulty: int = int(beat.get("difficulty", 1))
	width = 880.0 + difficulty * 32.0
	var variant: int = int(beat.get("variant", 1))
	var first: float = 170.0 + (variant % 3) * 14
	var second: float = 365.0 + (variant % 4) * 12
	var third: float = 600.0 + (variant % 3) * 18
	ground = [
		[0.0, first, 132.0],
		[first + 28 + (variant % 2) * 4, second, 132.0],
		[second + 32 + (variant % 3) * 2, third, 132.0],
		[third + 30 + (variant % 3) * 3, width, 132.0]
	]
	var health: int = 6 + int(progress.equipment.shield) + int(progress.skills.formation)
	health += 1 if progress.hero == "vorenus" else 0
	state = {
		"x": 24.0,
		"y": 132.0,
		"vx": 0.0,
		"vy": 0.0,
		"hp": health,
		"max_hp": health,
		"on_ground": true,
		"facing": 1,
		"attack": 0.0,
		"invincible": 0.0,
		"dodge": 0.0,
		"dodge_cooldown": 0.0,
		"block": false,
		"checkpoint": 24.0,
		"retries": 0,
		"tokens": [],
		"enemies": [],
		"ally_x": 4.0,
		"ally_y": 132.0,
		"ally_cooldown": 0.0,
		"won": false,
		"failed": false,
		"message": "Соберите три отметки и доберитесь до выхода."
	}
	for index in range(3 + difficulty / 3):
		var x: float = [140.0, 310.0, 550.0, 790.0, 980.0, 1080.0][index]
		if x < width - 30:
			state.enemies.append(
				{"x": x, "y": 132.0, "hp": 2 + difficulty / 4, "cooldown": 0.4, "charge": 0.0}
			)


func restore(snapshot: Dictionary) -> bool:
	if not Snapshot.matches(snapshot, state) or snapshot.enemies.size() != state.enemies.size():
		return false
	if (
		snapshot.x < 0
		or snapshot.x > width
		or snapshot.checkpoint < 0
		or snapshot.checkpoint > width
		or absf(snapshot.y) > 1000
		or snapshot.hp < 0
		or snapshot.hp > snapshot.max_hp
	):
		return false
	for token in snapshot.tokens:
		if not (token is float or token is int) or int(token) not in [0, 1, 2]:
			return false
	for enemy in snapshot.enemies:
		if enemy.x < 0 or enemy.x > width or enemy.hp < 0 or enemy.hp > 20:
			return false
	state = snapshot.duplicate(true)
	for key in ["hp", "max_hp", "facing", "retries"]:
		state[key] = int(state[key])
	var collected: Array = []
	for token in state.tokens:
		if int(token) not in collected:
			collected.append(int(token))
	state.tokens = collected
	for enemy in state.enemies:
		enemy.hp = int(enemy.hp)
	return true


func tick(delta: float, axis: float, jump: bool, strike: bool, block: bool, dodge: bool) -> void:
	if state.won:
		return
	var dt: float = clampf(delta, 0.0, 1.0 / 30.0)
	for key in ["attack", "invincible", "dodge", "dodge_cooldown", "ally_cooldown"]:
		state[key] = maxf(0.0, float(state[key]) - dt)
	state.block = block and state.on_ground
	var speed: float = 92.0 if progress.hero == "pullo" else 84.0
	if dodge and state.dodge_cooldown <= 0:
		state.dodge = 0.24
		state.invincible = 0.3
		state.dodge_cooldown = 0.8
	if absf(axis) > 0.1:
		state.facing = 1 if axis > 0 else -1
	state.vx = clampf(axis, -1.0, 1.0) * speed * (0.35 if state.block else 1.0)
	if state.dodge > 0:
		state.vx = state.facing * speed * 1.65
	if jump and state.on_ground:
		state.vy = -168.0 if progress.hero == "pullo" else -160.0
		if companion and bond >= 65 and absf(state.ally_x - state.x) < 30:
			state.vy -= 8.0
			state.message = "Напарник помог подняться."
		state.on_ground = false
	var previous_y: float = state.y
	state.x = clampf(float(state.x) + float(state.vx) * dt, 6.0, width - 6.0)
	state.vy += 400.0 * dt
	state.y += float(state.vy) * dt
	state.on_ground = false
	for platform in ground:
		if (
			state.x >= platform[0]
			and state.x <= platform[1]
			and previous_y <= platform[2]
			and state.y >= platform[2]
			and state.vy >= 0
		):
			state.y = platform[2]
			state.vy = 0.0
			state.on_ground = true
	if strike and state.attack <= 0:
		state.attack = 0.38
		for enemy in state.enemies:
			if enemy.hp > 0 and absf(enemy.x - state.x) < 29 and absf(enemy.y - state.y) < 28:
				if (enemy.x - state.x) * state.facing >= -4:
					enemy.hp = maxi(
						0,
						(
							int(enemy.hp)
							- 2
							- (1 if progress.hero == "pullo" else 0)
							- int(progress.skills.strength)
							- int(progress.equipment.sword)
						)
					)
	_update_enemies(dt)
	_update_companion(dt)
	for index in range(tokens.size()):
		if index not in state.tokens and absf(state.x - tokens[index]) < 18 and state.y > 90:
			state.tokens.append(index)
	if state.on_ground and state.x > float(state.checkpoint) + 210:
		state.checkpoint = state.x
		state.message = "Контрольная точка."
	if state.y > 205 or state.hp <= 0:
		_respawn()
	state.won = state.x >= width - 24 and state.tokens.size() == tokens.size()
	if state.x >= width - 24 and not state.won:
		state.message = "Найдите все три отметки; затем вернитесь к выходу."


func _update_enemies(dt: float) -> void:
	for enemy in state.enemies:
		if enemy.hp <= 0:
			continue
		enemy.cooldown = maxf(0.0, float(enemy.cooldown) - dt)
		if enemy.charge > 0:
			enemy.charge -= dt
			if enemy.charge <= 0 and absf(enemy.x - state.x) < 24 and absf(enemy.y - state.y) < 28:
				_damage(1 + int(config.get("difficulty", 1)) / 6)
				enemy.cooldown = 1.0
		elif enemy.cooldown <= 0 and absf(enemy.x - state.x) < 25 and absf(enemy.y - state.y) < 28:
			enemy.charge = 0.3


func _damage(amount: int) -> void:
	if state.invincible > 0:
		return
	if state.block:
		amount = maxi(
			0,
			amount - 1 - int(progress.skills.formation) - (1 if progress.hero == "vorenus" else 0)
		)
	if companion and bond >= 55 and state.ally_cooldown <= 0 and absf(state.ally_x - state.x) < 30:
		amount = maxi(0, amount - 1)
		state.ally_cooldown = 2.0
	state.hp = maxi(0, int(state.hp) - amount)
	state.invincible = 0.65
	state.message = "Щит принял удар." if amount == 0 else "Удар. Используйте щит или уклонение."


func _update_companion(dt: float) -> void:
	if not companion:
		return
	state.ally_x = move_toward(float(state.ally_x), maxf(6.0, float(state.x) - 22), 110.0 * dt)
	state.ally_y = move_toward(float(state.ally_y), float(state.y), 180.0 * dt)
	if bond >= 55 and state.ally_cooldown <= 0:
		for enemy in state.enemies:
			if enemy.hp > 0 and absf(enemy.x - state.ally_x) < 30:
				enemy.hp = maxi(0, int(enemy.hp) - 1)
				state.ally_cooldown = 1.6
				state.message = "Напарник прикрывает."
				break


func _respawn() -> void:
	state.x = state.checkpoint
	state.y = 132.0
	state.vx = 0.0
	state.vy = 0.0
	state.hp = state.max_hp
	state.on_ground = true
	state.invincible = 1.0
	state.retries += 1
	state.message = "Возвращение к контрольной точке."


func bot_input() -> Dictionary:
	var jump: bool = false
	for index in range(ground.size() - 1):
		var edge: float = ground[index][1]
		if state.x > edge - 19 and state.x < edge and state.on_ground:
			jump = true
	var near_enemy: bool = false
	for enemy in state.enemies:
		if enemy.hp > 0 and enemy.x >= state.x - 5 and enemy.x - state.x < 26:
			near_enemy = true
	return {
		"axis": 0.0 if near_enemy else 1.0,
		"jump": jump,
		"strike": near_enemy,
		"block": false,
		"dodge": false
	}
