extends Node
## Listen-host round authority. Loading is a transport substate of LOBBY.
signal stage_changed(stage: String)
signal board_changed
signal settings_changed
const DEFAULT_DURATION := 300
const COUNTDOWN_SECONDS := 3.0
var stage := "LOBBY"
var duration := DEFAULT_DURATION
var kill_limit := 0
var remaining := 0.0
var countdown := 0.0
var board: Array = []
var final_results: Dictionary = {}
var records: Dictionary = {}
var revision := 0
var last_stage_revision := -1
var last_board_revision := -1
var clock_sequence := 0
var last_clock_sequence := -1
var clock_received := 0
var clock_accumulator := 0.0
var pending_finish := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 30 # Combat finishes its tick before the round is finalized.
	Lan.combat_updated.connect(_on_combat)
	Lan.roster_changed.connect(_on_roster)

func can_play() -> bool:
	return stage == "PLAYING" and Lan.phase == "match"

func configure_rules(seconds: int, limit: int) -> bool:
	if not Lan.is_host() or Lan.phase != "lobby" or stage != "LOBBY" or seconds < 5 or seconds > 3600 or limit < 0 or limit > 100:
		return false
	Lan.send_connected(self, "_settings", [seconds, limit], true)
	return true

@rpc("authority", "call_local", "reliable", 0)
func _settings(seconds: int, limit: int) -> void:
	if stage != "LOBBY" or seconds < 5 or seconds > 3600 or limit < 0 or limit > 100:
		return
	duration = seconds
	kill_limit = limit
	settings_changed.emit()

func send_settings(id: int) -> void:
	if Lan.is_host() and Lan.connected_peers().has(id):
		_settings.rpc_id(id, duration, kill_limit)

func clear_session() -> void:
	stage = "LOBBY"
	duration = DEFAULT_DURATION
	kill_limit = 0
	_clear_round()
	revision = 0
	last_stage_revision = -1
	last_board_revision = -1
	stage_changed.emit(stage)
	settings_changed.emit()

func _clear_round() -> void:
	remaining = 0
	countdown = 0
	board.clear()
	final_results.clear()
	records.clear()
	clock_sequence = 0
	last_clock_sequence = -1
	clock_received = Time.get_ticks_msec()
	clock_accumulator = 0
	pending_finish = ""
	board_changed.emit()

func prepare_round() -> void:
	_clear_round()
	last_stage_revision = -1
	last_board_revision = -1
	if Lan.is_host():
		for id in Lan.roster:
			records[id] = {"id": id, "name": Lan.roster[id].name, "eliminations": 0, "deaths": 0, "score": 0, "connected": true}

func begin_countdown() -> bool:
	if not Lan.is_host() or Lan.phase != "loading" or stage != "LOBBY" or Lan.roster.size() < 2:
		return false
	for player in Lan.roster.values():
		if not player.loaded:
			return false
	_publish_stage("COUNTDOWN", {"countdown": COUNTDOWN_SECONDS, "remaining": float(duration), "board": rank_rows(records.values())})
	return true

static func rank_rows(rows: Array) -> Array:
	var ranked := rows.duplicate(true)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.eliminations) != int(b.eliminations):
			return int(a.eliminations) > int(b.eliminations)
		if int(a.deaths) != int(b.deaths):
			return int(a.deaths) < int(b.deaths)
		return int(a.id) < int(b.id))
	for index in ranked.size():
		ranked[index]["rank"] = index + 1
		ranked[index]["score"] = int(ranked[index].eliminations) * 100
	return ranked

func _publish_stage(next: String, payload: Dictionary) -> void:
	if not Lan.is_host():
		return
	revision += 1
	Lan.send_connected(self, "_transition", [Lan.epoch, revision, next, payload], true)

@rpc("authority", "call_local", "reliable", 0)
func _transition(match_epoch: int, serial: int, next: String, payload: Dictionary) -> void:
	if match_epoch != Lan.epoch or serial <= last_stage_revision:
		return
	var legal := (stage == "LOBBY" and next == "COUNTDOWN") or (stage == "COUNTDOWN" and next in ["PLAYING", "LOBBY"]) or (stage == "PLAYING" and next == "RESULTS") or (stage == "RESULTS" and next == "LOBBY")
	if not legal:
		return
	last_stage_revision = serial
	stage = next
	clock_received = Time.get_ticks_msec()
	last_clock_sequence = -1
	if next == "LOBBY":
		_clear_round()
	else:
		remaining = float(payload.get("remaining", duration))
		countdown = float(payload.get("countdown", 0.0))
		if payload.has("board"):
			board = payload.board.duplicate(true)
		if next == "RESULTS":
			final_results = payload.results.duplicate(true)
		board_changed.emit()
	stage_changed.emit(stage)

