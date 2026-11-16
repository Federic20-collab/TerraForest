# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/vehicle_adapter.gd"

## Vehicle-pack adapter for the supplied boat. Buoyancy samples the main
## world's volumetric lake runtime; the single-part baked mesh keeps the native
## parked prototype inside its 64-part limit.

var follow: RefCounted


func accepts(body: Node) -> bool:
	return super.accepts(body) and body.has_method("bind_water") \
		and body.has_method("set_controls_enabled") and not body.has_method("bind_streamed_world")


func install(body: RigidBody3D, world: Node) -> bool:
	if not "lakes" in world or world.lakes == null:
		return false
	if not body.bind_water(world.lakes):
		return false
	follow = ClassDB.instantiate("NativeVehicleCamera")
	return follow != null


func controls(body: RigidBody3D, enabled: bool) -> void:
	body.set_controls_enabled(enabled)


func restore_parked(body: RigidBody3D, pose: Transform3D) -> void:
	body.global_transform = pose
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.throttle = 0.0
	body.steering = 0.0
	body.set_controls_enabled(false)
	body.freeze = true
	body.set_physics_process(false)


func can_park(body: RigidBody3D, _frame: int) -> bool:
	return not body.freeze and body.linear_velocity.length() < 0.15 \
		and body.angular_velocity.length() < 0.1


func bounds(body: RigidBody3D) -> AABB:
	return AABB(body.global_position - Vector3(2.8, 1.2, 2.8), Vector3(5.6, 2.8, 5.6))


func collision(body: RigidBody3D) -> CollisionShape3D:
	return body.get_node_or_null("HullCollision") as CollisionShape3D


func camera_update(body: RigidBody3D, camera: Camera3D, delta: float) -> void:
	if follow != null:
		follow.update(body, camera, delta)


func physics_rate() -> int:
	return 120


func capture_state(_body: RigidBody3D) -> PackedByteArray:
	return PackedByteArray()


func restore_state(_body: RigidBody3D, state: PackedByteArray) -> bool:
	return state.is_empty()


func status_text(body: RigidBody3D) -> String:
	return "Boat · %.0f km/h · %.1f kn · E exit" % [body.speed_kph, body.speed_knots]


func requested_pose(world: Node) -> Dictionary:
	if not "lakes" in world or world.lakes == null or world.lakes.water == null:
		return {"ok": false, "reason": "Water runtime is unavailable"}
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var heading := Basis(Vector3.UP, world.player.global_rotation.y + PI)
	var forward: Vector3 = heading.z
	var side: Vector3 = heading.x
	var reason := "Aim at open water near a shore"
	for distance: float in [6.0, 9.0, 12.0]:
		for offset: float in [0.0, 3.0, -3.0]:
			var point: Vector3 = world.player.global_position + forward * distance + side * offset
			var surface: Vector3 = world.lakes.water.surface_near(Vector3(point.x, point.y + 1.0, point.z), 3.0)
			if not surface.is_finite() or absf(surface.y - point.y) > 8.0:
				continue
			if Vector2(surface.x - point.x, surface.z - point.z).length() > 6.0:
				continue
			if world.lakes.depth_at(surface - Vector3.UP * 0.6) < 0.2:
				reason = "Water is too shallow for the boat"
				continue
			var pose := Transform3D(heading, surface + Vector3.UP * 0.28)
			var bounds := AABB(pose.origin - Vector3(3.0, 1.0, 3.0), Vector3(6.0, 3.0, 6.0))
			if not world.world_vehicle.ready_bounds(world, bounds):
				reason = "Water area is still loading"
				continue
			if AABB(pose.origin - Vector3(3.25, 1.0, 3.25), Vector3(6.5, 3.0, 6.5)).has_point(world.player.global_position):
				reason = "Place the boat farther from the player"
				continue
			var box := BoxShape3D.new()
			box.size = Vector3(2.2, 1.4, 4.6)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = box
			query.collision_mask = 15
			query.transform = Transform3D(pose.basis, pose.origin + Vector3.UP * 0.7)
			query.exclude = [world.player.get_rid()]
			if not space.intersect_shape(query, 1).is_empty():
				reason = "Boat space is obstructed"
				continue
			return {"ok": true, "pose": pose, "reason": ""}
	return {"ok": false, "reason": reason}
