extends Node
## Real multi-process ENet integration. Only host test fixtures position authoritative bodies.
var app: Node
var role := "host"
var label := "Host"
var directory := ""
var players := 2
var checks := 0
var failures := 0
var step := 0
var seen_step := 0
var live := false
var busy := false
var age := 0.0
var health_seen: Dictionary = {}
var deaths_seen: Dictionary = {}
var effects_seen: Dictionary = {}
var reload_seen := false
var feed_seen: Array = []
var session_finished := false
var death_times: Dictionary = {}
var main_client := 0

func option(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="):
			return argument.get_slice("=", 1)
	return fallback

func check(value: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + label + " / " + description)
	if not value:
		failures += 1

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(directory.path_join(path + ".tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(directory.path_join(path + ".tmp"), directory.path_join(path))

func read_json(path: String) -> Variant:
	var file := FileAccess.open(directory.path_join(path), FileAccess.READ)
	if not file:
		return null
	return JSON.parse_string(file.get_as_text())

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func wait_phase(value: String) -> void:
	while Lan.phase != value:
		await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = option("role", "host")
	label = option("label", role)
	directory = option("directory", "/tmp")
	players = int(option("players", "2"))
	Lan.combat_event_received.connect(func(event: Dictionary):
		if event.kind == "shot":
			effects_seen[event.player] = int(effects_seen.get(event.player, 0)) + 1
		elif event.kind == "elimination":
			feed_seen.append(event.text)
			death_times[event.player] = Time.get_ticks_msec())
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	app.open_lan("host" if role == "host" else "join")
	var port := int(option("port", "17780"))
	if option("capture", "False") == "True":
		Settings.set_value("quality", 0)
	if role == "host":
		check(Lan.host_game(label, players, port), "host creates combat lobby")
		write_json("hosting", true)
		while Lan.roster.size() != players or not Lan.can_start():
			await get_tree().process_frame
		check(Lan.start_match(), "host starts ready combat roster")
		await wait_phase("match")
		live = true
		await host_scenario()
	else:
		check(Lan.join_game(label, "127.0.0.1", port), "client starts real ENet connection")
		await wait_phase("lobby")
		Lan.set_ready(true)
		await wait_phase("match")
		live = true
		var slot: int = Lan.roster[Lan.local_id()].slot
		if slot > 1:
			await wait(0.4)
			aim(app.player, PI / 2 if slot == 2 else -PI / 2, 0)
			await tap_local()

func aim(body: FPSPlayer, yaw_value: float, pitch_value: float) -> void:
	body.yaw = yaw_value
	body.target_yaw = yaw_value
	body.pitch = pitch_value
	body.target_pitch = pitch_value
	body.rotation.y = yaw_value
	if body.camera:
		body.camera.rotation.x = pitch_value

func tap_local() -> void:
	Input.action_press("fire")
	for i in range(3):
		await get_tree().physics_frame
	Input.action_release("fire")
	await wait(0.16)

func host_tap(head: bool = false) -> void:
	aim(app.player, 0, 0 if head else -0.10)
	await tap_local()

func client_action(action: String, fields: Dictionary = {}) -> void:
	step += 1
	fields["step"] = step
	fields["action"] = action
	fields["id"] = main_client
	write_json("control.json", fields)
	var elapsed := 0.0
	while not FileAccess.file_exists(directory.path_join("reply-%d-%d" % [step, main_client])):
		await wait(0.02)
		elapsed += 0.02
		if elapsed > 6:
			check(false, "client action timed out: " + action)
			break
	await wait(0.08)

func fixture_positions() -> void:
	var match_node: LANMatch = app.network_match
	for id in match_node.bodies:
		var body: FPSPlayer = match_node.bodies[id]
		var slot: int = Lan.roster[id].slot
		body.position = Vector3(0, 0.05, 8) if id == 1 else Vector3(0, 0.05, 1)
		if slot > 1:
			body.position = Vector3(-17 if slot == 2 else 17, 0.05, 16)
		body.velocity = Vector3.ZERO
		body.last_server_command = []

func capture(name: String) -> void:
	if option("capture", "False") != "True":
		return
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://docs/screenshots/phase3-" + name + ".png")
	check(error == OK, "rendered capture: " + name)

func host_scenario() -> void:
	var authority: CombatAuthority = app.network_match.combat
	for id in Lan.roster:
		if int(Lan.roster[id].slot) == 1:
			main_client = id
	fixture_positions()
	await wait(0.18)
	check(authority.states.size() == players, "host owns one combat record per player")
	check(authority.states[1].magazine == 30 and authority.states[1].reserve == 120, "LAN loadout is 30/120")
	await capture("protection")
	await host_tap()
	check(authority.states[main_client].hp == 100, "initial spawn protection blocks damage")
	check(authority.states[1].magazine == 29 and authority.states[1].protection == 0, "accepted fire consumes ammo and ends shooter protection")
	await wait(2.0)
	await host_tap()
	check(authority.states[main_client].hp == 80, "server ray body hit deals exactly 20 HP")
	await host_tap(true)
	check(authority.states[main_client].hp == 40, "distinct head hitbox deals exactly 40 HP")
	var wall := Geometry.box(app.world, Vector3(0, 1.5, 4), Vector3(2, 3, 0.5), Color.GRAY, true)
	await wait(0.05)
	await host_tap(true)
	check(authority.states[main_client].hp == 40, "wall raycast occlusion prevents damage")
	wall.queue_free()
	await wait(0.05)
	await client_action("tap", {"yaw": PI, "pitch": -0.10})
	check(authority.states[1].hp == 80, "client body shot is validated on host")
	await client_action("tap", {"yaw": PI, "pitch": 0.0})
	check(authority.states[1].hp == 40, "client head shot deals authoritative 40 HP")
	await capture("damaged")
	await client_action("hold", {"yaw": PI, "pitch": -0.10, "seconds": 0.29})
	var death_at: int = death_times.get(1, Time.get_ticks_msec())
	check(not authority.states[1].alive and authority.states[1].hp == 0, "automatic client fire eliminates host at zero HP")
	check(authority.states[main_client].eliminations == 1 and authority.states[1].deaths == 1, "host maintains elimination/death statistics")
	await capture("eliminated")
	var frozen_ammo: int = authority.states[1].magazine
	Lan.send_combat_intent(true, true)
	await wait(0.15)
	check(authority.states[1].magazine == frozen_ammo, "eliminated host cannot fire or reload")
	var before_deaths: int = authority.states[1].deaths
	check(not authority._damage(main_client, 1, 20, "body", Vector3.ZERO), "dead hit guard rejects repeated damage")
	check(authority.states[1].deaths == before_deaths, "duplicate damage cannot repeat elimination stats")
	while not authority.states[1].alive:
		await wait(0.02)
	var elapsed := (Time.get_ticks_msec() - death_at) / 1000.0
	check(elapsed > 2.6 and elapsed < 3.5, "automatic respawn occurs after about three seconds")
	check(authority.states[1].hp == 100 and authority.states[1].magazine == 30 and authority.states[1].reserve == 120, "respawn restores HP and complete loadout")
	check(authority.states[1].life == 2 and authority.states[1].protection > 1.7, "respawn increments life and starts two-second protection")
	var spawn: Vector3 = app.player.position
	check(spawn.distance_to(app.network_match.bodies[main_client].position) > 1.2, "spawn is separated from living operators")
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, spawn + Vector3(0, 0.9, 0))
	query.collision_mask = 1
	check(app.player.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "respawn capsule is not inside arena obstacles")
	fixture_positions()
	await wait(0.15)
	await client_action("tap", {"yaw": PI, "pitch": -0.10})
	check(authority.states[1].hp == 100, "post-respawn protection rejects an incoming live shot")
	await host_tap()
	check(authority.states[1].protection == 0, "protected player firing ends protection early")
	await client_action("tap", {"yaw": PI, "pitch": -0.10})
	check(authority.states[1].hp == 80, "damage resumes immediately after protection ends")
	var shots_before := authority.accepted_shots
	await client_action("touch_combo", {"yaw": PI / 2, "pitch": 0.0})
	check(authority.accepted_shots > shots_before, "simultaneous touch movement/aim/fire reaches authoritative shooting")
	shots_before = authority.accepted_shots
	await client_action("edge", {"yaw": PI / 2, "pitch": 0.0})
	check(authority.accepted_shots == shots_before + 1, "press/release in one host update retains exactly one valid shot")
	shots_before = authority.accepted_shots
	await client_action("invalid_aim")
	check(authority.accepted_shots == shots_before, "non-finite or out-of-range combat aim cannot produce a shot")
	var rejected_before := authority.rejected_requests
	await client_action("flood", {"yaw": PI / 2, "pitch": 0.0})
	check(authority.rejected_requests > rejected_before, "host rejects combat request flooding/duplicates")
	check(authority.accepted_shots - shots_before <= 7, "excess requests cannot bypass 600 RPM server cooldown")
	await wait(1.1)
	await client_action("hold", {"yaw": PI / 2, "pitch": 0.0, "seconds": 3.4})
	check(authority.states[main_client].magazine == 0, "automatic fire drains magazine to zero")
	shots_before = authority.accepted_shots
	await client_action("hold", {"yaw": PI / 2, "pitch": 0.0, "seconds": 0.25})
	check(authority.accepted_shots == shots_before and authority.states[main_client].magazine == 0, "empty magazine cannot fire or become negative")
	await client_action("reload")
	check(authority.states[main_client].reload > 1.5, "touch reload request starts a two-second host timer")
	await capture("remote-reload")
	shots_before = authority.accepted_shots
	await client_action("hold", {"yaw": PI / 2, "pitch": 0.0, "seconds": 0.35})
	check(authority.accepted_shots == shots_before, "host rejects shooting while reloading")
	await wait(1.8)
	check(authority.states[main_client].magazine == 30 and authority.states[main_client].reserve == 90, "reload synchronizes conserved 30/90 loadout")
	fixture_positions()
	await wait(0.15)
	aim(app.player, 0, -0.10)
	Input.action_press("fire")
	await wait(0.29)
	Input.action_release("fire")
	await wait(0.1)
	check(not authority.states[main_client].alive, "host can eliminate a client through server raycasts")
	check(authority.states[1].eliminations == 1 and authority.states[main_client].deaths == 1, "both players' authoritative statistics update")
	await client_action("dead_request")
	while not authority.states[main_client].alive:
		await wait(0.03)
	check(authority.states[main_client].life == 2, "eliminated client respawns into a new life")
	var restored: int = authority.states[main_client].magazine
	await client_action("stale_request")
	check(authority.states[main_client].magazine == restored, "old-life combat and movement requests cannot affect the new life")
	check(app.hud.hit_confirms > 0 and app.hud.damage_events > 0 and app.hud.elimination_events >= 2, "host HUD receives hit, damage and kill-feed confirmations")
	for id in Lan.roster:
		check(int(effects_seen.get(id, 0)) > 0, "firing effects received for operator %d" % id)
	# Exercise self-elimination through the actual fall path; it must not award a kill.
	var old_elims: int = authority.states[1].eliminations
	app.player.position.y = -9
	await wait(0.1)
	check(not authority.states[1].alive and authority.states[1].deaths == 2, "falling triggers a host-owned self-elimination")
	check(authority.states[1].eliminations == old_elims, "self-elimination never awards a kill")
	while not authority.states[1].alive:
		await wait(0.03)
	check(authority.states[1].life == 3 and app.player.combat_alive, "self-eliminated host respawns normally")
	# Host-only ammo fixture exercises the last reserve round without a long five-magazine drain.
	authority.states[1].magazine = 28
	authority.states[1].reserve = 1
	authority.dirty[1] = true
	authority._publish()
	await wait(0.05)
	app.player.rifle.reload()
	await wait(0.15)
	await capture("partial-reload")
	await wait(2.05)
	check(authority.states[1].magazine == 29 and authority.states[1].reserve == 0, "partial reserve reload conserves the last round")
	Lan.send_combat_intent(false, true)
	await wait(0.12)
	check(authority.states[1].reload == 0 and authority.states[1].reserve == 0, "empty reserve cannot start a reload or become negative")
	# Verify all clients receive the same final critical state, not merely host-local changes.
	var expected := {}
	for id in authority.states:
		expected[str(id)] = Lan.combat_states[id].duplicate(true)
	step += 1
	write_json("control.json", {"step": step, "action": "finish", "expected": expected, "feed_count": 3})
	for id in Lan.roster.keys():
		if id == 1:
			continue
		while not FileAccess.file_exists(directory.path_join("done-%d.json" % id)):
			await wait(0.03)
	write_json("Host-done.json", {"checks": checks, "failures": failures, "label": label})
	print("COMBAT PEER RESULT: %s / %d checks / %d failures" % [label, checks, failures])
	Lan.leave()
	get_tree().quit(1 if failures else 0)

func _process(delta: float) -> void:
	age += delta
	if age > 65 and not session_finished:
		check(false, "combat test watchdog")
		get_tree().quit(1)
	if not live or session_finished:
		return
	for id in Lan.combat_states:
		var state: Dictionary = Lan.combat_states[id]
		if int(state.hp) in [80, 40, 0]:
			health_seen[str(id) + ":" + str(state.hp)] = true
		if not state.alive:
			deaths_seen[id] = true
		if state.magazine < 0 or state.reserve < 0 or state.hp < 0:
			check(false, "combat state became negative")
		if id == Lan.local_id() and state.reload > 0:
			reload_seen = true
	if role == "host" or busy:
		return
	var command = read_json("control.json")
	if command == null or int(command.step) <= seen_step:
		return
	seen_step = command.step
	if command.action != "finish" and int(command.id) != Lan.local_id():
		return
	busy = true
	run_client_command(command)

func run_client_command(command: Dictionary) -> void:
	var body: FPSPlayer = app.player
	if command.has("yaw"):
		aim(body, command.yaw, command.pitch)
		await wait(0.08) # Aim reaches host via the existing validated movement stream.
	match command.action:
		"tap": await tap_local()
		"hold":
			Input.action_press("fire")
			await wait(command.seconds)
			Input.action_release("fire")
			await wait(0.1)
		"touch_combo":
			var touch: TouchHUD = app.hud.touch
			touch.layout_controls()
			var start := body.position
			var ammo_before: int = Lan.combat_states[Lan.local_id()].magazine
			var points := [touch.joystick_center + Vector2(0, -50), touch.zones.aim.get_center(), touch.zones.fire.get_center(), Vector2(700, 280)]
			for index in range(4):
				var contact := InputEventScreenTouch.new()
				contact.index = index
				contact.position = points[index]
				contact.pressed = true
				get_viewport().push_input(contact, true)
			await wait(0.35)
			check(touch.contacts.size() == 4 and body.aiming, "four touch contacts independently own movement, aim, fire and look")
			check(body.position.distance_to(start) > 0.3, "touch movement continues while aiming and firing")
			check(Lan.combat_states[Lan.local_id()].magazine < ammo_before, "touch held fire consumes only host-confirmed ammunition")
			for index in range(4):
				var contact := InputEventScreenTouch.new()
				contact.index = index
				contact.position = points[index]
				contact.pressed = false
				get_viewport().push_input(contact, true)
			await wait(0.15)
		"invalid_aim":
			for invalid in [Vector2(NAN, 0), Vector2(0, PI)]:
				Lan.combat_sequence += 1
				Lan._combat_request.rpc_id(1, Lan.epoch, Lan.combat_sequence, body.network_life, true, false, invalid, body.sequence)
			await wait(0.15)
		"edge":
			Lan.send_combat_intent(true, false)
			Lan.send_combat_intent(false, false)
			await wait(0.2)
		"flood":
			for i in range(100):
				Lan.send_combat_intent(true, false)
			for i in range(10):
				Lan._combat_request.rpc_id(1, Lan.epoch, Lan.combat_sequence, app.player.network_life, true, false, Vector2(wrapf(body.yaw, -PI, PI), body.pitch), body.sequence)
			await wait(0.55)
			Lan.send_combat_intent(false, false)
		"reload":
			# Actual touch event passes through the shipped HUD's reload wiring.
			app.hud.touch.layout_controls()
			for down in [true, false]:
				var event := InputEventScreenTouch.new()
				event.index = 7
				event.position = app.hud.touch.zones.reload.get_center()
				event.pressed = down
				get_viewport().push_input(event, true)
			await wait(0.1)
		"dead_request":
			var before: int = Lan.combat_states[Lan.local_id()].magazine
			Lan.send_combat_intent(true, true)
			await wait(0.2)
			check(Lan.combat_states[Lan.local_id()].magazine == before, "dead client cannot alter authoritative ammo")
		"stale_request":
			Lan.combat_sequence += 1
			Lan._combat_request.rpc_id(1, Lan.epoch, Lan.combat_sequence, 1, true, false, Vector2.ZERO, body.sequence)
			Lan._inputs.rpc_id(1, Lan.epoch, [[app.player.sequence + 1, 1.0, 0.0, 0.0, 0.0, false, false, false]], 1)
			await wait(0.15)
		"finish":
			await wait(0.3)
			for id_text in command.expected:
				var id := int(id_text)
				var expected: Dictionary = command.expected[id_text]
				var state: Dictionary = Lan.combat_states.get(id, {})
				check(not state.is_empty() and state.hp == int(expected.hp) and state.life == int(expected.life), "health/life agrees with host for operator %d" % id)
				check(state.magazine == int(expected.magazine) and state.reserve == int(expected.reserve), "ammo agrees with host for operator %d" % id)
				check(state.eliminations == int(expected.eliminations) and state.deaths == int(expected.deaths), "statistics agree with host for operator %d" % id)
				check(int(effects_seen.get(id, 0)) > 0, "shot presentation received for operator %d" % id)
			check(deaths_seen.has(1) and deaths_seen.has(main_shooter_id()), "both eliminations observed through reliable state")
			check(feed_seen.size() == int(command.feed_count) and app.hud.elimination_events == int(command.feed_count), "kill feed contains each elimination exactly once")
			check(app.hud.health_bar.value == app.player.health, "health HUD follows authoritative local state")
			if int(Lan.roster[Lan.local_id()].slot) == 1:
				check(reload_seen and app.hud.hit_confirms > 0 and app.hud.damage_events > 0, "client reload, hitmarker and damage feedback dispatched")
				check(app.player.combat_alive and app.player.network_life == 2, "local client control restored after respawn")
			write_json("done-%d.json" % Lan.local_id(), {"checks": checks, "failures": failures, "label": label})
			print("COMBAT PEER RESULT: %s / %d checks / %d failures" % [label, checks, failures])
			session_finished = true
			# Keep the session alive until the host reads every report and closes it.
			while Lan.active():
				await get_tree().process_frame
			get_tree().quit(1 if failures else 0)
	write_json("reply-%d-%d" % [int(command.step), Lan.local_id()], true)
	busy = false

func main_shooter_id() -> int:
	for id in Lan.roster:
		if int(Lan.roster[id].slot) == 1:
			return id
	return 0
