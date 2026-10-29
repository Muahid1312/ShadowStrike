extends Node
## A real process using production screens, ENet, movement and remote models.
var app: Node
var role := "host"
var label := ""
var test_dir := ""
var udp_port := 17777
var total := 2
var live_time := 0.0
var age := 0.0
var ready_time := 0.0
var stage := "lobby"
var failed := false
var checks := 0
var unready_checked := false
var invalid_sent := false
var initial_local := Vector3.ZERO
var initial_visuals: Dictionary = {}
var moved_remotes: Dictionary = {}
var movement_checked := false
var pause_checked := false
var paused_position := Vector3.ZERO
var left_checked := false
var actor_ready := false
var previous_visuals: Dictionary = {}
var smooth_steps: Dictionary = {}
var saw_jump: Dictionary = {}
var max_visual_step := 0.0
var disconnect_victim := 0
var dead_fixture_started := false
var no_respawn_checked := false

func option(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="):
			return argument.get_slice("=", 1)
	return fallback

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + label + " / " + description)
	if not condition:
		failed = true

func report(event: String) -> void:
	var file := FileAccess.open(test_dir.path_join(label + "-" + event + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failed": failed, "roster": Lan.roster.size(), "snapshots": Lan.received_snapshots, "batches": Lan.sent_batches}))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = option("role", "host")
	label = option("label", role)
	test_dir = option("test-dir", "/tmp")
	udp_port = int(option("port", "17777"))
	total = int(option("players", "2"))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	app.open_lan("host" if role == "host" else "join")
	await get_tree().process_frame
	var panel: LANPanel = app.lan_panel
	panel.name_field.text = label
	panel.port_field.text = str(udp_port)
	if role == "host":
		panel.limit_field.selected = total - 2
	else:
		panel.address_field.text = "127.0.0.1"
	panel.action_button.pressed.emit()
	if role == "host":
		check(Lan.is_host() and Lan.roster.size() == 1, "host creates lobby and registers itself")
		check(not Lan.start_match(), "one-player match cannot start")
		report("hosting")
	else:
		check(not Lan.join_game("Duplicate", "127.0.0.1", udp_port), "duplicate session creation is rejected")

func _process(delta: float) -> void:
	age += delta
	if age > 38:
		check(false, "test watchdog expired in " + stage + " / " + Lan.phase)
		finish()
		return
	if not is_instance_valid(app):
		return
	if stage == "lobby" and Lan.phase == "lobby":
		if role == "host":
			if Lan.roster.size() >= 2 and not unready_checked:
				unready_checked = true
				check(not Lan.can_start() and not Lan.start_match(), "host refuses unready roster")
			if Lan.roster.size() == total and Lan.can_start():
				check(app.lan_panel.players_box.get_child_count() == total, "real lobby UI lists every connected operator")
				app.lan_panel.start_button.pressed.emit()
				check(not Lan.start_match(), "duplicate match start is rejected")
		else:
			ready_time += delta
			if ready_time > 0.6 and not actor_ready:
				actor_ready = true
				check(Lan.roster.has(1) and Lan.roster.has(Lan.local_id()), "client receives host and own roster entry")
				check(not Lan.start_match(), "client cannot start match")
				app.lan_panel.ready_button.pressed.emit()
	if stage == "lobby" and Lan.phase == "match" and is_instance_valid(app.player):
		stage = "live"
		var local: FPSPlayer = app.player
		initial_local = local.position
		check(app.mode == "match" and local.network_live, "load barrier activates the shared arena")
		check(app.network_match.visuals.size() == total - 1, "one remote model per other peer, no duplicates")
		var distinct: Dictionary = {}
		for spawn in Lan.assignments.values():
			distinct[spawn] = true
		check(distinct.size() == total, "host assigns distinct spawn locations")
		check(local.camera.current and local.rifle != null, "local player retains first-person camera and rifle")
		for id in app.network_match.visuals:
			var avatar: Node3D = app.network_match.visuals[id]
			initial_visuals[id] = avatar.position
			check(avatar.find_children("*", "Camera3D", true, false).is_empty(), "remote avatar has no camera")
		if role == "host":
			for id in app.network_match.bodies:
				if id != 1:
					check(app.network_match.bodies[id].camera == null and app.network_match.bodies[id].rifle == null, "server ghost has no first-person systems")
		Input.action_press("forward" if role == "host" else ("right" if int(Lan.roster[Lan.local_id()].slot) % 2 else "left"))
		report("live")
	if stage != "live":
		return
	if Lan.phase == "idle":
		check(app.mode == "menu" and not Lan.active(), "host departure returns client to clean menu")
		finish()
		return
	live_time += delta
	var local: FPSPlayer = app.player
	if live_time > 0.8 and not invalid_sent:
		invalid_sent = true
		if role != "host":
			local.pending_jump = true
			local.mouse_look = Vector2(25, -12)
			# Actual RPCs exercise server-side validation; normal movement continues afterward.
			Lan._inputs.rpc_id(1, Lan.epoch, [[999, 99.0, 0.0, 0.0, 0.0, false, false, false]], app.player.network_life)
			Lan._inputs.rpc_id(1, Lan.epoch, [[1000, NAN, 0.0, 0.0, 0.0, false, false, false]], app.player.network_life)
			Lan._inputs.rpc_id(1, Lan.epoch, [[1001, 0.0, 0.0, 0.0, 0.0, false, false, false, Vector3(999, 0, 0)]], app.player.network_life)
			Lan.set_ready(false) # Ignored outside lobby; cannot mutate match phase.
		else:
			app.pause_game()
			paused_position = local.position
			check(not get_tree().paused and not local.input_enabled, "host pause menu keeps LAN simulation alive")
	if role == "host" and live_time > 1.35 and not pause_checked:
		pause_checked = true
		check(app.mode == "pause" and app.network_match.tick > 20, "host keeps advancing match while its menu is open")
		app.resume_game()
		local.pending_jump = true
		local.mouse_look = Vector2(25, -12)
		check(app.mode == "match" and local.input_enabled, "host resumes local control")
	if live_time > 1.5:
		Input.action_press("sprint")
	for id in app.network_match.visuals:
		var avatar: Node3D = app.network_match.visuals[id]
		if initial_visuals.has(id) and avatar.position.distance_to(initial_visuals[id]) > 0.4:
			moved_remotes[id] = true
		if previous_visuals.has(id):
			var step := avatar.position.distance_to(previous_visuals[id])
			max_visual_step = maxf(max_visual_step, step)
			if step > 0.001 and step < 0.5:
				smooth_steps[id] = int(smooth_steps.get(id, 0)) + 1
		previous_visuals[id] = avatar.position
		if avatar.position.y > 0.4:
			saw_jump[id] = true
	if live_time > 2.8 and not movement_checked:
		movement_checked = true
		check(local.position.distance_to(initial_local) > 0.7, "own operator moves independently through controller input")
		check(moved_remotes.size() == total - 1, "every other operator visibly moves through replicated transforms")
		var smooth := max_visual_step < 1.0
		var pitch_updated := true
		for id in app.network_match.visuals:
			smooth = smooth and int(smooth_steps.get(id, 0)) > 8
			pitch_updated = pitch_updated and absf(app.network_match.visuals[id].head.rotation.x) > 0.005
		check(smooth, "remote interpolation produces intermediate motion without large position steps")
		check(saw_jump.size() == total - 1, "authoritative jumping replicates to every observer")
		check(pitch_updated, "remote head look pitch is synchronized")
		if role == "host":
			check(Lan.rejected_inputs >= (total - 1) * 3, "host rejects oversized axes, NaN and injected position fields")
		else:
			check(Lan.received_snapshots >= 20 and Lan.sent_batches >= 20, "real ENet snapshots and input batches flow")
			check(local.history.size() <= 24, "server acknowledgements keep prediction replay bounded")
		report("movement")
	if total == 4 and role == "host" and live_time > 3.0 and not dead_fixture_started:
		dead_fixture_started = true
		for id in Lan.roster:
			if int(Lan.roster[id].slot) == 3:
				disconnect_victim = id
				app.network_match.bodies[id].position.y = -9 # Host-only fall fixture.
	if total == 4 and role != "host" and int(Lan.roster[Lan.local_id()].slot) == 3 and live_time > 3.2:
		check(not local.combat_alive and Lan.combat_states[Lan.local_id()].hp == 0, "client disconnect fixture is eliminated before leaving")
		Input.action_release("left")
		Input.action_release("right")
		Input.action_release("sprint")
		Lan.leave()
		check(app.mode == "menu" and Lan.roster.is_empty() and Lan.peer == null, "client leave cleans up peer and returns to menu")
		check(Lan.host_game("Reuse", 2, udp_port + 1), "departed client can start a fresh session")
		Lan.leave()
		finish()
		return
	if total == 4 and live_time > 4.1 and not left_checked:
		left_checked = true
		check(Lan.roster.size() == 3 and app.network_match.visuals.size() == 2, "disconnect despawns exactly one remote and updates roster")
		check(Lan.combat_states.size() == 3, "disconnect also removes replicated combat state")
		if role == "host":
			check(app.network_match.bodies.size() == 3, "host removes disconnected authoritative body")
	if total == 4 and role == "host" and live_time > 6.2 and not no_respawn_checked:
		no_respawn_checked = true
		check(not app.network_match.combat.states.has(disconnect_victim) and not app.network_match.bodies.has(disconnect_victim), "disconnected eliminated player never respawns after its timer")
	if role == "host" and live_time > (6.5 if total == 4 else 5.0):
		check(Lan.roster.size() <= 4, "capacity stays within four operators")
		Lan.leave()
		check(app.mode == "menu" and Lan.peer == null, "host shutdown cleans up ENet and match")
		finish()

func finish() -> void:
	if stage == "done":
		return
	stage = "done"
	report("done")
	if Lan.active():
		Lan.leave()
	Input.action_release("forward")
	Input.action_release("right")
	Input.action_release("left")
	Input.action_release("sprint")
	print("LAN PEER RESULT: %s / %d checks / failed=%s" % [label, checks, failed])
	get_tree().quit(1 if failed else 0)
