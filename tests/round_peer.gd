extends Node
## Independent ENet peers exercise actual countdown, scoring, results and rematches.
var app: Node
var label := "Host"
var role := "host"
var directory := ""
var total := 2
var checks := 0
var failures := 0
var age := 0.0
var started := false
var busy := false
var step := 0
var seen_step := 0
var round_number := 0
var last_stage := "LOBBY"
var digits: Dictionary = {}
var result_history: Array = []
var countdown_start := 0
var playing_start := 0
var finished := false
var last_elimination: Dictionary = {}
var target_id := 0
var connected_count := 2
var lobby_since := -1

func option(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="):
			return argument.get_slice("=", 1)
	return fallback

func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + label + " / " + message)
	if not value:
		failures += 1

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func write_json(name: String, value: Variant) -> void:
	var path := directory.path_join(name)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func read_json(name: String) -> Variant:
	var file := FileAccess.open(directory.path_join(name), FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) if file else null

func await_stage(value: String) -> void:
	while Rules.stage != value:
		await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = option("role", "host")
	label = option("label", role)
	directory = option("directory", "/tmp")
	total = int(option("players", "2"))
	connected_count = total
	Rules.stage_changed.connect(on_stage)
	Lan.combat_event_received.connect(func(event: Dictionary):
		if event.kind == "elimination":
			last_elimination = event.duplicate(true))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	if option("capture", "False") == "True":
		Settings.set_value("quality", 0)
	app.open_lan("host" if role == "host" else "join")
	var panel: LANPanel = app.lan_panel
	panel.name_field.text = label
	panel.port_field.text = option("port", "17781")
	if role == "host":
		panel.limit_field.selected = total - 2
		check(panel.duration_field.get_selected_id() == 300 and panel.kill_field.value == 0, "host UI defaults to five minutes with kill limit off")
		await capture("host")
		panel.action_button.pressed.emit()
		check(Lan.is_host(), "host creates FFA lobby")
		check(Rules.configure_rules(8, 0), "short automated duration is host-configurable")
		write_json("hosting", true)
		while Lan.roster.size() != total or not Lan.can_start():
			await get_tree().process_frame
		started = true
		await host_scenario()
	else:
		panel.address_field.text = "127.0.0.1"
		panel.action_button.pressed.emit()
		started = true

func on_stage(value: String) -> void:
	if value == "COUNTDOWN":
		digits.clear()
		countdown_start = Time.get_ticks_msec()
		if role != "host":
			check(not Rules.begin_countdown() and not Rules.configure_rules(5, 1), "client cannot start countdown or configure host rules")
	elif value == "PLAYING":
		round_number += 1
		playing_start = Time.get_ticks_msec()
		check(digits.has(3) and digits.has(2) and digits.has(1), "3/2/1 countdown observed before play")
		check(Time.get_ticks_msec() - countdown_start >= 2800, "play waits for host's three-second countdown")
	elif value == "RESULTS":
		result_history.append(Rules.final_results.duplicate(true))
	last_stage = value

func _process(delta: float) -> void:
	age += delta
	if age > 80 and not finished:
		check(false, "round acceptance watchdog")
		get_tree().quit(1)
	if not started or finished:
		return
	if Rules.stage == "COUNTDOWN":
		digits[maxi(1, ceili(Rules.countdown_left()))] = true
	if Lan.phase != "lobby":
		lobby_since = -1
	if role != "host" and Lan.phase == "lobby" and not busy:
		if lobby_since < 0:
			lobby_since = Time.get_ticks_msec()
		if Time.get_ticks_msec() - lobby_since > 300 and Lan.roster.has(Lan.local_id()) and not Lan.roster[Lan.local_id()].ready:
			app.lan_panel.ready_button.pressed.emit()
	if role == "host" or busy:
		return
	var command = read_json("control.json")
	if command == null or int(command.step) <= seen_step:
		return
	seen_step = int(command.step)
	busy = true
	client_command(command)

