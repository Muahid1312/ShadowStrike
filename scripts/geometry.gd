class_name Geometry
extends RefCounted
## Shared low polygon geometry with cached materials.
static var materials: Dictionary = {}
static var surface_texture: NoiseTexture2D

static func material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var key := str(color) + str(metallic)
	if not materials.has(key):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = 0.92
		if surface_texture == null:
			var noise := FastNoiseLite.new()
			noise.seed = 1312
			noise.frequency = 0.08
			noise.fractal_octaves = 3
			surface_texture = NoiseTexture2D.new()
			surface_texture.width = 256
			surface_texture.height = 256
			surface_texture.noise = noise
			surface_texture.seamless = true
			var ramp := Gradient.new()
			ramp.set_color(0, Color(0.48, 0.48, 0.48))
			ramp.set_color(1, Color.WHITE)
			surface_texture.color_ramp = ramp
		result.albedo_texture = surface_texture
		result.uv1_triplanar = true
		result.uv1_world_triplanar = true
		result.uv1_scale = Vector3.ONE * 0.8
		result.metallic = metallic
		materials[key] = result
	return materials[key]

static func box(parent: Node3D, pos: Vector3, dimensions: Vector3, color: Color, solid: bool = false) -> Node3D:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.material_override = material(color)
	holder.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = dimensions
		collision.shape = box_shape
		holder.add_child(collision)
	return holder

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 12
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh
