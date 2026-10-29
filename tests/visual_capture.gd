extends Node
## Optional rendered visual check. Requires a display; never run with --headless.
func capture(file: String) -> void:
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png("res://docs/screenshots/" + file + ".png")
	assert(result == OK, "Screenshot must save")
	print("CAPTURE: ", file)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Settings.set_value("quality", 1)
	await capture("menu")
	app.open_settings()
	await capture("settings")
	app.close_settings()
	app.start_training()
	# Capture without OS cursor capture to simplify local display automation.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await capture("training")
	app.pause_game()
	await capture("pause")
	app.resume_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().size = Vector2i(1600, 720)
	await capture("training-wide")
	get_tree().paused = false
	app.queue_free()
	await get_tree().process_frame
	Geometry.materials.clear()
	get_tree().quit()
