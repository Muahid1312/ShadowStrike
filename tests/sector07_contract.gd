extends Node
var checks:=0
var failures:=0
var app:Node
func check(value:bool,title:String)->void:
	checks+=1;print(("PASS: " if value else "FAIL: ")+title)
	if not value:failures+=1
func frames(n:int)->void:
	for i in n:await get_tree().physics_frame
func clear_capsule(point:Vector3)->bool:
	var shape:=CapsuleShape3D.new();shape.radius=.36;shape.height=1.8
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,.9,0));query.collision_mask=1;query.margin=.01;query.exclude=[app.player.get_rid()]
	return app.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func ray(a:Vector3,b:Vector3)->Dictionary:
	var q:=PhysicsRayQueryParameters3D.create(a,b,1);q.exclude=[app.player.get_rid()]
	return app.world.get_world_3d().direct_space_state.intersect_ray(q)
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	app=load("res://scenes/main.tscn").instantiate();add_child(app);app.start_training();await frames(10)
	check(app.world.targets.size()==7,"seven original target positions retained")
	check(app.world.find_children("*","RigidBody3D",true,false).is_empty(),"environment introduces no synchronized dynamic physics")
	check(app.world.collision_bodies.size()>=100 and app.world.collision_bodies.size()<160,"bounded deterministic static collision layout")
	for point in Lan.SPAWNS:
		check(clear_capsule(point),"initial spawn capsule is clear: "+str(point))
	for point in CombatAuthority.EXTRA_SPAWNS:
		check(clear_capsule(point),"respawn capsule is clear: "+str(point))
	for point in [Vector3(-18,.05,-8),Vector3(14,.05,-1),Vector3(-17.5,.05,13.5),Vector3(-22,.05,-12)]:
		check(clear_capsule(point),"open building entrance fits standing player: "+str(point))
	check(ray(Vector3(-20.56,1.8,-6.8),Vector3(-20.56,1.8,-9.5)).is_empty(),"window opening passes a real shot")
	check(not ray(Vector3(-20.56,.7,-6.8),Vector3(-20.56,.7,-9.5)).is_empty(),"wall below window blocks a real shot")
	check(not ray(Vector3(0,1,-15.5),Vector3(0,1,-18)).is_empty(),"tapered concrete cover blocks low shots")
	check(ray(Vector3(0,1.8,-15.5),Vector3(0,1.8,-18)).is_empty(),"shots above concrete cover remain clear")
	check(not ray(Vector3(23,5.5,0),Vector3(25,5.5,0)).is_empty(),"security boundary also blocks tower-height escape")
	app.player.position=Vector3(14.3,.05,-8.0);app.player.velocity=Vector3.ZERO;app.player.target_yaw=0;app.player.yaw=0;app.player.target_pitch=0;app.player.pitch=0
	await frames(3)
	Input.action_press("forward")
	var reached:=false
	for i in 280:
		await frames(1)
		if app.player.position.y>4.08 and app.player.position.z< -15.95:
			reached=true;break
	Input.action_release("forward");app.player.velocity=Vector3.ZERO
	check(reached,"unchanged player controller can walk up the actual tower staircase")
	await frames(6)
	check(app.player.is_on_floor() and app.player.position.y>4.05,"tower landing supports the standing player")
	check(clear_capsule(Vector3(17,4.25,-17)),"observation platform has standing clearance")
	var target:Node=app.world.targets[3]
	check(target.receive_hit(Vector3.ZERO) and not target.available and target.plate.material_override!=null,"new target art preserves hit lockout and bright feedback")
	await frames(45)
	check(target.available and target.plate.material_override==null,"target cooldown restores imported PBR materials")
	for quality in 3:
		Settings.set_value("quality",quality)
		check(app.world.sun.shadow_enabled==(quality>0) and app.world.environment.fog_enabled==(quality>0),"quality preset %d controls supported sun shadows/fog"%quality)
	app.queue_free();await get_tree().process_frame;Geometry.materials.clear()
	print("SECTOR07 CONTRACT RESULT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
