# SPDX-License-Identifier: 0BSD
extends "res://vehicle_demo/scripts/car_native.gd"

## Static-shell city vehicle: the supplied Taxi/Ambulance GLBs are single full
## meshes with no separate wheel or door nodes. The proven Ranger chassis,
## suspension and driving policy still own the body; only the per-part visual
## animation/damage hooks are disabled. Steering, suspension travel and
## collision remain active.

func _bind_wheel_visual(_visual: MeshInstance3D, _source_name: String) -> void:
	pass

func _bind_driver_door_visual() -> void:
	pass

func repair_visual_damage() -> void:
	pass