func _on_combat() -> void:
	if not Lan.is_host() or stage != "PLAYING":
		return
	var changed := false
	for id in Lan.combat_states:
		if not records.has(id):
			continue
		var state: Dictionary = Lan.combat_states[id]
		var row: Dictionary = records[id]
		if row.eliminations != state.eliminations or row.deaths != state.deaths:
			row.eliminations = int(state.eliminations)
			row.deaths = int(state.deaths)
			row.score = int(state.eliminations) * 100
			changed = true
		if kill_limit > 0 and int(row.eliminations) >= kill_limit:
			pending_finish = "Kill limit reached"
	if changed:
		_publish_board()

func _on_roster() -> void:
	if not Lan.is_host() or stage not in ["COUNTDOWN", "PLAYING"]:
		return
	var changed := false
	for id in records:
		var connected := Lan.roster.has(id)
		if records[id].connected != connected:
			records[id].connected = connected
			changed = true
	if changed:
		_publish_board()

func _publish_board() -> void:
	revision += 1
	Lan.send_connected(self, "_scoreboard", [Lan.epoch, revision, rank_rows(records.values())], true)

@rpc("authority", "call_local", "reliable", 0)
func _scoreboard(match_epoch: int, serial: int, rows: Array) -> void:
	if match_epoch != Lan.epoch or serial <= last_board_revision or stage not in ["COUNTDOWN", "PLAYING"]:
		return
	last_board_revision = serial
	board = rows.duplicate(true)
	board_changed.emit()

func finish(reason: String) -> bool:
	if not Lan.is_host() or not can_play():
		return false
	var ranked := rank_rows(records.values())
	var result := {"rows": ranked, "winner_id": ranked[0].id if not ranked.is_empty() else 0,
		"winner_name": ranked[0].name if not ranked.is_empty() else "No operators",
		"reason": reason, "duration": duration, "elapsed": float(duration) - remaining, "epoch": Lan.epoch}
	_publish_stage("RESULTS", {"remaining": remaining, "board": ranked, "results": result})
	return true

func return_to_lobby() -> bool:
	if not Lan.is_host() or stage != "RESULTS" or Lan.phase != "match":
		return false
	_publish_stage("LOBBY", {})
	Lan.reopen_lobby()
	return true

func cancel_loading() -> void:
	if not Lan.is_host() or Lan.phase != "loading":
		return
	if stage == "COUNTDOWN":
		_publish_stage("LOBBY", {})
	Lan.reopen_lobby()

func _physics_process(delta: float) -> void:
	if not Lan.is_host() or not Lan.in_match():
		return
	if stage == "COUNTDOWN":
		countdown = maxf(0, countdown - delta)
		if countdown <= 0:
			_publish_stage("PLAYING", {"remaining": float(duration), "board": board})
			Lan.release_arena()
	elif stage == "PLAYING":
		remaining = maxf(0, remaining - delta)
		if not pending_finish.is_empty() or remaining <= 0:
			var reason := pending_finish if not pending_finish.is_empty() else "Time expired"
			pending_finish = ""
			finish(reason)
	if stage in ["COUNTDOWN", "PLAYING"]:
		clock_accumulator += delta
		if clock_accumulator >= 0.2:
			clock_accumulator = fmod(clock_accumulator, 0.2)
			clock_sequence += 1
			Lan.send_connected(self, "_clock", [Lan.epoch, clock_sequence, stage, remaining, countdown])

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _clock(match_epoch: int, serial: int, host_stage: String, seconds: float, count: float) -> void:
	if match_epoch != Lan.epoch or host_stage != stage or serial <= last_clock_sequence:
		return
	last_clock_sequence = serial
	remaining = maxf(0, seconds)
	countdown = maxf(0, count)
	clock_received = Time.get_ticks_msec()

func seconds_left() -> float:
	if Lan.is_host() or stage != "PLAYING":
		return remaining
	return maxf(0, remaining - (Time.get_ticks_msec() - clock_received) / 1000.0)

func countdown_left() -> float:
	if Lan.is_host():
		return countdown
	return maxf(0, countdown - (Time.get_ticks_msec() - clock_received) / 1000.0)

func clock_text() -> String:
	var seconds := maxi(0, ceili(seconds_left()))
	return "%02d:%02d" % [seconds / 60, seconds % 60]
