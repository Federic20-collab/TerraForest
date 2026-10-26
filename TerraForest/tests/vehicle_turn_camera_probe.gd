# SPDX-License-Identifier: 0BSD
extends SceneTree

const WARMUP_TICKS := 180
const TURN_TICKS := 420
const SAMPLE_EVERY := 30

var _samples: Array[Dictionary] = []
var _previous_camera_yaw := 0.0
var _have_previous_camera_yaw := false

func _initialize() -> void:
	call_deferred("run")

func _set_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _camera_yaw(camera: Camera3D) -> float:
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	return atan2(forward.x, forward.z)

func run() -> void:
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 120
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")

	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(500.0, 1.0, 500.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor.add_child(floor_shape)
	root.add_child(floor)

	var car = load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.position = Vector3(0.0, 0.62, 0.0)
	root.add_child(car)

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 72.0
	camera.near = 0.08
	root.add_child(camera)
	var follow: RefCounted = ClassDB.instantiate("NativeVehicleCamera")

	for _tick in 12:
		await physics_frame
	for _tick in 12:
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame

	_set_key(KEY_W, true)
	for _tick in WARMUP_TICKS:
		_set_key(KEY_W, true)
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame

	_set_key(KEY_A, true)
	var elapsed := 0.0
	for tick in TURN_TICKS:
		# Synthetic key state can be cleared by focus changes in the test window;
		# re-assert the held controls so this measures a continuous full-lock turn.
		_set_key(KEY_W, true)
		_set_key(KEY_A, true)
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame
		elapsed += 1.0 / 120.0
		var camera_yaw := _camera_yaw(camera)
		var camera_yaw_rate := 0.0
		if _have_previous_camera_yaw:
			camera_yaw_rate = rad_to_deg(wrapf(camera_yaw - _previous_camera_yaw, -PI, PI) / (1.0 / 120.0))
		_previous_camera_yaw = camera_yaw
		_have_previous_camera_yaw = true
		if tick % SAMPLE_EVERY == 0:
			var planar_velocity: Vector3 = car.linear_velocity
			planar_velocity.y = 0.0
			var speed := planar_velocity.length()
			var yaw_rate := rad_to_deg(car.angular_velocity.dot(Vector3.UP))
			var radius := INF
			if absf(yaw_rate) > 0.01:
				radius = speed / deg_to_rad(absf(yaw_rate))
			_samples.append({
				"t": elapsed,
				"speed_mps": speed,
				"speed_kph": speed * 3.6,
				"yaw_rate_deg_s": yaw_rate,
				"steering_deg": car.steering_degrees,
				"turn_radius_m": radius,
				"camera_yaw_rate_deg_s": camera_yaw_rate,
				"camera_distance_m": camera.global_position.distance_to(car.global_position),
				"loaded_wheels": car.loaded_wheels,
			})

	_set_key(KEY_A, false)
	_set_key(KEY_W, false)
	await physics_frame

	var tail: Array = _samples.slice(maxi(0, _samples.size() - 6))
	var speed_sum := 0.0
	var yaw_sum := 0.0
	var camera_yaw_sum := 0.0
	var radius_sum := 0.0
	var distance_sum := 0.0
	for sample: Dictionary in tail:
		speed_sum += float(sample["speed_mps"])
		yaw_sum += absf(float(sample["yaw_rate_deg_s"]))
		camera_yaw_sum += absf(float(sample["camera_yaw_rate_deg_s"]))
		radius_sum += float(sample["turn_radius_m"])
		distance_sum += float(sample["camera_distance_m"])
	var count := float(maxi(tail.size(), 1))
	var average_speed := speed_sum / count
	var average_yaw := yaw_sum / count
	var average_camera_yaw := camera_yaw_sum / count
	var average_radius := radius_sum / count
	var average_distance := distance_sum / count
	var camera_ratio := average_camera_yaw / maxf(average_yaw, 0.001)
	var passed := (
		average_speed > 5.0
		and average_yaw > 10.0
		and average_radius > 5.0
		and average_camera_yaw > 5.0
		and average_distance < 15.0
	)
	var report := {
		"passed": passed,
		"warmup_ticks": WARMUP_TICKS,
		"turn_ticks": TURN_TICKS,
		"average_speed_mps": average_speed,
		"average_speed_kph": average_speed * 3.6,
		"average_car_yaw_rate_deg_s": average_yaw,
		"average_camera_yaw_rate_deg_s": average_camera_yaw,
		"camera_to_car_yaw_ratio": camera_ratio,
		"average_turn_radius_m": average_radius,
		"average_camera_distance_m": average_distance,
		"tail_samples": tail,
		"all_samples": _samples,
	}
	print("TURN_CAMERA_PROBE ", JSON.stringify({
		"passed": passed,
		"average_speed_kph": average_speed * 3.6,
		"average_car_yaw_rate_deg_s": average_yaw,
		"average_camera_yaw_rate_deg_s": average_camera_yaw,
		"camera_to_car_yaw_ratio": camera_ratio,
		"average_turn_radius_m": average_radius,
		"average_camera_distance_m": average_distance,
	}))
	var report_file := FileAccess.open("res://reports/vehicle_turn_camera_probe.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "  "))
		report_file.close()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_turn_camera_probe.png")
	quit(0 if passed else 1)
