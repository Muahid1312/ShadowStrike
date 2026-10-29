class_name CombatAuthority
extends Node
## Server-only gameplay state. No client-provided origins, victims, damage or ammo.
const MAGAZINE := 30
const RESERVE := 120
const RELOAD_SECONDS := 2.0
const FIRE_SECONDS := 0.10
const RESPAWN_SECONDS := 3.0
const PROTECTION_SECONDS := 2.0
const EXTRA_SPAWNS := [Vector3(-18, 0.05, 18), Vector3(18, 0.05, 18), Vector3(-18, 0.05, -8), Vector3(18, 0.05, -8), Vector3(0, 0.05, 19), Vector3(-17, 0.05, 5), Vector3(17, 0.05, 5)]
var match_node: LANMatch
var states: Dictionary = {}
var dirty: Dictionary = {}
var started := false
var event_sequence := 0
var periodic := 0.0
var accepted_shots := 0
var rejected_requests := 0
var request_budget: Dictionary = {}
var spawn_cursor := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 20 # Simulate after the authoritative movement bodies.
	Lan.combat_intent.connect(accept_intent)
	Lan.fall_reported.connect(_fall)

func begin() -> void:
	if not Lan.is_host():
		return
	started = true
	for id in match_node.bodies:
		states[id] = {"hp": 100, "alive": true, "magazine": MAGAZINE, "reserve": RESERVE,
			"reload": 0.0, "cooldown": 0.0, "respawn": 0.0, "protection": PROTECTION_SECONDS,
			"life": 1, "eliminations": 0, "deaths": 0, "revision": 0,
			"last_request": 0, "trigger": false, "pending_shot": false, "burst_announced": false, "pending_aim": Vector2.ZERO, "aim": Vector2.ZERO, "aim_sequence": 0, "lease": 0.0, "spawn": Lan.assignments[id]}
		dirty[id] = true
	_publish()

func accept_intent(id: int, sequence: int, life: int, fire: bool, reload_request: bool, aim: Vector2, movement_sequence: int) -> void:
	if not Lan.is_host() or not started or not Rules.can_play() or not states.has(id) or not Lan.roster.has(id):
		return
	var state: Dictionary = states[id]
	if not aim.is_finite() or absf(aim.x) > PI + 0.001 or absf(aim.y) > deg_to_rad(84) + 0.001 or movement_sequence < 0 or movement_sequence > 2147483647:
		rejected_requests += 1
		return
	if sequence < 1 or sequence > 2147483647 or sequence <= int(state.last_request) or life != int(state.life):
		rejected_requests += 1
		return
	var now := Time.get_ticks_msec()
	var budget: Array = request_budget.get(id, [now, 0])
	if now - int(budget[0]) >= 1000:
		budget = [now, 0]
	budget[1] += 1
	request_budget[id] = budget
	if budget[1] > 35:
		rejected_requests += 1
		return
	state.last_request = sequence
	if not state.alive:
		rejected_requests += 1
		return
	state.aim = aim
	state.aim_sequence = movement_sequence
	if fire and not state.trigger and state.reload <= 0:
		state.pending_aim = aim
		state.burst_announced = false
		state.pending_shot = true # Preserve a short press/release pair until the next physics tick.
	state.trigger = fire
	state.lease = 0.30
	if reload_request:
		_reload(id)

func _reload(id: int) -> bool:
	if not Lan.is_host() or not Rules.can_play():
		return false
	var state: Dictionary = states[id]
	if not state.alive or state.reload > 0 or state.magazine >= MAGAZINE or state.reserve <= 0:
		return false
	state.reload = RELOAD_SECONDS
	state.burst_announced = false
	state.pending_shot = false
	dirty[id] = true
	_event("reload", {"player": id, "life": state.life}, true)
	return true

