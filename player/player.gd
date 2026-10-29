class_name FPSPlayer
extends CharacterBody3D
signal pause_requested
const RIFLE := preload("res://weapons/rifle.tscn")
var camera: Camera3D
var rifle: Node3D
var hud: TouchHUD
var yaw := 0.0
var pitch := 0.0
var target_yaw := 0.0
var target_pitch := 0.0
var pending_jump := false
var aiming := false
var active := true
var health := 100
var mouse_look := Vector2.ZERO
var walk_time := 0.0
# offline / host / client / server_remote. All physics bodies remain server authority.
var network_role := "offline"
var peer_id := 1
var input_enabled := true
var network_live := false
var sequence := 0
var last_processed := 0
var history: Array = []
var send_accumulator := 0.0
var correction := Vector3.ZERO
var pending_state: Array = []
var running := false
var server_idle_time := 0.0
var last_server_command: Array = []
var combat_alive := true
var network_life := 1
var hitboxes: Array[StaticBody3D] = []

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	if network_role != "offline":
		# Players collide with the arena, not with client-predicted/remote bodies.
		collision_layer = 2
		collision_mask = 1
		if network_role != "client":
			create_hitboxes()
	if network_role == "server_remote":
		return
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.near = 0.05
	camera.fov = 76
	add_child(camera)
	camera.current = true
	rifle = RIFLE.instantiate()
	camera.add_child(rifle)
	rifle.shooter = self
	rifle.camera = camera
	rifle.network_mode = network_role != "offline"
	register_actions()

func register_actions() -> void:
	var actions := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "reload": KEY_R, "pause_game": KEY_ESCAPE}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = actions[action]
			InputMap.action_add_event(action, event)
	for action in {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, event)

func bind_hud(touch: TouchHUD) -> void:
	hud = touch
	hud.jump_requested.connect(func(): pending_jump = true)
	hud.reload_requested.connect(func(): rifle.reload())

