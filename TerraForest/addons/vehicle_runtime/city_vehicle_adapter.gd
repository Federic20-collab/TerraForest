# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/ranger_adapter.gd"

## The shared chassis controller is reused for the static-shell city vehicles.
## Placement is stricter than the legacy Ranger fallback: a spawn must have
## sampled, level, loaded ground across the whole footprint. Returning no pose is
## better than freezing a full-mesh vehicle in mid-air or across a cliff.

const RIDE_HEIGHT := 0.85

func half_width() -> float:
	return 1.25

func half_length() -> float:
	return 2.60

func clearance_height() -> float:
	return 2.6

func ground_spread_limit() -> float:
	return 0.30

func ground_normal_min() -> float:
	return 0.7

func footprint() -> Array[Vector3]:
	return [
		Vector3(0, 0, 0),
		Vector3(-1.0, 0, -2.2), Vector3(0, 0, -2.2), Vector3(1.0, 0, -2.2),
		Vector3(-1.0, 0, 0), Vector3(1.0, 0, 0),
		Vector3(-1.0, 0, 2.2), Vector3(0, 0, 2.2), Vector3(1.0, 0, 2.2),
	]

func requested_pose(world: Node) -> Dictionary:
	var heading := Basis(Vector3.UP, world.player.global_rotation.y + PI)
	var forward: Vector3 = heading.z
	var side: Vector3 = heading.x
	var candidates: Array[Vector3] = []
	for distance: float in [6.0, 8.0, 10.0, 12.0]:
		for offset: float in [0.0, 2.5, -2.5]:
			candidates.append(world.player.global_position + forward * distance + side * offset)
	for radius: float in [6.0, 9.0, 12.0, 16.0, 20.0]:
		for step in 12:
			var angle := TAU * step / 12.0
			candidates.append(world.player.global_position + Vector3(sin(angle), 0, cos(angle)) * radius)
	var reason := "No clear, level, loaded ground within 20 m"
	for point: Vector3 in candidates:
		point.x = clampf(point.x, 2, 1998)
		point.z = clampf(point.z, 2, 1998)
		var fit := _ground_pose(world, heading, point)
		if fit.ok:
			return fit
		if fit.reason != "":
			reason = fit.reason
	return {"ok": false, "reason": reason}

func _ground_pose(world: Node, heading: Basis, point: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var exclusions: Array[RID] = [world.player.get_rid()]
	var start := Vector3(point.x, world.player.global_position.y + 10.0, point.z)
	var center_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 30.0, 1, exclusions))
	if center_hit.is_empty():
		return {"ok": false, "reason": ""}
	if center_hit.normal.dot(Vector3.UP) < ground_normal_min():
		return {"ok": false, "reason": "Vehicle ground is too steep"}
	var lowest := INF
	var highest := -INF
	var normal_sum := Vector3.ZERO
	for sample: Vector3 in footprint():
		var at: Vector3 = center_hit.position + heading * sample
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 8.0, 1, exclusions)
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			return {"ok": false, "reason": "Vehicle footprint has missing support"}
		if hit.normal.dot(Vector3.UP) < ground_normal_min():
			return {"ok": false, "reason": "Vehicle ground is too uneven"}
		lowest = minf(lowest, hit.position.y)
		highest = maxf(highest, hit.position.y)
		normal_sum += hit.normal
	if highest - lowest > ground_spread_limit() or highest - center_hit.position.y > ground_spread_limit():
		return {"ok": false, "reason": "Vehicle ground is too uneven"}
	var up := normal_sum.normalized()
	var forward: Vector3 = heading.z.slide(up)
	if forward.length_squared() < 0.0001: forward = heading.x.slide(up)
	if forward.length_squared() < 0.0001: forward = heading.z
	forward = forward.normalized()
	var right := up.cross(forward).normalized()
	if right.length_squared() < 0.0001: right = heading.x
	var basis := Basis(right, up, forward)
	var pose := Transform3D(basis, center_hit.position + up * RIDE_HEIGHT)
	if AABB(pose.origin - Vector3(half_width(), 1, half_length()), Vector3(half_width() * 2.0, 3, half_length() * 2.0)).has_point(world.player.global_position):
		return {"ok": false, "reason": "Place the vehicle farther from the player"}
	var bounds := AABB(pose.origin - Vector3(half_width(), clearance_height() * 0.5, half_length()), Vector3(half_width() * 2.0, clearance_height() + 2.0, half_length() * 2.0))
	if not _region_ready(world, bounds):
		return {"ok": false, "reason": "Vehicle area is still loading"}
	var probe := BoxShape3D.new()
	probe.size = Vector3(half_width() * 2.0, clearance_height(), half_length() * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 15 | (1 << 16)
	query.transform = Transform3D(basis, pose.origin + up * (clearance_height() * 0.5 - 0.8))
	query.exclude = exclusions
	if not space.intersect_shape(query, 1).is_empty():
		return {"ok": false, "reason": "Vehicle space is obstructed"}
	return {"ok": true, "pose": pose, "reason": ""}

func _region_ready(world: Node, bounds: AABB) -> bool:
	if not is_instance_valid(world.terrain) or not world.terrain.is_collision_region_ready(bounds):
		return false
	if "structures" in world and world.structures != null and not world.structures.is_collision_region_ready(bounds):
		return false
	if "vegetation" in world and world.vegetation != null and not world.vegetation.is_collision_region_ready(bounds):
		return false
	return true
