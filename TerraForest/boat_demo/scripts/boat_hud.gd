# SPDX-License-Identifier: 0BSD
extends CanvasLayer

@export var boat_path: NodePath = ^"../Boat"

@onready var speed_label: Label = $SpeedLabel
@onready var state_label: Label = $StateLabel
@onready var controls_label: Label = $ControlsLabel

var boat: BoatVehicle


func _ready() -> void:
	boat = get_node_or_null(boat_path) as BoatVehicle
	if boat == null:
		push_error("Boat HUD boat_path does not point to a BoatVehicle")


func _process(_delta: float) -> void:
	if boat == null:
		return
	speed_label.text = "%d km/h  ·  %.1f kn" % [roundi(boat.speed_kph), boat.speed_knots]
	state_label.text = "Throttle:%+d%%  Rudder:%+d%%  Draft:%.2f m  Wet probes:%d/%d  Water:%+.2f m" % [
		roundi(boat.throttle * 100.0),
		roundi(boat.steering * 100.0),
		boat.draft,
		boat.wet_probes,
		boat.probe_total(),
		boat.water_height,
	]
	controls_label.text = "W/S: throttle & reverse   A/D: steer   Space: idle   R: reset to dock"
