# SPDX-License-Identifier: 0BSD
extends RigidBody3D

## Arcade flight controller for the full-mesh aircraft. It keeps the same
## entry/exit and persistence host contract as the ground vehicles but owns
## thrust, lift, banking, pitch and landing. There are no wheel or door
## animations; the supplied mesh is the complete visual.

const FlightStreaming = preload("res://addons/vehicle_runtime/aircraft_streaming.gd")

@export var max_thrust := 55000.0
@export var reverse_thrust := 12000.0
@export var lift_speed := 20.0
@export var lift_gain := 1.6
@export var pitch_torque := 9000.0
@export var roll_torque := 3400.0
@export var yaw_torque := 2600.0
@export var level_strength := 4200.0
@export var max_speed := 65.0
@export var ceiling := 220.0

var streaming: RefCounted
var controls_enabled := false
var throttle := 0.0
var steer := 0.0
var pitch_input := 0.0
var speed_kph := 0.0
var altitude := 0.0
var grounded := false
var _ground_distance := INF
var _spawn_transform := Transform3D.IDENTITY
var _reset_was_down := false
var _gravity := 20.0

func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0))
	can_sleep = false
	_spawn_transform = global_transform

func bind_streamed_world(terrain: Node, structures: Node) -> bool:
	if streaming != null and streaming.waiting: return false
	streaming = FlightStreaming.new()
	return streaming.bind(terrain, structures)

func bind_vegetation(provider: Node) -> bool:
	return streaming != null and streaming.bind_vegetation(provider)

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		throttle = 0.0
		steer = 0.0
		pitch_input = 0.0

func restore_parked(pose: Transform3D) -> void:
	set_controls_enabled(false)
	set_physics_process(false)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	throttle = 0.0
	steer = 0.0
	pitch_input = 0.0
	grounded = false
	_ground_distance = INF
	_spawn_transform = pose
	global_transform = pose
	if streaming != null:
		streaming.restore_parked(self)
	else:
		freeze = true

func reset_aircraft() -> void:
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	throttle = 0.0
	steer = 0.0
	pitch_input = 0.0
	grounded = false
	_ground_distance = INF
	if streaming != null:
		streaming.reset(self)
	else:
		freeze = false
	set_physics_process(controls_enabled)

func can_park(_frame: int) -> bool:
	return not freeze and linear_velocity.length() < 0.4 and angular_velocity.length() < 0.3 and _ground_distance < 1.5

func _physics_process(delta: float) -> void:
	if streaming != null and not streaming.update(self, delta):
		_update_telemetry()
		return
	_update_ground()
	_update_controls(delta)
	_apply_flight(delta)
	_update_telemetry()

func _update_ground() -> void:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.0, global_position - Vector3.UP * 12.0, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(ray)
	_ground_distance = global_position.y - hit.position.y if not hit.is_empty() else INF
	grounded = _ground_distance < 1.2

func _update_controls(delta: float) -> void:
	var reset_down := Input.is_key_pressed(KEY_R)
	if controls_enabled and reset_down and not _reset_was_down:
		reset_aircraft()
	_reset_was_down = reset_down
	var throttle_target := 0.0
	var steer_target := 0.0
	var pitch_target := 0.0
	if controls_enabled:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_PAGEUP):
			throttle_target = 1.0
		elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_PAGEDOWN):
			throttle_target = -0.35
		if Input.is_key_pressed(KEY_SPACE):
			throttle_target = 0.0
		steer_target = float(int(Input.is_key_pressed(KEY_A)) - int(Input.is_key_pressed(KEY_D)))
		pitch_target = float(int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP)))
	throttle = move_toward(throttle, throttle_target, 1.8 * delta)
	steer = move_toward(steer, steer_target, 3.5 * delta)
	pitch_input = move_toward(pitch_input, pitch_target, 3.5 * delta)

func _apply_flight(_delta: float) -> void:
	var basis := global_transform.basis
	var forward := basis.z.normalized()
	var up := basis.y.normalized()
	var forward_speed := linear_velocity.dot(forward)
	var thrust := max_thrust * throttle if throttle >= 0.0 else reverse_thrust * throttle
	if throttle > 0.0 and Input.is_key_pressed(KEY_SHIFT):
		thrust *= 1.35
	if forward_speed > max_speed:
		thrust = 0.0
	apply_central_force(forward * thrust)
	var lift_ratio := clampf(absf(forward_speed) / lift_speed, 0.0, 1.6)
	var lift := lift_ratio * lift_ratio * mass * _gravity * lift_gain
	if forward_speed < 0.0:
		lift *= 0.2
	apply_central_force(up * lift)
	var weight := mass * _gravity
	if grounded and throttle > 0.3:
		apply_central_force(Vector3.UP * weight * 0.15 * throttle)
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(-linear_velocity * mass * 0.008)
	apply_central_force(-horizontal * mass * 0.006)
	if forward_speed > max_speed:
		apply_central_force(-forward * (forward_speed - max_speed) * mass * 0.5)
	if grounded:
		if absf(throttle) < 0.05:
			apply_central_force(-horizontal * mass * 2.0)
		var side := basis.x
		side.y = 0.0
		if side.length_squared() > 0.0001:
			side = side.normalized()
			apply_central_force(-side * linear_velocity.dot(side) * mass * 1.5)
	var authority := clampf(absf(forward_speed) / 10.0, 0.0, 1.0) if not grounded else clampf(absf(forward_speed) / 14.0, 0.0, 1.0)
	apply_torque(basis.x * pitch_input * pitch_torque * authority)
	apply_torque(basis.z * steer * roll_torque * authority)
	apply_torque(basis.y * steer * yaw_torque * authority)
	apply_torque(-angular_velocity * mass * 0.8)
	if absf(steer) < 0.05 and not grounded:
		apply_torque(basis.z * (-basis.x.dot(Vector3.UP) * level_strength))
	if absf(pitch_input) < 0.05 and not grounded:
		apply_torque(basis.x * (basis.z.dot(Vector3.UP) * level_strength * 0.5))
	if global_position.y > ceiling:
		apply_central_force(Vector3.DOWN * weight * 0.6)

func _update_telemetry() -> void:
	speed_kph = linear_velocity.length() * 3.6
	altitude = maxf(0.0, _ground_distance) if is_finite(_ground_distance) else 0.0

func status_text() -> String:
	return "AirCraft · %.0f km/h · alt %.1f m · W/S throttle · A/D bank · ↑/↓ pitch · E exit" % [speed_kph, altitude]
