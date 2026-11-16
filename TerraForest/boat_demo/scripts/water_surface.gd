# SPDX-License-Identifier: 0BSD
class_name BoatWaterSurface
extends MeshInstance3D

# Height function shared with water.gdshader. Keep the wave constants identical
# in both files so buoyancy probes stay on the visible surface.
const W1 := Vector3(0.35, 0.22, 1.15)
const A1 := 0.055
const W2 := Vector3(-0.21, 0.47, 1.6)
const A2 := 0.035
const W3 := Vector3(0.58, -0.31, 2.1)
const A3 := 0.022

@export var wave_time_scale := 1.0

var time := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = material_override as ShaderMaterial
	if _material != null:
		_material.set_shader_parameter("water_time", time)


func _process(delta: float) -> void:
	time += delta * wave_time_scale
	if _material != null:
		_material.set_shader_parameter("water_time", time)


func height_at(point: Vector3) -> float:
	var x := point.x
	var z := point.z
	return A1 * sin(W1.x * x + W1.y * z + W1.z * time) \
		+ A2 * sin(W2.x * x + W2.y * z + W2.z * time) \
		+ A3 * sin(W3.x * x + W3.y * z + W3.z * time)


func normal_at(point: Vector3) -> Vector3:
	var x := point.x
	var z := point.z
	var dx := A1 * W1.x * cos(W1.x * x + W1.y * z + W1.z * time) \
		+ A2 * W2.x * cos(W2.x * x + W2.y * z + W2.z * time) \
		+ A3 * W3.x * cos(W3.x * x + W3.y * z + W3.z * time)
	var dz := A1 * W1.y * cos(W1.x * x + W1.y * z + W1.z * time) \
		+ A2 * W2.y * cos(W2.x * x + W2.y * z + W2.z * time) \
		+ A3 * W3.y * cos(W3.x * x + W3.y * z + W3.z * time)
	return Vector3(-dx, 1.0, -dz).normalized()
