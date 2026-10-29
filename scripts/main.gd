extends Node
## Screen flow only. Player, rifle and arena have independent responsibilities.
const ARENA := preload("res://maps/arena.tscn")
const PLAYER := preload("res://player/player.tscn")
var world: Node3D
var menu_camera: Camera3D
var player: FPSPlayer
var hud: GameHUD
var layer: CanvasLayer
var screen: Control
var settings_panel: SettingsPanel
var mode := "menu"
var hits := 0
var menu_time := 0.0
var lan_panel: LANPanel
var network_match: LANMatch
var pause_origin := "training"
var menu_notice := ""
var scoreboard: ScoreboardOverlay
var results_screen: ResultsScreen

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Lan.match_loading.connect(start_lan_match)
	Lan.ended.connect(_session_ended)
	Lan.lobby_opened.connect(_session_lobby)
	Rules.stage_changed.connect(_round_stage)
	layer = CanvasLayer.new()
	add_child(layer)
	show_menu()
	if OS.get_cmdline_user_args().has("--arena"):
		start_training()

func clear_screen() -> void:
	if is_instance_valid(screen):
		layer.remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.theme = MilitaryStyle.theme()
	layer.add_child(screen)
	MilitaryStyle.full(screen)

func build_world() -> void:
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = ARENA.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

