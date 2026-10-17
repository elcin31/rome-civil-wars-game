extends Node
## Local preferences and one bounded audio mixer. No network or external telemetry.

const SETTINGS_PATH = "user://settings.cfg"
var settings: Dictionary = {
	"music": 0.45,
	"effects": 0.65,
	"button_scale": 1.0,
	"button_offset": 0.0,
	"language": "ru",
	"text_speed": 36.0
}
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var music_layer: String = ""
var voice_index: int = 0


func _ready() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		for key in settings:
			set_preference(key, config.get_value("game", key, settings[key]), false)
	music = AudioStreamPlayer.new()
	add_child(music)
	for index in range(4):
		var voice = AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	_update_volumes()


func set_preference(key: String, value: Variant, persist: bool = true) -> void:
	if not settings.has(key):
		return
	if key == "language":
		settings[key] = "ru"  # English data are prepared; do not expose an empty locale.
	elif value is float or value is int:
		if not is_finite(float(value)):
			return
		match key:
			"button_scale":
				settings[key] = clampf(value, 1.0, 1.3)
			"button_offset":
				settings[key] = clampf(value, -8.0, 8.0)
			"text_speed":
				settings[key] = clampf(value, 18.0, 72.0)
			_:
				settings[key] = clampf(value, 0.0, 1.0)
	else:
		return
	_update_volumes()
	if persist:
		var config = ConfigFile.new()
		for item in settings:
			config.set_value("game", item, settings[item])
		config.save(SETTINGS_PATH)


func _update_volumes() -> void:
	if is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(0.0001, settings.music))
	for voice in voices:
		voice.volume_db = linear_to_db(maxf(0.0001, settings.effects))


func play_layer(value: String) -> void:
	if value == music_layer:
		return
	music_layer = value
	var path: String = "res://assets/audio/" + value + ".ogg"
	if ResourceLoader.exists(path):
		music.stream = load(path)
		music.play()


func effect(value: String) -> void:
	if voices.is_empty():
		return
	var path: String = "res://assets/audio/" + value + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var voice: AudioStreamPlayer = voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	voice.stream = load(path)
	voice.play()
