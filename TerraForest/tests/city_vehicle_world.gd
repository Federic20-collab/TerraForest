# SPDX-License-Identifier: 0BSD
extends SceneTree

## Actual-world check: spawn the Taxi, FireTruck and Ambulance providers through
## the Dev Spawner, confirm their full meshes are visible, drive the Taxi, and
## verify all typed fleet records persist in the compound vehicle snapshot.

const Scene = preload("res://demo/world.tscn")
const TAXI := "terraforest.taxi.v1"
const AMBULANCE := "terraforest.ambulance.v1"
const FIRETRUCK := "terraforest.firetruck.v1"
var game: Node3D
var failures := 0
var output := "res://reports/city_vehicle_world"

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

func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func spawn(index: int, kind: String) -> int:
	var spawner: RefCounted = game.session_menu.spawner
	spawner.vehicle_kind.select(index)
	spawner.vehicle_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 30000
	while is_instance_valid(game) and Time.get_ticks_msec() < deadline and (spawner.vehicle_busy or game.world_vehicle.last_spawn_identity == 0):
		game.app_focused = true
		await process_frame
	var identity: int = game.world_vehicle.last_spawn_identity
	check(identity != 0, "Dev Spawner creates " + kind + ": " + spawner.menu.message.text)
	return identity

func photograph(label: String) -> void:
	game.app_focused = true
	for frame in 4: await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func shot(position: Vector3, target: Vector3, label: String) -> void:
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.08
	camera.far = 2000.0
	game.add_child(camera)
	camera.top_level = true
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	camera.current = true
	await photograph(label)
	camera.queue_free()
	await process_frame
	game.camera.current = true

func frame_vehicle(body: RigidBody3D, side: float, label: String) -> void:
	await shot(body.global_position + Vector3(9.0, 2.0, 0.0) * side, body.global_position + Vector3.UP * 0.7, label)

func top_vehicle(body: RigidBody3D, label: String) -> void:
	await shot(body.global_position + Vector3(0.0, 20.0, 0.2), body.global_position, label)

