# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## BMX-42 pack adapter. The tank is a full-size tracked body, so it reuses the
## terrain-aware placement checks with a larger level footprint. Motion, turret
## and fire are owned by bmx42_body.gd; parked/far presentation is merged by
## material so the native 64-part prototype limit is respected.

var _merged_parts: Dictionary = {}

func accepts(body: Node) -> bool:
	return body is RigidBody3D and body.has_method("adapter_ready") and body.has_method("bind_world") \
		and body.has_method("set_controls_enabled") and body.has_method("restore_parked") \
		and body.has_method("can_park") and body.has_method("status_text")

func install(body: RigidBody3D, world: Node) -> bool:
	if not body.adapter_ready() or not body.bind_world(world):
		return false
	return true

func controls(body: RigidBody3D, enabled: bool) -> void:
	body.set_controls_enabled(enabled)

func restore_parked(body: RigidBody3D, pose: Transform3D) -> void:
	body.restore_parked(pose)

func can_park(body: RigidBody3D, frame: int) -> bool:
	return body.can_park(frame)

func half_width() -> float:
	return 1.70

func half_length() -> float:
	return 3.35

func clearance_height() -> float:
	return 4.5

func ground_spread_limit() -> float:
	return 0.18

func ground_normal_min() -> float:
	return 0.72

func footprint() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(-1.45, 0, -3.0), Vector3(0, 0, -3.0), Vector3(1.45, 0, -3.0),
		Vector3(-1.45, 0, 0), Vector3(1.45, 0, 0),
		Vector3(-1.45, 0, 3.0), Vector3(0, 0, 3.0), Vector3(1.45, 0, 3.0),
	]

func bounds(body: RigidBody3D) -> AABB:
	return AABB(body.global_position - Vector3(3.5, 2.2, 3.8), Vector3(7.0, 5.2, 7.6))

func collision(body: RigidBody3D) -> CollisionShape3D:
	return body.get_node_or_null("ChassisCollision") as CollisionShape3D

func camera_update(body: RigidBody3D, camera: Camera3D, delta: float) -> void:
	var forward := body.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var anchor := body.global_position + Vector3.UP * 2.0
	var desired := body.global_position - forward * 14.0 + Vector3.UP * 7.5
	var current := camera.global_position
	if not current.is_finite() or current.distance_to(desired) > 60.0:
		current = desired
	else:
		current = current.lerp(desired, 1.0 - exp(-4.0 * minf(delta, 0.1)))
	var ray := PhysicsRayQueryParameters3D.create(anchor, current, 7, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		current = hit.position - (current - anchor).normalized() * 0.8
	camera.global_position = current
	var look := anchor + forward * 7.0 + Vector3.UP * 0.5
	if current.distance_squared_to(look) > 0.01:
		camera.look_at(look, Vector3.UP)

func physics_rate() -> int:
	return 60

func capture_state(body: RigidBody3D) -> PackedByteArray:
	var state := PackedByteArray()
	state.resize(8)
	state.encode_float(0, body.turret_yaw)
	state.encode_float(4, body.gun_elevation)
	return state

func restore_state(body: RigidBody3D, state: PackedByteArray) -> bool:
	if state.is_empty():
		body.set_turret_state(0.0, 0.0)
		return true
	if state.size() != 8:
		return false
	var yaw := state.decode_float(0)
	var elevation := state.decode_float(4)
	if not is_finite(yaw) or not is_finite(elevation):
		return false
	body.set_turret_state(yaw, elevation)
	return true

func status_text(body: RigidBody3D) -> String:
	return body.status_text()

func exit_offsets() -> Array:
	return [
		Vector3(4.2, 0, 0), Vector3(-4.2, 0, 0),
		Vector3(0, 0, -5.0), Vector3(0, 0, 5.0),
		Vector3(5.0, 0, 0), Vector3(-5.0, 0, 0),
	]

func parked_render_parts(body: RigidBody3D, original: Array) -> Array:
	if original.is_empty():
		return original
	var kind := String(body.get_meta("vehicle_kind", "bmx42"))
	if _merged_parts.has(kind):
		return _merged_parts[kind]
	var groups: Dictionary = {}
	for part: Variant in original:
		if not part is Dictionary:
			continue
		var mesh: Mesh = part.get("mesh", null) as Mesh
		if mesh == null:
			continue
		var xform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var override: Material = part.get("material", null) as Material
		for surface in mesh.get_surface_count():
			var material: Material = override if override != null else mesh.surface_get_material(surface)
			var key: int = material.get_instance_id() if material != null else 0
			var group: Dictionary
			if groups.has(key):
				group = groups[key]
			else:
				group = {"material": material, "tool": SurfaceTool.new()}
				group.tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = group
			group.tool.append_from(mesh, surface, xform)
	var result: Array = []
	for key: int in groups:
		var group: Dictionary = groups[key]
		var tool: SurfaceTool = group.tool
		if group.material != null:
			tool.set_material(group.material)
		var merged: ArrayMesh = tool.commit()
		if merged != null and merged.get_surface_count() > 0:
			result.append({"mesh": merged, "transform": Transform3D.IDENTITY, "material": null})
	if result.is_empty():
		return original
	_merged_parts[kind] = result
	return result
