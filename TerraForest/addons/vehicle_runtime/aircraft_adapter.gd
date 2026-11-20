# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## The full-mesh aircraft is 6.5 m long with a 6.5 m wingspan. Placement uses a
## core footprint that covers the fuselage and most of the wing span while
## keeping the Dev Spawner usable in ordinary forest clearings.

func half_width() -> float:
	return 2.40

func half_length() -> float:
	return 3.20

func footprint() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(-2.0, 0, -2.90), Vector3(0, 0, -2.90), Vector3(2.0, 0, -2.90),
		Vector3(-2.0, 0, 0), Vector3(2.0, 0, 0),
		Vector3(-2.0, 0, 2.90), Vector3(0, 0, 2.90), Vector3(2.0, 0, 2.90),
	]
