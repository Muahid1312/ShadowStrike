class_name GameHUD
extends Control
signal pause_requested
signal reset_requested
signal leave_requested
signal scoreboard_requested
var timer_label: Label
var countdown_label: Label
var network_game := false
var connection_label: Label
var touch: TouchHUD
var player: FPSPlayer
var ammo_label: Label
var objective_label: Label
var fps_label: Label
var status_label: Label
var feedback := 0.0
var hit_count := 0
var reset_button: Button
var health_label: Label
var health_bar: ProgressBar
var stats_label: Label
var life_label: Label
var feed_label: Label
var kill_feed: Array = []
var damage_time := 0.0
var damage_direction := Vector2.UP
var hit_confirms := 0
var damage_events := 0
var elimination_events := 0
var life_font_size := 34
var fps_update := 0.0

func _ready() -> void:
	MilitaryStyle.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MilitaryStyle.theme()
	resized.connect(queue_redraw)
	# Independent dark backplates maintain contrast against bright desert lighting.
	for rect in [Rect2(18, 15, 440, 70), Rect2(18, -82, 230, 70), Rect2(-125, -82, 250, 74)]:
		var backing := Panel.new()
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.add_theme_stylebox_override("panel", MilitaryStyle.panel(Color(0.025, 0.04, 0.035, 0.78), Color(0.3, 0.35, 0.3, 0.35)))
		add_child(backing)
		if rect.position.y < 0:
			backing.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM if rect.position.x < 0 else Control.PRESET_BOTTOM_LEFT)
		backing.offset_left = rect.position.x
		backing.offset_top = rect.position.y
		backing.offset_right = rect.end.x
		backing.offset_bottom = rect.end.y
	touch = TouchHUD.new()
	add_child(touch)
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 30
	header.offset_top = 22
	header.offset_right = -30
	header.add_theme_constant_override("separation", 12 if network_game else 20)
	add_child(header)
	var title := VBoxContainer.new()
	header.add_child(title)
	title.add_child(MilitaryStyle.label("LIVE FIRE  /  SECTOR 07", 24, MilitaryStyle.GOLD, true))
	objective_label = MilitaryStyle.label("TRAINING OBJECTIVE   •   0 / 10 HITS", 17)
	title.add_child(objective_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	fps_label = MilitaryStyle.label("", 18, MilitaryStyle.MUTED)
	header.add_child(fps_label)
	reset_button = MilitaryStyle.button("NEW DRILL" if OS.has_feature("android") else "NEW DRILL [T]", func(): reset_requested.emit())
	reset_button.custom_minimum_size.x = 170
	reset_button.visible = false
	header.add_child(reset_button)
	var pause_button := MilitaryStyle.button("Ⅱ  PAUSE", func(): pause_requested.emit())
	pause_button.custom_minimum_size.x = 135
	header.add_child(pause_button)
	if network_game:
		header.add_child(MilitaryStyle.button("SCORES", func(): scoreboard_requested.emit()))
		header.add_child(MilitaryStyle.button("LEAVE MATCH", func(): leave_requested.emit()))
		connection_label = objective_label
		connection_label.text = "LAN • CONNECTING"
	var health := VBoxContainer.new()
	health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	health.offset_left = 30
	health.offset_top = -70
	health.offset_right = 240
	health.offset_bottom = -15
	add_child(health)
	health_label = MilitaryStyle.label("+  100 HP" if network_game else "+  100   /   RANGE SAFE", 18, MilitaryStyle.TEXT, true)
	health.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(210, 5)
	health_bar.add_theme_stylebox_override("fill", MilitaryStyle.panel(MilitaryStyle.GOLD, MilitaryStyle.GOLD))
	health.add_child(health_bar)
	ammo_label = MilitaryStyle.label("30  /  150", 32, MilitaryStyle.TEXT, true)
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ammo_label.offset_left = -100
	ammo_label.offset_top = -75
	ammo_label.offset_right = 100
	ammo_label.offset_bottom = -25
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ammo_label)
	status_label = MilitaryStyle.label("AR-01   /   AUTO", 16, MilitaryStyle.MUTED)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.offset_left = -170
	status_label.offset_top = -34
	status_label.offset_right = 170
	status_label.offset_bottom = -6
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status_label)
	var hints := MilitaryStyle.label("WASD MOVE   •   SHIFT RUN   •   SPACE JUMP   •   RMB AIM   •   R RELOAD", 14, MilitaryStyle.MUTED)
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hints.offset_left = -370
	hints.offset_top = 120 if network_game else 90
	hints.offset_right = 370
	hints.offset_bottom = 144 if network_game else 114
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.visible = not OS.has_feature("android") and not network_game
	add_child(hints)
	if network_game:
		var timer_panel := PanelContainer.new()
		timer_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		timer_panel.offset_left = -70
		timer_panel.offset_right = 70
		timer_panel.offset_top = 18
		timer_panel.offset_bottom = 82
		add_child(timer_panel)
		timer_label = MilitaryStyle.label("05:00", 30, MilitaryStyle.GOLD, true)
		timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		timer_panel.add_child(timer_label)
		countdown_label = MilitaryStyle.label("", 76, MilitaryStyle.GOLD, true)
		countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		countdown_label.offset_left = -220
		countdown_label.offset_right = 220
		countdown_label.offset_top = -130
		countdown_label.offset_bottom = 40
		countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		countdown_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		countdown_label.add_theme_constant_override("shadow_offset_x", 3)
		countdown_label.add_theme_constant_override("shadow_offset_y", 3)
		add_child(countdown_label)
		Lan.combat_event_received.connect(_combat_event)
		stats_label = MilitaryStyle.label("ELIMS  0    /    DEATHS  0", 18, MilitaryStyle.GOLD, true)
		stats_label.position = Vector2(30, 94)
		add_child(stats_label)
		feed_label = MilitaryStyle.label("", 17, MilitaryStyle.TEXT, true)
		feed_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		feed_label.offset_left = -510
		feed_label.offset_right = -30
		feed_label.offset_top = 105
		feed_label.offset_bottom = 235
		feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(feed_label)
		life_label = MilitaryStyle.label("", 34, MilitaryStyle.GOLD, true)
		life_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		life_label.offset_left = -290
		life_label.offset_right = 290
		life_label.offset_top = -75
		life_label.offset_bottom = 75
		life_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		life_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		life_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		life_label.add_theme_constant_override("shadow_offset_x", 2)
		life_label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(life_label)

