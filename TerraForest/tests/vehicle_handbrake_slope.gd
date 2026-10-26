# SPDX-License-Identifier: 0BSD
extends SceneTree

const SLOPE_DEGREES := 20.0
const SETTLE_TICKS := 120
const HOLD_TICKS := 240
const START_SPEED := 5.0

func _initialize() -> void:
	call_deferred("run")

func _set_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _heading(car: Node3D) -> float:
	var forward: Vector3 = car.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0.0
	return atan2(forward.x, forward.z)

func run() -> void:
	Engine.physics_ticks_per_second = 120
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var angle := deg_to_rad(SLOPE_DEGREES)
	var up := Vector3(0.0, cos(angle), -sin(angle))
	var forward := Vector3(0.0, sin(angle), cos(angle))
	var plane_rise := tan(angle)
	var span := 40.0

	var slope := StaticBody3D.new()
	slope.collision_layer = 1
	var slope_collider := CollisionShape3D.new()
	var slope_shape := ConcavePolygonShape3D.new()
	slope_shape.set_faces(PackedVector3Array([
		Vector3(-span, -span * plane_rise, -span),
		Vector3(span, -span * plane_rise, -span),
		Vector3(span, span * plane_rise, span),
		Vector3(-span, -span * plane_rise, -span),
		Vector3(span, span * plane_rise, span),
		Vector3(-span, span * plane_rise, span),
	]))
	slope_shape.backface_collision = true
	slope_collider.shape = slope_shape
	slope.add_child(slope_collider)
	root.add_child(slope)

	var basis := Basis()
	basis.x = up.cross(forward)
	basis.y = up
	basis.z = forward
	var car = load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.transform = Transform3D(basis, up * 0.62)
	root.add_child(car)

	for _tick in SETTLE_TICKS:
		await physics_frame
	var loaded_before: int = car.loaded_wheels
	var rest_start: Vector3 = car.global_position
	_set_key(KEY_SPACE, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_SPACE, true)
		await physics_frame
	var rest_hold_drift: float = (car.global_position - rest_start).slide(up).length()
	var rest_hold_speed: Vector3 = car.linear_velocity.slide(up)
	_set_key(KEY_SPACE, false)
	for _tick in 24:
		await physics_frame
	car.linear_velocity = -forward * START_SPEED
	_set_key(KEY_SPACE, true)
	var start: Vector3 = car.global_position
	for _tick in HOLD_TICKS:
		_set_key(KEY_SPACE, true)
		await physics_frame
	var planar: Vector3 = car.linear_velocity.slide(up)
	var drift: float = (car.global_position - start).slide(up).length()
	var hold_y: float = car.global_position.y
	var hold_normal_speed: float = car.linear_velocity.dot(up)
	_set_key(KEY_SPACE, false)
	var roll_start: Vector3 = car.global_position
	var release_max_y: float = hold_y
	var release_max_up_speed: float = -INF
	for _tick in HOLD_TICKS:
		await physics_frame
		release_max_y = maxf(release_max_y, car.global_position.y)
		release_max_up_speed = maxf(release_max_up_speed, car.linear_velocity.y)
	var roll_planar: Vector3 = car.linear_velocity.slide(up)
	var roll_downhill: float = (car.global_position - roll_start).dot(-forward)
	_set_key(KEY_SPACE, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_SPACE, true)
		await physics_frame
	var roll_stop_planar: Vector3 = car.linear_velocity.slide(up)
	var locked_start: Vector3 = car.global_position
	var spin_before: float = car._wheel_spin_angles[2]
	_set_key(KEY_W, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_W, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var throttle_planar: Vector3 = car.linear_velocity.slide(up)
	var throttle_drift: float = (car.global_position - locked_start).slide(up).length()
	var burnout_speed: float = car._burnout_visual_speed
	var spin_delta: float = absf(wrapf(car._wheel_spin_angles[2] - spin_before, -PI, PI))
	_set_key(KEY_W, false)
	var reverse_start: Vector3 = car.global_position
	_set_key(KEY_S, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_S, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var reverse_planar: Vector3 = car.linear_velocity.slide(up)
	var reverse_drift: float = (car.global_position - reverse_start).slide(up).length()
	_set_key(KEY_S, false)
	var pivot_a_start: Vector3 = car.global_position
	var yaw_before_a: float = _heading(car)
	_set_key(KEY_W, true)
	_set_key(KEY_A, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_W, true)
		_set_key(KEY_A, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var yaw_delta_a: float = rad_to_deg(wrapf(_heading(car) - yaw_before_a, -PI, PI))
	var pivot_a_drift: float = (car.global_position - pivot_a_start).slide(up).length()
	var pivot_a_speed: Vector3 = car.linear_velocity.slide(up)
	var pivot_burnout: float = car._burnout_visual_speed
	_set_key(KEY_A, false)
	var pivot_d_start: Vector3 = car.global_position
	var yaw_before_d: float = _heading(car)
	_set_key(KEY_D, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_W, true)
		_set_key(KEY_D, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var yaw_delta_d: float = rad_to_deg(wrapf(_heading(car) - yaw_before_d, -PI, PI))
	var pivot_d_drift: float = (car.global_position - pivot_d_start).slide(up).length()
	var pivot_d_speed: Vector3 = car.linear_velocity.slide(up)
	_set_key(KEY_D, false)
	_set_key(KEY_W, false)
	var pivot_s_a_start: Vector3 = car.global_position
	var yaw_before_s_a: float = _heading(car)
	_set_key(KEY_S, true)
	_set_key(KEY_A, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_S, true)
		_set_key(KEY_A, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var yaw_delta_s_a: float = rad_to_deg(wrapf(_heading(car) - yaw_before_s_a, -PI, PI))
	var pivot_s_a_drift: float = (car.global_position - pivot_s_a_start).slide(up).length()
	var pivot_s_a_speed: Vector3 = car.linear_velocity.slide(up)
	var pivot_s_a_burnout: float = car._burnout_visual_speed
	_set_key(KEY_A, false)
	var pivot_s_d_start: Vector3 = car.global_position
	var yaw_before_s_d: float = _heading(car)
	_set_key(KEY_D, true)
	for _tick in HOLD_TICKS:
		_set_key(KEY_S, true)
		_set_key(KEY_D, true)
		_set_key(KEY_SPACE, true)
		await physics_frame
	var yaw_delta_s_d: float = rad_to_deg(wrapf(_heading(car) - yaw_before_s_d, -PI, PI))
	var pivot_s_d_drift: float = (car.global_position - pivot_s_d_start).slide(up).length()
	var pivot_s_d_speed: Vector3 = car.linear_velocity.slide(up)
	_set_key(KEY_D, false)
	_set_key(KEY_S, false)
	_set_key(KEY_SPACE, false)
	var passed: bool = (
		loaded_before >= 3
		and planar.length() < 0.2
		and drift < 0.5
		and throttle_planar.length() < 0.2
		and throttle_drift < 0.1
		and absf(burnout_speed) > 1.0
		and spin_delta > 0.05
		and reverse_planar.length() < 0.2
		and reverse_drift < 0.1
		and roll_planar.length() > 0.5
		and roll_downhill > 0.2
		and roll_stop_planar.length() < 0.2
		and absf(yaw_delta_a) > 15.0
		and absf(yaw_delta_d) > 15.0
		and signf(yaw_delta_a) != signf(yaw_delta_d)
		and pivot_a_drift < 0.25
		and pivot_d_drift < 0.25
		and pivot_a_speed.length() < 0.2
		and pivot_d_speed.length() < 0.2
		and absf(pivot_burnout) > 1.0
		and absf(yaw_delta_s_a) > 15.0
		and absf(yaw_delta_s_d) > 15.0
		and signf(yaw_delta_s_a) == signf(yaw_delta_a)
		and signf(yaw_delta_s_d) == signf(yaw_delta_d)
		and pivot_s_a_drift < 0.25
		and pivot_s_d_drift < 0.25
		and pivot_s_a_speed.length() < 0.2
		and pivot_s_d_speed.length() < 0.2
		and absf(pivot_s_a_burnout) > 1.0
	)
	var report := {
		"passed": passed,
		"slope_degrees": SLOPE_DEGREES,
		"loaded_wheels_before": loaded_before,
		"rest_hold_drift_m": rest_hold_drift,
		"rest_hold_speed_mps": rest_hold_speed.length(),
		"loaded_wheels_after": car.loaded_wheels,
		"start_speed_mps": START_SPEED,
		"final_planar_speed_mps": planar.length(),
		"planar_drift_m": drift,
		"throttle_lock_speed_mps": throttle_planar.length(),
		"throttle_lock_drift_m": throttle_drift,
		"burnout_visual_speed_mps": burnout_speed,
		"wheel_spin_delta_rad": spin_delta,
		"reverse_lock_speed_mps": reverse_planar.length(),
		"reverse_lock_drift_m": reverse_drift,
		"gravity_roll_speed_mps": roll_planar.length(),
		"gravity_roll_downhill_m": roll_downhill,
		"gravity_roll_stop_speed_mps": roll_stop_planar.length(),
		"release_y_gain_m": release_max_y - hold_y,
		"release_peak_up_speed_mps": release_max_up_speed,
		"hold_normal_speed_mps": hold_normal_speed,
		"pivot_a_yaw_deg": yaw_delta_a,
		"pivot_d_yaw_deg": yaw_delta_d,
		"pivot_a_drift_m": pivot_a_drift,
		"pivot_d_drift_m": pivot_d_drift,
		"pivot_a_speed_mps": pivot_a_speed.length(),
		"pivot_d_speed_mps": pivot_d_speed.length(),
		"pivot_burnout_visual_speed_mps": pivot_burnout,
		"pivot_s_a_yaw_deg": yaw_delta_s_a,
		"pivot_s_d_yaw_deg": yaw_delta_s_d,
		"pivot_s_a_drift_m": pivot_s_a_drift,
		"pivot_s_d_drift_m": pivot_s_d_drift,
		"pivot_s_a_speed_mps": pivot_s_a_speed.length(),
		"pivot_s_d_speed_mps": pivot_s_d_speed.length(),
		"pivot_s_a_burnout_visual_speed_mps": pivot_s_a_burnout,
		"final_position": car.global_position,
	}
	print("HANDBRAKE_SLOPE ", JSON.stringify(report))
	var file := FileAccess.open("res://reports/vehicle_handbrake_slope.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if passed else 1)
