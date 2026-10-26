# SPDX-License-Identifier: 0BSD
extends SceneTree

const SETTLE_TICKS := 120
const HOLD_TICKS := 6
const RELEASE_TICKS := 120

func _initialize() -> void:
	call_deferred("run")

func _set_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	Engine.physics_ticks_per_second = 120
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var use_space: bool = not ("--no-space" in OS.get_cmdline_user_args())
	var static_test: bool = "--static" in OS.get_cmdline_user_args()

	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	floor.add_child(floor_shape)
	root.add_child(floor)

	# A low front-wheel bump creates uneven suspension compression while the
	# handbrake is held; releasing Space should not launch the body.
	var bump := StaticBody3D.new()
	bump.collision_layer = 1
	var bump_shape := CollisionShape3D.new()
	var bump_box := BoxShape3D.new()
	bump_box.size = Vector3(2.2, 0.28, 1.2)
	bump_shape.shape = bump_box
	bump_shape.position = Vector3(0, 0.14, 1.43)
	bump.add_child(bump_shape)
	root.add_child(bump)

	var car = load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.position = Vector3(0, 0.62, 0.0 if static_test else -4.0)
	root.add_child(car)
	var camera := Camera3D.new()
	camera.current = true
	root.add_child(camera)
	var follow: RefCounted = ClassDB.instantiate("NativeVehicleCamera")

	for _tick in SETTLE_TICKS:
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame
	var loaded_before: int = car.loaded_wheels
	if not static_test:
		_set_key(KEY_W, true)
		for _tick in 240:
			_set_key(KEY_W, true)
			follow.update(car, camera, 1.0 / 120.0)
			await physics_frame
			if car.global_position.z >= 0.0:
				break
		_set_key(KEY_W, false)
	var hold_y: float = car.global_position.y
	var hold_camera_y: float = camera.global_position.y
	var hold_start_position: Vector3 = car.global_position
	if use_space:
		_set_key(KEY_SPACE, true)
	for _tick in HOLD_TICKS:
		if use_space:
			_set_key(KEY_SPACE, true)
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame
	var hold_settled_y: float = car.global_position.y
	var hold_camera_settled_y: float = camera.global_position.y
	var hold_horizontal_drift: float = (car.global_position - hold_start_position).slide(Vector3.UP).length()
	if use_space:
		_set_key(KEY_SPACE, false)
	var max_y: float = hold_settled_y
	var max_camera_y: float = hold_camera_settled_y
	var max_up_speed: float = -INF
	for _tick in RELEASE_TICKS:
		follow.update(car, camera, 1.0 / 120.0)
		await physics_frame
		max_y = maxf(max_y, car.global_position.y)
		max_camera_y = maxf(max_camera_y, camera.global_position.y)
		max_up_speed = maxf(max_up_speed, car.linear_velocity.y)
	var report := {
		"loaded_wheels_before": loaded_before,
		"used_space": use_space,
		"static_test": static_test,
		"bump_height_m": 0.28,
		"hold_y": hold_y,
		"hold_settled_y": hold_settled_y,
		"hold_horizontal_drift_m": hold_horizontal_drift,
		"release_y_gain_m": max_y - hold_settled_y,
		"camera_release_y_gain_m": max_camera_y - hold_camera_settled_y,
		"release_peak_up_speed_mps": max_up_speed,
		"final_y": car.global_position.y,
		"final_speed_mps": car.linear_velocity.length(),
	}
	print("HANDBRAKE_BUMP ", JSON.stringify(report))
	var report_path := "res://reports/vehicle_handbrake_bump.json" if use_space else "res://reports/vehicle_handbrake_bump_control.json"
	if static_test:
		report_path = "res://reports/vehicle_handbrake_bump_static.json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0)