func run() -> void:
	game = Scene.instantiate()
	game.temporary_world = true
	game.background_fps = 60
	game.player_view.settings_path = ""
	root.add_child(game)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await wait_settled(), "temporary world and streamed terrain finish loading")
	if failures:
		await finish()
		return
	game.fly = false
	game.needs_floor_spawn = false
	game.set_physics_process(false)
	game._clear_motion()
	var spawner: RefCounted = game.session_menu.spawner
	check(spawner != null, "Dev Spawner page is available")
	if spawner == null:
		await finish()
		return
	game.session_menu.set_open(true)
	game.session_menu.show_page("Dev Spawner")
	var indices := {}
	for index in spawner.vehicle_kind.item_count:
		var kind: String = spawner.vehicle_kind.get_item_metadata(index)
		if kind in [TAXI, AMBULANCE, FIRETRUCK]: indices[kind] = index
	check(indices.has(TAXI) and indices.has(AMBULANCE) and indices.has(FIRETRUCK), "Dev Spawner lists all city vehicle providers")
	if not (indices.has(TAXI) and indices.has(AMBULANCE) and indices.has(FIRETRUCK)):
		await finish()
		return
	game.set_physics_process(true)
	var taxi_id: int = await spawn(indices[TAXI], TAXI)
	if taxi_id == 0:
		await finish()
		return
	var taxi: RigidBody3D = game.world_vehicle.activation.residents.get(taxi_id)
	check(is_instance_valid(taxi) and game.world_vehicle.kind_of(taxi) == TAXI, "Taxi becomes a live fleet resident")
	if not is_instance_valid(taxi):
		await finish()
		return
	await create_timer(1.2).timeout
	game.set_physics_process(false)
	game._clear_motion()
	await frame_vehicle(taxi, 1.0, "taxi_spawned")
	await top_vehicle(taxi, "taxi_top")
	var taxi_bounds := _visual_bounds(taxi)
	check(taxi_bounds.size.z > 4.4 and taxi_bounds.size.z < 5.0, "Taxi full mesh is visible at car length " + str(snappedf(taxi_bounds.size.z, 0.01)))
	check(_ground_gap(taxi) < 0.25, "Taxi parks on the actual sampled ground")
	print("CITY_VEHICLE_GROUND taxi body=", taxi.global_position, " gap=", _ground_gap(taxi), " ground=", _ground(taxi))
	check(await _mesh_visible(taxi), "Taxi full mesh renders after its wheel/door bindings are skipped")
	# Reuse the proven chassis controller: enter the Taxi and drive onto the open
	# grass. The second spawn then happens in that clear area.
	game.set_physics_process(true)
	game.player.global_position = taxi.global_position + taxi.global_basis.x * 2.6
	game.player.velocity = Vector3.ZERO
	game._clear_motion()
	await physics_frame
	game.app_focused = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.world_vehicle.interaction_available = func() -> bool: return true
	check(game.world_vehicle.enter(game, taxi_id), "player enters the Taxi through the standard vehicle host")
	check(game.world_vehicle.driving and Engine.physics_ticks_per_second == 120, "Taxi entry owns input and the 120 Hz physics rate")
	var start := taxi.global_position
	_press(KEY_W, true)
	for frame in 240:
		taxi.set_controls_enabled(true)
		game.app_focused = true
		await physics_frame
	_press(KEY_W, false)
	var moved := Vector2(taxi.global_position.x - start.x, taxi.global_position.z - start.z).length()
	check(moved > 2.0, "Taxi drives under throttle using the existing chassis controller: " + str(snappedf(moved, 0.1)) + " m")
	await frame_vehicle(taxi, 1.0, "taxi_driving")
	check(game.world_vehicle.exit_vehicle(game).length() > 0 and not game.world_vehicle.driving, "player exits the Taxi")
	game.player.rotation.y = taxi.global_rotation.y
	game.yaw = taxi.global_rotation.y
	await create_timer(0.3).timeout
	game.set_physics_process(true)
	var firetruck_id: int = await spawn(indices[FIRETRUCK], FIRETRUCK)
	if firetruck_id == 0:
		await finish()
		return
	var firetruck: RigidBody3D = game.world_vehicle.activation.residents.get(firetruck_id)
	check(is_instance_valid(firetruck) and game.world_vehicle.kind_of(firetruck) == FIRETRUCK, "FireTruck becomes a live fleet resident")
	if not is_instance_valid(firetruck):
		await finish()
		return
	await create_timer(1.2).timeout
	game.set_physics_process(false)
	game._clear_motion()
	await frame_vehicle(firetruck, -1.0, "firetruck_spawned")
	await top_vehicle(firetruck, "firetruck_top")
	var firetruck_bounds := _visual_bounds(firetruck)
	check(firetruck_bounds.size.z > 6.2 and firetruck_bounds.size.z < 6.6, "FireTruck full mesh is visible at truck length " + str(snappedf(firetruck_bounds.size.z, 0.01)))
	check(_ground_gap(firetruck) < 0.25, "FireTruck parks on the actual sampled ground")
	print("CITY_VEHICLE_GROUND firetruck body=", firetruck.global_position, " gap=", _ground_gap(firetruck), " ground=", _ground(firetruck))
	check(await _mesh_visible(firetruck), "FireTruck full mesh renders after its wheel/door bindings are skipped")
	game.set_physics_process(true)
	game.player.global_position = firetruck.global_position + firetruck.global_basis.x * 3.2
	game.player.velocity = Vector3.ZERO
	game._clear_motion()
	await physics_frame
	game.app_focused = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	check(game.world_vehicle.enter(game, firetruck_id), "player enters the FireTruck through the standard vehicle host")
	var truck_start := firetruck.global_position
	_press(KEY_W, true)
	for frame in 150:
		firetruck.set_controls_enabled(true)
		game.app_focused = true
		await physics_frame
	_press(KEY_W, false)
	var truck_moved := Vector2(firetruck.global_position.x - truck_start.x, firetruck.global_position.z - truck_start.z).length()
	check(truck_moved > 1.0, "FireTruck drives under throttle using the existing chassis controller: " + str(snappedf(truck_moved, 0.1)) + " m")
	check(game.world_vehicle.exit_vehicle(game).length() > 0 and not game.world_vehicle.driving, "player exits the FireTruck")
	game.player.rotation.y = wrapf(game.player.rotation.y + PI, -PI, PI)
	game.yaw = game.player.rotation.y
	game.set_physics_process(true)
	var ambulance_id: int = await spawn(indices[AMBULANCE], AMBULANCE)
	if ambulance_id == 0:
		await finish()
		return
	var ambulance: RigidBody3D = game.world_vehicle.activation.residents.get(ambulance_id)
	check(is_instance_valid(ambulance) and game.world_vehicle.kind_of(ambulance) == AMBULANCE, "Ambulance becomes a live fleet resident")
	if not is_instance_valid(ambulance):
		await finish()
		return
	await create_timer(1.2).timeout
	game.set_physics_process(false)
	game._clear_motion()
	await frame_vehicle(ambulance, -1.0, "ambulance_spawned")
	await top_vehicle(ambulance, "ambulance_top")
	var ambulance_bounds := _visual_bounds(ambulance)
	check(ambulance_bounds.size.z > 5.1 and ambulance_bounds.size.z < 5.7, "Ambulance full mesh is visible at van length " + str(snappedf(ambulance_bounds.size.z, 0.01)))
	check(_ground_gap(ambulance) < 0.25, "Ambulance parks on the actual sampled ground")
	print("CITY_VEHICLE_GROUND ambulance body=", ambulance.global_position, " gap=", _ground_gap(ambulance), " ground=", _ground(ambulance))
	check(await _mesh_visible(ambulance), "Ambulance full mesh renders after its wheel/door bindings are skipped")
	var snapshot: PackedByteArray = game.world_vehicle.capture_snapshot()
	check(not snapshot.is_empty() and game.world_vehicle.storage.validate_fleet_snapshot(snapshot), "city vehicle fleet snapshot is valid versioned storage")
	check(game.world_vehicle.fleet.first_of_kind(TAXI) > 0 and game.world_vehicle.fleet.first_of_kind(AMBULANCE) > 0 and game.world_vehicle.fleet.first_of_kind(FIRETRUCK) > 0, "snapshot retains all typed vehicle identities")
	await finish()

