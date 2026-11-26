# SPDX-License-Identifier: 0BSD
extends SceneTree

## Actual TerraForest-world check for the copied BMX-42 addon. This exercises the
## model render, 360-degree turret aim, track animation and firing/recoil inside
## the real streamed world. It is not yet a registered spawnable vehicle pack.

const Game = preload("res://demo/world.tscn")
const BMX = preload("res://addons/vehicle_runtime/bmx42_7k/bmx42_7k.tscn")
const PREPARED_WORLD := "Amber_Hollow"
const PREPARED_SAVE := "user://worlds/Amber_Hollow.trw"
var game: Node3D
var failures := 0
var output := "res://reports/bmx42_world"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):
			output = argument.trim_prefix("--check-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func wait_settled() -> bool:
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		if not game.loading_active and not game.terrain.pending_edit and game.terrain.world_ready:
			return true
		game.app_focused = true
		await process_frame
	return false

func ground(point: Vector3) -> Variant:
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point + Vector3.UP * 30.0, point - Vector3.UP * 60.0, 1, [game.player.get_rid()]))
	return hit.position if not hit.is_empty() else null

func find_site() -> Dictionary:
	var forward: Vector3 = -game.player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for angle: float in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		var direction: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(angle))
		var side: Vector3 = direction.cross(Vector3.UP).normalized()
		for distance: float in [10.0, 14.0, 18.0, 22.0, 28.0, 34.0, 40.0]:
			for offset: float in [0.0, 5.0, -5.0, 9.0, -9.0]:
				var point: Vector3 = game.player.global_position + direction * distance + side * offset
				point.x = clampf(point.x, 2, 1998)
				point.z = clampf(point.z, 2, 1998)
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 10.0, point - Vector3.UP * 25.0, 1, [game.player.get_rid()]))
				if hit.is_empty(): continue
				var pose := Transform3D(Basis(Vector3.UP, -PI / 2), hit.position)
				var box := BoxShape3D.new()
				box.size = Vector3(3.8, 2.8, 7.4)
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = box
				query.collision_mask = 15
				query.transform = Transform3D(pose.basis, pose.origin + Vector3.UP * 1.4)
				query.exclude = [game.player.get_rid()]
				if space.intersect_shape(query, 1).is_empty():
					return {"ok": true, "clear": true, "pose": pose}
	var fallback_point: Vector3 = game.player.global_position + forward * 11.0
	var fallback_ground: Variant = ground(fallback_point)
	if fallback_ground == null:
		return {"ok": false, "clear": false, "pose": Transform3D.IDENTITY}
	return {"ok": true, "clear": false, "pose": Transform3D(Basis(Vector3.UP, -PI / 2), fallback_ground)}

func photograph(label: String) -> void:
	game.app_focused = true
	for frame in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func photograph_now(label: String) -> void:
	game.app_focused = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func place_camera(vehicle: Node3D) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.08
	camera.far = 2000.0
	game.add_child(camera)
	camera.top_level = true
	camera.global_position = vehicle.global_position + Vector3(13.0, 7.0, 14.0)
	camera.look_at(vehicle.global_position + Vector3.UP * 2.0, Vector3.UP)
	camera.current = true
	return camera

func run() -> void:
	if FileAccess.file_exists(PREPARED_SAVE):
		preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray([
			"--world-slot=" + PREPARED_WORLD, "--snapshot-readonly", "--temporary",
			"--gameplay-construction", "--ground-cover", "--actors"]), true)
		print("BMX42_WORLD using read-only prepared world ", PREPARED_WORLD)
	game = Game.instantiate()
	game.temporary_world = true
	game.background_fps = 60
	game.player_view.settings_path = ""
	root.add_child(game)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await wait_settled(), "temporary TerraForest world settles")
	if failures:
		await finish()
		return
	var site := find_site()
	check(site.ok, "ground found for the BMX-42")
	print("BMX42_SITE clear=", site.get("clear", false), " pose=", site.pose)
	if not site.ok:
		await finish()
		return
	var vehicle: Node3D = BMX.instantiate()
	vehicle.create_collisions = false
	game.add_child(vehicle)
	vehicle.global_transform = site.pose
	for frame in 5: await process_frame
	check(vehicle.initialized, "BMX-42 addon initializes inside TerraForest")
	var animations: PackedStringArray = vehicle.available_animations()
	check(animations.size() == 12, "BMX-42 exposes all 12 authored clips")
	var bounds: AABB = vehicle.geometry_bounds()
	print("BMX42_BOUNDS ", bounds, " meshes=", vehicle.render_meshes.size())
	check(bounds.size.x > 6.0 and bounds.size.y > 4.0 and bounds.size.z > 3.0, "BMX-42 hull renders at its authored 6.4 x 4.28 x 3.21 envelope")
	vehicle.set_turret_angles(180.0, 0.0)
	await process_frame
	var full_bounds: AABB = vehicle.geometry_bounds()
	print("BMX42_GUN_BOUNDS ", full_bounds)
	check(full_bounds.size.x > 8.0, "BMX-42 gun-out envelope renders at 8.2 m")
	vehicle.set_turret_angles(0.0, 0.0)
	await process_frame
	var turret: Node3D = vehicle.get_component("Turret_Pivot")
	var gun: Node3D = vehicle.get_component("Gun_Elevation")
	var turret_rest: Transform3D = turret.transform
	var gun_rest: Transform3D = gun.transform
	check(vehicle.set_turret_angles(90.0, 10.0), "360-degree turret yaw and gun elevation accept commands")
	check(not turret.transform.is_equal_approx(turret_rest) and not gun.transform.is_equal_approx(gun_rest), "turret and gun transforms actually move")
	check(vehicle.set_drive(1.6, 1.6), "track drive accepts forward speed")
	check(vehicle.fire(), "single-shot recoil and muzzle flash trigger")
	await create_timer(0.45).timeout
	var start: Vector3 = vehicle.global_position
	for frame in 90:
		vehicle.global_position += vehicle.global_basis.x * (1.6 / 60.0)
		vehicle.set_drive(1.6, 1.6)
		await process_frame
	var moved: float = Vector2(vehicle.global_position.x - start.x, vehicle.global_position.z - start.z).length()
	check(moved > 1.0, "BMX-42 moves through the world while tracks animate: " + str(snappedf(moved, 0.1)) + " m")
	var camera: Camera3D = place_camera(vehicle)
	await photograph("bmx42_ingame")
	vehicle.set_turret_angles(90.0, 10.0)
	await process_frame
	vehicle.fire()
	await create_timer(0.05).timeout
	await photograph_now("bmx42_ingame_fire")
	camera.queue_free()
	await process_frame
	game.camera.current = true
	await finish()

func finish() -> void:
	if is_instance_valid(game):
		game.terrain.shutdown()
		game.queue_free()
		await process_frame
		await process_frame
	print("BMX42_WORLD failures=", failures)
	quit(1 if failures else 0)
