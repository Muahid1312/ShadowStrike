extends Node
## ENet session/roster authority. No positions are ever accepted from clients.
signal roster_changed
signal status_changed(message: String)
signal lobby_opened
signal match_loading(assignments: Dictionary)
signal match_live
signal snapshot_received(tick: int, frames: Array)
signal ended(message: String)
signal combat_intent(id: int, sequence: int, life: int, fire: bool, reload_request: bool, aim: Vector2, movement_sequence: int)
signal combat_updated
signal combat_event_received(event: Dictionary)
signal fall_reported(id: int)
const PROTOCOL := 4
const DEFAULT_PORT := 7777
const CONNECT_TIMEOUT := 10.0
const LOAD_TIMEOUT := 25.0
const INPUT_HZ := 20.0
const SPAWNS := [Vector3(-3, 0.05, 8), Vector3(3, 0.05, 8), Vector3(-3, 0.05, 15), Vector3(3, 0.05, 15)]
var phase := "idle"
var roster: Dictionary = {}
var assignments: Dictionary = {}
var max_players := 4
var port := DEFAULT_PORT
var status := "Offline • direct LAN only"
var peer: ENetMultiplayerPeer
var display_name := "Operator"
var deadline := 0.0
var pending: Dictionary = {}
var queues: Dictionary = {}
var processed: Dictionary = {}
var packet_budget: Dictionary = {}
var action_times: Dictionary = {}
var epoch := 0
var last_snapshot := -1
var snapshot_age := 0.0
var rejected_inputs := 0
var sent_batches := 0
var received_snapshots := 0
var combat_states: Dictionary = {}
var seen_combat_events: Dictionary = {}
var combat_sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The protocol is a star: clients only talk to authority 1. Avoid automatic
	# client-to-client relay/peer announcements, including sends to closing peers.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _connect_failed("Could not connect. Check host IP, UDP port and Wi-Fi isolation."))
	multiplayer.server_disconnected.connect(func():
		if phase == "connecting":
			_connect_failed("Could not connect: host refused the session (full or match active), or closed it.")
		elif active():
			_close("Host disconnected. No host migration is available.", true))

func active() -> bool:
	return phase != "idle"

func is_host() -> bool:
	return peer != null and multiplayer.is_server()

func in_match() -> bool:
	return phase == "loading" or phase == "match"

func local_id() -> int:
	return multiplayer.get_unique_id() if peer != null else 0

func set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

static func valid_name(value: String) -> bool:
	if value != value.strip_edges() or value.is_empty() or value.length() > 20:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		if code < 32 or code == 127 or (code >= 0x202a and code <= 0x202e):
			return false
	return true

