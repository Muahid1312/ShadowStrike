extends Node
## Integration suite runs the shipped scenes, actual physics queries and UI callbacks.
var checks := 0
var failures := 0
var app: Node
var settings_snapshot: Dictionary

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func frames(number: int) -> void:
	for i in number:
		await get_tree().physics_frame

func find_button(parent: Node, prefix: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text.begins_with(prefix):
			return child
		var nested := find_button(child, prefix)
		if nested:
			return nested
	return null

func click_button(button: Button) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = button.get_global_rect().get_center()
		get_viewport().push_input(event, true)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		get_viewport().push_input(event, true)

func touch(index: int, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	get_viewport().push_input(event, true)

func drag(index: int, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = relative
	get_viewport().push_input(event, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings_snapshot = Settings.values.duplicate()
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await frames(4)
	check(app.mode == "menu", "main scene opens the menu")
	check(find_button(app.screen, "PLAY") != null and find_button(app.screen, "QUIT") != null, "main menu has real Play and Quit buttons")
	click_button(find_button(app.screen, "SETTINGS"))
	await frames(2)
	check(is_instance_valid(app.settings_panel), "Settings button opens settings")
	app.settings_panel.rows.sensitivity.value = 1.65
	app.settings_panel.rows.aim_sensitivity.value = 0.35
	app.settings_panel.rows.joystick_size.value = 1.2
	app.settings_panel.rows.volume.value = 0.4
	app.settings_panel.rows.invert_look.button_pressed = true
	app.settings_panel.rows.show_fps.button_pressed = true
	app.settings_panel.rows.quality.selected = 0
	app.settings_panel.rows.quality.item_selected.emit(0)
	var saved := ConfigFile.new()
	check(saved.load(Settings.PATH) == OK and is_equal_approx(saved.get_value("preferences", "sensitivity"), 1.65), "slider writes ConfigFile to disk")
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.load_settings()
	check(is_equal_approx(Settings.values.aim_sensitivity, 0.35) and Settings.values.invert_look and Settings.values.show_fps, "preferences reload from disk")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.4)), "master volume changes audio bus")
	check(not app.world.sun.shadow_enabled and not app.world.environment.fog_enabled, "low quality disables shadows and fog")
	check(is_equal_approx(get_viewport().scaling_3d_scale, 0.65), "low quality changes render scale")
	find_button(app.settings_panel, "BACK").pressed.emit()
	click_button(find_button(app.screen, "PLAY"))
	await frames(16)
	check(app.mode == "training" and is_instance_valid(app.player), "Play loads arena and CharacterBody3D")
	check(app.world.targets.size() == 7, "arena contains seven physical targets")
	var player: FPSPlayer = app.player
	var gun = player.rifle
	var hud: TouchHUD = app.hud.touch
	check(player.is_on_floor(), "player settles on collidable ground")
	# Real actions go through the player's physics controller.
	var start := player.position
	Input.action_press("forward")
	await frames(30)
	Input.action_release("forward")
	await frames(4)
	var walked := start.z - player.position.z
	check(walked > 1.0, "W action moves player forward")
	start = player.position
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(30)
	Input.action_release("forward")
	Input.action_release("sprint")
	await frames(4)
	check(start.z - player.position.z > walked * 1.3, "sprinting moves faster than walking")
	var grounded_y := player.position.y
	player.pending_jump = true
	await frames(10)
	check(player.position.y > grounded_y + 0.3, "jump leaves ground")
	await frames(70)
	check(player.is_on_floor(), "gravity returns player to floor")
	Settings.set_value("invert_look", false)
	var initial_pitch := player.target_pitch
	player.apply_look(Vector2(20, 20))
	check(player.target_yaw < 0 and player.target_pitch < initial_pitch, "camera yaw and pitch respond to look")
	Settings.set_value("invert_look", true)
	initial_pitch = player.target_pitch
	player.apply_look(Vector2(0, 20))
	check(player.target_pitch > initial_pitch, "invert look reverses pitch")
	Settings.set_value("invert_look", false)
	player.aiming = false
	initial_pitch = player.target_pitch
	player.apply_look(Vector2(0, 10))
	var un_aimed := absf(player.target_pitch - initial_pitch)
	player.aiming = true
	initial_pitch = player.target_pitch
	player.apply_look(Vector2(0, 10))
	check(absf(player.target_pitch - initial_pitch) < un_aimed * 0.5, "aim sensitivity reduces camera motion")
	# Multitouch ownership and InputEvent dispatch, not just direct flag changes.
	hud.layout_controls()
	check(is_equal_approx(hud.joystick_radius, 91.2), "joystick size preference changes touch geometry")
	touch(0, hud.joystick_center + Vector2(0, -50), true)
	touch(1, Vector2(700, 280), true)
	touch(2, hud.zones.fire.get_center(), true)
	check(hud.contacts.size() == 3 and hud.firing and hud.movement.y < 0, "three simultaneous contacts independently move, look and fire")
	drag(1, Vector2(730, 290), Vector2(30, 10))
	check(hud.look_delta == Vector2(30, 10), "right swipe accumulates look delta")
	touch(2, hud.zones.fire.get_center(), false)
	check(not hud.firing and hud.movement.y < 0 and hud.contacts.size() == 2, "fire release preserves other contacts")
	touch(0, hud.joystick_center, false)
	touch(1, Vector2(730, 290), false)
	touch(3, hud.zones.aim.get_center(), true)
	touch(4, hud.zones.sprint.get_center(), true)
	check(hud.aiming and hud.sprinting, "aim and sprint touch actions have separate ownership")
	touch(3, hud.zones.aim.get_center(), false)
	touch(4, hud.zones.sprint.get_center(), false)
	touch(5, hud.zones.jump.get_center(), true)
	check(player.pending_jump, "touch Jump reaches controller")
	touch(5, hud.zones.jump.get_center(), false)
	player.pending_jump = false
	hud.reset()
	player.position = Vector3(0, 0.05, -9)
	player.velocity = Vector3.ZERO
	player.target_yaw = 0
	player.yaw = 0
	player.target_pitch = 0
	player.pitch = 0
	await frames(12)
	# Target center lies directly down the camera ray from this lane.
	check(gun.shoot(), "rifle fires a live physics ray")
	check(gun.magazine == 29 and app.hits == 1, "shot consumes ammunition and valid target hit increments objective")
	check(app.hud.feedback > 0 and not app.world.targets[3].available, "hitmarker and target flash activate")
	check(not gun.shoot() and gun.magazine == 29, "fire rate rejects immediate duplicate shot")
	await frames(45)
	check(app.world.targets[3].available, "target becomes available after visual cooldown")
	# Insert a real collision wall between muzzle direction and target.
	var blocker := Geometry.box(app.world, Vector3(0, 1.5, -11), Vector3(3, 3, 0.5), Color.GRAY, true)
	await frames(3)
	gun.cooldown = 0
	gun.shoot()
	check(app.hits == 1, "concrete cover blocks raycast target damage")
	blocker.queue_free()
	await frames(3)
	gun.magazine = 12
	gun.reserve = 40
	touch(6, hud.zones.reload.get_center(), true)
	touch(6, hud.zones.reload.get_center(), false)
	check(gun.reload_remaining > 0 and not gun.shoot(), "touch Reload starts reload and prevents firing")
	await frames(110)
	check(gun.magazine == 30 and gun.reserve == 22, "reload transfers only missing rounds from reserve")
	gun.magazine = 28
	gun.reserve = 1
	gun.reload()
	await frames(110)
	check(gun.magazine == 29 and gun.reserve == 0, "partial reserve reload conserves ammunition")
	gun.magazine = 0
	check(not gun.shoot() and not gun.reload(), "empty rifle and empty reserve cannot fire or reload")
	gun.resupply()
	Input.action_press("fire")
	await frames(34)
	Input.action_release("fire")
	await frames(2)
	check(gun.magazine <= 25 and gun.magazine >= 23, "holding fire produces rate-limited automatic shots")
	# Pause through real HUD button; state must freeze while UI keeps processing.
	gun.reload()
	touch(9, hud.zones.fire.get_center(), true)
	find_button(app.hud, "Ⅱ").pressed.emit()
	await frames(3)
	check(get_tree().paused and app.mode == "pause" and hud.contacts.is_empty(), "Pause freezes gameplay and clears held contacts")
	var frozen_reload: float = gun.reload_remaining
	var frozen_pos := player.position
	await frames(20)
	check(is_equal_approx(gun.reload_remaining, frozen_reload) and player.position == frozen_pos, "reload clock and player physics stay frozen during pause")
	find_button(app.screen.get_node("PauseOverlay"), "SETTINGS").pressed.emit()
	await frames(2)
	check(is_instance_valid(app.settings_panel), "settings remain interactive while paused")
	find_button(app.settings_panel, "BACK").pressed.emit()
	find_button(app.screen.get_node("PauseOverlay"), "RESUME").pressed.emit()
	await frames(2)
	check(not get_tree().paused and app.mode == "training" and not hud.firing, "Resume restores gameplay without a stuck trigger")
	# Qualification uses actual accepted hits (no fake score).
	for i in range(10):
		app.world.targets[0].available = true
		app.world.targets[0].receive_hit(Vector3.ZERO)
	check(app.hits >= 10 and app.hud.reset_button.visible, "10-hit objective unlocks new drill")
	key(KEY_T)
	check(app.hits == 0 and gun.magazine == 30 and gun.reserve == 150, "T shortcut starts new drill and resupplies with captured mouse")
	key(KEY_ESCAPE)
	check(get_tree().paused and app.mode == "pause", "Esc pauses once without consuming its own resume")
	key(KEY_ESCAPE)
	check(not get_tree().paused and app.mode == "training", "Esc resumes from the paused UI")
	app.pause_game()
	find_button(app.screen.get_node("PauseOverlay"), "BACK TO MENU").pressed.emit()
	await frames(3)
	check(app.mode == "menu" and not get_tree().paused, "Back to Menu cleans up paused match")
	Settings.values = settings_snapshot
	for key in settings_snapshot:
		Settings.set_value(key, settings_snapshot[key])
	print("SHADOWSTRIKE TEST RESULT: %d checks, %d failures" % [checks, failures])
	app.queue_free()
	await frames(2)
	Geometry.materials.clear()
	get_tree().quit(1 if failures else 0)
