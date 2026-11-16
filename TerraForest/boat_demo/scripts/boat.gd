# SPDX-License-Identifier: 0BSD
class_name BoatVehicle
extends RigidBody3D

## Arcade buoyancy boat: eight probes sample the shared water height field and
## apply spring/damper forces, while thrust, rudder yaw and water drag produce
## planing motion. This is a self-contained vehicle controller; it does not use
## the car suspension or vehicle-pack adapter.

const HULL_BOTTOM := -0.55
const PROBES := [
	Vector3(-0.62, HULL_BOTTOM, -1.50),
	Vector3(0.62, HULL_BOTTOM, -1.50),
	Vector3(-0.68, HULL_BOTTOM, -0.50),
	Vector3(0.68, HULL_BOTTOM, -0.50),
	Vector3(-0.68, HULL_BOTTOM, 0.50),
	Vector3(0.68, HULL_BOTTOM, 0.50),
	Vector3(-0.62, HULL_BOTTOM, 1.50),
	Vector3(0.62, HULL_BOTTOM, 1.50),
]

@export var water_path: NodePath = ^"../Water"
@export var max_thrust_newtons := 4200.0
@export var reverse_thrust_newtons := 1500.0
@export var throttle_slew_rate := 1.6
@export var steer_rate := 2.4
@export var max_yaw_rate := 0.85
@export var yaw_response := 3400.0
@export var buoyancy_probe_area := 0.15
@export var water_density := 1000.0
@export var forward_drag := 16.0
@export var lateral_drag := 900.0
@export var vertical_drag := 1500.0
@export var idle_brake := 900.0
@export var righting_strength := 9000.0
@export var roll_damping := 3200.0
@export var gravity := 20.0

var water: BoatWaterSurface
var controls_enabled := true
var throttle := 0.0
var steering := 0.0
var speed_kph := 0.0
var speed_knots := 0.0
var forward_speed := 0.0
var draft := 0.0
var wet_probes := 0
var water_height := 0.0

var _spawn_transform := Transform3D.IDENTITY
var _reset_was_down := false


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0))
	water = get_node_or_null(water_path) as BoatWaterSurface
	if water == null:
		push_error("Boat water_path does not point to a BoatWaterSurface")
	_spawn_transform = global_transform
	can_sleep = false
	sleeping = false


func _physics_process(delta: float) -> void:
	var reset_down := Input.is_key_pressed(KEY_R)
	if reset_down and not _reset_was_down:
		reset_boat()
	_reset_was_down = reset_down
	if global_position.y < -20.0:
		reset_boat()
	_update_controls(delta)
	_apply_water_forces()
	_update_telemetry()


func _update_controls(delta: float) -> void:
	var throttle_target := 0.0
	var steer_target := 0.0
	if controls_enabled:
		var accelerate := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		var reverse := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		var left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
		var right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
		if accelerate:
			throttle_target = 1.0
		elif reverse:
			throttle_target = -0.6
		if Input.is_key_pressed(KEY_SPACE):
			throttle_target = 0.0
		steer_target = float(int(left) - int(right))
	throttle = move_toward(throttle, throttle_target, throttle_slew_rate * delta)
	steering = move_toward(steering, steer_target, steer_rate * delta)


func _apply_water_forces() -> void:
	if water == null:
		return
	water_height = water.height_at(global_position)
	var basis := global_transform.basis
	var submerged := 0
	for local in PROBES:
		var offset: Vector3 = basis * local
		var world_point := global_position + offset
		var depth: float = water_height - world_point.y
		if depth <= 0.0:
			continue
		submerged += 1
		var point_velocity := linear_velocity + angular_velocity.cross(offset)
		var lift := minf(depth, 0.6) * buoyancy_probe_area * water_density * gravity
		var damping := -point_velocity.y * buoyancy_probe_area * water_density * 0.8
		apply_force(Vector3.UP * (lift + damping), offset)
	wet_probes = submerged
	if submerged == 0:
		return
	var flat_forward := Vector3(basis.z.x, 0.0, basis.z.z)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = Vector3.FORWARD
	else:
		flat_forward = flat_forward.normalized()
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	forward_speed = horizontal.dot(flat_forward)
	var lateral := horizontal - flat_forward * forward_speed
	var drag := -flat_forward * forward_speed * absf(forward_speed) * forward_drag
	drag -= lateral * lateral_drag
	drag -= horizontal * idle_brake * (1.0 - absf(throttle))
	apply_central_force(drag)
	apply_central_force(Vector3.DOWN * linear_velocity.y * vertical_drag)
	if absf(throttle) > 0.001:
		var thrust := throttle * (max_thrust_newtons if throttle > 0.0 else reverse_thrust_newtons)
		var thrust_direction := flat_forward.rotated(Vector3.UP, steering * 0.30)
		apply_force(thrust_direction * thrust, basis * Vector3(0.0, -0.12, 1.55))
	var yaw_target := steering * max_yaw_rate * clampf(absf(forward_speed) / 6.0, 0.0, 1.0)
	if forward_speed < 0.0:
		yaw_target = -yaw_target
	var yaw_error := yaw_target - angular_velocity.y
	apply_torque(Vector3.UP * (yaw_error * yaw_response))
	apply_torque(Vector3(-angular_velocity.x, 0.0, -angular_velocity.z) * roll_damping)
	var up: Vector3 = basis.y
	apply_torque(up.cross(Vector3.UP) * righting_strength)


func _update_telemetry() -> void:
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	speed_kph = horizontal.length() * 3.6
	speed_knots = speed_kph / 1.852
	if water != null:
		draft = maxf(0.0, water.height_at(global_position) - (global_position.y + HULL_BOTTOM))


func probe_total() -> int:
	return PROBES.size()


func reset_boat() -> void:
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	throttle = 0.0
	steering = 0.0
	forward_speed = 0.0
	speed_kph = 0.0
	speed_knots = 0.0
	draft = 0.0
	wet_probes = 0
	sleeping = false