func _visual_bounds(body: RigidBody3D) -> AABB:
	var result := AABB()
	var first := true
	var inverse := body.global_transform.affine_inverse()
	for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null or not node.is_visible_in_tree(): continue
		var box: AABB = (inverse * node.global_transform) * node.mesh.get_aabb()
		if first: result = box; first = false
		else: result = result.merge(box)
	return result

func _ground(body: RigidBody3D) -> Variant:
	var ray := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 30.0, body.global_position - Vector3.UP * 60.0, 1, [body.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() else null

func _ground_gap(body: RigidBody3D) -> float:
	var lowest := INF
	for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null or not node.is_visible_in_tree(): continue
		lowest = minf(lowest, (node.global_transform * node.mesh.get_aabb()).position.y)
	var ray := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 3.0, body.global_position - Vector3.UP * 10.0, 1, [body.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not is_finite(lowest): return INF
	return absf(lowest - hit.position.y)

func _mesh_visible(body: RigidBody3D) -> bool:
	await RenderingServer.frame_post_draw
	var visible := 0
	for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if node.mesh != null and node.is_visible_in_tree() and node.mesh.get_surface_count() > 0:
			visible += 1
	return visible > 0

func finish() -> void:
	if is_instance_valid(game):
		game.terrain.shutdown()
		game.queue_free()
		await process_frame
		await process_frame
	print("CITY_VEHICLE_WORLD failures=", failures)
	quit(1 if failures else 0)
