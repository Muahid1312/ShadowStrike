extends Node
var checks := 0
var failures := 0

func check(value: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if value else "FAIL: ") + description)
	if not value:
		failures += 1

func _ready() -> void:
	check(Lan.valid_name("Raven 2"), "ordinary display names accepted")
	check(Lan.valid_name("مجاهد"), "Unicode display names accepted")
	check(not Lan.valid_name("\nGhost"), "control characters rejected")
	check(not Lan.valid_name("  Ghost"), "untrimmed names rejected at authority boundary")
	check(not Lan.valid_name("A".repeat(21)), "oversized display names rejected")
	check(not Lan.valid_name(""), "empty display names rejected")
	for address in ["127.0.0.1", "10.0.0.25", "192.168.53.7", "172.20.10.1"]:
		check(Lan.valid_address(address), "valid direct IPv4 accepted: " + address)
	for address in ["", "host.example", "999.2.3.4", "224.0.0.1", "255.255.255.255", "0.0.0.0", "192.168.001.2", "::1"]:
		check(not Lan.valid_address(address), "invalid/broadcast/non-IPv4 endpoint rejected: " + address)
	var command := [1, 0.7, -0.7, 0.1, 0.1, true, false, false]
	check(Lan.valid_command(command), "bounded input command accepted")
	var invalid := command.duplicate()
	invalid[1] = 5.0
	check(not Lan.valid_command(invalid), "speed-hack axis rejected")
	invalid = command.duplicate()
	invalid[3] = INF
	check(not Lan.valid_command(invalid), "non-finite orientation rejected")
	invalid = command.duplicate()
	invalid[6] = 100
	check(not Lan.valid_command(invalid), "nonboolean action flags rejected")
	invalid = command.duplicate()
	invalid.append(Vector3(900, 900, 900))
	check(not Lan.valid_command(invalid), "extra arbitrary position field rejected")
	check(not Lan.valid_command({"position": Vector3.ZERO}), "state dictionary cannot substitute for input packet")
	check(not Lan.host_game("Host", 5, 7777) and not Lan.active(), "host refuses capacity above four before binding")
	check(not Lan.host_game("Host", 1, 7777), "host refuses capacity below two")
	check(not Lan.join_game("Guest", "127.0.0.1", 0) and not Lan.active(), "invalid port cannot create a session")
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK, "Android export configuration parses")
	check(preset.get_value("preset.0.options", "permissions/internet", false), "Android INTERNET permission enabled for local sockets")
	check(preset.get_value("preset.0.options", "permissions/access_network_state", false), "Android network-state permission configured")
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == 0, "landscape setting preserved")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "mobile", "Mobile renderer preserved")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await get_tree().process_frame
	app.open_lan("host")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	check(app.mode == "menu", "Esc returns from the LAN form")
	app.mode = "match"
	app.pause_game()
	check(app.mode == "match" and not get_tree().paused, "premature focus/pause during network loading is safe")
	app.queue_free()
	await get_tree().process_frame
	Geometry.materials.clear()
	print("NETWORK CONTRACT RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
