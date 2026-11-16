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
	return AABB(body.global_position - Vector3(3.4, 1.6, 3.4), Vector3(6.8, 3.2, 6.8))


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
	var heading := Basis(Vector3.UP, world.player.global_rotation.y + PI)
	var forward: Vector3 = heading.z
	var side: Vector3 = heading.x
	var reason := "No open water within 40 m · move to a lake or the coast"
	for distance: float in [6.0, 9.0, 12.0]:
		for offset: float in [0.0, 3.0, -3.0]:
			var point: Vector3 = world.player.global_position + forward * distance + side * offset
			var placement := _pose_on_water(world, heading, point)
			if placement.ok:
				return placement
			reason = placement.reason if placement.reason != "" else reason
	# The Dev Spawner promises no aiming, so also look for nearby water around
	# the player and report clearly when the area is dry.
	for radius: float in [8.0, 12.0, 16.0, 24.0, 32.0, 40.0]:
		for step in 8:
			var angle := TAU * step / 8.0
			var point: Vector3 = world.player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * radius
			var placement := _pose_on_water(world, heading, point)
			if placement.ok:
				return placement
			if placement.reason != "":
				reason = placement.reason
	return {"ok": false, "reason": reason}


func _pose_on_water(world: Node, heading: Basis, point: Vector3) -> Dictionary:
	var surface := _surface_below(world, point)
	if not surface.is_finite():
		return {"ok": false, "reason": ""}
	# The 6 m hull draws about 0.9 m; a 0.2 m puddle would ground it and leave the
	# boat sitting under the surface. Require clearance below the whole hull.
	if world.lakes.depth_at(surface - Vector3.UP * 0.9) < 0.6:
		return {"ok": false, "reason": "Water is too shallow for the boat's hull"}
	var pose := Transform3D(heading, surface + Vector3.UP * 0.28)
	var bounds := AABB(pose.origin - Vector3(3.5, 1.0, 3.5), Vector3(7.0, 3.0, 7.0))
	if not world.world_vehicle.ready_bounds(world, bounds):
		return {"ok": false, "reason": "Water area is still loading"}
	if AABB(pose.origin - Vector3(4.0, 1.0, 4.0), Vector3(8.0, 3.0, 8.0)).has_point(world.player.global_position):
		return {"ok": false, "reason": "Place the boat farther from the player"}
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.8, 6.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 15
	query.transform = Transform3D(pose.basis, pose.origin + Vector3.UP * 0.7)
	query.exclude = [world.player.get_rid()]
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {"ok": false, "reason": "Boat space is obstructed"}
	return {"ok": true, "pose": pose, "reason": ""}


func _surface_below(world: Node, point: Vector3) -> Vector3:
	# surface_near accepts a radius of at most three metres, so probe downward
	# through the range where a shore, lake or coast can be relative to the player.
	for step in range(-15, 2, 2):
		var surface: Vector3 = world.lakes.water.surface_near(point + Vector3.UP * float(step), 3.0)
		if surface.is_finite():
			return surface
	return Vector3.INF
