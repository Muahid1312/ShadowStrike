extends Node
## Persistent user preferences; no account or network dependencies.
signal changed
const PATH := "user://settings.cfg"
const DEFAULTS := {
	"sensitivity": 1.0, "aim_sensitivity": 0.55, "joystick_size": 1.0,
	"invert_look": false, "volume": 0.7, "quality": 1, "show_fps": false
}
var values: Dictionary = DEFAULTS.duplicate()

func _ready() -> void:
	load_settings()
	apply()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in DEFAULTS:
		var value = config.get_value("preferences", key, DEFAULTS[key])
		if typeof(value) == typeof(DEFAULTS[key]):
			values[key] = value
	values.sensitivity = clampf(values.sensitivity, 0.2, 3.0)
	values.aim_sensitivity = clampf(values.aim_sensitivity, 0.15, 1.5)
	values.joystick_size = clampf(values.joystick_size, 0.7, 1.4)
	values.volume = clampf(values.volume, 0.0, 1.0)
	values.quality = clampi(values.quality, 0, 2)

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = value
	apply()
	var config := ConfigFile.new()
	for item in values:
		config.set_value("preferences", item, values[item])
	var error := config.save(PATH)
	if error != OK:
		push_error("Cannot save preferences: %s" % error_string(error))
	changed.emit()

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, values.volume)))
	get_viewport().scaling_3d_scale = [0.65, 0.85, 1.0][values.quality]
	get_viewport().msaa_3d = Viewport.MSAA_2X if values.quality == 2 else Viewport.MSAA_DISABLED
