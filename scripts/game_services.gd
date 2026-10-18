extends Node
## Local preferences and one bounded audio mixer. No network or external telemetry.

const SETTINGS_PATH = "user://settings.cfg"
var settings: Dictionary = {
	"music": 0.45,
	"effects": 0.65,
	"button_scale": 1.0,
	"button_offset": 0.0,
	"language": "ru",
	"text_speed": 36.0,
	"hints": true,
	"text_size": 1,
	"skip_read": false,
	"auto_advance": false,
	"vibration": true,
	"battery": false,
	"left_handed": false,
	"skip_minigames": false
}
var read_nodes: Dictionary = {}
var dialogue: bool = false
var ambient: AudioStreamPlayer
var ambient_layer: String = ""
var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var music_layer: String = ""
var voice_index: int = 0


func _ready() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		for key in settings:
			set_preference(key, config.get_value("game", key, settings[key]), false)
	var remembered: Variant = config.get_value("reading", "nodes", [])
	if remembered is Array and remembered.size() < 10000:
		for ident in remembered:
			if ident is String:
				read_nodes[ident] = true
	ambient = AudioStreamPlayer.new()
	add_child(ambient)
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
	elif (
		key
		in [
			"hints",
			"skip_read",
			"auto_advance",
			"vibration",
			"battery",
			"left_handed",
			"skip_minigames"
		]
	):
		if not value is bool:
			return
		settings[key] = value
	elif value is float or value is int:
		if not is_finite(float(value)):
			return
		match key:
			"text_size":
				settings[key] = clampi(int(value), 0, 2)
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
		config.set_value("reading", "nodes", read_nodes.keys())
		config.save(SETTINGS_PATH)


func _update_volumes() -> void:
	if is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(0.0001, settings.music * (0.42 if dialogue else 1.0)))
	if is_instance_valid(ambient):
		ambient.volume_db = linear_to_db(maxf(0.0001, settings.effects * 0.24))
	Engine.max_fps = 30 if settings.battery else 60
	for voice in voices:
		voice.volume_db = linear_to_db(maxf(0.0001, settings.effects))


func play_layer(value: String) -> void:
	music.stream_paused = false
	if is_instance_valid(ambient):
		ambient.stream_paused = false
	if value == music_layer:
		return
	music_layer = value
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		return
	var path: String = "res://assets/audio/" + value + ".ogg"
	if ResourceLoader.exists(path):
		music.stop()
		music.stream = load(path)
		if music.stream is AudioStreamOggVorbis:
			music.stream.loop = true
		music.play()


func effect(value: String) -> void:
	if (
		voices.is_empty()
		or DisplayServer.get_name() == "headless"
		or AudioServer.get_driver_name() == "Dummy"
	):
		return
	var path: String = "res://assets/audio/" + value + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var voice: AudioStreamPlayer = voices[voice_index]
	voice_index = (voice_index + 1) % voices.size()
	voice.stream = load(path)
	voice.play()


func _exit_tree() -> void:
	if is_instance_valid(music):
		music.stream_paused = false
		music.stop()
		music.stream = null
	for voice in voices:
		voice.stop()
		voice.stream = null


func set_dialogue(active: bool) -> void:
	dialogue = active
	_update_volumes()


func mark_read(ident: String) -> void:
	if read_nodes.has(ident):
		return
	read_nodes[ident] = true
	set_preference("hints", settings.hints)


func set_ambience(value: String) -> void:
	if not is_instance_valid(ambient) or ambient_layer == value:
		return
	ambient_layer = value
	ambient.stop()
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		return
	var path: String = "res://assets/audio/ambient_" + value + ".ogg"
	if ResourceLoader.exists(path):
		ambient.stream = load(path)
		ambient.stream.loop = true
		ambient.play()
