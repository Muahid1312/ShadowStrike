class_name ScoreTable
extends VBoxContainer
## Built only for an authoritative board change, never on the render loop.
var build_count := 0
var compact := false

func show_rows(rows: Array) -> void:
	build_count += 1
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 7)
	add_child(make_row({"rank": "#", "name": "OPERATOR", "eliminations": "ELIMS", "deaths": "DEATHS", "score": "SCORE"}, true))
	for item in rows:
		add_child(make_row(item, false))

func make_row(item: Dictionary, header: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var local := not header and int(item.id) == Lan.local_id()
	var style := MilitaryStyle.panel(Color(0.08, 0.11, 0.10, 0.96), MilitaryStyle.GOLD if local else Color("3f4843"))
	style.set_content_margin_all(6 if compact else 10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = 40 if compact else 48
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var name_text: String = str(item.name)
	if not header:
		if local:
			name_text += "  • YOU"
		if not item.get("connected", true):
			name_text += "  • LEFT"
	var values := [str(item.rank), name_text, str(item.eliminations), str(item.deaths), str(item.score)]
	for index in range(5):
		var label := MilitaryStyle.label(values[index], (16 if header else 20) if compact else (18 if header else 22), MilitaryStyle.GOLD if header or index == 4 else MilitaryStyle.TEXT, true)
		if index == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.custom_minimum_size.x = 240
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.clip_text = true
		else:
			label.custom_minimum_size.x = [44, 0, 88, 88, 110][index]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
	return panel