func command(action: String, fields: Dictionary = {}) -> void:
	step += 1
	fields["step"] = step
	fields["action"] = action
	if fields.has("expected"):
		# Test coordination must preserve Variant integer/float types, as ENet does.
		fields["expected_binary"] = Marshalls.raw_to_base64(var_to_bytes(fields.expected))
	var ids := Lan.roster.keys()
	write_json("control.json", fields)
	for id in ids:
		if id == 1:
			continue
		var elapsed := 0.0
		while not FileAccess.file_exists(directory.path_join("reply-%d-%d" % [step, id])):
			await wait(0.02)
			elapsed += 0.02
			if elapsed > 8:
				check(false, "client command timed out: " + action)
				break

func capture(name: String) -> void:
	if option("capture", "False") != "True":
		return
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://docs/screenshots/phase4-" + name + ".png")
	check(result == OK, "rendered capture " + name)

func assert_frozen() -> void:
	var original: Vector3 = app.player.position
	var shots: int = app.network_match.combat.accepted_shots
	Input.action_press("forward")
	Input.action_press("fire")
	Lan.send_combat_intent(true, false, Vector2.ZERO, app.player.sequence)
	await wait(0.25)
	Input.action_release("forward")
	Input.action_release("fire")
	check(app.player.position == original and app.network_match.combat.accepted_shots == shots, "movement/fire blocked outside PLAYING")

func position_fixture() -> void:
	for id in app.network_match.bodies:
		var body: FPSPlayer = app.network_match.bodies[id]
		var slot: int = Lan.roster[id].slot
		body.position = Vector3(0, 0.05, 8) if id == 1 else Vector3(0, 0.05, 1)
		if slot > 1:
			body.position = Vector3(-17 if slot == 2 else 17, 0.05, 16)
		body.velocity = Vector3.ZERO
		body.last_server_command = []
		if slot == 1:
			target_id = id
	app.player.yaw = 0
	app.player.target_yaw = 0
	app.player.pitch = -0.10
	app.player.target_pitch = -0.10

func eliminate_target() -> void:
	position_fixture()
	Input.action_press("fire")
	await wait(0.56)
	Input.action_release("fire")
	await wait(0.1)

