extends StaticBody3D
signal hit(point: Vector3)
var available := true
var cooldown := 0.0
var plate: MeshInstance3D
var base_color := Color("b8b7a0")

func _ready() -> void:
	set_process(false)
	var source: Node3D = preload("res://assets/sector07/props.glb").instantiate()
	var frame: MeshInstance3D = source.find_child("TargetFrame",true,false)
	plate = source.find_child("TargetPlate",true,false)
	frame.get_parent().remove_child(frame)
	plate.get_parent().remove_child(plate)
	frame.owner = null
	plate.owner = null
	add_child(frame)
	add_child(plate)
	source.free()
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
	plate.material_override = preload("res://assets/sector07/target_flash.tres")
	hit.emit(point)
	return true

func _process(delta: float) -> void:
	if not available:
		cooldown -= delta
		if cooldown <= 0:
			available = true
			set_process(false)
			plate.material_override = null
