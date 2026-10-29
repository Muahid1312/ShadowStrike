class_name ResultsScreen
extends Control
signal lobby_requested
signal menu_requested
var table: ScoreTable
var heading: Label
var local_label: Label
var return_button: Button

func _ready() -> void:
	theme = MilitaryStyle.theme()
	theme.set_font_size("font_size", "Button", 22)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var compact := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		compact.set_content_margin_all(10)
		theme.set_stylebox(state, "Button", compact)
	MilitaryStyle.full(self)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.02, 0.90)
	add_child(shade)
	MilitaryStyle.full(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -510
	panel.offset_right = 510
	panel.offset_top = -325
	panel.offset_bottom = 325
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var result: Dictionary = Rules.final_results
	var won: bool = int(result.get("winner_id", 0)) == Lan.local_id()
	heading = MilitaryStyle.label("VICTORY" if won else "MATCH COMPLETE", 40, MilitaryStyle.GOLD if won else MilitaryStyle.TEXT, true)
	column.add_child(heading)
	column.add_child(MilitaryStyle.label("WINNER  /  " + str(result.get("winner_name", "")), 20, MilitaryStyle.TEXT, true))
	column.add_child(MilitaryStyle.label("SECTOR 07   •   FREE FOR ALL   •   " + str(result.get("reason", "")), 14, MilitaryStyle.MUTED))
	table = ScoreTable.new()
	table.compact = true
	column.add_child(table)
	table.show_rows(result.get("rows", []))
	local_label = MilitaryStyle.label("", 18, MilitaryStyle.GOLD, true)
	for row in result.get("rows", []):
		if int(row.id) == Lan.local_id():
			local_label.text = "YOUR RESULT   #%d   /   %d ELIMS   /   %d DEATHS   /   %d POINTS" % [row.rank, row.eliminations, row.deaths, row.score]
	column.add_child(local_label)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space)
	return_button = MilitaryStyle.button("REMATCH  /  RETURN TO LOBBY" if Lan.is_host() else "WAITING FOR HOST TO RETURN TO LOBBY", func(): lobby_requested.emit(), true)
	return_button.disabled = not Lan.is_host()
	column.add_child(return_button)
	column.add_child(MilitaryStyle.button("MAIN MENU", func(): menu_requested.emit()))
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