func shade(parent: Control, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	MilitaryStyle.full(rect)
	return rect

func show_menu() -> void:
	if Lan.active():
		Lan.leave()
		return
	network_match = null
	settings_panel = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mode = "menu"
	player = null
	hud = null
	build_world()
	menu_camera = Camera3D.new()
	world.add_child(menu_camera)
	menu_camera.position = Vector3(13, 3.4, 17)
	menu_camera.look_at(Vector3(1, 1.3, -9))
	menu_camera.current = true
	clear_screen()
	shade(screen, Color(0.01, 0.025, 0.027, 0.28))
	var left_shade := shade(screen, Color(0.015, 0.025, 0.025, 0.86))
	left_shade.anchor_right = 0.50
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	content.position = Vector2(72, 30)
	content.size = Vector2(442, 600)
	content.add_theme_constant_override("separation", 10)
	screen.add_child(content)
	content.add_child(MilitaryStyle.label("///   TACTICAL OPERATIONS DIVISION", 17, MilitaryStyle.GOLD, true))
	var title := MilitaryStyle.label("SHADOW\nSTRIKE", 80, MilitaryStyle.TEXT, true)
	title.add_theme_constant_override("line_spacing", -23)
	content.add_child(title)
	content.add_child(MilitaryStyle.label("LOCAL MULTIPLAYER SHOOTER", 22, MilitaryStyle.GOLD, true))
	content.add_child(MilitaryStyle.label("TRAIN. ADAPT. DOMINATE.", 17, MilitaryStyle.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	content.add_child(gap)
	content.add_child(MilitaryStyle.button("PLAY     /     TRAINING RANGE", start_training, true))
	var lan_buttons := HBoxContainer.new()
	content.add_child(lan_buttons)
	for kind in ["host", "join"]:
		var button := MilitaryStyle.button("HOST GAME" if kind == "host" else "JOIN GAME", open_lan.bind(kind))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lan_buttons.add_child(button)
	content.add_child(MilitaryStyle.button("SETTINGS", open_settings))
	content.add_child(MilitaryStyle.button("QUIT", quit_game))
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	card.offset_left = -402
	card.offset_top = -214
	card.offset_right = -52
	card.offset_bottom = -64
	screen.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(MilitaryStyle.label("01  /  PROVING GROUND", 26, MilitaryStyle.GOLD, true))
	column.add_child(MilitaryStyle.label("SECTOR 07 • DESERT TRAINING", 17))
	column.add_child(MilitaryStyle.label("Free for All + solo training\nDirect IP • No account required.", 16, MilitaryStyle.MUTED))
	var version := MilitaryStyle.label("PHASE 5   /   v0.5.0     •     OFFLINE LAN / ENET", 14, MilitaryStyle.MUTED)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 72
	version.offset_top = -37
	version.offset_right = 750
	version.offset_bottom = -10
	screen.add_child(version)
	if not menu_notice.is_empty():
		var notice := MilitaryStyle.label(menu_notice, 18, MilitaryStyle.GOLD)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		notice.offset_left = -570
		notice.offset_right = -45
		notice.offset_top = 35
		notice.offset_bottom = 135
		screen.add_child(notice)
		menu_notice = ""

func start_training() -> void:
	get_tree().paused = false
	mode = "training"
	hits = 0
	build_world()
	world.target_hit.connect(on_target_hit)
	player = PLAYER.instantiate()
	world.add_child(player)
	player.position = Vector3(0, 0.1, 8)
	player.pause_requested.connect(pause_game)
	clear_screen()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud = GameHUD.new()
	screen.add_child(hud)
	hud.bind_player(player)
	hud.pause_requested.connect(pause_game)
	hud.reset_requested.connect(reset_drill)
	capture_mouse()

func capture_mouse() -> void:
	if not OS.has_feature("android") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func on_target_hit(_point: Vector3) -> void:
	hits += 1
	hud.set_hits(hits)

func reset_drill() -> void:
	hits = 0
	hud.set_hits(0)
	player.rifle.resupply()
	player.clear_input()
	capture_mouse()

func pause_game() -> void:
	if mode != "training" and mode != "match":
		return
	if not is_instance_valid(player) or not is_instance_valid(hud):
		return # A focus/back event can arrive while deferred network bodies load.
	pause_origin = mode
	player.clear_input()
	player.input_enabled = false
	hud.touch.set_process_input(false)
	get_tree().paused = not Lan.in_match()
	mode = "pause"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var overlay := Control.new()
	overlay.name = "PauseOverlay"
	screen.add_child(overlay)
	MilitaryStyle.full(overlay)
	shade(overlay, Color(0.015, 0.025, 0.025, 0.78))
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -230
	panel.offset_top = -255
	panel.offset_right = 230
	panel.offset_bottom = 255
	overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(MilitaryStyle.label("MISSION PAUSED", 44, MilitaryStyle.TEXT, true))
	column.add_child(MilitaryStyle.label("SECTOR 07   /   LAN CONTINUES" if Lan.in_match() else "SECTOR 07   /   TRAINING", 18, MilitaryStyle.GOLD))
	column.add_child(MilitaryStyle.button("RESUME", resume_game, true))
	column.add_child(MilitaryStyle.button("SETTINGS", open_settings))
	column.add_child(MilitaryStyle.button("LEAVE MATCH" if Lan.in_match() else "BACK TO MENU", show_menu))
	column.add_child(MilitaryStyle.button("QUIT GAME", quit_game))

func resume_game() -> void:
	if mode != "pause":
		return
	var overlay := screen.get_node_or_null("PauseOverlay")
	if overlay:
		screen.remove_child(overlay)
		overlay.queue_free()
	player.clear_input()
	get_tree().paused = false
	mode = pause_origin
	player.input_enabled = true
	hud.touch.set_process_input(true)
	capture_mouse()

func open_settings() -> void:
	if is_instance_valid(settings_panel):
		return
	settings_panel = SettingsPanel.new()
	var backdrop := Control.new()
	backdrop.name = "SettingsOverlay"
	screen.add_child(backdrop)
	MilitaryStyle.full(backdrop)
	shade(backdrop, Color(0.02, 0.03, 0.03, 0.94))
	backdrop.add_child(settings_panel)
	settings_panel.closed.connect(close_settings)

func close_settings() -> void:
	var backdrop := screen.get_node_or_null("SettingsOverlay")
	if backdrop:
		screen.remove_child(backdrop)
		backdrop.queue_free()
	settings_panel = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T and mode == "training" and hits >= 10:
		reset_drill()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if is_instance_valid(settings_panel):
			close_settings()
		elif mode == "pause":
			resume_game()
		elif mode == "scoreboard":
			close_scoreboard()
		elif mode == "training" or mode == "match":
			pause_game()
		elif mode == "lan":
			show_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if mode == "training" or mode == "match":
			pause_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == "scoreboard":
			close_scoreboard()
		elif mode == "lan" or (Lan.phase == "loading" and Rules.stage == "LOBBY"):
			show_menu()
		elif is_instance_valid(settings_panel):
			close_settings()
		elif mode == "training" or mode == "match":
			pause_game()
		elif mode == "pause":
			resume_game()

func _process(delta: float) -> void:
	if mode == "menu" and is_instance_valid(menu_camera):
		menu_time += delta
		menu_camera.position.x = 13 + sin(menu_time * 0.09) * 0.8
		menu_camera.look_at(Vector3(1, 1.3, -9))

func open_lan(kind: String) -> void:
	mode = "lan"
	clear_screen()
	shade(screen, Color(0.015, 0.025, 0.025, 0.80))
	lan_panel = LANPanel.new()
	lan_panel.kind = kind
	screen.add_child(lan_panel)
	lan_panel.back_requested.connect(show_menu)

func start_lan_match(_assignments: Dictionary) -> void:
	var start_epoch: int = Lan.epoch
	get_tree().paused = false
	mode = "match"
	hits = 0
	build_world()
	world.process_mode = Node.PROCESS_MODE_ALWAYS
	network_match = LANMatch.new()
	world.add_child(network_match)
	clear_screen()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# NetworkMatch adds authoritative/predicted bodies deferred, after arena tree entry.
	await get_tree().process_frame
	if not Lan.in_match() or Lan.epoch != start_epoch or not is_instance_valid(network_match):
		return
	player = network_match.local_player
	if not player.is_node_ready():
		await player.ready
	if not Lan.in_match() or Lan.epoch != start_epoch or not is_instance_valid(player):
		return
	player.pause_requested.connect(pause_game)
	hud = GameHUD.new()
	hud.network_game = true
	screen.add_child(hud)
	hud.bind_player(player)
	hud.pause_requested.connect(pause_game)
	hud.leave_requested.connect(show_menu)
	hud.scoreboard_requested.connect(open_scoreboard)
	capture_mouse()
	Lan.mark_loaded()

func _session_ended(message: String) -> void:
	menu_notice = message
	show_menu()

func quit_game() -> void:
	if Lan.active():
		Lan.leave()
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		if mode == "scoreboard":
			close_scoreboard()
		elif mode == "match" and Lan.in_match():
			open_scoreboard()
		else:
			return
		get_viewport().set_input_as_handled()

func open_scoreboard() -> void:
	if mode != "match" or not Lan.in_match():
		return
	player.clear_input()
	player.input_enabled = false
	hud.touch.set_process_input(false)
	mode = "scoreboard"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	scoreboard = ScoreboardOverlay.new()
	screen.add_child(scoreboard)
	scoreboard.closed.connect(close_scoreboard)

func close_scoreboard() -> void:
	if mode != "scoreboard":
		return
	if is_instance_valid(scoreboard):
		screen.remove_child(scoreboard)
		scoreboard.queue_free()
	scoreboard = null
	mode = "match"
	player.clear_input()
	player.input_enabled = true
	capture_mouse()

func _round_stage(value: String) -> void:
	if value != "RESULTS" or not is_instance_valid(network_match):
		return
	player.clear_input()
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	mode = "results"
	settings_panel = null
	scoreboard = null
	clear_screen()
	results_screen = ResultsScreen.new()
	screen.add_child(results_screen)
	results_screen.lobby_requested.connect(func(): Rules.return_to_lobby())
	results_screen.menu_requested.connect(show_menu)

func _session_lobby() -> void:
	if mode not in ["match", "pause", "scoreboard", "results"]:
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player = null
	hud = null
	network_match = null
	settings_panel = null
	scoreboard = null
	results_screen = null
	build_world()
	menu_camera = Camera3D.new()
	world.add_child(menu_camera)
	menu_camera.position = Vector3(13, 3.4, 17)
	menu_camera.look_at(Vector3(1, 1.3, -9))
	menu_camera.current = true
	open_lan("host" if Lan.is_host() else "join")
