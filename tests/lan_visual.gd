extends Node
var app: Node
var role := "host"
var ready_sent := false
var was_live := false
var age := 0.0

func option(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="):
			return argument.get_slice("=", 1)
	return fallback

func capture(name: String) -> void:
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://docs/screenshots/phase2-" + name + ".png")
	assert(result == OK)
	print("CAPTURE: phase2-", name)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = option("role", "host")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	var port := int(option("port", "17779"))
	if role != "host":
		app.open_lan("join")
		Lan.join_game(option("name", "Guest"), "127.0.0.1", port)
		return
	await capture("menu")
	app.open_lan("join")
	await capture("join")
	app.show_menu()
	app.open_lan("host")
	await capture("host")
	assert(Lan.host_game("COMMANDER", 4, port))
	var marker := FileAccess.open(option("directory", "/tmp").path_join("visual-host-ready"), FileAccess.WRITE)
	marker.store_string("ready")
	marker.close()
	while not Lan.can_start():
		await get_tree().process_frame
		if age > 25:
			get_tree().quit(1)
			return
		if Lan.roster.size() < 4:
			continue
		break
	# Ensure all four connected names/ready indicators are present before capture.
	while Lan.roster.size() != 4 or not Lan.can_start():
		await get_tree().process_frame
	await capture("lobby")
	assert(Lan.start_match())
	while Lan.phase != "match":
		await get_tree().process_frame
	app.player.position = Vector3(0, 0.05, 21)
	app.player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in range(30):
		await get_tree().process_frame
	await capture("arena")
	app.pause_game()
	await capture("pause")
	Lan.leave()
	get_tree().quit()

func _process(delta: float) -> void:
	age += delta
	if age > 35:
		get_tree().quit(1)
	if role == "host":
		return
	if Lan.phase == "lobby" and not ready_sent:
		ready_sent = true
		Lan.set_ready(true)
	if Lan.phase == "match":
		was_live = true
	if was_live and Lan.phase == "idle":
		get_tree().quit()