func bind_player(body: FPSPlayer) -> void:
	player = body
	player.bind_hud(touch)
	player.rifle.fired.connect(func(hit: bool):
		if hit:
			feedback = 0.18)

func set_hits(number: int) -> void:
	hit_count = number
	objective_label.text = "TRAINING OBJECTIVE   •   %d / 10 HITS" % mini(number, 10)
	if number >= 10:
		objective_label.text = "DRILL COMPLETE   •   10 / 10   •   KEEP PRACTICING"
		objective_label.add_theme_color_override("font_color", MilitaryStyle.GOLD)
	else:
		objective_label.add_theme_color_override("font_color", MilitaryStyle.TEXT)
	reset_button.visible = number >= 10

func _process(delta: float) -> void:
	if not player:
		return
	var redraw_feedback := feedback > 0 or damage_time > 0
	if not get_tree().paused:
		feedback = maxf(0, feedback - delta)
	if network_game:
		var connection := "LOADING" if Lan.phase == "loading" else "LAN CONNECTED"
		if Lan.phase == "match" and not Lan.is_host() and Lan.snapshot_age > 1.0:
			connection = "WAITING FOR HOST"
		connection_label.text = "%s   /   %d OPERATORS" % ["FREE FOR ALL" if Rules.can_play() else connection, Lan.roster.size()]
		var clock := Rules.clock_text()
		if timer_label.text != clock:
			timer_label.text = clock
		if Rules.stage == "COUNTDOWN":
			countdown_label.text = str(maxi(1, ceili(Rules.countdown_left())))
		elif Rules.stage == "PLAYING" and Rules.seconds_left() > Rules.duration - 0.7:
			countdown_label.text = "GO"
		else:
			countdown_label.text = ""
	damage_time = maxf(0, damage_time - delta)
	if network_game:
		var state := Lan.combat_view(Lan.local_id())
		if not state.is_empty():
			health_label.text = "+  %03d HP" % int(state.hp)
			health_bar.value = state.hp
			stats_label.text = "ELIMS  %d    /    DEATHS  %d" % [state.eliminations, state.deaths]
			var desired_size := 24 if state.alive else 34
			if life_font_size != desired_size:
				life_font_size = desired_size
				life_label.add_theme_font_size_override("font_size", desired_size)
			if not state.alive:
				life_label.text = "ELIMINATED\nRESPAWN IN %.1fs" % state.respawn
			elif state.protection > 0:
				life_label.text = "SPAWN PROTECTION  %.1fs" % state.protection
			else:
				life_label.text = ""
			# Suppress dead touches while preserving the top-level menu buttons.
			touch.set_process_input(state.alive and player.input_enabled and Rules.can_play())
			if Rules.stage != "PLAYING":
				life_label.text = ""
		var now := Time.get_ticks_msec()
		while not kill_feed.is_empty() and kill_feed[0].until <= now:
			kill_feed.pop_front()
		var lines := PackedStringArray()
		for item in kill_feed:
			lines.append(item.text)
		feed_label.text = "\n".join(lines)
	var gun = player.rifle
	ammo_label.text = "%02d  /  %03d" % [gun.magazine, gun.reserve]
	status_label.text = "RELOADING…" if gun.reload_remaining > 0 else ("EMPTY • RELOAD" if gun.magazine == 0 else "AR-01   /   AUTO")
	fps_label.visible = Settings.values.show_fps
	fps_update += delta
	if fps_label.visible and fps_update >= 0.25:
		fps_update = 0
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if redraw_feedback or feedback > 0 or damage_time > 0:
		queue_redraw()

func _draw() -> void:
	var center := size / 2
	if damage_time > 0:
		var warning := Color(0.9, 0.28, 0.18, damage_time / 0.45 * 0.7)
		draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), warning, false, 10)
		var direction := damage_direction.normalized()
		var point := center + direction * 100
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([point + direction * 14, point - direction * 8 + side * 8, point - direction * 8 - side * 8]), warning)
	var color := MilitaryStyle.GOLD if feedback > 0 else Color(0.95, 0.96, 0.9, 0.9)
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + axis * 6, center + axis * 14, color, 2, true)
	draw_circle(center, 1.5, color)
	if feedback > 0:
		for axis in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + axis * 18, center + axis * 25, MilitaryStyle.GOLD, 3, true)

func _combat_event(event: Dictionary) -> void:
	if event.kind == "damage":
		if int(event.shooter) == Lan.local_id():
			feedback = 0.18
			hit_confirms += 1
		if int(event.player) == Lan.local_id():
			damage_time = 0.45
			damage_events += 1
			var direction: Vector3 = player.global_basis.inverse() * (event.origin - player.global_position)
			damage_direction = Vector2(direction.x, direction.z)
	elif event.kind == "elimination":
		elimination_events += 1
		kill_feed.append({"text": event.text, "until": Time.get_ticks_msec() + 6500})
		while kill_feed.size() > 4:
			kill_feed.pop_front()
