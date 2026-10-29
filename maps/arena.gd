extends Node3D
signal target_hit(position: Vector3)
const TARGET := preload("res://maps/target.tscn")
var targets: Array[Node3D] = []
var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	build()
	Settings.changed.connect(apply_quality)
	apply_quality()

func build() -> void:
	var sand := Color("8e8165")
	var concrete := Color("686f69")
	var dark := Color("323b3a")
	Geometry.box(self, Vector3(0, -0.4, 0), Vector3(64, 0.8, 64), sand, true)
	for x in [-24, 24]:
		Geometry.box(self, Vector3(x, 2, 0), Vector3(0.8, 4, 48), concrete, true)
		for z in range(-24, 25, 6):
			Geometry.box(self, Vector3(x, 2.2, z), Vector3(1.1, 4.5, 0.5), dark)
	for z in [-24, 24]:
		Geometry.box(self, Vector3(0, 2, z), Vector3(48, 4, 0.8), concrete, true)
	# Distant mesas form an original, inexpensive skyline.
	for i in range(15):
		var x := float(i - 7) * 9.0
		var hill := Geometry.box(self, Vector3(x, 1.5, -38 - (i % 3) * 4), Vector3(11, 9 + (i % 4) * 2, 12), Color("6d776c"))
		hill.rotation.z = sin(i * 3.0) * 0.18
	for pos in [Vector3(-7, 0, -2), Vector3(9, 0, -7), Vector3(-12, 0, -12), Vector3(12, 0, 10), Vector3(-5, 0, 13)]:
		crate(pos, Vector3(2.5, 2.0, 2.0))
		if pos.x < 0:
			crate(pos + Vector3(0.2, 2, 0), Vector3(1.7, 1.6, 1.7))
	for pos in [Vector3(-6, 0.65, -9), Vector3(5, 0.65, 2), Vector3(0, 0.65, -17)]:
		Geometry.box(self, pos, Vector3(4.5, 1.3, 0.8), concrete, true)
		Geometry.box(self, pos + Vector3(0, 0.72, 0), Vector3(4.7, 0.18, 1), dark)
	# Hazard markings on the protected face of cover.
	for position in [Vector3(-6, 0.65, -9), Vector3(5, 0.65, 2), Vector3(0, 0.65, -17)]:
		for stripe in range(9):
			var paint := Geometry.box(self, position + Vector3(-1.6 + stripe * 0.4, 0, 0.413), Vector3(0.15, 0.32, 0.018), Color("c2a557") if stripe % 2 == 0 else Color("363f38"))
			paint.rotation.z = -0.4
	# Painted lanes and range markers.
	for x in [-3.5, 3.5]:
		Geometry.box(self, Vector3(x, 0.015, -4), Vector3(0.07, 0.015, 24), Color("c5b16d"))
	for z in [-4, -10, -16]:
		Geometry.box(self, Vector3(0, 0.02, z), Vector3(7, 0.02, 0.08), Color("c5b16d"))
	watchtower(Vector3(17, 0, -17))
	for i in range(7):
		var target := TARGET.instantiate()
		add_child(target)
		target.position = Vector3((i - 3) * 4.5, 0, -20 + (i % 2) * 5)
		target.hit.connect(func(point: Vector3): target_hit.emit(point))
		targets.append(target)
	var sign := Label3D.new()
	sign.text = "SECTOR 07   /   LIVE FIRE RANGE"
	sign.font_size = 100
	sign.pixel_size = 0.009
	sign.modulate = Color("e7c369")
	sign.position = Vector3(0, 3.2, -23.4)
	add_child(sign)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("455e68")
	sky_material.sky_horizon_color = Color("c2bd9f")
	sky_material.ground_bottom_color = Color("6b6658")
	sky_material.ground_horizon_color = Color("bcb394")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bac3ba")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_light_color = Color("b5b49e")
	environment.fog_density = 0.003
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -32, 0)
	sun.light_color = Color("ffe1aa")
	sun.light_energy = 1.05
	sun.directional_shadow_max_distance = 48.0
	add_child(sun)

func crate(pos: Vector3, dimensions: Vector3) -> void:
	var wood := Color("746044")
	Geometry.box(self, pos + Vector3(0, dimensions.y / 2, 0), dimensions, wood, true)
	for plank in range(1, 5):
		Geometry.box(self, pos + Vector3(0, dimensions.y * plank / 5.0, dimensions.z / 2 + 0.01), Vector3(dimensions.x, 0.022, 0.02), Color("4b4938"))
	for dx in [-1, 1]:
		Geometry.box(self, pos + Vector3(dx * (dimensions.x / 2 - 0.12), dimensions.y / 2, dimensions.z / 2 + 0.02), Vector3(0.17, dimensions.y, 0.08), Color("433f30"))
	for y in [0.15, dimensions.y - 0.15]:
		Geometry.box(self, pos + Vector3(0, y, dimensions.z / 2 + 0.04), Vector3(dimensions.x, 0.12, 0.08), Color("b09a69"))

func watchtower(pos: Vector3) -> void:
	for x in [-1.8, 1.8]:
		for z in [-1.8, 1.8]:
			Geometry.box(self, pos + Vector3(x, 2.5, z), Vector3(0.28, 5, 0.28), Color("4d5145"), true)
	Geometry.box(self, pos + Vector3(0, 5, 0), Vector3(4.5, 0.3, 4.5), Color("656752"), true)
	Geometry.box(self, pos + Vector3(0, 7.4, 0), Vector3(5, 0.3, 5), Color("3e4741"))
	for x in [-2, 2]:
		Geometry.box(self, pos + Vector3(x, 6.15, 0), Vector3(0.15, 2.2, 4.2), Color("555e50"))
	Geometry.box(self, pos + Vector3(0, 5.6, 2.1), Vector3(4.2, 0.9, 0.15), Color("555e50"))

func apply_quality() -> void:
	sun.shadow_enabled = Settings.values.quality > 0
	environment.fog_enabled = Settings.values.quality > 0
