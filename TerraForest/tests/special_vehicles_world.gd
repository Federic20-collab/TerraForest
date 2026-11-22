# SPDX-License-Identifier: 0BSD
extends SceneTree

## Actual-world check for the Police and Train full-mesh packs. The Police
## exercises its authored door/wheel hierarchy; both spawn through Dev Spawner,
## sit on sampled terrain, render and drive. AirCraft has its own flight test.

const Scene = preload("res://demo/world.tscn")
const POLICE := "terraforest.police.v1"
const TRAIN := "terraforest.train.v1"
var game: Node3D
var failures := 0
var output := "res://reports/special_vehicles_world"

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
	await shot(body.global_position + Vector3(10.0, 2.2, 0.0) * side, body.global_position + Vector3.UP * 0.8, label)

func top_vehicle(body: RigidBody3D, label: String) -> void:
	await shot(body.global_position + Vector3(0.0, 24.0, 0.2), body.global_position, label)

func drive_vehicle(body: RigidBody3D, identity: int, label: String) -> void:
	game.set_physics_process(true)
	game.player.global_position = body.global_position + body.global_basis.x * 3.2
	game.player.velocity = Vector3.ZERO
	game._clear_motion()
	await physics_frame
	game.app_focused = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	check(game.world_vehicle.enter(game, identity), "player enters the " + label)
	if body.get("model_hierarchy_visuals") == true:
		await create_timer(0.8).timeout
		var hinge: Variant = body.get("driver_door_hinge")
		check(hinge != null and is_instance_valid(hinge) and absf(hinge.rotation.y) > 0.2, label + " door opens on entry")
	var start := body.global_position
	_press(KEY_W, true)
	for frame in 150:
		body.set_controls_enabled(true)
		game.app_focused = true
		await physics_frame
	_press(KEY_W, false)
	var moved := Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()
	check(moved > 1.0, label + " drives under throttle using the existing chassis controller: " + str(snappedf(moved, 0.1)) + " m")
	if body.get("model_hierarchy_visuals") == true:
		var spins: Variant = body.get("wheel_spin_pivots")
		check(spins != null and spins is Array and spins.size() == 4 and is_instance_valid(spins[0]) and absf(spins[0].rotation.x) > 0.01, label + " wheels spin while driving")
	check(game.world_vehicle.exit_vehicle(game).length() > 0 and not game.world_vehicle.driving, "player exits the " + label)

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
		if kind in [POLICE, TRAIN]: indices[kind] = index
	check(indices.has(POLICE) and indices.has(TRAIN), "Dev Spawner lists Police and Train")
	if not (indices.has(POLICE) and indices.has(TRAIN)):
		await finish()
		return
	game.world_vehicle.interaction_available = func() -> bool: return true
	game.set_physics_process(true)
	var police_id: int = await spawn(indices[POLICE], POLICE)
	if police_id == 0:
		await finish()
		return
	var police: RigidBody3D = game.world_vehicle.activation.residents.get(police_id)
	check(is_instance_valid(police) and game.world_vehicle.kind_of(police) == POLICE, "Police becomes a live fleet resident")
	if not is_instance_valid(police):
		await finish()
		return
	await create_timer(1.2).timeout
	game.set_physics_process(false)
	game._clear_motion()
	await frame_vehicle(police, 1.0, "police_spawned")
	await top_vehicle(police, "police_top")
	var police_bounds := _visual_bounds(police)
	check(police_bounds.size.z > 4.6 and police_bounds.size.z < 5.0, "Police full mesh is visible at car length " + str(snappedf(police_bounds.size.z, 0.01)))
	check(_ground_gap(police) < 0.25, "Police parks on the actual sampled ground")
	check(await _mesh_visible(police), "Police full mesh renders with its animated hierarchy")
	check(game.world_vehicle.activation.parked_views.has(POLICE), "Police compact parked prototype configures")
	await drive_vehicle(police, police_id, "Police")
	await create_timer(0.3).timeout
	game.player.rotation.y = police.global_rotation.y
	game.yaw = police.global_rotation.y
	game.set_physics_process(true)
	var train_id: int = await spawn(indices[TRAIN], TRAIN)
	if train_id == 0:
		await finish()
		return
	var train: RigidBody3D = game.world_vehicle.activation.residents.get(train_id)
	check(is_instance_valid(train) and game.world_vehicle.kind_of(train) == TRAIN, "Train becomes a live fleet resident")
	if not is_instance_valid(train):
		await finish()
		return
	await create_timer(1.2).timeout
	game.set_physics_process(false)
	game._clear_motion()
	await frame_vehicle(train, -1.0, "train_spawned")
	await top_vehicle(train, "train_top")
	var train_bounds := _visual_bounds(train)
	check(train_bounds.size.z > 6.2 and train_bounds.size.z < 6.6, "Train full mesh is visible at car length " + str(snappedf(train_bounds.size.z, 0.01)))
	check(_ground_gap(train) < 0.25, "Train parks on the actual sampled ground")
	check(await _mesh_visible(train), "Train full mesh renders after its wheel/door bindings are skipped")
	await drive_vehicle(train, train_id, "Train")
	var snapshot: PackedByteArray = game.world_vehicle.capture_snapshot()
	check(not snapshot.is_empty() and game.world_vehicle.storage.validate_fleet_snapshot(snapshot), "special vehicle fleet snapshot is valid versioned storage")
	check(game.world_vehicle.fleet.first_of_kind(POLICE) > 0 and game.world_vehicle.fleet.first_of_kind(TRAIN) > 0, "snapshot retains Police and Train identities")
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
	var ground = _ground(body)
	if ground == null or not is_finite(lowest): return INF
	return absf(lowest - float(ground.y))

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
	print("SPECIAL_VEHICLES_WORLD failures=", failures)
	quit(1 if failures else 0)
