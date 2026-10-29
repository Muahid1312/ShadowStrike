class_name ScoreboardOverlay
extends Control
signal closed
var table: ScoreTable

func _ready() -> void:
	theme = MilitaryStyle.theme()
	MilitaryStyle.full(self)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.02, 0.86)
	add_child(shade)
	MilitaryStyle.full(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -500
	panel.offset_right = 500
	panel.offset_top = -265
	panel.offset_bottom = 265
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	panel.add_child(column)
	column.add_child(MilitaryStyle.label("FIELD RANKINGS", 40, MilitaryStyle.TEXT, true))
	column.add_child(MilitaryStyle.label("FREE FOR ALL   /   100 POINTS PER ELIMINATION", 17, MilitaryStyle.GOLD))
	table = ScoreTable.new()
	column.add_child(table)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space)
	column.add_child(MilitaryStyle.label("Eliminations ↓   •   Deaths ↑   •   Player ID ↑", 16, MilitaryStyle.MUTED))
	column.add_child(MilitaryStyle.button("BACK TO MATCH   /   TAB", func(): closed.emit(), true))
	Rules.board_changed.connect(refresh)
	refresh()
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)

func refresh() -> void:
	table.show_rows(Rules.board)
