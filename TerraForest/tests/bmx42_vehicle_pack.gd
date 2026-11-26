# SPDX-License-Identifier: 0BSD
extends SceneTree

## Actual-world acceptance for the BMX-42 vehicle pack: the Dev Spawner must
## list it, spawn it into the fleet, show the addon visual, drive it with the
## track controller, aim/fire the turret, park it and retain its typed state.

const Scene = preload("res://demo/world.tscn")
const KIND := "terraforest.bmx42.v1"
var game: Node3D
var failures := 0
var output := "res://reports/bmx42_vehicle_pack"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):
			output = argument.trim_prefix("--check-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

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

func _click(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func photograph(label: String) -> void:
	game.app_focused = true
	for frame in 4:
		await RenderingServer.frame_post_draw
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

func ground_gap(body: RigidBody3D) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		body.global_position + Vector3.UP * 6.0,
		body.global_position - Vector3.UP * 12.0,
		1, [body.get_rid(), game.player.get_rid()])
	var hit := game.get_world_3d().direct_space_state.intersect_ray(ray)
	return body.global_position.y - hit.position.y if not hit.is_empty() else INF

func place_player_beside(body: RigidBody3D) -> void:
	var at := body.global_position + body.global_basis.x * 3.0
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 8.0, at - Vector3.UP * 20.0, 1, [body.get_rid()])
	var hit := game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		at = hit.position
	game.player.global_position = at + Vector3.UP * 0.2
	game.player.velocity = Vector3.ZERO
	game._clear_motion()

func spawn_bmx(spawner: RefCounted, index: int) -> int:
	spawner.vehicle_kind.select(index)
	spawner.vehicle_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 45000
	while is_instance_valid(game) and Time.get_ticks_msec() < deadline:
		game.app_focused = true
		if not spawner.vehicle_busy and game.world_vehicle.last_spawn_identity != 0:
			break
		await process_frame
	return game.world_vehicle.last_spawn_identity

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
	var session: Node = game.world_vehicle
	var spawner: RefCounted = game.session_menu.spawner
	check(session.fleet_enabled, "world runs in the vehicle-fleet mode used by the gameplay launcher")
	check(spawner != null and session.packs.vehicles.has(KIND), "BMX-42 is an admitted vehicle provider")
	if not session.fleet_enabled or spawner == null or not session.packs.vehicles.has(KIND):
		await finish()
		return
	game.session_menu.set_open(true)
	game.session_menu.show_page("Dev Spawner")
	var index := -1
	for item in spawner.vehicle_kind.item_count:
		if String(spawner.vehicle_kind.get_item_metadata(item)) == KIND:
			index = item
	check(index >= 0, "Dev Spawner vehicle selection lists BMX-42")
	if index < 0:
		await finish()
		return
	var identity := await spawn_bmx(spawner, index)
	check(identity != 0, "Dev Spawner spawns BMX-42: " + spawner.menu.message.text)
	if identity == 0:
		await finish()
		return
	var body: RigidBody3D = session.activation.residents.get(identity)
	check(body != null and body is RigidBody3D, "BMX-42 appears as a live vehicle body")
	if body == null:
		await finish()
		return
	var model: Node3D = body.get_node_or_null("Model")
	check(model != null and model.get("initialized") == true, "BMX-42 addon visual initializes inside the fleet")
	check(model != null and model.available_animations().size() == 12, "BMX-42 keeps all 12 authored clips")
	check(session.activation.parked_views.has(KIND), "BMX-42 compact parked/far prototype configures")
	check(ground_gap(body) < 1.2, "BMX-42 parks on the sampled ground at " + str(snappedf(ground_gap(body), 0.01)) + " m")
	body.contact_monitor = true
	body.max_contacts_reported = 8
	await shot(body.global_position + body.global_basis.x * 10.0 + body.global_basis.z * 9.0 + Vector3.UP * 5.0,
		body.global_position + Vector3.UP * 1.4, "bmx42_dev_spawner")

	place_player_beside(body)
	await physics_frame
	game.app_focused = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	session.interaction_available = func() -> bool: return true
	check(session.enter(game, identity), "player enters BMX-42 through the standard vehicle host")
	check(session.driving and Engine.physics_ticks_per_second == 60, "BMX-42 entry owns input at its declared 60 Hz physics rate")
	check(not body.freeze and body.is_physics_processing(), "BMX-42 unlocks its body on entry")
	if not session.driving:
		await finish()
		return
	var start := body.global_position
	_press(KEY_W, true)
	for frame in 180:
		game.app_focused = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		body.set_controls_enabled(true)
		await physics_frame
		if frame % 30 == 0:
			var flat := body.global_basis.z
			flat.y = 0.0
			var contact_paths: Array[String] = []
			for contact in body.get_colliding_bodies():
				contact_paths.append(String(contact.get_path()))
			print("DBG frame=", frame, " freeze=", body.freeze, " sleep=", body.sleeping,
				" pos=", body.global_position, " vel=", body.linear_velocity,
				" throttle=", body.get("throttle"), " grounded=", body.call("_grounded"),
				" basis_z=", body.global_basis.z, " flat=", flat.length(),
				" rot=", body.rotation_degrees, " contacts=", contact_paths)
	_press(KEY_W, false)
	var moved := Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()
	check(moved > 1.0, "BMX-42 drives under throttle through the world: " + str(snappedf(moved, 0.1)) + " m")
	check(model.get("manual_drive") == true, "BMX-42 tracks animate while driving")
	await photograph("bmx42_driving")

	var turret: Node3D = model.get_component("Turret_Pivot")
	var before_aim: Transform3D = turret.transform
	_press(KEY_LEFT, true)
	for frame in 30:
		game.app_focused = true
		body.set_controls_enabled(true)
		await physics_frame
	_press(KEY_LEFT, false)
	check(not turret.transform.is_equal_approx(before_aim), "BMX-42 turret aims while driving")
	var clip := String(model.get("active_clip"))
	_click(true)
	for frame in 3:
		game.app_focused = true
		body.set_controls_enabled(true)
		await physics_frame
	_click(false)
	clip = String(model.get("active_clip"))
	check(clip.begins_with("Fire"), "BMX-42 fires through the vehicle controller: " + clip)
	await photograph("bmx42_firing")
	var message: String = session.exit_vehicle(game)
	check(not session.driving and message.length() > 0, "player exits BMX-42: " + message)
	if session.driving:
		await finish()
		return
	for frame in 180:
		await physics_frame
		if body.freeze:
			break
	check(body.freeze, "BMX-42 parks itself after exit")
	var snapshot: PackedByteArray = session.capture_snapshot()
	var decoded: Dictionary = session.storage.decode_fleet(snapshot)
	var saved := false
	var state_size := 0
	for row: Dictionary in decoded.get("records", []):
		if String(row.get("kind", "")) == KIND and int(row.get("identity", 0)) == identity:
			saved = true
			state_size = (row.get("state", PackedByteArray()) as PackedByteArray).size()
	check(saved and state_size == 8, "BMX-42 typed fleet record and turret state persist: " + str(state_size) + " bytes")
	await finish()

func finish() -> void:
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	await process_frame
	await process_frame
	print("BMX42_VEHICLE_PACK failures=", failures)
	quit(1 if failures else 0)
