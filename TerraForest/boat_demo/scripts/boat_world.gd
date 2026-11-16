# SPDX-License-Identifier: 0BSD
extends "res://boat_demo/scripts/boat.gd"

## Main-world boat body. Water comes from the volumetric lake runtime instead of
## the standalone demo height field; reticle resets are owned by the host.

var lakes: Node


func _ready() -> void:
	allow_reset = false
	super._ready()


func bind_water(provider: Node) -> bool:
	if not is_instance_valid(provider) or not "water" in provider or provider.water == null:
		return false
	lakes = provider
	return true


func _water_height_at(point: Vector3) -> float:
	if not is_instance_valid(lakes) or lakes.water == null:
		return NAN
	var surface: Vector3 = lakes.water.surface_near(point, 3.0)
	if not surface.is_finite():
		return NAN
	if absf(surface.y - point.y) > 8.0:
		return NAN
	if Vector2(surface.x - point.x, surface.z - point.z).length() > 8.0:
		return NAN
	return surface.y
