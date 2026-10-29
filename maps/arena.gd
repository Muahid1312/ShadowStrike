extends Node3D
signal target_hit(position: Vector3)
const TARGET := preload("res://maps/target.tscn")
const COMPOUND := preload("res://assets/sector07/compound.glb")
const PROPS := preload("res://assets/sector07/props.glb")
const CARGO := preload("res://assets/sector07/cargo.glb")
var targets: Array[Node3D] = []
var environment: Environment
var sun: DirectionalLight3D
var collision_bodies: Array[StaticBody3D] = []

func _ready() -> void:
	build()
	Settings.changed.connect(apply_quality)
	apply_quality()

func build() -> void:
	var geometry := COMPOUND.instantiate()
	add_child(geometry)
	var layout: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sector07/collision_layout.json"))
	_body_box("Ground",Vector3(0,-0.4,0),Vector3(64,0.8,64))
	for spec: Dictionary in layout:
		if spec.shape == "box":
			_body_box(spec.name,_vector(spec.position),_vector(spec.size))
		else:
			var body := StaticBody3D.new()
			body.name = spec.name
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for p: Array in spec.points: points.append(_vector(p))
			shape.points = points
			var collider := CollisionShape3D.new()
			collider.shape=shape;body.add_child(collider);add_child(body)
			collision_bodies.append(body)
	var ground := MeshInstance3D.new()
	ground.name = "Layered desert surface"
	var plane := PlaneMesh.new();plane.size=Vector2(64,64)
	ground.mesh=plane
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/sector07/ground.gdshader")
	material.set_shader_parameter("sand_albedo",preload("res://assets/sector07/textures/sand_albedo.png"))
	material.set_shader_parameter("dirt_albedo",preload("res://assets/sector07/textures/dirt_albedo.png"))
	material.set_shader_parameter("sand_normal",preload("res://assets/sector07/textures/sand_normal.png"))
	material.set_shader_parameter("wear_mask",preload("res://assets/sector07/textures/ground_mask.png"))
	ground.material_override=material;add_child(ground)
	var prop_source:=PROPS.instantiate()
	var cargo_source:=CARGO.instantiate()
	var crate_mesh: Mesh = (cargo_source.find_child("CargoCrate",true,false) as MeshInstance3D).mesh
	var barrel_mesh: Mesh = (prop_source.find_child("FuelDrum",true,false) as MeshInstance3D).mesh
	var bag_mesh: Mesh = (prop_source.find_child("Sandbag",true,false) as MeshInstance3D).mesh
	var crates: Array[Transform3D] = []
	for p in [Vector3(-7,0,-2),Vector3(9,0,-7),Vector3(-12,0,-12),Vector3(12,0,10),Vector3(-5,0,13)]:
		_crate(crates,p,Vector3(2.5,2,2))
		if p.x < 0: _crate(crates,p+Vector3(.2,2,0),Vector3(1.7,1.6,1.7))
	_instances("CC-BY cargo",crate_mesh,crates,80)
	var barrels: Array[Transform3D]=[]
	for p in [Vector3(21,0,-3),Vector3(21,0,-1.8),Vector3(20,0,-3),Vector3(-21,0,-15),Vector3(-20,0,-15),Vector3(-21,0,19),Vector3(-15,0,19)]:
		barrels.append(Transform3D(Basis.IDENTITY,p))
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=CylinderShape3D.new()
		shape.radius=.38;shape.height=1.04;collision.shape=shape;collision.position.y=.52;body.add_child(collision);body.position=p;add_child(body);collision_bodies.append(body)
	_instances("Fuel storage",barrel_mesh,barrels,70)
	var bags: Array[Transform3D]=[]
	for center: Vector3 in [Vector3(-4.6,0,10.4),Vector3(4.6,0,17.4),Vector3(-10,0,-5),Vector3(10,0,-11)]:
		for row in 3:
			for i in 4:
				var p:=center+Vector3((i-1.5)*.66+(row%2)*.14,row*.26,0)
				bags.append(Transform3D(Basis(Vector3.UP,0.035*sin(i*4+row)),p))
		_body_box("Sandbag cover",center+Vector3(.07,.40,0),Vector3(2.8,.8,.40))
	_instances("Sandbag positions",bag_mesh,bags,65)
	prop_source.free();cargo_source.free()
	for i in range(7):
		var target := TARGET.instantiate()
		add_child(target)
		target.position=Vector3((i-3)*4.5,0,-20+(i%2)*5)
		target.hit.connect(func(point:Vector3):target_hit.emit(point))
		targets.append(target)
	_sign("SECTOR 07   /   RANGE A",Vector3(0,3.8,-23.25),0,70,.008)
	_sign("RANGE SAFETY\nEYE PROTECTION\nMUZZLES DOWNRANGE",Vector3(-20.5,1.8,-15.77),0,38,.004)
	_sign("FIELD OPERATIONS",Vector3(-18,3.05,-7.84),0,54,.007)
	_sign("MAINTENANCE 02",Vector3(13.84,3.25,-1),-PI/2,50,.008)
	_sign("BARRACKS   /   03",Vector3(-17.5,2.9,20.68),0,48,.007)
	_sign("OBSERVATION 07",Vector3(17,4.85,-14.73),0,42,.007)
	for x in [-3.5,3.5]:
		var stripe:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.055,.008,24);stripe.mesh=mesh;stripe.position=Vector3(x,.006,-4);stripe.material_override=_paint();add_child(stripe)
	for z in [-4,-10,-16]:
		_sign("%02d M"%int(abs(z-8)),Vector3(-3.9,.08,z),-PI/2,32,.006)
	_lighting()

