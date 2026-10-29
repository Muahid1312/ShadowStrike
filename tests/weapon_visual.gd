extends Node
## Actual game frames; an optional --before captures the old model before replacement.
var app: Node
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png("res://docs/screenshots/weapon-" + name + ".png")
	assert(error == OK)
	print("CAPTURE: weapon-", name, ".png")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	Settings.set_value("quality", 1)
	app.start_training()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(25)
	await capture("idle")
	Input.action_press("aim")
	await frames(25)
	await capture("aim")
	Input.action_release("aim")
	Input.action_press("forward")
	await frames(12)
	await capture("walk")
	Input.action_press("sprint")
	await frames(18)
	await capture("sprint")
	Input.action_release("forward")
	Input.action_release("sprint")
	app.player.position = Vector3(0, 0.05, 8)
	app.player.velocity = Vector3.ZERO
	await frames(25)
	app.player.rifle.shoot()
	get_tree().paused = true
	await frames(2)
	await capture("fire")
	get_tree().paused = false
	await frames(10)
	app.player.rifle.reload()
	await get_tree().create_timer(0.75).timeout
	get_tree().paused = true
	await frames(2)
	await capture("reload")
	get_tree().paused = false
	await get_tree().create_timer(1.2).timeout
	await capture("reload-seated")
	get_window().size = Vector2i(1600, 720)
	await frames(12)
	await capture("wide")
	app.player.rifle.audio.stop()
	app.player.rifle.reload_audio.stop()
	app.queue_free()
	await frames(4)
	Geometry.materials.clear()
	await frames(2)
	get_tree().quit()
