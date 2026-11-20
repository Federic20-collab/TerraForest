# SPDX-License-Identifier: 0BSD
extends RefCounted

## Flight-aware streaming guard. Terrain collision readiness is column-based, so
## the vertical extent is conservative while the horizontal reach follows speed.

var terrain: Node
var structures: Node
var vegetation: Node
var structures_required := false
var vegetation_required := false
var owns_focus := true
var waiting := false
var _linear := Vector3.ZERO
var _angular := Vector3.ZERO

func bind(world_terrain: Node, world_structures: Node, world_vegetation: Node = null) -> bool:
	if not is_instance_valid(world_terrain): return false
	terrain = world_terrain
	structures = world_structures
	vegetation = world_vegetation
	structures_required = world_structures != null
	vegetation_required = world_vegetation != null
	return true

func bind_vegetation(provider: Node) -> bool:
	if waiting or not is_instance_valid(provider) or not provider.has_method("is_collision_region_ready"): return false
	vegetation = provider
	vegetation_required = true
	return true

func restore_parked(body: RigidBody3D) -> void:
	_linear = Vector3.ZERO
	_angular = Vector3.ZERO
	waiting = false
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true

func reset(body: RigidBody3D) -> void:
	_linear = Vector3.ZERO
	_angular = Vector3.ZERO
	waiting = false
	body.freeze = false

func update(body: RigidBody3D, delta: float) -> bool:
	if not is_instance_valid(terrain):
		_hold(body)
		return false
	var velocity: Vector3 = _linear if waiting else body.linear_velocity
	if owns_focus:
		terrain.focus = body.global_position
		terrain.require_collision = true
		terrain.travel_velocity = velocity
	var reach := clampf(18.0 + velocity.length() * 0.5, 18.0, 64.0)
	var bounds := AABB(body.global_position - Vector3(reach, 30.0, reach), Vector3(reach * 2.0, 60.0, reach * 2.0))
	var ready: bool = terrain.is_collision_region_ready(bounds)
	if structures_required:
		ready = ready and is_instance_valid(structures) and structures.is_collision_region_ready(bounds)
	if vegetation_required:
		ready = ready and is_instance_valid(vegetation) and vegetation.is_collision_region_ready(bounds)
	if not ready:
		_hold(body)
		return false
	if waiting:
		body.freeze = false
		body.linear_velocity = _linear
		body.angular_velocity = _angular
		waiting = false
	return true

func _hold(body: RigidBody3D) -> void:
	if waiting or body.freeze: return
	_linear = body.linear_velocity
	_angular = body.angular_velocity
	body.freeze = true
	waiting = true
