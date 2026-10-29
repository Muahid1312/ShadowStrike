extends Node
## Functional release regressions. Synthetic input does not establish phone support.
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func native_touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = get_viewport().get_final_transform() * point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "Android preset loads")
	check(preset.get_value("preset.0.options", "gradle_build/use_gradle_build", false), "official Gradle Android template selected")
	check(preset.get_value("preset.0.options", "gradle_build/min_sdk", "") == "" and preset.get_value("preset.0.options", "gradle_build/target_sdk", "") == "", "export uses matching template SDK defaults")
	check(preset.get_value("preset.0.options", "architectures/arm64-v8a", false), "ARM64 export enabled")
	check(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false), "Android ETC2/ASTC import enabled")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.start_training()
	await frames(8)
	for quality in 3:
		Settings.set_value("quality", quality)
		check(is_equal_approx(get_viewport().scaling_3d_scale, [0.65, 0.85, 1.0][quality]), "preset %d applies real render scale" % quality)
		check(app.world.sun.shadow_enabled == (quality > 0) and app.world.environment.fog_enabled == (quality > 0), "preset %d changes shadows/fog" % quality)
		check(get_viewport().msaa_3d == (Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED), "preset %d applies supported MSAA" % quality)
	Settings.set_value("quality", 1)
	Settings.set_value("volume", 0.4)
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.4)), "master volume changes the actual audio bus")
	app.pause_game()
	app.open_settings()
	check(app.settings_panel.rows.quality.get_item_text(1).begins_with("MEDIUM"), "LOW/MEDIUM/HIGH labels match real presets")
	app.close_settings()
	app.resume_game()
	var player: FPSPlayer = app.player
	var touch: TouchHUD = app.hud.touch
	var gun = player.rifle
	check(gun.flash.mesh.get_faces().size() / 3 <= 128, "small muzzle flash uses a bounded low polygon mesh")
	var idle := true
	for target in app.world.targets: idle = idle and not target.is_processing()
	check(idle, "idle range targets do not schedule per-frame callbacks")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.relative = Vector2(50, 20)
	player._unhandled_input(motion)
	check(player.mouse_look == Vector2.ZERO, "emulated touch mouse motion cannot double camera look")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	touch.layout_controls()
	native_touch(0, touch.joystick_center + Vector2(0, -45), true)
	await frames(2)
	check(touch.movement.y < 0 and not gun.trigger_held and gun.magazine == 30, "native emulated joystick touch moves without accidental shooting")
	native_touch(1, touch.zones.fire.get_center(), true)
	var ammo_before: int = gun.magazine
	await frames(24)
	var consumed: int = ammo_before - gun.magazine
	check(touch.firing and consumed >= 3 and consumed <= 5, "held native fire fires at the 600 RPM rate while moving")
	app._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(app.mode == "pause" and touch.contacts.is_empty() and not gun.trigger_held and not player.input_enabled, "background notification clears held touch/fire and opens local pause")
	native_touch(0, touch.joystick_center, false)
	native_touch(1, touch.zones.fire.get_center(), false)
	app.resume_game()
	var ammo_after: int = gun.magazine
	await frames(12)
	check(gun.magazine == ammo_after and touch.movement == Vector2.ZERO and player.input_enabled, "resume does not restore stale movement or fire")
	native_touch(2, touch.zones.reload.get_center(), true)
	native_touch(2, touch.zones.reload.get_center(), false)
	check(gun.reload_remaining > 0, "native touch Reload reaches the real weapon")
	for dimensions in [Vector2(1280,720), Vector2(1600,720), Vector2(1440,720)]:
		touch.size = dimensions
		touch.layout_controls()
		var valid := true
		for zone in touch.zones.values():
			valid = valid and Rect2(Vector2.ZERO,dimensions).encloses(zone)
		check(valid and touch.joystick_center.x + touch.joystick_radius < touch.zones.sprint.position.x, "landscape %s touch zones remain on-screen and separate" % dimensions)
	gun.audio.stop()
	gun.reload_audio.stop()
	await get_tree().create_timer(0.15).timeout
	app.show_menu()
	gun = null
	player = null
	touch = null
	app.queue_free()
	await get_tree().process_frame
	Geometry.materials.clear()
	print("RELEASE AUDIT RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