func host_scenario() -> void:
	var names := {}
	for id in Lan.roster:
		names[id] = Lan.roster[id].name
	check(Lan.start_match(), "host starts ready FFA roster")
	await await_stage("COUNTDOWN")
	check(not Lan.start_match() and not Rules.begin_countdown(), "duplicate starts/countdowns rejected")
	await assert_frozen()
	await command("countdown_guard")
	await capture("countdown")
	await await_stage("PLAYING")
	await wait(0.12)
	check(Rules.duration == 8 and Rules.seconds_left() <= 8, "short host timer begins at PLAYING")
	await command("clock", {"seconds": Rules.seconds_left()})
	position_fixture()
	await wait(2.1)
	await eliminate_target()
	check(Rules.board[0].id == 1 and Rules.board[0].score == 100, "real elimination awards exactly 100 points and rank one")
	var victim: Dictionary = {}
	for row in Rules.board:
		if int(row.id) == target_id:
			victim = row
	check(victim.deaths == 1 and victim.score == 0, "death increments once and awards zero points")
	var board_before := Rules.board.duplicate(true)
	app.network_match.combat._eliminate(1, target_id)
	if not last_elimination.is_empty():
		Lan.publish_combat_event(last_elimination, true)
	await wait(0.1)
	check(Rules.board == board_before, "duplicate elimination/notification cannot add score")
	app.open_scoreboard()
	await wait(0.1)
	var builds: int = app.scoreboard.table.build_count
	await wait(0.25)
	check(app.scoreboard.table.build_count == builds, "scoreboard is event-driven, not rebuilt each frame")
	await capture("scoreboard")
	app.close_scoreboard()
	app.pause_game()
	var remaining_before := Rules.seconds_left()
	await wait(0.4)
	check(not get_tree().paused and Rules.seconds_left() < remaining_before - 0.3, "personal pause keeps authoritative match time running")
	app.resume_game()
	await capture("playing")
	await await_stage("RESULTS")
	await wait(0.1)
	check(Rules.final_results.reason == "Time expired", "timer reaching zero ends the match")
	check(absf((Time.get_ticks_msec() - playing_start) / 1000.0 - 8.0) < 0.8, "configured short round lasts the host's configured duration")
	check(Rules.final_results.winner_id == 1 and app.results_screen.heading.text == "VICTORY", "host winner and victory presentation agree")
	check(app.results_screen.return_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "results controls fit landscape viewport")
	var frozen_results := Rules.final_results.duplicate(true)
	await assert_frozen()
	await command("results", {"expected": frozen_results})
	await capture("results")
	check(not Rules.finish("duplicate"), "duplicate results transition rejected")
	check(Rules.final_results == frozen_results, "results remain immutable after attempted actions")
	if total == 4:
		var leaving := 0
		for id in Lan.roster:
			if int(Lan.roster[id].slot) == 3:
				leaving = id
		await command("leave_results", {"id": leaving})
		await wait(0.2)
		connected_count -= 1
		check(Lan.roster.size() == connected_count and Rules.final_results == frozen_results, "results stay frozen when an operator disconnects")
		check(Rules.final_results.rows.size() == 4, "completed rankings retain the departed participant")
		await command("results_stable", {"expected": frozen_results})
	# Preserve transport and identities while tearing down the old match.
	app.results_screen.return_button.pressed.emit()
	await wait(0.15)
	check(Lan.phase == "lobby" and Rules.stage == "LOBBY" and Lan.roster.size() == connected_count, "host rematch returns the existing session to lobby")
	for id in Lan.roster:
		check(names.has(id) and Lan.roster[id].name == names[id], "rematch preserves operator identity/name")
	check(app.world.find_children("*", "CharacterBody3D", true, false).is_empty(), "lobby contains no stale player bodies")
	check(Lan.combat_states.is_empty() and Rules.board.is_empty() and Rules.final_results.is_empty(), "lobby resets combat/stat/result data")
	var unready := true
	for id in Lan.roster:
		if id != 1:
			unready = unready and not Lan.roster[id].ready
	check(unready, "rematch resets clients to Not Ready")
	await capture("rematch-lobby")
	check(Rules.configure_rules(6, 1), "host configures optional kill limit for rematch")
	while not Lan.can_start():
		await get_tree().process_frame
	var old_epoch: int = Lan.epoch
	check(Lan.start_match(), "host starts a new ready round")
	await await_stage("PLAYING")
	check(Lan.epoch != old_epoch and app.network_match.bodies.size() == connected_count, "rematch has a fresh epoch and no duplicated bodies")
	for state in Lan.combat_states.values():
		check(state.hp == 100 and state.magazine == 30 and state.reserve == 120 and state.eliminations == 0 and state.deaths == 0 and state.life == 1 and state.reload == 0 and state.respawn == 0, "rematch resets full loadout/health/stats/respawn state")
	position_fixture()
	await wait(2.1)
	await eliminate_target()
	await await_stage("RESULTS")
	check(Rules.final_results.reason == "Kill limit reached" and Rules.remaining > 1, "kill limit ends rematch before time expires")
	check(Rules.final_results.rows[0].score == 100 and Rules.final_results.rows[0].eliminations == 1, "new round scoring does not accumulate old-round kills")
	await command("results", {"expected": Rules.final_results})
	# A third start loses its required peers in COUNTDOWN; it must cancel safely.
	check(Rules.return_to_lobby(), "host alone can reopen results lobby")
	while not Lan.can_start():
		await get_tree().process_frame
	Lan.start_match()
	await await_stage("COUNTDOWN")
	await command("leave_countdown")
	await wait(0.2)
	check(Lan.phase == "lobby" and Rules.stage == "LOBBY" and Lan.roster.size() == 1, "countdown cancels to lobby when fewer than two remain")
	check(not Lan.start_match() and not Rules.can_play(), "cancelled one-player lobby cannot start gameplay")
	check(app.world.find_children("*", "CharacterBody3D", true, false).is_empty(), "cancelled countdown tears down loaded player scenes")
	finish()

