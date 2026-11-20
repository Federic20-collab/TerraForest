# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## The full-mesh train car is 6.4 m long and 2.2 m wide. It remains inside the
## API 1 envelope but uses its own narrow, long placement footprint.

func half_width() -> float:
	return 1.15

func half_length() -> float:
	return 3.20

func footprint() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(-1.0, 0, -2.90), Vector3(0, 0, -2.90), Vector3(1.0, 0, -2.90),
		Vector3(-1.0, 0, 0), Vector3(1.0, 0, 0),
		Vector3(-1.0, 0, 2.90), Vector3(0, 0, 2.90), Vector3(1.0, 0, 2.90),
	]