func _physics_process(delta: float) -> void:
	if not Lan.is_host() or not Rules.can_play() or not started:
		return
	for id in states.keys():
		if not Lan.roster.has(id) or not match_node.bodies.has(id):
			states.erase(id)
			dirty.erase(id)
			request_budget.erase(id)
			continue
		var state: Dictionary = states[id]
		state.cooldown = maxf(0, state.cooldown - delta)
		state.lease = maxf(0, state.lease - delta)
		if state.lease <= 0:
			state.trigger = false
			state.pending_shot = false
		if not state.alive:
			state.respawn = maxf(0, state.respawn - delta)
			if state.respawn <= 0:
				_respawn(id)
			continue
		if state.protection > 0:
			state.protection = maxf(0, state.protection - delta)
			if state.protection <= 0:
				dirty[id] = true
		if state.reload > 0:
			state.pending_shot = false
			state.reload = maxf(0, state.reload - delta)
			if state.reload <= 0:
				var count := mini(MAGAZINE - int(state.magazine), int(state.reserve))
				state.magazine += count
				state.reserve -= count
				dirty[id] = true
			continue
		if state.trigger or state.pending_shot:
			var shot_aim: Variant = state.pending_aim if state.pending_shot else null
			state.pending_shot = false
			_fire(id, shot_aim)
	periodic += delta
	if periodic >= 0.2:
		periodic = fmod(periodic, 0.2)
		for id in states:
			if states[id].reload > 0 or states[id].respawn > 0 or states[id].protection > 0:
				dirty[id] = true
	_publish()

func _fire(id: int, aim_override: Variant = null) -> bool:
	if not Lan.is_host() or not Rules.can_play():
		return false
	if not states.has(id) or not match_node.bodies.has(id):
		return false
	var state: Dictionary = states[id]
	if not state.alive or state.reload > 0 or state.cooldown > 0.00001 or state.magazine <= 0:
		return false
	var body: FPSPlayer = match_node.bodies[id]
	if not body.is_inside_tree():
		return false
	state.magazine -= 1
	state.cooldown = FIRE_SECONDS
	state.protection = 0.0 # Only an accepted shot ends protection, not an invalid request.
	dirty[id] = true
	accepted_shots += 1
	var origin := body.global_position + Vector3(0, 1.65, 0)
	# Reliable fire can arrive before its movement-channel aim. Use validated aim
	# from that press for the first shot; otherwise prefer newer simulated input.
	var aim := Vector2(body.rotation.y, body.pitch)
	if aim_override is Vector2:
		aim = aim_override
	elif body.last_processed < int(state.aim_sequence):
		aim = state.aim
	var direction := Basis(Vector3.UP, aim.x) * Basis(Vector3.RIGHT, aim.y) * Vector3.FORWARD
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 150.0, 1 | 4 | 8)
	query.exclude = body.shot_exclusions()
	var result := body.get_world_3d().direct_space_state.intersect_ray(query)
	var point := origin + direction * 150.0
	var damaged := false
	if not result.is_empty():
		point = result.position
		var collider: Object = result.collider
		if collider.has_meta("combat_peer"):
			var target: int = collider.get_meta("combat_peer")
			var zone: String = collider.get_meta("hit_zone")
			if target != id and states.has(target):
				damaged = _damage(id, target, 40 if zone == "head" else 20, zone, origin)
		elif collider.has_method("receive_hit"):
			# Existing practice target flashes on the host, never supplies player damage.
			collider.receive_hit(point)
	# A lone/first shot must not disappear for an observer. Sustained automatic
	# cosmetics remain best effort; all ammunition and damage are always reliable.
	var opening_shot: bool = not state.burst_announced
	state.burst_announced = true
	_event("shot", {"player": id, "life": state.life, "origin": origin, "point": point,
		"impact": not result.is_empty(), "hit": damaged}, opening_shot)
	return true

func _damage(shooter: int, target: int, damage: int, zone: String, origin: Vector3) -> bool:
	if not Lan.is_host() or not Rules.can_play() or not Lan.roster.has(shooter) or not Lan.roster.has(target):
		return false
	if not states.has(target) or not states.has(shooter) or shooter == target:
		return false
	var victim: Dictionary = states[target]
	if not victim.alive or victim.protection > 0 or not states[shooter].alive:
		return false
	victim.hp = maxi(0, int(victim.hp) - damage)
	dirty[target] = true
	_event("damage", {"player": target, "shooter": shooter, "life": victim.life,
		"damage": damage, "zone": zone, "origin": origin}, true)
	if victim.hp == 0:
		_eliminate(shooter, target)
	return true

func _eliminate(shooter: int, target: int) -> void:
	if not Lan.is_host() or not Rules.can_play() or not Lan.roster.has(target):
		return
	if not states.has(target) or not states[target].alive:
		return
	var victim: Dictionary = states[target]
	victim.hp = 0
	victim.alive = false
	victim.trigger = false
	victim.pending_shot = false
	victim.reload = 0.0
	victim.protection = 0.0
	victim.respawn = RESPAWN_SECONDS
	victim.deaths += 1
	if shooter != target and states.has(shooter):
		states[shooter].eliminations += 1
		dirty[shooter] = true
	var body: FPSPlayer = match_node.bodies[target]
	body.set_combat_alive(false)
	Lan.queues[target] = []
	dirty[target] = true
	_publish() # Reliable critical state precedes its elimination notification.
	var killer_name: String = Lan.roster.get(shooter, {}).get("name", "Operator")
	var victim_name: String = Lan.roster.get(target, {}).get("name", "Operator")
	_event("elimination", {"player": target, "shooter": shooter, "life": victim.life,
		"text": "%s eliminated %s" % [killer_name, victim_name] if shooter != target else "%s was eliminated by a fall" % victim_name}, true)

func _fall(id: int) -> void:
	if Lan.is_host() and states.has(id) and states[id].alive:
		_eliminate(id, id)

func choose_spawn(id: int) -> Variant:
	var candidates: Array = Lan.SPAWNS.duplicate()
	candidates.append_array(EXTRA_SPAWNS)
	var best: Variant = null
	var best_distance := -1.0
	for offset in candidates.size():
		var candidate: Vector3 = candidates[(spawn_cursor + offset) % candidates.size()]
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.36
		capsule.height = 1.8
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3(0, 0.9, 0))
		query.collision_mask = 1
		query.margin = 0.01
		var body: FPSPlayer = match_node.bodies[id]
		if not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		var distance := 100.0
		for other in states:
			if other != id and states[other].alive and match_node.bodies.has(other):
				distance = minf(distance, candidate.distance_to(match_node.bodies[other].position))
		if distance > 1.2 and distance > best_distance:
			best = candidate
			best_distance = distance
	spawn_cursor += 1
	return best

func _respawn(id: int) -> void:
	if not Lan.is_host() or not Rules.can_play():
		return
	var spawn = choose_spawn(id)
	if spawn == null:
		states[id].respawn = 0.25 # Wait, never force an occupied/blocked spawn.
		return
	var state: Dictionary = states[id]
	state.life += 1
	state.hp = 100
	state.alive = true
	state.magazine = MAGAZINE
	state.reserve = RESERVE
	state.reload = 0.0
	state.cooldown = 0.0
	state.respawn = 0.0
	state.protection = PROTECTION_SECONDS
	state.trigger = false
	state.pending_shot = false
	state.burst_announced = false
	state.pending_aim = Vector2.ZERO
	state.aim = Vector2.ZERO
	state.aim_sequence = 0
	state.lease = 0.0
	state.spawn = spawn
	Lan.queues[id] = []
	var body: FPSPlayer = match_node.bodies[id]
	body.reset_for_respawn(spawn, state.life)
	dirty[id] = true
	_publish()
	_event("respawn", {"player": id, "life": state.life, "position": spawn}, true)

func _publish() -> void:
	if dirty.is_empty():
		return
	var changes: Dictionary = {}
	for id in dirty:
		if not states.has(id) or not match_node.bodies.has(id):
			continue
		var state: Dictionary = states[id]
		state.revision += 1
		var public_state := {}
		for key in ["hp", "alive", "magazine", "reserve", "reload", "respawn", "protection", "life", "eliminations", "deaths", "revision", "spawn"]:
			public_state[key] = state[key]
		changes[id] = public_state
	dirty.clear()
	Lan.publish_combat(changes)

func _event(kind: String, fields: Dictionary, reliable: bool) -> void:
	event_sequence += 1
	fields["kind"] = kind
	fields["event_id"] = event_sequence
	Lan.publish_combat_event(fields, reliable)
