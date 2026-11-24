class_name VigilAudio
extends Node
## Original, bounded PCM cues. Playback also works with Godot's dummy audio driver.

signal cue_played(cue: StringName)
signal settings_changed

const SETTINGS_PATH := "user://audio.cfg"
const DEFAULT_VOLUME := 0.85
const SAMPLE_RATE := 22050
const VOICE_COUNT := 8
const CUES := {
	&"menu_confirm": Vector3(660, 990, 0.09),
	&"pause": Vector3(440, 220, 0.16),
	&"dash": Vector3(180, 820, 0.12),
	&"friendly_hit": Vector3(880, 240, 0.07),
	&"keeper_hurt": Vector3(220, 70, 0.22),
	&"reward": Vector3(520, 1040, 0.28),
	&"win": Vector3(392, 1568, 0.65),
	&"loss": Vector3(294, 55, 0.65),
}

var master_volume := DEFAULT_VOLUME
var muted := false
var last_save_error: Error = OK
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var _next_voice := 0


func _ready() -> void:
	_load_settings()
	_apply_settings()
	for cue: StringName in CUES:
		streams[cue] = _synthesize(CUES[cue])
	for index in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Master"
		add_child(voice)
		voices.append(voice)


func set_master_volume(value: float) -> void:
	if not is_finite(value):
		return
	master_volume = clampf(value, 0.0, 1.0)
	_update_settings()


func set_muted(value: bool) -> void:
	muted = value
	_update_settings()


func toggle_mute() -> void:
	set_muted(not muted)


func play_cue(cue: StringName) -> void:
	if not streams.has(cue) or voices.is_empty():
		return
	var voice := voices[_next_voice]
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	_next_voice = (_next_voice + 1) % voices.size()
	voice.stop()
	voice.stream = streams[cue]
	voice.play()
	cue_played.emit(cue)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var volume: Variant = config.get_value("audio", "master_volume", DEFAULT_VOLUME)
	if (volume is float or volume is int) and is_finite(float(volume)):
		master_volume = clampf(float(volume), 0.0, 1.0)
	var saved_mute: Variant = config.get_value("audio", "muted", false)
	if saved_mute is bool:
		muted = saved_mute


func _apply_settings() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, muted or master_volume == 0.0)


func _update_settings() -> void:
	_apply_settings()
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "muted", muted)
	last_save_error = config.save(SETTINGS_PATH)
	if last_save_error != OK:
		push_warning("Audio settings could not be saved; they apply for this session.")
	settings_changed.emit()


func _synthesize(tone: Vector3) -> AudioStreamWAV:
	var count := int(tone.z * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var phase := 0.0
	for index in count:
		var progress := float(index) / float(count - 1)
		var envelope := minf(float(index) / (SAMPLE_RATE * 0.005), 1.0)
		envelope *= pow(1.0 - progress, 2.0)
		var wave := (sin(phase) + 0.3 * sin(phase * 2.0)) / 1.3
		pcm.encode_s16(index * 2, int(wave * envelope * 0.09 * 32767.0))
		phase += TAU * lerpf(tone.x, tone.y, progress) / SAMPLE_RATE
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream
