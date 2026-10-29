class_name TouchHUD
extends Control
## Each contact owns exactly one role until release; actions never steal look/joystick.
signal jump_requested
signal reload_requested
var movement := Vector2.ZERO
var look_delta := Vector2.ZERO
var firing := false
var sprinting := false
var aiming := false
var contacts: Dictionary = {}
var joystick_tip := Vector2.ZERO
var controls_visible := true
var joystick_center := Vector2.ZERO
var joystick_radius := 76.0
var zones: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MilitaryStyle.full(self)
	Settings.changed.connect(queue_redraw)
	resized.connect(queue_redraw)

func layout_controls() -> void:
	joystick_radius = 76 * Settings.values.joystick_size
	joystick_center = Vector2(56 + joystick_radius, size.y - 100 - joystick_radius)
	zones = {
		"fire": Rect2(size.x - 166, size.y - 212, 116, 116),
		"reload": Rect2(size.x - 264, size.y - 112, 80, 80),
		"jump": Rect2(size.x - 112, size.y - 106, 80, 80),
		"sprint": Rect2(size.x - 365, size.y - 112, 80, 80),
		"aim": Rect2(size.x - 272, size.y - 215, 80, 80)
	}

func _draw() -> void:
	if not controls_visible:
		return
	layout_controls()
	draw_circle(joystick_center, joystick_radius, Color(0.04, 0.065, 0.065, 0.4))
	draw_arc(joystick_center, joystick_radius, 0, TAU, 48, Color(0.9, 0.92, 0.83, 0.35), 2, true)
	draw_arc(joystick_center, joystick_radius * 0.55, 0, TAU, 40, Color(0.9, 0.92, 0.83, 0.15), 1, true)
	draw_circle(joystick_center + joystick_tip * joystick_radius * 0.65, 28, Color(0.8, 0.82, 0.72, 0.3))
	for key in zones:
		var zone: Rect2 = zones[key]
		var active: bool = (key == "fire" and firing) or (key == "sprint" and sprinting) or (key == "aim" and aiming)
		var color := MilitaryStyle.GOLD if active or key == "fire" else Color("d6dacb")
		draw_circle(zone.get_center(), zone.size.x / 2, Color(0.04, 0.06, 0.055, 0.72))
		draw_arc(zone.get_center(), zone.size.x / 2, 0, TAU, 40, Color(color, 0.8), 2, true)
		var caption: String = {"fire": "FIRE", "reload": "RLD", "jump": "JUMP", "sprint": "RUN", "aim": "AIM"}[key]
		var width := MilitaryStyle.HEADING.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(MilitaryStyle.HEADING, zone.get_center() + Vector2(-width / 2, 7), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)

func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			begin_contact(event.index, event.position)
		else:
			end_contact(event.index)
	elif event is InputEventScreenDrag and contacts.has(event.index):
		var role: String = contacts[event.index]
		if role == "move":
			move_contact(event.position)
		elif role == "look":
			look_delta += event.relative
		get_viewport().set_input_as_handled()

func begin_contact(index: int, point: Vector2) -> void:
	layout_controls()
	# Top strip belongs to GUI pause / objective controls.
	if point.y < 110:
		return
	var role := ""
	for key in zones:
		if zones[key].has_point(point) and not contacts.values().has(key):
			role = key
			break
	if role.is_empty() and point.distance_to(joystick_center) < joystick_radius * 1.5 and not contacts.values().has("move"):
		role = "move"
	if role.is_empty() and point.x > size.x * 0.38 and not contacts.values().has("look"):
		role = "look"
	if role.is_empty():
		return
	contacts[index] = role
	match role:
		"move": move_contact(point)
		"fire": firing = true
		"sprint": sprinting = true
		"aim": aiming = true
		"jump": jump_requested.emit()
		"reload": reload_requested.emit()
	queue_redraw()
	get_viewport().set_input_as_handled()

func move_contact(point: Vector2) -> void:
	joystick_tip = ((point - joystick_center) / joystick_radius).limit_length()
	movement = joystick_tip if joystick_tip.length() > 0.12 else Vector2.ZERO
	queue_redraw()

func end_contact(index: int) -> void:
	if not contacts.has(index):
		return
	match contacts[index]:
		"move":
			movement = Vector2.ZERO
			joystick_tip = Vector2.ZERO
		"fire": firing = false
		"sprint": sprinting = false
		"aim": aiming = false
	contacts.erase(index)
	queue_redraw()

func take_look() -> Vector2:
	var result := look_delta
	look_delta = Vector2.ZERO
	return result

func reset() -> void:
	contacts.clear()
	movement = Vector2.ZERO
	look_delta = Vector2.ZERO
	joystick_tip = Vector2.ZERO
	firing = false
	sprinting = false
	aiming = false
	queue_redraw()