static func valid_address(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 4 or not value.is_valid_ip_address():
		return false
	for part in parts:
		if not part.is_valid_int() or str(int(part)) != part:
			return false
	return int(parts[0]) > 0 and int(parts[0]) < 224 and int(parts[3]) < 255

static func private_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if not valid_address(address):
			continue
		var part := address.split(".")
		if int(part[0]) == 10 or (int(part[0]) == 172 and int(part[1]) >= 16 and int(part[1]) <= 31) or (int(part[0]) == 192 and int(part[1]) == 168) or (int(part[0]) == 169 and int(part[1]) == 254):
			if not result.has(address):
				result.append(address)
	result.sort()
	return result

func host_game(player_name: String, limit: int, udp_port: int) -> bool:
	if active():
		set_status("Leave the existing session before hosting another.")
		return false
	if not valid_name(player_name) or limit < 2 or limit > 4 or udp_port < 1024 or udp_port > 65535:
		set_status("Use a 1–20 character name, 2–4 players and port 1024–65535.")
		return false
	var candidate := ENetMultiplayerPeer.new()
	candidate.set_bind_ip("0.0.0.0")
	var error := candidate.create_server(udp_port, limit - 1, 3)
	if error != OK:
		candidate.close()
		set_status("Cannot bind UDP port %d: %s" % [udp_port, error_string(error)])
		return false
	peer = candidate
	multiplayer.multiplayer_peer = peer
	phase = "lobby"
	Rules.clear_session()
	port = udp_port
	max_players = limit
	display_name = player_name
	roster = {1: {"name": player_name, "ready": true, "loaded": false, "slot": 0}}
	set_status("Hosting UDP %d • share a local IPv4 address with your squad" % port)
	lobby_opened.emit()
	roster_changed.emit()
	return true

func join_game(player_name: String, address: String, udp_port: int) -> bool:
	if active():
		set_status("A session is already active or connecting.")
		return false
	if not valid_name(player_name) or not valid_address(address) or udp_port < 1024 or udp_port > 65535:
		set_status("Enter a valid name, numeric IPv4 address and port 1024–65535.")
		return false
	var candidate := ENetMultiplayerPeer.new()
	var error := candidate.create_client(address, udp_port, 3)
	if error != OK:
		candidate.close()
		set_status("Cannot create client: " + error_string(error))
		return false
	peer = candidate
	multiplayer.multiplayer_peer = peer
	display_name = player_name
	port = udp_port
	phase = "connecting"
	Rules.clear_session()
	deadline = CONNECT_TIMEOUT
	set_status("Connecting to %s:%d… (10-second timeout)" % [address, port])
	return true

func _connected() -> void:
	if phase == "connecting":
		peer.get_peer(1).set_timeout(32, 3000, 6000)
		_register.rpc_id(1, display_name, PROTOCOL)
		set_status("Connected • waiting for host roster…")

func _peer_connected(id: int) -> void:
	if not is_host():
		return
	peer.get_peer(id).set_timeout(32, 3000, 6000)
	if phase != "lobby":
		peer.disconnect_peer(id)
		return
	pending[id] = 8.0
	# Limits silent half-joined peers and bounds the application handshake.
	_publish_roster()

@rpc("any_peer", "call_remote", "reliable", 0)
func _register(player_name: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not pending.has(id):
		return
	if phase != "lobby" or roster.size() >= max_players or not valid_name(player_name) or protocol != PROTOCOL:
		peer.disconnect_peer(id)
		return
	var slot := 0
	var occupied: Array = []
	for player in roster.values():
		occupied.append(player.slot)
	while occupied.has(slot):
		slot += 1
	roster[id] = {"name": player_name, "ready": false, "loaded": false, "slot": slot}
	pending.erase(id)
	_publish_roster()
	Rules.send_settings(id)

func _publish_roster() -> void:
	if not is_host():
		return
	send_connected(self, "_roster", [roster, max_players, phase])
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _roster(players: Dictionary, limit: int, host_phase: String) -> void:
	if is_host() or players.size() > 4:
		return
	var first := phase == "connecting"
	roster = players.duplicate(true)
	for id in combat_states.keys():
		if not roster.has(id):
			combat_states.erase(id)
	max_players = limit
	if first and roster.has(local_id()):
		phase = "lobby"
		deadline = 0
		set_status("Connected to host • UDP %d" % port)
		lobby_opened.emit()
	# Match transitions arrive via dedicated authority RPCs, not roster side effects.
	if host_phase == "lobby" or in_match():
		roster_changed.emit()

func set_ready(value: bool) -> void:
	if phase == "lobby" and not is_host() and roster.has(local_id()):
		_ready_request.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable", 0)
func _ready_request(value: bool) -> void:
	if not is_host() or phase != "lobby":
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or not _action_allowed(id):
		return
	roster[id].ready = value
	_publish_roster()

func _action_allowed(id: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(action_times.get(id, -1000)) < 120:
		return false
	action_times[id] = now
	return true

func can_start() -> bool:
	if not is_host() or phase != "lobby" or Rules.stage != "LOBBY" or roster.size() < 2 or not pending.is_empty():
		return false
	for player in roster.values():
		if not player.ready:
			return false
	return true

func start_match() -> bool:
	if not can_start():
		set_status("At least two players and every client's Ready status are required.")
		return false
	peer.refuse_new_connections = true
	assignments.clear()
	for id in roster:
		assignments[id] = SPAWNS[int(roster[id].slot)]
	epoch = maxi(epoch + 1, int(Time.get_ticks_msec()) + 1)
	send_connected(self, "_launch", [assignments, epoch], true)
	return true

@rpc("authority", "call_local", "reliable", 0)
func _launch(spawns: Dictionary, match_epoch: int) -> void:
	if phase != "lobby" or spawns.size() != roster.size():
		return
	for id in roster:
		if not spawns.has(id) or not spawns[id] is Vector3:
			return
	assignments = spawns.duplicate()
	epoch = match_epoch
	Rules.prepare_round()
	phase = "loading"
	deadline = LOAD_TIMEOUT
	last_snapshot = -1
	sent_batches = 0
	received_snapshots = 0
	rejected_inputs = 0
	snapshot_age = 0
	queues.clear()
	processed.clear()
	combat_states.clear()
	seen_combat_events.clear()
	combat_sequence = 0
	for id in roster:
		roster[id].loaded = false
		queues[id] = []
		processed[id] = 0
	set_status("Loading the arena • waiting for all peers…")
	match_loading.emit(assignments)

func mark_loaded() -> void:
	if phase != "loading":
		return
	if is_host():
		_mark_loaded(1)
	else:
		_loaded.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _loaded(match_epoch: int) -> void:
	if is_host() and phase == "loading" and match_epoch == epoch:
		_mark_loaded(multiplayer.get_remote_sender_id())

func _mark_loaded(id: int) -> void:
	if not roster.has(id):
		return
	roster[id].loaded = true
	for player in roster.values():
		if not player.loaded:
			return
	Rules.begin_countdown()

func release_arena() -> void:
	if is_host() and phase == "loading" and Rules.stage == "PLAYING":
		send_connected(self, "_go", [epoch], true)

@rpc("authority", "call_local", "reliable", 0)
func _go(match_epoch: int) -> void:
	if phase != "loading" or match_epoch != epoch or Rules.stage != "PLAYING":
		return
	phase = "match"
	deadline = 0
	set_status("LAN CONNECTED • %d operators" % roster.size())
	match_live.emit()

static func valid_command(command: Variant) -> bool:
	# [sequence, move_x, move_z, yaw, pitch, sprint, jump, aim]; no dt or position.
	if not command is Array or command.size() != 8 or not command[0] is int:
		return false
	if command[0] < 1 or command[0] > 2147483647:
		return false
	for index in range(1, 5):
		if not (command[index] is float or command[index] is int) or not is_finite(float(command[index])):
			return false
	for index in range(5, 8):
		if not command[index] is bool:
			return false
	return Vector2(command[1], command[2]).length() <= 1.001 and absf(command[3]) <= PI + 0.001 and absf(command[4]) <= deg_to_rad(84) + 0.001

func send_inputs(commands: Array) -> void:
	if Rules.can_play() and not is_host() and not commands.is_empty():
		sent_batches += 1
		_inputs.rpc_id(1, epoch, commands.slice(maxi(0, commands.size() - 12)), int(combat_states.get(local_id(), {}).get("life", 1)))

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _inputs(match_epoch: int, commands: Array, life: int) -> void:
	if not is_host() or not Rules.can_play() or match_epoch != epoch:
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or commands.size() > 12 or commands.is_empty():
		rejected_inputs += 1
		return
	var now := Time.get_ticks_msec()
	var budget: Array = packet_budget.get(id, [now, 0])
	if now - int(budget[0]) >= 1000:
		budget = [now, 0]
	budget[1] += 1
	packet_budget[id] = budget
	if budget[1] > 35:
		rejected_inputs += 1
		return
	for command in commands:
		if not valid_command(command):
			rejected_inputs += 1
			return
	var combat: Dictionary = combat_states.get(id, {})
	if not combat.is_empty() and (int(combat.life) != life or not combat.alive):
		return
	# Sender identity, not a client-supplied peer ID, selects the queue.
	var queue: Array = queues[id]
	for command in commands:
		if command[0] <= processed[id]:
			continue
		var duplicate := false
		for existing in queue:
			if existing[0] == command[0]:
				duplicate = true
		if not duplicate and queue.size() < 24:
			queue.append(command.duplicate())
	queue.sort_custom(func(a: Array, b: Array): return a[0] < b[0])

func consume_input(id: int) -> Array:
	var queue: Array = queues.get(id, [])
	if queue.is_empty():
		return []
	var command: Array = queue.pop_front()
	processed[id] = command[0]
	return command

func broadcast_snapshot(tick: int, frames: Array) -> void:
	if is_host() and phase == "match":
		send_connected(self, "_snapshot", [epoch, tick, frames])

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(match_epoch: int, tick: int, frames: Array) -> void:
	if phase != "match" or epoch != match_epoch or tick <= last_snapshot or frames.size() > 4:
		return
	last_snapshot = tick
	snapshot_age = 0
	received_snapshots += 1
	snapshot_received.emit(tick, frames)

func _peer_disconnected(id: int) -> void:
	if not is_host():
		return
	pending.erase(id)
	roster.erase(id)
	queues.erase(id)
	processed.erase(id)
	packet_budget.erase(id)
	action_times.erase(id)
	combat_states.erase(id)
	_publish_roster()
	if phase == "loading":
		if roster.size() < 2:
			Rules.cancel_loading()
		else:
			_mark_loaded(1)

func leave(message: String = "You left the LAN session.") -> void:
	if not active():
		return
	if is_host():
		send_connected(self, "_shutdown", ["Host closed the session."])
		peer.host.flush()
	_close(message, true)

@rpc("authority", "call_remote", "reliable", 0)
func _shutdown(message: String) -> void:
	_close(message, true)

func _connect_failed(message: String) -> void:
	if phase == "connecting":
		_close(message, false)

func _close(message: String, notify: bool) -> void:
	# Reset before close/signals so repeated disconnect events are harmless.
	phase = "idle"
	var old := peer
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if old:
		old.close()
	roster.clear()
	assignments.clear()
	pending.clear()
	queues.clear()
	processed.clear()
	packet_budget.clear()
	action_times.clear()
	deadline = 0
	Rules.clear_session()
	combat_states.clear()
	seen_combat_events.clear()
	combat_sequence = 0
	set_status(message)
	roster_changed.emit()
	if notify:
		ended.emit(message)

func _process(delta: float) -> void:
	if phase == "connecting":
		deadline -= delta
		if deadline <= 0:
			_connect_failed("Connection timed out. Check IP, port, hotspot routing and client isolation.")
	elif phase == "loading":
		deadline -= delta
		if deadline <= 0:
			leave("Arena load timed out. Return to the lobby and try again.")
	elif phase == "match" and Rules.stage == "PLAYING" and not is_host():
		snapshot_age += delta
		if snapshot_age > 6:
			_close("Host stopped responding. Session closed safely.", true)
	if is_host() and phase == "lobby":
		for id in pending.keys():
			pending[id] -= delta
			if pending[id] <= 0:
				pending.erase(id)
				peer.disconnect_peer(id)

# Combat requests carry intent only. Sender identity and current life are checked on host.
func send_combat_intent(fire: bool, reload_request: bool, aim: Vector2 = Vector2.ZERO, movement_sequence: int = 0) -> void:
	if not Rules.can_play():
		return
	combat_sequence += 1
	var life: int = combat_states.get(local_id(), {}).get("life", 1)
	if is_host():
		combat_intent.emit(1, combat_sequence, life, fire, reload_request, aim, movement_sequence)
	else:
		_combat_request.rpc_id(1, epoch, combat_sequence, life, fire, reload_request, aim, movement_sequence)

@rpc("any_peer", "call_remote", "reliable", 0)
func _combat_request(match_epoch: int, sequence: int, life: int, fire: bool, reload_request: bool, aim: Vector2, movement_sequence: int) -> void:
	if not is_host() or not Rules.can_play() or match_epoch != epoch:
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		combat_intent.emit(id, sequence, life, fire, reload_request, aim, movement_sequence)

func publish_combat(changes: Dictionary) -> void:
	if not is_host() or not in_match() or Rules.stage not in ["COUNTDOWN", "PLAYING"]:
		return
	_apply_combat(changes)
	send_connected(self, "_combat_state", [epoch, changes])

@rpc("authority", "call_remote", "reliable", 0)
func _combat_state(match_epoch: int, changes: Dictionary) -> void:
	if in_match() and match_epoch == epoch and not is_host() and Rules.stage in ["COUNTDOWN", "PLAYING"]:
		_apply_combat(changes)

func _apply_combat(changes: Dictionary) -> void:
	for id in changes:
		if not roster.has(id):
			continue
		var update: Dictionary = changes[id]
		if int(update.revision) <= int(combat_states.get(id, {}).get("revision", -1)):
			continue
		combat_states[id] = update.duplicate(true)
		combat_states[id]["received_at"] = Time.get_ticks_msec()
	combat_updated.emit()

func combat_view(id: int) -> Dictionary:
	var result: Dictionary = combat_states.get(id, {}).duplicate(true)
	if result.is_empty():
		return result
	var elapsed := maxf(0, (Time.get_ticks_msec() - int(result.received_at)) / 1000.0)
	for key in ["reload", "respawn", "protection"]:
		result[key] = maxf(0, float(result[key]) - elapsed)
	return result

func publish_combat_event(event: Dictionary, reliable: bool) -> void:
	if not is_host() or phase != "match":
		return
	_apply_combat_event(event)
	if reliable:
		send_connected(self, "_combat_critical", [epoch, event])
	else:
		send_connected(self, "_combat_transient", [epoch, event])

@rpc("authority", "call_remote", "reliable", 0)
func _combat_critical(match_epoch: int, event: Dictionary) -> void:
	if phase == "match" and match_epoch == epoch and not is_host():
		_apply_combat_event(event)

@rpc("authority", "call_remote", "unreliable", 2)
func _combat_transient(match_epoch: int, event: Dictionary) -> void:
	if phase == "match" and match_epoch == epoch and not is_host():
		_apply_combat_event(event)

func _apply_combat_event(event: Dictionary) -> void:
	var id: int = event.get("event_id", 0)
	if id <= 0 or seen_combat_events.has(id):
		return
	# A bounded sliding window also rejects old duplicates after they leave the map.
	var highest := 0
	for key in seen_combat_events:
		highest = maxi(highest, key)
	if id < highest - 256:
		return
	seen_combat_events[id] = true
	for key in seen_combat_events.keys():
		if key < maxi(id, highest) - 256:
			seen_combat_events.erase(key)
	combat_event_received.emit(event)

func report_fall(id: int) -> void:
	if is_host() and Rules.can_play() and roster.has(id):
		fall_reported.emit(id)

# Only the host's round authority can reopen a finished/cancelled session.
func reopen_lobby() -> void:
	if not is_host() or Rules.stage != "LOBBY" or phase not in ["loading", "match"]:
		return
	var players := roster.duplicate(true)
	for id in players:
		players[id].ready = id == 1
		players[id].loaded = false
	send_connected(self, "_lobby", [epoch, players], true)

@rpc("authority", "call_local", "reliable", 0)
func _lobby(match_epoch: int, players: Dictionary) -> void:
	if match_epoch != epoch or Rules.stage != "LOBBY" or phase not in ["loading", "match"]:
		return
	phase = "lobby"
	if is_host():
		peer.refuse_new_connections = false
	roster = players.duplicate(true)
	assignments.clear()
	queues.clear()
	processed.clear()
	packet_budget.clear()
	action_times.clear()
	combat_states.clear()
	seen_combat_events.clear()
	combat_sequence = 0
	deadline = 0
	set_status("Lobby reopened • clients must choose Ready for a new round")
	roster_changed.emit()
	lobby_opened.emit()

func connected_peers() -> Array[int]:
	var ids: Array[int] = []
	if not is_host():
		return ids
	# SceneMultiplayer can still list a peer until its queued disconnect callback
	# runs, even though ENet has already closed its channels during this poll.
	for id in multiplayer.get_peers():
		var packet: ENetPacketPeer = peer.get_peer(id)
		if packet.get_state() == ENetPacketPeer.STATE_CONNECTED:
			ids.append(id)
	return ids

func send_connected(target: Node, method: String, arguments: Array, include_self: bool = false) -> void:
	if not is_host():
		return
	for id in connected_peers():
		target.callv("rpc_id", [id, method] + arguments)
	if include_self:
		target.callv(method, arguments)
