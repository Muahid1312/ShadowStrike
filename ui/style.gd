class_name MilitaryStyle
extends RefCounted
const GOLD := Color("e4b64e")
const TEXT := Color("eeeede")
const MUTED := Color("a3aca5")
const HEADING := preload("res://assets/fonts/Heading.ttf")
const BODY := preload("res://assets/fonts/Body.ttf")

static func panel(color: Color = Color(0.06, 0.085, 0.085, 0.94), border: Color = Color("3f4843")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_content_margin_all(16)
	box.corner_radius_top_left = 3
	box.corner_radius_bottom_right = 3
	return box

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 18
	result.set_font("font", "Button", HEADING)
	result.set_font_size("font_size", "Button", 24)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", GOLD)
	result.set_color("font_pressed_color", "Button", Color("131a18"))
	result.set_stylebox("normal", "Button", panel())
	result.set_stylebox("hover", "Button", panel(Color("30362b"), GOLD))
	result.set_stylebox("pressed", "Button", panel(GOLD, GOLD))
	result.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), GOLD))
	result.set_stylebox("disabled", "Button", panel(Color("171e1c"), Color("303a34")))
	result.set_color("font_disabled_color", "Button", Color("6f7d73"))
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_color("font_color", "Label", TEXT)
	var track := panel(Color("343f38"))
	track.set_content_margin_all(2)
	var fill := panel(GOLD, GOLD)
	fill.set_content_margin_all(2)
	result.set_stylebox("slider", "HSlider", track)
	result.set_stylebox("grabber_area", "HSlider", fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return result

static func label(text: String, font_size: int = 20, color: Color = TEXT, heading: bool = false) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	if heading:
		item.add_theme_font_override("font", HEADING)
	return item

static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 56
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		item.add_theme_stylebox_override("normal", panel(GOLD, GOLD))
		item.add_theme_color_override("font_color", Color("151c18"))
		item.add_theme_stylebox_override("hover", panel(GOLD.lightened(0.15), GOLD))
		item.add_theme_color_override("font_hover_color", Color("151c18"))
	item.pressed.connect(callback)
	item.button_down.connect(func(): item.modulate = Color(0.85, 0.85, 0.85))
	item.button_up.connect(func(): item.modulate = Color.WHITE)
	item.mouse_entered.connect(func(): item.create_tween().tween_property(item, "self_modulate", Color(1.12, 1.12, 1.05), 0.1))
	item.mouse_exited.connect(func(): item.create_tween().tween_property(item, "self_modulate", Color.WHITE, 0.1))
	return item

static func full(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
