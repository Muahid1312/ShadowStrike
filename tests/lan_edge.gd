extends Node
var app: Node
var role := "host"
var case_name := "capacity"
var directory := ""
var checks := 0
var failures := 0
var age := 0.0
var joining := false
var was_live := false
var reported_pair := false
var finished := false
var ready_sent := false

func option(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="):
			return argument.get_slice("=", 1)
	return fallback

func check(value: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + role + " / " + description)
	if not value:
		failures += 1

func mark(tag: String) -> void:
	var file := FileAccess.open(directory.path_join(role + "-" + tag), FileAccess.WRITE)
	file.store_string("ready")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = option("role", "host")
	case_name = option("case", "capacity")
	directory = option("directory", "/tmp")
	var port := int(option("port", "17778"))
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	if role == "host":
		check(Lan.host_game("Host", 2 if case_name == "capacity" else 4, port), "create edge-case host")
		mark("hosting")
	else:
		if role == "probe" and case_name == "old_map":
			multiplayer.connected_to_server.disconnect(Lan._connected)
			multiplayer.connected_to_server.connect(func(): Lan._register.rpc_id(1,"Legacy map",4))
		app.open_lan("join")
		app.lan_panel.name_field.text = "Probe" if role == "probe" else "Guest"
		app.lan_panel.address_field.text = "127.0.0.1"
		app.lan_panel.port_field.text = str(port)
		app.lan_panel.action_button.pressed.emit()
		joining = true

func _process(delta: float) -> void:
	if finished or not joining and role != "host":
		return
	age += delta
	if age > 32:
		check(false, "edge-case watchdog")
		finish()
		return
	if role == "host":
		if Lan.phase == "lobby" and Lan.roster.size() == 2 and not reported_pair:
			reported_pair = true
			mark("pair")
		if Lan.phase == "lobby" and FileAccess.file_exists(directory.path_join("release")) and Lan.can_start():
			check(Lan.start_match(), "ready pair starts after test coordinator releases gate")
		if Lan.phase == "match" and not was_live:
			was_live = true
			check(Lan.roster.size() == 2, "only admitted players reach match")
			mark("live")
		if FileAccess.file_exists(directory.path_join("stop")):
			check(Lan.roster.size() == 2, "refused probe never changes authoritative roster")
			Lan.leave()
			finish()
	elif role == "participant":
		if Lan.phase == "lobby" and not ready_sent:
			ready_sent = true
			Lan.set_ready(true)
		if Lan.phase == "match" and not was_live:
			was_live = true
			check(app.mode == "match", "participant enters match")
			mark("live")
		if was_live and Lan.phase == "idle":
			check(app.mode == "menu" and Lan.peer == null, "host exit or crash returns participant to safe menu")
			check(not get_tree().paused and Lan.roster.is_empty(), "host loss clears paused state and roster")
			finish()
	else:
		if Lan.phase == "lobby" or Lan.in_match():
			check(false, "probe must never be admitted")
			finish()
		elif Lan.phase == "idle":
			check(age <= 12, "refused connection ends within bounded timeout")
			check(Lan.peer == null and Lan.roster.is_empty(), "failed connection clears ENet state")
			check(app.mode == "lan" and not app.lan_panel.action_button.disabled, "join form remains usable with visible error")
			check("timed out" in Lan.status or "Could not connect" in Lan.status, "join displays actionable connection failure")
			app.lan_panel.back_requested.emit()
			check(app.mode == "menu", "Back returns from failed join")
			finish()

func finish() -> void:
	if finished:
		return
	finished = true
	mark("done")
	if Lan.active():
		Lan.leave()
	print("EDGE RESULT: %s / %d checks / %d failures" % [role, checks, failures])
	get_tree().quit(1 if failures else 0)