func _paint() -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=Color("b2a47d");result.roughness=.95;return result
func _crate(instances:Array[Transform3D],p:Vector3,dimensions:Vector3)->void:
	instances.append(Transform3D(Basis.from_scale(dimensions),p))
	_body_box("Cargo cover",p+Vector3(0,dimensions.y/2,0),dimensions)
func _instances(title:String,mesh:Mesh,transforms:Array[Transform3D],end:float)->void:
	var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=mesh;multi.instance_count=transforms.size()
	for i in transforms.size():multi.set_instance_transform(i,transforms[i])
	var node:=MultiMeshInstance3D.new();node.name=title;node.multimesh=multi;node.visibility_range_end=end;add_child(node)
func _body_box(title:String,point:Vector3,dimensions:Vector3)->void:
	var body:=StaticBody3D.new();body.name=title;body.position=point
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=dimensions;collision.shape=shape;body.add_child(collision);add_child(body);collision_bodies.append(body)
func _sign(caption:String,point:Vector3,yaw:float,font_size:int,pixel_size:float)->void:
	var sign:=Label3D.new();sign.text=caption;sign.font=MilitaryStyle.HEADING;sign.font_size=font_size;sign.pixel_size=pixel_size;sign.position=point;sign.rotation.y=yaw;sign.modulate=Color("e2dac1");sign.set_draw_flag(Label3D.FLAG_DOUBLE_SIDED,false);sign.outline_size=1;sign.outline_modulate=Color("272f30");add_child(sign)
static func _vector(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))
func _lighting()->void:
	var world:=WorldEnvironment.new();environment=Environment.new();var sky:=Sky.new();var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_curve=.55;sky_material.sky_top_color=Color("426b8b");sky_material.sky_horizon_color=Color("bcc9cc");sky_material.ground_bottom_color=Color("48515a");sky_material.ground_horizon_color=Color("9fa9a7");sky.sky_material=sky_material
	environment.background_mode=Environment.BG_SKY;environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("b9cddd");environment.ambient_light_energy=.34
	environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.tonemap_exposure=.95
	environment.fog_light_color=Color("a9bac3");environment.fog_light_energy=.65;environment.fog_density=.0015
	world.environment=environment;add_child(world)
	sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-32,0);sun.light_color=Color("ffe9d0");sun.light_energy=1.05;sun.directional_shadow_max_distance=55
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
func apply_quality()->void:
	sun.shadow_enabled=Settings.values.quality>0;environment.fog_enabled=Settings.values.quality>0
