extends Node3D
## Owns weapon state; the player supplies intent, the arena owns training progress.
signal fired(hit_target: bool)
signal ammo_changed
const MAGAZINE := 30
const FIRE_INTERVAL := 0.10
const RELOAD_TIME := 1.7
var magazine := MAGAZINE
var reserve := 150
var cooldown := 0.0
var reload_remaining := 0.0
var trigger_held := false
var aiming := false
var shooter: CharacterBody3D
var camera: Camera3D
var flash: MeshInstance3D
var flash_remaining := 0.0
var kick := 0.0
var audio: AudioStreamPlayer
var reload_audio: AudioStreamPlayer
var network_mode := false
var network_alive := true
var pending_reload := false

func _ready() -> void:
	position = Vector3(0.27, -0.26, -0.45)
	var steel := Color("303a3d")
	var black := Color("161e21")
	Geometry.box(self, Vector3(0, 0, -0.15), Vector3(0.11, 0.14, 0.50), steel)
	Geometry.box(self, Vector3(0, -0.025, 0.16), Vector3(0.10, 0.13, 0.22), black)
	Geometry.box(self, Vector3(0, 0.045, -0.51), Vector3(0.075, 0.09, 0.31), black)
	for z in range(6):
		Geometry.box(self, Vector3(0, 0.097, -0.1 - z * 0.065), Vector3(0.09, 0.02, 0.025), Color("515954"))
	Geometry.box(self, Vector3(0, -0.13, -0.08), Vector3(0.075, 0.22, 0.12), black).rotation.x = -0.15
	Geometry.box(self, Vector3(0, -0.13, 0.08), Vector3(0.06, 0.18, 0.07), black).rotation.x = -0.3
	Geometry.box(self, Vector3(0, 0.14, -0.03), Vector3(0.035, 0.09, 0.035), black)
	Geometry.box(self, Vector3(0, 0.13, -0.63), Vector3(0.025, 0.08, 0.025), steel)
	Geometry.box(self, Vector3(0.056, 0, -0.03), Vector3(0.01, 0.05, 0.10), Color("b99342"))
	# Gloved hands and forearms, original block geometry.
	Geometry.box(self, Vector3(0.03, -0.19, 0.12), Vector3(0.12, 0.17, 0.15), Color("444b3a")).rotation.x = -0.3
	Geometry.box(self, Vector3(-0.08, -0.10, -0.40), Vector3(0.13, 0.12, 0.18), Color("444b3a"))
	Geometry.box(self, Vector3(-0.16, -0.24, -0.22), Vector3(0.12, 0.15, 0.37), Color("535a45")).rotation.x = -0.6
	flash = MeshInstance3D.new()
	var flare := SphereMesh.new()
	flare.radius = 0.06
	flare.height = 0.12
	flare.radial_segments = 8
	flare.rings = 4
	flash.mesh = flare
	flash.position = Vector3(0, 0.045, -0.75)
	flash.scale = Vector3(1, 1, 2.5)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffe095")
	flash.material_override = glow
	flash.visible = false
	add_child(flash)
	audio = AudioStreamPlayer.new()
	audio.stream = preload("res://assets/rifle.wav")
	audio.volume_db = -9
	add_child(audio)
	reload_audio = AudioStreamPlayer.new()
	reload_audio.stream = preload("res://assets/reload.wav")
	reload_audio.volume_db = -12
	add_child(reload_audio)

func _physics_process(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	flash_remaining = maxf(0, flash_remaining - delta)
	flash.visible = flash_remaining > 0
	kick = move_toward(kick, 0, delta * 0.5)
	var resting := Vector3(0.0, -0.205, -0.49) if aiming else Vector3(0.27, -0.26, -0.45)
	position = position.lerp(resting + Vector3(0, 0, kick), 1 - exp(-16 * delta))
	rotation.z = lerp_angle(rotation.z, -0.4 if reload_remaining > 0 else 0, 1 - exp(-12 * delta))
	if network_mode:
		return # Presentation only; the host owns all network weapon timers/ammunition.
	if reload_remaining > 0:
		reload_remaining -= delta
		if reload_remaining <= 0:
			var count := mini(MAGAZINE - magazine, reserve)
			magazine += count
			reserve -= count
			ammo_changed.emit()
		return
	if trigger_held:
		shoot()

func shoot() -> bool:
	if network_mode:
		return false # Network fire is collected as intent by LANMatch.
	if cooldown > 0 or reload_remaining > 0 or magazine <= 0:
		return false
	magazine -= 1
	cooldown = FIRE_INTERVAL
	flash_remaining = 0.04
	kick = 0.045
	audio.pitch_scale = randf_range(0.96, 1.04)
	audio.play()
	var origin := camera.global_position
	var destination := origin - camera.global_basis.z * 150
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.exclude = [shooter.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var valid_hit := false
	if not result.is_empty():
		var collider: Object = result.collider
		if collider.has_method("receive_hit"):
			valid_hit = collider.receive_hit(result.position)
	shooter.recoil(0.007 if aiming else 0.012)
	ammo_changed.emit()
	fired.emit(valid_hit)
	return true

func reload() -> bool:
	if network_mode:
		if not network_alive or reload_remaining > 0 or magazine >= MAGAZINE or reserve <= 0:
			return false
		pending_reload = true
		return true
	if reload_remaining > 0 or magazine == MAGAZINE or reserve <= 0:
		return false
	reload_remaining = RELOAD_TIME
	reload_audio.play()
	ammo_changed.emit()
	return true

func resupply() -> void:
	magazine = MAGAZINE
	reserve = 150
	reload_remaining = 0
	cooldown = 0
	ammo_changed.emit()

func apply_server_state(state: Dictionary) -> void:
	var changed := magazine != int(state.magazine) or reserve != int(state.reserve)
	magazine = state.magazine
	reserve = state.reserve
	reload_remaining = state.reload
	network_alive = state.alive
	if changed:
		ammo_changed.emit()

func confirmed_shot(hit: bool) -> void:
	flash_remaining = 0.045
	kick = 0.045
	audio.pitch_scale = randf_range(0.96, 1.04)
	audio.play()
	shooter.recoil(0.007 if aiming else 0.012)
	fired.emit(hit)

func confirmed_reload() -> void:
	reload_audio.play()
