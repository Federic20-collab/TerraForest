# SPDX-License-Identifier: 0BSD
extends SceneTree

## Isolated flight check: flat pad, 10 m aircraft, real controller and adapter.
## Proves takeoff/climb, forward flight, chase camera, reset and parking.

const Scene = preload("res://vehicle_demo/scenes/aircraft.tscn")
const Adapter = preload("res://addons/vehicle_runtime/aircraft_adapter.gd")

class ReadyProvider extends Node:
	var focus := Vector3.ZERO
	var travel_velocity := Vector3.ZERO
	var require_collision := false
	func is_collision_region_ready(_bounds: AABB) -> bool: return true

class World extends Node3D:
	var terrain := ReadyProvider.new()
	var structures := ReadyProvider.new()
	var vegetation := ReadyProvider.new()
	var camera := Camera3D.new()

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize() -> void:
	run.call_deferred()

func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.add_child(world.terrain)
	world.add_child(world.structures)
	world.add_child(world.vegetation)
	world.add_child(world.camera)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	world.add_child(floor)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(300, 0.2, 300)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0, -0.1, 0)
	floor.add_child(floor_collision)
	var aircraft: RigidBody3D = Scene.instantiate()
	world.add_child(aircraft)
	var adapter: RefCounted = Adapter.new()
	check(adapter.accepts(aircraft), "aircraft adapter accepts the flight body")
	check(adapter.install(aircraft, world), "aircraft binds flight streaming and vegetation")
	check(adapter.collision(aircraft) != null and adapter.bounds(aircraft).size.length() > 9.0, "aircraft exposes its chassis and large edit bounds")
	var pose := Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0))
	adapter.restore_parked(aircraft, pose)
	check(aircraft.global_position.is_equal_approx(pose.origin) and aircraft.freeze, "aircraft parks frozen at the supplied pose")
	check(adapter.status_text(aircraft).contains("AirCraft") and adapter.status_text(aircraft).contains("alt"), "status text identifies aircraft and altitude")
	adapter.controls(aircraft, true)
	aircraft.freeze = false
	aircraft.set_physics_process(true)
	for frame in 20:
		aircraft.set_controls_enabled(true)
		await physics_frame
	var start := aircraft.global_position
	_press(KEY_W, true)
	for frame in 600:
		aircraft.set_controls_enabled(true)
		await physics_frame
		if aircraft.global_position.y > start.y + 8.0:
			break
	_press(KEY_W, false)
	var climbed := aircraft.global_position.y - start.y
	var flown := Vector2(aircraft.global_position.x - start.x, aircraft.global_position.z - start.z).length()
	check(climbed > 6.0, "aircraft takes off and climbs: " + str(snappedf(climbed, 0.1)) + " m")
	check(flown > 6.0, "aircraft moves forward under throttle: " + str(snappedf(flown, 0.1)) + " m")
	check(aircraft.altitude > 5.0 and aircraft.speed_kph > 30.0, "flight telemetry reports altitude and speed")
	adapter.camera_update(aircraft, world.camera, 1.0 / 120.0)
	check(world.camera.global_position.is_finite() and world.camera.global_position.distance_to(aircraft.global_position) > 8.0, "aircraft chase camera follows at flight distance")
	var heading_before := atan2(aircraft.global_basis.z.x, aircraft.global_basis.z.z)
	_press(KEY_D, true)
	for frame in 180:
		aircraft.set_controls_enabled(true)
		await physics_frame
	_press(KEY_D, false)
	var heading_after := atan2(aircraft.global_basis.z.x, aircraft.global_basis.z.z)
	check(absf(wrapf(heading_after - heading_before, -PI, PI)) > 0.08, "right bank turns the aircraft")
	aircraft.reset_aircraft()
	for frame in 20:
		aircraft.set_controls_enabled(true)
		await physics_frame
	_press(KEY_W, true)
	for frame in 600:
		aircraft.set_controls_enabled(true)
		await physics_frame
		if aircraft.altitude > 8.0:
			break
	_press(KEY_W, false)
	var flight_altitude: float = aircraft.altitude
	_press(KEY_DOWN, true)
	for frame in 180:
		aircraft.set_controls_enabled(true)
		await physics_frame
	_press(KEY_DOWN, false)
	check(aircraft.altitude < flight_altitude - 2.0, "pitch-down input descends the aircraft")
	aircraft.reset_aircraft()
	await physics_frame
	await physics_frame
	check(aircraft.global_position.distance_to(start) < 1.0, "aircraft reset returns to the takeoff pose")
	check(aircraft.can_park(Engine.get_physics_frames()), "reset aircraft reports a valid parked state")
	adapter.controls(aircraft, false)
	print("AIRCRAFT_FLIGHT failures=", failures)
	quit(1 if failures else 0)
