extends StaticBody3D
signal hit(point: Vector3)
var available := true
var cooldown := 0.0
var plate: MeshInstance3D
var base_color := Color("b8b7a0")

func _ready() -> void:
	set_process(false)
	Geometry.box(self, Vector3(0, 0.6, 0), Vector3(0.1, 1.2, 0.15), Color("454e46"))
	Geometry.box(self, Vector3(0, 0.1, 0), Vector3(1.2, 0.2, 0.8), Color("454e46"))
	var body := Geometry.box(self, Vector3(0, 1.65, 0), Vector3(0.95, 1.1, 0.18), base_color)
	plate = body.get_child(0)
	Geometry.box(self, Vector3(0, 2.32, 0), Vector3(0.42, 0.4, 0.18), base_color)
	Geometry.box(self, Vector3(0, 1.73, 0.103), Vector3(0.46, 0.53, 0.02), Color("333d38"))
	Geometry.box(self, Vector3(0, 1.73, 0.12), Vector3(0.2, 0.25, 0.02), Color("d3a84e"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 1.7, 0.22)
	collision.shape = shape
	collision.position.y = 1.85
	add_child(collision)

func receive_hit(point: Vector3) -> bool:
	if not available:
		return false
	available = false
	cooldown = 0.65
	set_process(true)
	plate.material_override = Geometry.material(Color("f5ca5d"))
	hit.emit(point)
	return true

func _process(delta: float) -> void:
	if not available:
		cooldown -= delta
		if cooldown <= 0:
			available = true
			set_process(false)
			plate.material_override = Geometry.material(base_color)
