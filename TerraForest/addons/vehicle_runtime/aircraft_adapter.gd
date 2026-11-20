# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## Aircraft adapter: the aircraft uses its own flight controller and a larger
## 10 m body, so it reuses only the terrain-aware placement logic from the city
## adapter. Camera, streaming, entry/exit and parking are flight-specific.

var _world: Node
var _relaxed := false

func requested_pose(world: Node) -> Dictionary:
	_relaxed = false
	var strict := super.requested_pose(world)
	if strict.ok: return strict
	_relaxed = true
	var relaxed := super.requested_pose(world)
	_relaxed = false
	return relaxed

func half_width() -> float:
	return 1.35 if _relaxed else 2.80

func half_length() -> float:
	return 4.20

func clearance_height() -> float:
	return 3.4

func ground_spread_limit() -> float:
	return 0.15

func ground_normal_min() -> float:
	return 0.8

func footprint() -> Array[Vector3]:
	var width := 1.1 if _relaxed else 2.4
	return [
		Vector3(0, 0, 0),
		Vector3(-width, 0, -3.9), Vector3(0, 0, -3.9), Vector3(width, 0, -3.9),
		Vector3(-width, 0, 0), Vector3(width, 0, 0),
		Vector3(-width, 0, 3.9), Vector3(0, 0, 3.9), Vector3(width, 0, 3.9),
	]

func accepts(body: Node) -> bool:
	return body is RigidBody3D and body.has_method("bind_streamed_world") and body.has_method("set_controls_enabled") and body.has_method("restore_parked") and body.has_method("can_park")

func install(body: RigidBody3D, world: Node) -> bool:
	_world = world
	if not body.bind_streamed_world(world.terrain, world.structures): return false
	if "vegetation" in world and world.vegetation != null and not body.bind_vegetation(world.vegetation): return false
	return true

func controls(body: RigidBody3D, enabled: bool) -> void:
	body.set_controls_enabled(enabled)

func restore_parked(body: RigidBody3D, pose: Transform3D) -> void:
	body.restore_parked(pose)

func can_park(body: RigidBody3D, frame: int) -> bool:
	return body.can_park(frame)

func bounds(body: RigidBody3D) -> AABB:
	return AABB(body.global_position - Vector3(6.0, 3.0, 6.0), Vector3(12.0, 6.0, 12.0))

func collision(body: RigidBody3D) -> CollisionShape3D:
	return body.get_node_or_null("ChassisCollision") as CollisionShape3D

func camera_update(body: RigidBody3D, camera: Camera3D, delta: float) -> void:
	var forward := body.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var anchor := body.global_position + Vector3.UP * 1.6
	var desired := body.global_position - forward * 22.0 + Vector3.UP * 8.0
	var current := camera.global_position
	if not current.is_finite() or current.distance_to(desired) > 80.0:
		current = desired
	else:
		current = current.lerp(desired, 1.0 - exp(-4.0 * minf(delta, 0.1)))
	var ray := PhysicsRayQueryParameters3D.create(anchor, current, 7, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		current = hit.position - (current - anchor).normalized() * 0.6
	camera.global_position = current
	var look := anchor + forward * 8.0 + Vector3.UP * 1.0
	if current.distance_squared_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)

func physics_rate() -> int:
	return 120

func status_text(body: RigidBody3D) -> String:
	return body.status_text()

func capture_state(_body: RigidBody3D) -> PackedByteArray:
	return PackedByteArray()

func restore_state(_body: RigidBody3D, state: PackedByteArray) -> bool:
	return state.is_empty()

func update_focus(_body: RigidBody3D, _world: Node) -> void:
	pass

func exit_offsets() -> Array:
	return [Vector3(7.5, 0, 0), Vector3(-7.5, 0, 0), Vector3(0, 0, -7.0), Vector3(0, 0, 7.0), Vector3(9.0, 0, 0), Vector3(-9.0, 0, 0)]

func prepare_resources() -> void:
	pass

func preparation_ready() -> bool:
	return true

func finish_resources() -> void:
	pass

func parked_render_parts(_body: RigidBody3D, original: Array) -> Array:
	return original
