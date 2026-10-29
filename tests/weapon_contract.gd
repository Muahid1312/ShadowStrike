extends Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func mesh_nodes(parent: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in parent.get_children():
		if child is MeshInstance3D: result.append(child)
		result.append_array(mesh_nodes(child))
	return result
func minimum_depth(view: RiflePresentation, camera: Camera3D) -> float:
	var depth := INF
	for node in mesh_nodes(view.model):
		for point in node.mesh.get_faces():
			var local := camera.to_local(node.to_global(point))
			depth = minf(depth, -local.z)
	return depth
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.start_training()
	await frames(12)
	var gun = app.player.rifle
	var view: RiflePresentation = gun.presentation
	var camera: Camera3D = app.player.camera
	check(is_instance_valid(view.magazine) and is_instance_valid(view.support_hand) and is_instance_valid(view.muzzle), "imported GLB exposes magazine, support hand and muzzle")
	var triangles := 0
	var surfaces := 0
	for node in mesh_nodes(view.model):
		triangles += node.mesh.get_faces().size() / 3
		surfaces += node.mesh.get_surface_count()
	check(triangles > 5000 and triangles <= 8000 and surfaces <= 16, "detailed imported model stays within 8k triangles / 16 surfaces")
	check(gun.flash.get_parent() == view.muzzle and gun.flash.position == Vector3.ZERO, "flash is attached exactly to the modeled muzzle")
	check(gun.flash.mesh.get_faces().size() / 3 <= 8, "muzzle flash uses a tiny mobile billboard")
	check(minimum_depth(view,camera) > camera.near, "hip model never crosses camera near plane")
	var state_before := [gun.magazine,gun.reserve,gun.reload_remaining,app.player.health,app.player.target_yaw,app.player.target_pitch]
	var camera_before := camera.transform
	var original := view.transform
	for i in 60: view.update_pose(1.0/60.0,false,app.player,0,0,true)
	check(view.transform != original, "idle breathing moves the viewmodel")
	check(camera.transform == camera_before and state_before == [gun.magazine,gun.reserve,gun.reload_remaining,app.player.health,app.player.target_yaw,app.player.target_pitch], "visual updates leave camera aim, health and ammo unchanged")
	for i in 90: view.update_pose(1.0/60.0,true,app.player,0,0,true)
	var optic: Node3D = view.model.find_child("OpticAxis",true,false)
	var optic_in_camera := camera.to_local(optic.global_position)
	check(absf(optic_in_camera.x) < 0.002 and absf(optic_in_camera.y) < 0.002, "ADS centers hollow optic on the camera aiming axis")
	check(minimum_depth(view,camera) > camera.near, "ADS model stays behind the near plane")
	var resting := view.transform
	for i in 3: view.update_pose(1.0/60.0,true,app.player,0.045,0,true)
	check(view.position.z > resting.origin.z and view.rotation.x > resting.basis.get_euler().x, "shot recoil kicks the model back and up")
	app.player.running = true
	app.player.velocity = Vector3(0,0,-7)
	for i in 60:view.update_pose(1.0/60.0,false,app.player,0,0,true)
	check(view.position.y < RiflePresentation.HIP.y - 0.03 and view.sprint_blend > 0.9, "sprint smoothly lowers and cants the rifle")
	check(minimum_depth(view,camera) > camera.near, "sprint model stays behind the near plane")
	app.player.running = false
	app.player.velocity = Vector3.ZERO
	view.reset_pose()
	for i in 60:view.update_pose(1.0/60.0,false,app.player,0,0,true)
	check(gun.shoot() and gun.magazine == 29, "real camera-ray firing still consumes one round")
	check(gun.flash.visible and gun.flash_remaining > 0, "accepted shot immediately displays the muzzle flash")
	check(gun.reload(), "real training reload starts normally")
	await frames(45)
	check(view.magazine.position.distance_to(view.magazine_home.origin) > 0.10 and view.support_hand.position.distance_to(view.hand_home.origin) > 0.20, "reload removes the magazine and reaches it with the support hand")
	check(minimum_depth(view,camera) > camera.near, "reload model and moving hand avoid near-plane clipping")
	var mag_point := view.magazine.to_global(Vector3(0,-.12,0))
	var screen := camera.unproject_position(mag_point)
	check(get_viewport().get_visible_rect().has_point(screen), "removed magazine remains in the gameplay viewport")
	check(not gun.shoot() and gun.magazine == 29, "reload presentation cannot permit firing or alter ammo")
	await frames(75)
	check(gun.magazine == 30 and gun.reserve == 149 and gun.reload_remaining <= 0, "training reload preserves original transfer and timing")
	check(view.magazine.transform.is_equal_approx(view.magazine_home) and view.support_hand.transform.is_equal_approx(view.hand_home), "magazine and support hand return exactly to rest")
	# Production network presentation consumes host state; it never advances host ammo/timers.
	gun.network_mode = true
	gun.apply_server_state({"magazine": 28,"reserve":120,"reload":2.0,"alive":true})
	gun.confirmed_reload()
	gun._physics_process(1.0/60.0)
	check(gun.reload_remaining == 2.0 and gun.magazine == 28 and gun.reserve == 120, "network visual step does not simulate host reload/ammo")
	# Mirror the production role for duration selection; no session is created here.
	app.player.network_role = "client"
	view.reset_pose()
	gun.apply_server_state({"magazine":28,"reserve":120,"reload":1.0,"alive":true})
	gun._physics_process(1.0/60.0)
	check(is_equal_approx(view.reload_progress,0.5), "LAN reload animation follows the two-second host remaining time")
	gun.apply_server_state({"magazine":30,"reserve":118,"reload":0.0,"alive":true})
	gun._physics_process(1.0/60.0)
	check(view.magazine.transform.is_equal_approx(view.magazine_home), "host completion seats magazine without client ammo simulation")
	gun.apply_server_state({"magazine":28,"reserve":120,"reload":1.0,"alive":true})
	gun._physics_process(1.0/60.0)
	gun.apply_server_state({"magazine":28,"reserve":120,"reload":0.0,"alive":false})
	gun._physics_process(1.0/60.0)
	check(not view.reload_active and view.magazine.transform.is_equal_approx(view.magazine_home), "death cancels reload presentation and restores transforms")
	gun.audio.stop();gun.reload_audio.stop()
	await get_tree().create_timer(0.15).timeout
	app.queue_free()
	await get_tree().process_frame
	Geometry.materials.clear()
	print("WEAPON CONTRACT RESULT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
