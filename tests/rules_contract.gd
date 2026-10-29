extends Node
var count := 0
var failures := 0
func check(value: bool, title: String) -> void:
	count += 1
	print(("PASS: " if value else "FAIL: ") + title)
	if not value:
		failures += 1
func _ready() -> void:
	check(Rules.DEFAULT_DURATION == 300 and Rules.duration == 300, "five-minute FFA default retained")
	check(Rules.kill_limit == 0, "kill limit disabled by default")
	var rows := [
		{"id": 8, "name": "Eight", "eliminations": 3, "deaths": 5, "score": 9999},
		{"id": 9, "name": "Nine", "eliminations": 3, "deaths": 2, "score": -1},
		{"id": 2, "name": "Two", "eliminations": 3, "deaths": 2, "score": 0},
		{"id": 1, "name": "One", "eliminations": 2, "deaths": 0, "score": 9999}]
	var ranked := Rules.rank_rows(rows)
	check(ranked[0].id == 2 and ranked[1].id == 9, "equal eliminations/deaths use stable ID ordering")
	check(ranked[2].id == 8 and ranked[3].id == 1, "eliminations outrank fewer deaths, deaths break elimination ties")
	check(ranked[0].score == 300 and ranked[3].score == 200, "score is derived at 100 points per elimination")
	check(rows[0].score == 9999 and not rows[0].has("rank"), "ranking returns a copy without mutating source records")
	check(not Rules.begin_countdown(), "offline peer cannot initiate countdown")
	check(not Rules.configure_rules(5, 1), "offline/client cannot change a live host's rules")
	check(not Rules.finish("forged"), "non-host cannot force results")
	check(not Rules.return_to_lobby(), "non-host cannot force rematch")
	check(Rules.stage == "LOBBY" and Rules.board.is_empty(), "rejected requests leave state unchanged")
	check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), "menu touch mouse emulation enabled")
	var button := Button.new()
	button.position = Vector2(20, 20)
	button.size = Vector2(200, 80)
	var taps := [0]
	button.pressed.connect(func(): taps[0] += 1)
	add_child(button)
	await get_tree().process_frame
	await get_tree().process_frame
	for down in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = down
		touch.position = get_viewport().get_final_transform() * button.get_global_rect().get_center()
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
	await get_tree().process_frame
	check(taps[0] == 1, "synthetic screen tap activates standard GUI button exactly once")
	print("RULES CONTRACT RESULT: %d checks, %d failures" % [count, failures])
	get_tree().quit(1 if failures else 0)
