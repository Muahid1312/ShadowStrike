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
var presentation: RiflePresentation

func _ready() -> void:
	presentation = RiflePresentation.new()
	presentation.name = "Presentation"
	add_child(presentation)
	flash = presentation.flash
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
	presentation.update_pose(delta, aiming, shooter, kick, reload_remaining, network_alive)
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
	flash.visible = true
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
	presentation.start_reload(RELOAD_TIME)
	reload_audio.play()
	ammo_changed.emit()
	return true

func resupply() -> void:
	magazine = MAGAZINE
	reserve = 150
	reload_remaining = 0
	cooldown = 0
	presentation.reset_pose()
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
	flash.visible = true
	kick = 0.045
	audio.pitch_scale = randf_range(0.96, 1.04)
	audio.play()
	shooter.recoil(0.007 if aiming else 0.012)
	fired.emit(hit)

func confirmed_reload() -> void:
	reload_audio.play()
