class_name RemoteAvatar
extends Node3D
## Lightweight visual only: no camera, audio listener, input, or player collision.
var head: Node3D
var limbs: Array[Node3D] = []
var samples: Array = []
var walk_time := 0.0
var last_position := Vector3.ZERO
var initialized := false
var slot := 0
var player_name := "Operator"
var flash: MeshInstance3D
var shot_audio: AudioStreamPlayer3D
var reload_audio: AudioStreamPlayer3D
var shield: MeshInstance3D
var flash_time := 0.0
var protection_until := 0
var alive := true
var shots_seen := 0
var reload_pose := 0.0
var weapon: Node3D

func _ready() -> void:
	var colors := [Color("c9ad60"), Color("6799ac"), Color("9aa96b"), Color("b47c6a")]
	var uniform: Color = colors[slot % 4]
	Geometry.box(self, Vector3(0, 1.13, 0), Vector3(0.55, 0.65, 0.3), uniform)
	Geometry.box(self, Vector3(0, 1.12, -0.18), Vector3(0.43, 0.46, 0.1), Color("303c35"))
	head = Node3D.new()
	add_child(head)
	head.position.y = 1.68
	Geometry.box(head, Vector3.ZERO, Vector3(0.32, 0.34, 0.31), Color("a69474"))
	Geometry.box(head, Vector3(0, 0.12, 0), Vector3(0.38, 0.16, 0.37), uniform.darkened(0.25))
	Geometry.box(head, Vector3(0, 0, -0.165), Vector3(0.28, 0.12, 0.03), Color("252f30"))
	for side in [-1, 1]:
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(side * 0.17, 0.8, 0)
		Geometry.box(leg, Vector3(0, -0.36, 0), Vector3(0.22, 0.7, 0.25), uniform.darkened(0.3))
		Geometry.box(leg, Vector3(0, -0.72, -0.05), Vector3(0.24, 0.15, 0.35), Color("242f2c"))
		limbs.append(leg)
		Geometry.box(self, Vector3(side * 0.37, 1.2, -0.08), Vector3(0.19, 0.45, 0.22), uniform).rotation.x = -0.65
	weapon = Geometry.box(self, Vector3(0.22, 1.25, -0.48), Vector3(0.1, 0.12, 0.7), Color("293537"))
	var label := Label3D.new()
	label.text = player_name
	label.font = MilitaryStyle.HEADING
	label.font_size = 40
	label.pixel_size = 0.007
	label.position.y = 2.12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = uniform.lightened(0.3)
	add_child(label)
	flash = Geometry.cylinder(self, Vector3(0.22, 1.25, -0.86), 0.07, 0.12, Color("ffe195"))
	flash.rotation.x = PI / 2
	flash.visible = false
	shield = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.5
	ring.rings = 12
	ring.ring_segments = 4
	shield.mesh = ring
	shield.position.y = 0.05
	shield.material_override = Geometry.material(MilitaryStyle.GOLD)
	add_child(shield)
	shield.visible = false
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = preload("res://assets/rifle.wav")
	shot_audio.volume_db = -6
	shot_audio.max_distance = 45
	shot_audio.unit_size = 5
	shot_audio.position.y = 1.3
	add_child(shot_audio)
	reload_audio = AudioStreamPlayer3D.new()
	reload_audio.stream = preload("res://assets/reload.wav")
	reload_audio.volume_db = -10
	reload_audio.max_distance = 18
	reload_audio.position.y = 1.2
	add_child(reload_audio)

func push_state(frame: Array) -> void:
	var sample := {"time": Time.get_ticks_msec() / 1000.0, "position": frame[1], "yaw": frame[3], "pitch": frame[4], "running": frame[5], "grounded": frame[6]}
	samples.append(sample)
	if samples.size() > 8:
		samples.pop_front()
	if not initialized:
		position = frame[1]
		rotation.y = frame[3]
		last_position = position
		initialized = true

func _process(delta: float) -> void:
	flash_time = maxf(0, flash_time - delta)
	flash.visible = flash_time > 0 and alive
	shield.visible = alive and Time.get_ticks_msec() < protection_until
	reload_pose = maxf(0, reload_pose - delta)
	weapon.rotation.z = lerp_angle(weapon.rotation.z, -0.45 if reload_pose > 0 else 0.0, 1 - exp(-12 * delta))
	if not samples.is_empty():
		# Render about two 20 Hz snapshots behind receipt; no runaway extrapolation.
		var render_time := Time.get_ticks_msec() / 1000.0 - 0.10
		while samples.size() >= 2 and samples[1].time <= render_time:
			samples.pop_front()
		var first: Dictionary = samples[0]
		var second: Dictionary = samples[1] if samples.size() > 1 else first
		var blend := clampf((render_time - first.time) / maxf(0.001, second.time - first.time), 0, 1)
		position = (first.position as Vector3).lerp(second.position, blend)
		rotation.y = lerp_angle(first.yaw, second.yaw, blend)
		head.rotation.x = lerpf(first.pitch, second.pitch, blend) - (0.14 if reload_pose > 0 else 0.0)
	var distance := position.distance_to(last_position)
	walk_time += distance * 7
	for i in limbs.size():
		limbs[i].rotation.x = sin(walk_time + i * PI) * minf(0.55, distance / maxf(delta, 0.001) * 0.1)
	last_position = position

func apply_combat(state: Dictionary, changed_life: bool) -> void:
	protection_until = Time.get_ticks_msec() + int(float(state.protection) * 1000)
	if changed_life:
		samples.clear()
		initialized = false
		position = state.spawn
		last_position = position
		scale = Vector3.ONE
	if alive != state.alive:
		alive = state.alive
		if alive:
			scale = Vector3.ONE
		else:
			create_tween().tween_property(self, "scale", Vector3(1, 0.24, 1), 0.18)

func show_shot() -> void:
	shots_seen += 1
	flash_time = 0.055
	shot_audio.pitch_scale = randf_range(0.96, 1.04)
	shot_audio.play()

func show_reload() -> void:
	reload_pose = 2.0
	reload_audio.play()
