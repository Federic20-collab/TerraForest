# SPDX-License-Identifier: 0BSD
extends SceneTree

## Vehicle-pack contract check for the boat: registration, adapter install,
## water placement, buoyancy against a host surface provider, controls, camera,
## opaque state, parking and the single-part parked prototype.

const Packs = preload("res://addons/vehicle_runtime/vehicle_packs.gd")
const KIND := "terraforest.boat.v1"
var failures := 0


class ReadyProvider extends Node:
	var focus := Vector3.ZERO
	var travel_velocity := Vector3.ZERO
	func is_collision_region_ready(_bounds: AABB) -> bool: return true


class ReadyVehicle extends Node:
	func ready_bounds(_world: Node, _bounds: AABB) -> bool: return true


class Water extends RefCounted:
	var level := 0.0
	func surface_near(point: Vector3, _radius: float) -> Vector3:
		return Vector3(point.x, level, point.z)
	func depth_at(point: Vector3) -> float:
		return maxf(0.0, level - point.y)


class Lakes extends Node:
	var water := Water.new()
	func depth_at(point: Vector3) -> float: return water.depth_at(point)


class Fixture extends Node3D:
	var lakes := Lakes.new()
	var terrain := ReadyProvider.new()
	var structures := ReadyProvider.new()
	var player := CharacterBody3D.new()
	var camera := Camera3D.new()
	var world_vehicle := ReadyVehicle.new()


func check(passed: bool, label: String) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1


func _initialize() -> void:
	run.call_deferred()


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var packs := Packs.new()
	check(packs.prepare(false) and packs.vehicles.size() == 4, "built-in providers include Ranger, Boat, Taxi and Ambulance")
	check(packs.vehicles.has(Packs.DEFAULT) and packs.vehicles.has(KIND), "both built-in vehicle kinds are present")
	check(packs.vehicles.has(KIND) and packs.vehicles[KIND].name == "Boat", "boat provider is registered by the built-in module")
	var driver: RefCounted = packs.adapter(KIND)
	check(driver != null and driver.API_VERSION == 1, "boat adapter implements vehicle API 1")
	check(packs.request(KIND), "boat scene request accepted")
	for frame in 600:
		if packs.ready(KIND): break
		await process_frame
	var scene: PackedScene = packs.take(KIND)
	check(scene != null, "boat scene loads through the pack")
	if scene == null:
		print("VEHICLE_BOAT_PACK failures=", failures)
		quit(1)
		return
	var world := Fixture.new()
	root.add_child(world)
	world.add_child(world.lakes)
	world.add_child(world.terrain)
	world.add_child(world.structures)
	world.add_child(world.player)
	world.add_child(world.camera)
	world.add_child(world.world_vehicle)
	world.player.position = Vector3(0, 1, 10)
	var body: RigidBody3D = scene.instantiate()
	world.add_child(body)
	check(driver.accepts(body), "boat body satisfies the adapter acceptance check")
	check(driver.install(body, world), "adapter binds the live lake provider and camera")
	driver.restore_parked(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
	check(driver.can_park(body, 0) == false, "restored parked boat is not reported as coasting")
	driver.controls(body, true)
	body.freeze = false
	body.set_physics_process(true)
	for frame in 360:
		await physics_frame
	check(body.wet_probes == body.probe_total() and absf(body.global_position.y - 0.23) < 0.35,
		"world boat settles on the host water surface with all probes wet")
	var rest := body.global_position
	check(driver.bounds(body).has_point(rest), "adapter reports a finite supported bounds")
	check(driver.collision(body) != null, "adapter exposes the hull collision shape")
	var parked_parts: Array = driver.parked_render_parts(body, [{ "mesh": BoxMesh.new(), "transform": Transform3D.IDENTITY }])
	check(parked_parts.size() <= 64, "parked prototype stays within the native part limit")
	driver.camera_update(body, world.camera, 0.016)
	check(world.camera.global_position.is_finite() and world.camera.global_position != Vector3.ZERO, "native chase camera follows the boat")
	check("Boat" in driver.status_text(body), "status text identifies the boat")
	_press(KEY_W, true)
	for frame in 360:
		await physics_frame
	var moved := Vector2(body.global_position.x - rest.x, body.global_position.z - rest.z).length()
	_press(KEY_W, false)
	check(moved > 8.0 and body.speed_kph > 15.0 and body.global_basis.y.dot(Vector3.UP) > 0.9,
		"throttle drives the world boat forward while upright")
	var state: PackedByteArray = driver.capture_state(body)
	check(state.is_empty() and driver.restore_state(body, state), "empty opaque state roundtrips")
	var placement: Dictionary = driver.requested_pose(world)
	check(placement.get("ok", false) and placement.pose.origin.y > 0.0,
		"water placement finds the fake lake surface instead of ground")
	if placement.get("ok", false):
		var requested := AABB(placement.pose.origin - Vector3(2.6, 1.0, 2.6), Vector3(5.2, 3.0, 5.2))
		check(not requested.has_point(world.player.global_position), "boat placement keeps clear of the player")
	driver.restore_parked(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
	check(body.freeze and body.linear_velocity == Vector3.ZERO, "parked restore freezes and clears motion")
	world.free()
	packs.finish()
	print("VEHICLE_BOAT_PACK failures=", failures)
	quit(1 if failures else 0)
