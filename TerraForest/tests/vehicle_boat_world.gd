# SPDX-License-Identifier: 0BSD
extends SceneTree

## Actual-world check: spawn the Boat vehicle pack on a baked volumetric lake,
## enter it, drive it, exit into the water, and confirm its fleet record saves.

const Scene = preload("res://demo/world.tscn")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const KIND := "terraforest.boat.v1"
var game: Node3D
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1


func wait_settled(water: bool = false) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if not game.loading_active and not game.terrain.pending_edit and game.terrain.world_ready:
			if not water or (game.lakes.statistics()["ready"] == 1 and game.lakes.statistics()["render_ready"]):
				return true
		await process_frame
	return false


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	game = Scene.instantiate()
	game.temporary_world = true
	root.add_child(game)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await wait_settled(), "terrain/player loading gate settles")
	if failures:
		await finish()
		return
	var point: Vector3 = game.player.global_position + Vector3(0, 0, -18)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 60, point - Vector3.UP * 60, 1))
	check(not hit.is_empty(), "lake authoring target has real terrain collision")
	if hit.is_empty():
		await finish()
		return
	var center: Vector3 = (hit["position"] as Vector3).floor()
	var lake: int = game.lakes.add_lake(center - Vector3(24, 8, 40), Vector3i(48, 12, 80), 1.0, center.y - 0.75, center - Vector3(0, 2, 0))
	var channel_a: Vector3 = center + Vector3(0, 1.5, 12)
	var channel_b: Vector3 = center + Vector3(0, 1.5, -28)
	var carved: bool = game.terrain.edit(Codec.brush(channel_a, channel_b, 6.0, 0, false, 1), channel_a, channel_b)
	if not carved:
		game.lakes.remove_lake(lake)
	check(lake > 0 and carved, "lake authoring accepts a boat-length excavation and water definition")
	check(await wait_settled(true), "worker-baked lake publishes in the real terrain scene")
	if failures:
		await finish()
		return
	game.fly = false
	game.needs_floor_spawn = false
	game.player.global_position = center + Vector3(0, 1.0, 6.0)
	game.player.rotation.y = 0
	game.yaw = 0
	game.pitch = -0.8
	game._clear_motion()
	# The Dev Spawner promises no aiming: stand on dry ground beside the lake,
	# face away from the water, and place from the nearest ready shore point.
	var provider: RefCounted = game.world_vehicle.packs.adapter(KIND)
	game.player.global_position = center + Vector3(10, 1, 0)
	game.player.rotation.y = -PI / 2
	game.yaw = -PI / 2
	game._clear_motion()
	await physics_frame
	var off_aim: Dictionary = provider.requested_pose(game)
	check(off_aim.get("ok", false), "boat placement finds nearby water without aiming: " + str(off_aim.get("reason", "")))
	if off_aim.get("ok", false):
		var pose: Transform3D = off_aim.pose
		check(Vector2(pose.origin.x - center.x, pose.origin.z - center.z).length() < 45.0, "off-aim placement lands on the nearby lake")
	game.player.global_position = center + Vector3(0, 1.0, 6.0)
	game.player.rotation.y = 0
	game.yaw = 0
	game.pitch = -0.8
	game._clear_motion()
	var spawner: RefCounted = game.session_menu.spawner
	check(spawner != null, "Dev Spawner page is available")
	var boat_index := -1
	if spawner != null:
		for index in spawner.vehicle_kind.item_count:
			if spawner.vehicle_kind.get_item_metadata(index) == KIND:
				boat_index = index
	check(boat_index >= 0, "Dev Spawner lists the Boat provider")
	if boat_index >= 0:
		spawner.vehicle_kind.select(boat_index)
		spawner.spawn_vehicle()
		var deadline := Time.get_ticks_msec() + 30000
		while is_instance_valid(game) and Time.get_ticks_msec() < deadline and (spawner.vehicle_busy or game.world_vehicle.last_spawn_identity == 0):
			await process_frame
	check(game.world_vehicle.last_spawn_identity != 0, "Dev Spawner spawns the Boat: " + spawner.menu.message.text)
	if game.world_vehicle.last_spawn_identity == 0:
		await finish()
		return
	var identity: int = game.world_vehicle.last_spawn_identity
	var boat: RigidBody3D = game.world_vehicle.activation.residents.get(identity) if game.world_vehicle.fleet_enabled else game.world_vehicle.car
	check(is_instance_valid(boat) and game.world_vehicle.kind_of(boat) == KIND, "boat becomes the live vehicle body")
	if not is_instance_valid(boat):
		await finish()
		return
	game.player.global_position = boat.global_position + Vector3(0, 0.6, 2.6)
	game.player.rotation.y = 0
	game._clear_motion()
	await physics_frame
	game.app_focused = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The check host has no capturable mouse, so bypass its on-screen gate.
	game.world_vehicle.interaction_available = func() -> bool: return true
	check(game.world_vehicle.enter(game, identity), "player enters the boat through the fleet host")
	check(game.world_vehicle.driving and Engine.physics_ticks_per_second == 120, "boat entry owns input and the 120 Hz physics rate")
	for frame in 240:
		await physics_frame
	check(boat.wet_probes == boat.probe_total() and boat.global_position.y > center.y - 3.0 and boat.global_position.y < center.y + 2.0,
		"boat floats on the actual lake surface")
	check(boat.global_basis.y.dot(Vector3.UP) > 0.95, "boat remains upright on the actual lake")
	var start := boat.global_position
	_press(KEY_W, true)
	for frame in 150:
		# Headless hosts cannot capture the mouse, so keep the host control gate open.
		boat.set_controls_enabled(true)
		await physics_frame
	var moved := Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length()
	check(moved > 6.0 and boat.speed_kph > 15.0, "boat drives across the actual lake under throttle")
	check(boat.global_basis.y.dot(Vector3.UP) > 0.9, "driving boat stays upright")
	check(boat.effects_active(), "moving boat leaves a visible wake on the lake")
	var heading_before := atan2(boat.global_basis.z.x, boat.global_basis.z.z)
	_press(KEY_D, true)
	for frame in 90:
		boat.set_controls_enabled(true)
		await physics_frame
	_press(KEY_D, false)
	_press(KEY_W, false)
	var heading_change := wrapf(atan2(boat.global_basis.z.x, boat.global_basis.z.z) - heading_before, -PI, PI)
	var chase_camera := game.get_viewport().get_camera_3d()
	var screen_right := boat.global_basis.z.dot(chase_camera.global_basis.x)
	check(heading_change < -0.08, "right rudder turns the boat right")
	check(screen_right > 0.0, "right rudder turns screen-right")
	check(game.player.global_position.y > boat.water_height + 0.05, "driver stays above the lake surface")
	check(chase_camera.global_position.y > boat.water_height + 0.3, "boat camera stays above the lake")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/vehicle_boat_world.png")
	var exit_message: String = game.world_vehicle.exit_vehicle(game)
	check(not game.world_vehicle.driving and game.player.global_position.is_finite(), "boat exit places the player in the water: " + exit_message)
	check(is_instance_valid(boat) and not boat.freeze, "boat keeps simulating after the player exits")
	await create_timer(0.5).timeout
	var snapshot: PackedByteArray = game.world_vehicle.capture_snapshot()
	check(not snapshot.is_empty() and game.world_vehicle.storage.validate_fleet_snapshot(snapshot), "boat fleet snapshot is valid versioned storage")
	check(game.world_vehicle.fleet.first_of_kind(KIND) > 0, "saved fleet retains the boat kind")
	var record: Dictionary = game.world_vehicle.fleet.get_record(game.world_vehicle.fleet.first_of_kind(KIND))
	check(record.get("present", false) and record.kind == KIND, "boat record keeps its provider identity")
	await finish()


func finish() -> void:
	if is_instance_valid(game):
		game.terrain.shutdown()
		game.queue_free()
		await process_frame
		await process_frame
	print("VEHICLE_BOAT_WORLD failures=", failures)
	quit(0 if failures == 0 else 1)
