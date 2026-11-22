# SPDX-License-Identifier: 0BSD
extends Node3D

## Police lightbar: red/blue beacon lights and a looping two-tone siren while
## the car is occupied/driving. The lights attach to the authored beacon meshes;
## no extra mesh parts are added to the parked prototype.

const SIREN_PATH := "res://vehicle_demo/assets/city/police_siren.wav"
var blue_light: OmniLight3D
var red_light: OmniLight3D
var audio: AudioStreamPlayer3D
var _active := false
var _phase := 0.0
var _audio_ready := false

func _ready() -> void:
	var model := get_parent().get_node_or_null("VehicleVisual/Model")
	if model == null: return
	blue_light = _make_light(model.find_child("Blue beacon", true, false), Color(0.12, 0.38, 1.0))
	red_light = _make_light(model.find_child("Red beacon", true, false), Color(1.0, 0.08, 0.06))
	audio = AudioStreamPlayer3D.new()
	audio.name = "SirenAudio"
	audio.volume_db = -6.0
	audio.max_distance = 50.0
	audio.unit_size = 5.0
	add_child(audio)

func _make_light(beacon: Node, color: Color) -> OmniLight3D:
	if beacon == null: return null
	var light := OmniLight3D.new()
	light.name = "BeaconLight"
	light.light_color = color
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	beacon.add_child(light)
	return light

func _ensure_audio() -> void:
	if _audio_ready or audio == null: return
	_audio_ready = true
	var stream: AudioStream = load(SIREN_PATH)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	audio.stream = stream

func _process(delta: float) -> void:
	var body := get_parent()
	var active: bool = body != null and body.get("controls_enabled") == true and not body.freeze
	if active != _active:
		_active = active
		if active:
			_ensure_audio()
			if audio != null and audio.stream != null and not audio.playing: audio.play()
		else:
			if audio != null: audio.stop()
			_phase = 0.0
	if not _active:
		_set_lights(false, false)
		return
	_phase = fmod(_phase + delta, 0.8)
	var step := int(_phase / 0.2)
	_set_lights(step == 0, step == 2)

func _set_lights(blue: bool, red: bool) -> void:
	if blue_light != null: blue_light.light_energy = 4.0 if blue else 0.0
	if red_light != null: red_light.light_energy = 4.0 if red else 0.0

func is_active() -> bool:
	return _active

func audio_ready() -> bool:
	return audio != null and audio.stream != null

func light_state() -> Dictionary:
	return {
		"blue": blue_light.light_energy if blue_light != null else 0.0,
		"red": red_light.light_energy if red_light != null else 0.0,
	}
