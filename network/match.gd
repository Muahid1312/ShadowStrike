class_name LANMatch
extends Node
const PLAYER := preload("res://player/player.tscn")
var bodies: Dictionary = {}
var visuals: Dictionary = {}
var local_player: FPSPlayer
var tick := 0
var snapshot_accumulator := 0.0
var combat: CombatAuthority
var intent_timer := 0.0
var last_fire := false
var applied_lives: Dictionary = {}
var impacts: Array[Node3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Lan.snapshot_received.connect(_on_snapshot)
	Lan.roster_changed.connect(_on_roster)
	Lan.match_live.connect(_on_live)
	Rules.stage_changed.connect(_on_stage)
	Lan.combat_updated.connect(_on_combat)
	Lan.combat_event_received.connect(_on_combat_event)
	combat = CombatAuthority.new()
	combat.match_node = self
	add_child(combat)
	for id in Lan.assignments:
		if Lan.is_host() or id == Lan.local_id():
			var body: FPSPlayer = PLAYER.instantiate()
			body.name = "Player_%d" % id
			body.peer_id = id
			body.set_multiplayer_authority(1)
			body.network_role = "host" if id == Lan.local_id() else "server_remote"
			if not Lan.is_host():
				body.network_role = "client"
			body.position = Lan.assignments[id]
			# Match is a child of arena; bodies share that arena coordinate space.
			get_parent().add_child.call_deferred(body)
			bodies[id] = body
			if id == Lan.local_id():
				local_player = body
		if id != Lan.local_id():
			var avatar := RemoteAvatar.new()
			avatar.name = "Avatar_%d" % id
			avatar.slot = Lan.roster[id].slot
			avatar.player_name = Lan.roster[id].name
			avatar.position = Lan.assignments[id]
			get_parent().add_child.call_deferred(avatar)
			visuals[id] = avatar
	# Readiness is announced by main after deferred children finish entering the tree.

func _on_live() -> void:
	for body in bodies.values():
		body.network_live = true
	if Lan.is_host() and not combat.started:
		combat.begin()

func _on_stage(value: String) -> void:
	if value == "COUNTDOWN" and Lan.is_host() and not combat.started:
		combat.begin()
	if value == "RESULTS":
		for body in bodies.values():
			body.network_live = false
			body.velocity = Vector3.ZERO
			body.pending_state = []
			body.clear_input()
		for avatar in visuals.values():
			avatar.samples.clear()
			avatar.flash_time = 0
			avatar.protection_until = 0
			avatar.reload_pose = 0

func _on_snapshot(_tick: int, frames: Array) -> void:
	if not Rules.can_play():
		return
	for frame in frames:
		if frame.size() != 9 or not Lan.roster.has(frame[0]):
			continue
		var life: int = Lan.combat_states.get(frame[0], {}).get("life", 1)
		if int(frame[8]) != life:
			continue # A pre-respawn snapshot must never undo a reliable respawn.
		if frame[0] == Lan.local_id():
			if local_player.combat_alive:
				local_player.pending_state = frame
		elif visuals.has(frame[0]):
			visuals[frame[0]].push_state(frame)

func _on_roster() -> void:
	for id in bodies.keys():
		if not Lan.roster.has(id):
			bodies[id].queue_free()
			bodies.erase(id)
	for id in visuals.keys():
		if not Lan.roster.has(id):
			visuals[id].queue_free()
			visuals.erase(id)

func _physics_process(delta: float) -> void:
	if Rules.can_play() and is_instance_valid(local_player) and local_player.is_node_ready():
		intent_timer += delta
		var fire: bool = local_player.combat_alive and local_player.input_enabled and local_player.rifle.trigger_held
		var reload_request: bool = local_player.combat_alive and local_player.input_enabled and local_player.rifle.pending_reload
		if intent_timer >= 0.1 or fire != last_fire or reload_request:
			intent_timer = 0
			last_fire = fire
			local_player.rifle.pending_reload = false
			Lan.send_combat_intent(fire, reload_request, Vector2(wrapf(local_player.yaw, -PI, PI), local_player.pitch), local_player.sequence)
	if not Lan.is_host() or not Rules.can_play():
		return
	tick += 1
	for id in visuals:
		if bodies.has(id) and bodies[id].is_inside_tree():
			# Host also interpolates other operators, while their physics remains authoritative.
			visuals[id].push_state(bodies[id].network_state())
	snapshot_accumulator += delta
	if snapshot_accumulator < 1.0 / Lan.INPUT_HZ:
		return
	snapshot_accumulator = fmod(snapshot_accumulator, 1.0 / Lan.INPUT_HZ)
	var states: Array = []
	for id in bodies:
		if bodies[id].is_inside_tree():
			states.append(bodies[id].network_state())
	Lan.broadcast_snapshot(tick, states)

func _on_combat() -> void:
	for id in Lan.combat_states:
		var state: Dictionary = Lan.combat_states[id]
		var changed_life := int(applied_lives.get(id, 1)) != int(state.life)
		applied_lives[id] = state.life
		if bodies.has(id) and bodies[id].is_node_ready():
			var body: FPSPlayer = bodies[id]
			if changed_life:
				body.reset_for_respawn(state.spawn, state.life)
			body.health = state.hp
			if body.combat_alive != state.alive:
				body.set_combat_alive(state.alive)
		if visuals.has(id) and visuals[id].is_node_ready():
			visuals[id].apply_combat(state, changed_life)

func _process(_delta: float) -> void:
	if is_instance_valid(local_player) and is_instance_valid(local_player.rifle):
		var state := Lan.combat_view(Lan.local_id())
		if not state.is_empty():
			local_player.rifle.apply_server_state(state)

func _on_combat_event(event: Dictionary) -> void:
	if Rules.stage != "PLAYING":
		return
	var id: int = event.get("player", 0)
	var state: Dictionary = Lan.combat_states.get(id, {})
	if int(event.get("life", 0)) != int(state.get("life", 1)):
		return
	if event.kind == "shot":
		if id == Lan.local_id() and is_instance_valid(local_player.rifle):
			local_player.rifle.confirmed_shot(event.hit)
		elif visuals.has(id) and visuals[id].is_node_ready():
			visuals[id].show_shot()
		if event.impact:
			impact(event.point, event.hit)
	elif event.kind == "reload":
		if id == Lan.local_id() and is_instance_valid(local_player.rifle):
			local_player.rifle.confirmed_reload()
		elif visuals.has(id):
			visuals[id].show_reload()

func impact(point: Vector3, player_hit: bool) -> void:
	# A bounded pool of short-lived simple geometry, no particle system or dynamic light.
	if impacts.size() >= 12:
		var oldest: Node3D = impacts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	marker.mesh = mesh
	marker.material_override = Geometry.material(Color("efb34e") if player_hit else Color("d9d7ba"))
	get_parent().add_child(marker)
	marker.global_position = point
	impacts.append(marker)
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE * 0.05, 0.18)
	tween.tween_callback(func():
		impacts.erase(marker)
		marker.queue_free())
