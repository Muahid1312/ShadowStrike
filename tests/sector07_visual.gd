extends Node
var app: Node
var prefix := "sector07"
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://docs/screenshots/"+prefix+"-"+label+".png")
	assert(result==OK)
	print("CAPTURE: ",prefix,"-",label)
func view(point: Vector3, look: Vector3) -> void:
	app.player.position = point
	app.player.velocity = Vector3.ZERO
	app.player.input_enabled = false
	var direction := (look-(point+Vector3(0,1.65,0))).normalized()
	app.player.target_yaw=atan2(-direction.x,-direction.z)
	app.player.target_pitch=asin(direction.y)
	app.player.yaw=app.player.target_yaw;app.player.rotation.y=app.player.target_yaw
	app.player.pitch=app.player.target_pitch;app.player.camera.rotation.x=app.player.target_pitch
	await frames(20)
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prefix="):prefix=arg.get_slice("=",1)
	app=load("res://scenes/main.tscn").instantiate();add_child(app)
	Settings.set_value("quality",1)
	app.start_training();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(20)
	await view(Vector3(0,.05,8),Vector3(0,1.65,-16))
	await capture("courtyard")
	await view(Vector3(-7,.05,5),Vector3(16,3.3,-16))
	await capture("tower")
	await view(Vector3(8,.05,4),Vector3(-18,2,-12))
	await capture("headquarters")
	await view(Vector3(0,.05,-9),Vector3(0,1.75,-20))
	await capture("range")
	await view(Vector3(-18,.05,-12),Vector3(-20.5,1.8,-15.8))
	await capture("interior")
	await view(Vector3(17,4.25,-17),Vector3(0,1.65,8))
	await capture("observation-deck")
	app.queue_free();await frames(3);Geometry.materials.clear()
	get_tree().quit()
