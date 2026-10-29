class_name LANPanel
extends PanelContainer
signal back_requested
var kind := "host"
var content: VBoxContainer
var name_field: LineEdit
var address_field: LineEdit
var port_field: LineEdit
var limit_field: OptionButton
var status_label: Label
var players_box: VBoxContainer
var action_button: Button
var start_button: Button
var ready_button: Button
var count_label: Label
var lobby_visible := false
var duration_field: OptionButton
var kill_field: SpinBox
var rules_label: Label

func _ready() -> void:
	theme = MilitaryStyle.theme()
	theme.set_font_size("font_size", "Button", 22)
	for state in ["normal", "hover", "pressed", "focus"]:
		var compact := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		compact.set_content_margin_all(10)
		theme.set_stylebox(state, "Button", compact)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -460
	offset_right = 460
	offset_top = -327
	offset_bottom = 327
	Lan.lobby_opened.connect(show_lobby)
	Lan.roster_changed.connect(refresh_lobby)
	Lan.status_changed.connect(_status)
	Rules.settings_changed.connect(refresh_rules)
	if Lan.phase == "lobby":
		show_lobby()
	else:
		show_form()

func clear_content() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)

func add_status() -> void:
	status_label = MilitaryStyle.label(Lan.status, 17, MilitaryStyle.GOLD)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 38
	content.add_child(status_label)

func field(title: String, value: String, placeholder: String, max_length: int) -> LineEdit:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46
	content.add_child(row)
	var label := MilitaryStyle.label(title, 20)
	label.custom_minimum_size.x = 240
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.custom_minimum_size.y = 46
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit

