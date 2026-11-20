# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## Fire truck placement: the full-mesh body is 6.4 m long, so it needs a wider
## and longer level footprint than the Taxi/Ambulance city vehicles. It still
## fits the existing 6.5 x 3 x 6.5 m API 1 envelope.

func half_width() -> float:
	return 1.30

func half_length() -> float:
	return 3.20

func footprint() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(-1.05, 0, -2.90), Vector3(0, 0, -2.90), Vector3(1.05, 0, -2.90),
		Vector3(-1.05, 0, 0), Vector3(1.05, 0, 0),
		Vector3(-1.05, 0, 2.90), Vector3(0, 0, 2.90), Vector3(1.05, 0, 2.90),
	]
