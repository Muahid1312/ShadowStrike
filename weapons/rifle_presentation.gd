class_name RiflePresentation
extends Node3D
## Camera-child art only. Never writes camera aim, ammo, hitboxes or network state.
const MODEL := preload("res://assets/weapons/ar01/AR01.glb")
const HIP := Vector3(0.18, -0.155, -0.43)
const ADS := Vector3(0.0, -0.125, -0.42)
var model: Node3D
var magazine: Node3D
var support_hand: Node3D
var support_arm: Node3D
var firing_arm: Node3D
var firing_hand: Node3D
var eye: Camera3D
var muzzle: Node3D
var flash: MeshInstance3D
var magazine_home: Transform3D
var hand_home: Transform3D
var elbow := Vector3(-0.185, -0.28, 0.20)
var phase := 0.0
var stride := 0.0
var aim_blend := 0.0
var sprint_blend := 0.0
var reload_blend := 0.0
var reload_length := 1.7
var reload_progress := 0.0
var reload_active := false
var was_alive := true

func _ready() -> void:
	eye = get_parent().get_parent() as Camera3D
	model = MODEL.instantiate()
	add_child(model)
	magazine = model.find_child("Magazine", true, false)
	support_hand = model.find_child("SupportHand", true, false)
	support_arm = model.find_child("SupportForearm", true, false)
	firing_arm = model.find_child("FiringForearm", true, false)
	firing_hand = model.find_child("FiringHand", true, false)
	muzzle = model.find_child("Muzzle", true, false)
	magazine_home = magazine.transform
	hand_home = support_hand.transform
	# Tiny billboard, no dynamic light, particles or runtime texture generation.
	flash = MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.16)
	flash.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = preload("res://assets/weapons/ar01/muzzle_flash.png")
	material.no_depth_test = false
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(flash)
	flash.visible = false
	position = HIP
	_follow_support_arm()

func start_reload(duration: float, remaining: float = -1.0) -> void:
	reload_length = maxf(0.1, duration)
	reload_active = true
	if remaining >= 0:
		reload_progress = clampf(1.0 - remaining / reload_length, 0, 1)
	else:
		reload_progress = 0

func reset_pose() -> void:
	reload_active = false
	reload_progress = 0
	reload_blend = 0
	magazine.transform = magazine_home
	support_hand.transform = hand_home
	_follow_support_arm()

func update_pose(delta: float, aimed: bool, body: CharacterBody3D, recoil: float, remaining: float, alive: bool) -> void:
	phase += delta
	var blend := 1.0 - exp(-14.0 * delta)
	if not alive or not was_alive:
		reset_pose()
	was_alive = alive
	if remaining > 0:
		if not reload_active:
			start_reload(2.0 if body.network_role != "offline" else 1.7, remaining)
		reload_progress = clampf(1.0 - remaining / reload_length, 0, 1)
	elif reload_active:
		reload_active = false
		reload_progress = 1
	reload_blend = lerpf(reload_blend, 1.0 if reload_active else 0.0, blend)
	aim_blend = lerpf(aim_blend, 1.0 if aimed and not reload_active else 0.0, blend)
	var speed := Vector2(body.velocity.x, body.velocity.z).length() if body.input_enabled and alive else 0.0
	var moving := clampf(speed / 4.1, 0, 1)
	stride += delta * speed * 2.5
	sprint_blend = lerpf(sprint_blend, 1.0 if body.running and not aimed and not reload_active and moving > 0.1 else 0.0, blend)
	var resting := HIP.lerp(ADS, aim_blend)
	resting += Vector3(0.035, -0.075, -0.035) * sprint_blend
	var breathe := Vector3(sin(phase * 1.35) * 0.0011, sin(phase * 2.0) * 0.0012, 0)
	var bob := Vector3(sin(stride) * 0.0035, absf(cos(stride)) * 0.004 - 0.002, 0) * moving
	resting += (breathe + bob) * lerpf(1.0, 0.12, aim_blend)
	resting += Vector3(0.0, 0.100, -0.220) * reload_blend
	resting.z += recoil * 0.45
	position = position.lerp(resting, blend)
	var angles := Vector3(-0.012, 0.015, -0.018) * (1 - aim_blend)
	angles += Vector3(-0.22, 0.25, -0.19) * sprint_blend
	angles += Vector3(0.10, -0.13, -0.32) * reload_blend
	angles.x += recoil * 1.05
	angles.z += sin(stride) * 0.009 * moving * (1.0 - aim_blend)
	rotation = rotation.lerp(angles, blend)
	_animate_reload()

func _animate_reload() -> void:
	# All offsets follow host remaining-time in LAN; no gameplay timer is changed.
	var p := reload_progress
	var reach := smoothstep(0.0, 0.18, p) * (1.0 - smoothstep(0.80, 1.0, p)) if reload_active else 0.0
	var out := smoothstep(0.20, 0.38, p) * (1.0 - smoothstep(0.55, 0.78, p)) if reload_active else 0.0
	magazine.position = magazine_home.origin + Vector3(-0.025, -0.120, 0.045) * out
	magazine.rotation = Vector3(-0.14, 0.0, -0.20) * out
	support_hand.position = hand_home.origin + Vector3(-0.040, -0.080, 0.292) * reach + Vector3(-0.025, -0.120, 0.045) * out
	support_hand.rotation = Vector3(0.0, -0.12, 0.18) * reach
	_follow_support_arm()

func _follow_support_arm() -> void:
	# Sleeves enter from below the camera frustum; moving the gun never reveals
	# a floating elbow cap during reload. No skeleton/IK solver is required.
	_follow_arm(support_arm, support_hand, Vector3(-0.22, -0.40, -0.16))
	_follow_arm(firing_arm, firing_hand, Vector3(0.28, -0.41, -0.16))

func _follow_arm(arm: Node3D, hand: Node3D, anchor: Vector3) -> void:
	var origin := model.to_local(eye.to_global(anchor))
	var wrist := model.to_local(hand.to_global(Vector3(-0.012, -0.015, 0.015)))
	var direction := wrist - origin
	arm.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), origin)
	arm.scale = Vector3(1, 1, direction.length() / 0.5)