func show_form() -> void:
	lobby_visible = false
	clear_content()
	content.add_child(MilitaryStyle.label("HOST GAME" if kind == "host" else "JOIN GAME", 36, MilitaryStyle.TEXT, true))
	content.add_child(MilitaryStyle.label("OFFLINE LAN   /   SAME WI-FI OR HOTSPOT", 18, MilitaryStyle.GOLD, true))
	name_field = field("Display name", Lan.display_name, "1–20 characters", 20)
	if kind == "join":
		address_field = field("Host IPv4 address", "", "e.g. 192.168.1.25", 15)
		address_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	else:
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := MilitaryStyle.label("Maximum players", 20)
		label.custom_minimum_size.x = 240
		row.add_child(label)
		limit_field = OptionButton.new()
		for amount in range(2, 5):
			limit_field.add_item("%d OPERATORS" % amount, amount)
		limit_field.selected = 2
		limit_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		limit_field.custom_minimum_size.y = 42
		row.add_child(limit_field)
	port_field = field("UDP port", "7777", "1024–65535", 5)
	port_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	if kind == "host":
		var rules_row := HBoxContainer.new()
		rules_row.custom_minimum_size.y = 46
		rules_row.add_theme_constant_override("separation", 18)
		content.add_child(rules_row)
		rules_row.add_child(MilitaryStyle.label("Match length", 18))
		duration_field = OptionButton.new()
		for item in [["5 MIN • STANDARD", 300], ["1 MIN • QUICK", 60], ["30 SEC • PRACTICE", 30]]:
			duration_field.add_item(item[0], item[1])
		duration_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rules_row.add_child(duration_field)
		rules_row.add_child(MilitaryStyle.label("Kill limit (0 = OFF)", 18))
		kill_field = SpinBox.new()
		kill_field.min_value = 0
		kill_field.max_value = 100
		kill_field.step = 1
		kill_field.custom_minimum_size.x = 115
		rules_row.add_child(kill_field)
	if kind == "host":
		var addresses := Lan.private_addresses()
		var ip_label := MilitaryStyle.label("LOCAL IPv4: " + (", ".join(addresses) if not addresses.is_empty() else "Not detected • check the device's Wi-Fi/hotspot settings"), 18, MilitaryStyle.MUTED)
		ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(ip_label)
		content.add_child(MilitaryStyle.label("Multiple addresses may exist. Use the address reachable from your squad's network.", 15, MilitaryStyle.MUTED))
	else:
		content.add_child(MilitaryStyle.label("Enter the host device's actual LAN address. No discovery or internet service is used.", 15, MilitaryStyle.MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	add_status()
	action_button = MilitaryStyle.button("HOST GAME" if kind == "host" else "JOIN GAME", submit, true)
	content.add_child(action_button)
	content.add_child(MilitaryStyle.button("BACK", func(): back_requested.emit()))

func submit() -> void:
	var port_text := port_field.text.strip_edges()
	if not port_text.is_valid_int():
		Lan.set_status("Port must be an integer from 1024 to 65535.")
		return
	var player_name := name_field.text.strip_edges()
	if kind == "host":
		var seconds := duration_field.get_selected_id()
		var kills := int(kill_field.value)
		if Lan.host_game(player_name, limit_field.get_selected_id(), int(port_text)):
			Rules.configure_rules(seconds, kills)
	else:
		Lan.join_game(player_name, address_field.text.strip_edges(), int(port_text))

func show_lobby() -> void:
	lobby_visible = true
	clear_content()
	content.add_child(MilitaryStyle.label("SQUAD LOBBY", 36, MilitaryStyle.TEXT, true))
	count_label = MilitaryStyle.label("", 20, MilitaryStyle.GOLD)
	content.add_child(count_label)
	rules_label = MilitaryStyle.label("", 17, MilitaryStyle.MUTED)
	content.add_child(rules_label)
	refresh_rules()
	if Lan.is_host():
		var address := MilitaryStyle.label("HOST IPv4: %s   /   UDP %d" % [", ".join(Lan.private_addresses()) if not Lan.private_addresses().is_empty() else "check device network settings", Lan.port], 17, MilitaryStyle.MUTED)
		address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(address)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 6)
	content.add_child(players_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	add_status()
	if Lan.is_host():
		start_button = MilitaryStyle.button("START MATCH", func(): Lan.start_match(), true)
		content.add_child(start_button)
	else:
		ready_button = MilitaryStyle.button("READY", toggle_ready, true)
		content.add_child(ready_button)
	content.add_child(MilitaryStyle.button("LEAVE LOBBY", func(): back_requested.emit()))
	refresh_lobby()

func toggle_ready() -> void:
	if Lan.roster.has(Lan.local_id()):
		Lan.set_ready(not Lan.roster[Lan.local_id()].ready)

func refresh_lobby() -> void:
	if not lobby_visible or not is_instance_valid(players_box):
		return
	count_label.text = "%d / %d OPERATORS   •   CONNECTED" % [Lan.roster.size(), Lan.max_players]
	for child in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	var ids := Lan.roster.keys()
	ids.sort_custom(func(a: int, b: int): return int(Lan.roster[a].slot) < int(Lan.roster[b].slot))
	for id in ids:
		var player: Dictionary = Lan.roster[id]
		var item := PanelContainer.new()
		item.custom_minimum_size.y = 44
		var compact := MilitaryStyle.panel()
		compact.set_content_margin_all(7)
		item.add_theme_stylebox_override("panel", compact)
		players_box.add_child(item)
		var row := HBoxContainer.new()
		item.add_child(row)
		var label := MilitaryStyle.label("%02d   %s%s" % [int(player.slot) + 1, player.name, "  (YOU)" if id == Lan.local_id() else ""], 21, MilitaryStyle.TEXT, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(MilitaryStyle.label("HOST" if id == 1 else ("READY" if player.ready else "NOT READY"), 18, MilitaryStyle.GOLD if player.ready else MilitaryStyle.MUTED))
	if is_instance_valid(start_button):
		start_button.disabled = not Lan.can_start()
		status_label.text = "All clients must be ready. At least two operators are required."
	if is_instance_valid(ready_button) and Lan.roster.has(Lan.local_id()):
		ready_button.text = "NOT READY  /  CANCEL" if Lan.roster[Lan.local_id()].ready else "READY"

func _status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
	if not lobby_visible and is_instance_valid(action_button):
		action_button.disabled = Lan.phase == "connecting"

func refresh_rules() -> void:
	if is_instance_valid(rules_label):
		rules_label.text = "FREE FOR ALL   /   %02d:%02d   /   %s" % [Rules.duration / 60, Rules.duration % 60, "KILL LIMIT OFF" if Rules.kill_limit == 0 else "%d ELIMINATIONS TO WIN" % Rules.kill_limit]