func _unhandled_input(event: InputEvent) -> void:
	if not active or not input_enabled or get_tree().paused:
		return
	if network_role != "offline" and not Rules.can_play() and not event.is_action_pressed("pause_game"):
		return
	if event.is_action_pressed("pause_game"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump") and combat_alive:
		pending_jump = true
	elif event.is_action_pressed("reload") and combat_alive:
		rifle.reload()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_look += event.relative

func _physics_process(delta: float) -> void:
	if not active:
		return
	if network_role != "offline" and (not network_live or not Rules.can_play()):
		return
	if not combat_alive:
		if camera:
			camera.position.y = lerpf(camera.position.y, 0.65, 1 - exp(-8 * delta))
			camera.rotation.z = lerpf(camera.rotation.z, -0.14, 1 - exp(-8 * delta))
		return
	if network_role == "server_remote":
		var received := Lan.consume_input(peer_id)
		if not received.is_empty():
			last_server_command = received
			last_processed = received[0]
			server_idle_time = 0
		else:
			server_idle_time += delta
		var command := last_server_command.duplicate()
		if command.is_empty():
			command = [0, 0.0, 0.0, 0.0, 0.0, false, false, false]
		if received.is_empty():
			command[6] = false # Never repeat an edge-triggered jump.
		if server_idle_time > 0.15:
			command[1] = 0.0
			command[2] = 0.0
			command[5] = false
		yaw = command[3]
		pitch = command[4]
		simulate_motion(command, delta)
		return
	if network_role == "client" and not pending_state.is_empty():
		reconcile(pending_state)
		pending_state = []
	aiming = input_enabled and (Input.is_action_pressed("aim") or (hud != null and hud.aiming))
	var look := mouse_look if input_enabled else Vector2.ZERO
	mouse_look = Vector2.ZERO
	if hud:
		var touch_look := hud.take_look()
		if input_enabled:
			look += touch_look
	apply_look(look)
	yaw = lerp_angle(yaw, target_yaw, 1 - exp(-24 * delta))
	pitch = lerpf(pitch, target_pitch, 1 - exp(-24 * delta))
	rotation.y = yaw
	camera.rotation.x = pitch
	camera.fov = lerpf(camera.fov, 51.0 if aiming else 76.0, 1 - exp(-12 * delta))
	var motion := Input.get_vector("left", "right", "forward", "back") if input_enabled else Vector2.ZERO
	if input_enabled and hud and hud.movement.length() > motion.length():
		motion = hud.movement
	var sprint := input_enabled and (Input.is_action_pressed("sprint") or (hud != null and hud.sprinting)) and not aiming
	sequence += 1
	var command := [sequence, motion.x, motion.y, wrapf(yaw, -PI, PI), pitch, sprint, pending_jump and input_enabled, aiming]
	pending_jump = false
	simulate_motion(command, delta)
	last_processed = sequence
	if network_role == "client":
		history.append(command)
		if history.size() > 120:
			history.pop_front() # Bounded prediction history, even if acknowledgements stop.
		send_accumulator += delta
		if send_accumulator >= 1.0 / Lan.INPUT_HZ:
			send_accumulator = fmod(send_accumulator, 1.0 / Lan.INPUT_HZ)
			Lan.send_inputs(history)
	walk_time += delta * Vector2(velocity.x, velocity.z).length() * 1.8
	correction = correction.lerp(Vector3.ZERO, 1 - exp(-14 * delta))
	camera.position = Vector3(0, 1.65 + sin(walk_time) * 0.018 * motion.length(), 0) + global_basis.inverse() * correction
	rifle.aiming = aiming
	# Menu mouse emulation must never turn a joystick/reload/pause tap into fire.
	var desktop_fire := Input.is_action_pressed("fire") and not OS.has_feature("android") and (hud == null or hud.contacts.is_empty())
	rifle.trigger_held = input_enabled and (desktop_fire or (hud != null and hud.firing))

func simulate_motion(command: Array, delta: float) -> void:
	# Shared prediction/server physics. Delta comes from the host's fixed tick, never RPC.
	rotation.y = command[3]
	var motion := Vector2(command[1], command[2]).limit_length()
	running = command[5] and not command[7] and motion.length() > 0.1
	var speed := 7.2 if running else 4.1
	if command[7]:
		speed = 2.7
	var direction := (transform.basis * Vector3(motion.x, 0, motion.y)).normalized()
	velocity.x = move_toward(velocity.x, direction.x * speed * motion.length(), 28 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed * motion.length(), 28 * delta)
	if not is_on_floor():
		velocity.y -= 20 * delta
	if command[6] and is_on_floor():
		velocity.y = 7
	move_and_slide()
	if position.y < -8:
		if network_role == "offline":
			position = Vector3(0, 0.1, 8)
			velocity = Vector3.ZERO
		elif network_role != "client":
			Lan.report_fall(peer_id)

func reconcile(state: Array) -> void:
	var previous := position
	position = state[1]
	velocity = state[2]
	var ack: int = state[7]
	while not history.is_empty() and history[0][0] <= ack:
		history.pop_front()
	# Limit replay to a bounded history. On a long outage, prioritize authoritative state.
	if history.size() <= 24:
		for command in history:
			simulate_motion(command, 1.0 / Engine.physics_ticks_per_second)
	else:
		history.clear()
	var error := previous - position
	correction = (correction + error).limit_length(1.0) if error.length() < 2 else Vector3.ZERO
	rotation.y = yaw

func network_state() -> Array:
	return [peer_id, position, velocity, wrapf(rotation.y, -PI, PI), pitch, running, is_on_floor(), last_processed, network_life]

func apply_look(motion: Vector2) -> void:
	var sensitivity: float = Settings.values.sensitivity * 0.0026
	if aiming:
		sensitivity *= Settings.values.aim_sensitivity
	target_yaw -= motion.x * sensitivity
	var invert := -1.0 if Settings.values.invert_look else 1.0
	target_pitch = clampf(target_pitch - motion.y * sensitivity * invert, deg_to_rad(-84), deg_to_rad(84))

func recoil(amount: float) -> void:
	target_pitch = clampf(target_pitch - amount, deg_to_rad(-84), deg_to_rad(84))

func clear_input() -> void:
	mouse_look = Vector2.ZERO
	pending_jump = false
	if is_instance_valid(rifle):
		rifle.trigger_held = false
		rifle.pending_reload = false
	if hud:
		hud.reset()

func create_hitboxes() -> void:
	for zone in ["body", "head"]:
		var hitbox := StaticBody3D.new()
		hitbox.collision_layer = 4 if zone == "body" else 8
		hitbox.collision_mask = 0
		hitbox.set_meta("combat_peer", peer_id)
		hitbox.set_meta("hit_zone", zone)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 1.46, 0.38) if zone == "body" else Vector3(0.38, 0.42, 0.38)
		collision.shape = shape
		hitbox.position.y = 0.75 if zone == "body" else 1.7
		hitbox.add_child(collision)
		add_child(hitbox)
		hitboxes.append(hitbox)

func shot_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = [get_rid()]
	for hitbox in hitboxes:
		exclusions.append(hitbox.get_rid())
	return exclusions

func set_combat_alive(value: bool) -> void:
	combat_alive = value
	if network_role != "offline":
		collision_layer = 2 if value else 0
	for i in hitboxes.size():
		hitboxes[i].collision_layer = (4 if i == 0 else 8) if value else 0
	if not value:
		velocity = Vector3.ZERO
		last_server_command = []
		pending_state = []
		history.clear()
		clear_input()
	if is_instance_valid(rifle):
		rifle.visible = value
		rifle.network_alive = value

func reset_for_respawn(spawn: Vector3, life: int) -> void:
	network_life = life
	position = spawn
	velocity = Vector3.ZERO
	pending_state = []
	history.clear()
	last_server_command = []
	server_idle_time = 0
	correction = Vector3.ZERO
	yaw = 0
	pitch = 0
	target_yaw = 0
	target_pitch = 0
	rotation = Vector3.ZERO
	if camera:
		camera.rotation = Vector3.ZERO
		camera.position = Vector3(0, 1.65, 0)
	clear_input()
	set_combat_alive(true)
