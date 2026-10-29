extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	root.get_node("Settings").set_value("quality", 0)
	app.start_training()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 15:
		await process_frame
	var draws := [0]
	app.hud.draw.connect(func(): draws[0] += 1)
	var start := Time.get_ticks_msec()
	var samples := []
	for i in 60:
		await process_frame
		samples.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var targets_active := 0
	for target in app.world.targets:
		if target.is_processing(): targets_active += 1
	var result := {"frames": 60, "elapsed_ms": Time.get_ticks_msec()-start, "hud_draws": draws[0], "idle_target_processes": targets_active,
		"flash_triangles": app.player.rifle.flash.mesh.get_faces().size()/3, "draw_call_samples": samples,
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	var path := OS.get_cmdline_user_args()[0]
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	app.queue_free()
	await process_frame
	quit()
