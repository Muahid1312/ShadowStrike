class_name SettingsPanel
extends PanelContainer
signal closed
var rows: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = MilitaryStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -420
	offset_right = 420
	offset_top = -315
	offset_bottom = 315
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	column.add_child(MilitaryStyle.label("FIELD SETTINGS", 36, MilitaryStyle.TEXT, true))
	column.add_child(MilitaryStyle.label("Changes apply and save immediately on this device", 16, MilitaryStyle.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	add_slider(content, "Camera sensitivity", "sensitivity", 0.2, 3.0, 0.05)
	add_slider(content, "Aim sensitivity", "aim_sensitivity", 0.15, 1.5, 0.05)
	add_slider(content, "Joystick size", "joystick_size", 0.7, 1.4, 0.05)
	add_slider(content, "Master volume", "volume", 0, 1, 0.05)
	add_toggle(content, "Invert vertical look", "invert_look")
	add_toggle(content, "Show FPS", "show_fps")
	var quality_row := row(content, "Graphics quality")
	var quality := OptionButton.new()
	for item in ["LOW • 65% / no shadows", "MEDIUM • 85% / shadows", "HIGH • 100% / 2× MSAA"]:
		quality.add_item(item)
	quality.selected = Settings.values.quality
	quality.custom_minimum_size = Vector2(350, 42)
	var option_style := MilitaryStyle.panel()
	option_style.set_content_margin_all(8)
	quality.add_theme_stylebox_override("normal", option_style)
	quality.item_selected.connect(func(index: int): Settings.set_value("quality", index))
	quality_row.add_child(quality)
	rows.quality = quality
	column.add_child(MilitaryStyle.label("Aim: RMB / AIM   •   Desktop: WASD, Shift, Space, R, Esc", 15, MilitaryStyle.MUTED))
	column.add_child(MilitaryStyle.button("BACK", func(): closed.emit(), true))

func row(parent: Control, title: String) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.custom_minimum_size.y = 46
	parent.add_child(result)
	var title_label := MilitaryStyle.label(title, 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_child(title_label)
	return result

func add_slider(parent: Control, title: String, key: String, low: float, high: float, step_size: float) -> void:
	var container := row(parent, title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = Settings.values[key]
	slider.custom_minimum_size = Vector2(260, 40)
	container.add_child(slider)
	var value := MilitaryStyle.label("%.2f" % slider.value, 18, MilitaryStyle.GOLD)
	value.custom_minimum_size.x = 65
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(value)
	slider.value_changed.connect(func(number: float):
		value.text = "%.2f" % number
		Settings.set_value(key, number))
	rows[key] = slider

func add_toggle(parent: Control, title: String, key: String) -> void:
	var container := row(parent, title)
	var toggle := CheckButton.new()
	toggle.text = "ON" if Settings.values[key] else "OFF"
	var toggle_style := MilitaryStyle.panel()
	toggle_style.set_content_margin_all(8)
	toggle.add_theme_stylebox_override("normal", toggle_style)
	toggle.button_pressed = Settings.values[key]
	toggle.custom_minimum_size = Vector2(350, 42)
	toggle.toggled.connect(func(enabled: bool):
		toggle.text = "ON" if enabled else "OFF"
		Settings.set_value(key, enabled))
	container.add_child(toggle)
	rows[key] = toggle