func client_command(data: Dictionary) -> void:
	match data.action:
		"countdown_guard":
			check(Rules.stage == "COUNTDOWN" and not Rules.can_play(), "client receives frozen countdown state")
			var original: Vector3 = app.player.position
			var ammo: int = Lan.combat_states[Lan.local_id()].magazine
			Input.action_press("forward")
			Input.action_press("fire")
			Lan.combat_sequence += 1
			Lan._combat_request.rpc_id(1, Lan.epoch, Lan.combat_sequence, app.player.network_life, true, false, Vector2.ZERO, app.player.sequence)
			await wait(0.25)
			Input.action_release("forward")
			Input.action_release("fire")
			check(app.player.position == original and Lan.combat_states[Lan.local_id()].magazine == ammo, "client input and raw fire RPC cannot bypass countdown")
		"clock":
			check(absf(Rules.seconds_left() - float(data.seconds)) < 0.7, "client timer follows host without wall-clock synchronization")
		"results":
			await wait(0.15)
			check(Rules.stage == "RESULTS" and app.mode == "results", "client receives results screen")
			check(Rules.final_results == bytes_to_var(Marshalls.base64_to_raw(data.expected_binary)), "every peer receives identical authoritative rankings/results")
			check(app.results_screen.heading.text == "MATCH COMPLETE", "non-winner receives match-complete presentation")
			check(not app.results_screen.local_label.text.is_empty(), "results display local player's real statistics")
			check(app.results_screen.return_button.disabled and not Rules.return_to_lobby() and not Rules.finish("forged"), "clients cannot force rematch or results transitions")
			var stats := Rules.final_results.duplicate(true)
			var ammo: int = Lan.combat_states[Lan.local_id()].magazine
			var position_before: Vector3 = app.player.position
			Input.action_press("forward")
			Lan.combat_sequence += 1
			Lan._combat_request.rpc_id(1, Lan.epoch, Lan.combat_sequence, app.player.network_life, true, true, Vector2.ZERO, app.player.sequence)
			await wait(0.25)
			Input.action_release("forward")
			check(Rules.final_results == stats and Lan.combat_states[Lan.local_id()].magazine == ammo and app.player.position == position_before, "results freeze statistics, ammo and movement against late inputs")
			check(app.results_screen.return_button.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "client results navigation fits landscape")
		"leave_results":
			if int(data.id) == Lan.local_id():
				check(Rules.stage == "RESULTS", "participant can leave from results")
				write_json("reply-%d-%d" % [int(data.step), Lan.local_id()], true)
				finish()
				return
		"results_stable":
			check(Rules.final_results == bytes_to_var(Marshalls.base64_to_raw(data.expected_binary)), "peer departure cannot change completed results on clients")
		"leave_countdown":
			check(Rules.stage == "COUNTDOWN" and result_history.size() == 2, "client completed two rounds before cancellation scenario")
			write_json("reply-%d-%d" % [int(data.step), Lan.local_id()], true)
			finish()
			return
	write_json("reply-%d-%d" % [int(data.step), Lan.local_id()], true)
	busy = false

func finish() -> void:
	if finished:
		return
	finished = true
	var id := Lan.local_id()
	write_json("done-" + label + ".json", {"checks": checks, "failures": failures, "label": label})
	Lan.leave()
	if role != "host":
		check(app.mode == "menu" and not Lan.active(), "leave cleans up peer and returns to main menu")
		write_json("done-" + label + ".json", {"checks": checks, "failures": failures, "label": label})
	print("ROUND PEER RESULT: %s / %d checks / %d failures" % [label, checks, failures])
	get_tree().quit(1 if failures else 0)
