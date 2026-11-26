# SPDX-License-Identifier: 0BSD
extends RigidBody3D

## World-drivable BMX-42. The copied addon supplies the hull, track rigs, turret
## and cosmetic fire; this body adds the single arcade track controller and the
## host entry/exit/parking contract. Terrain, structures and vegetation collision
## remain owned by TerraForest.

@export var max_forward_speed := 6.5
@export var max_reverse_speed := 2.8
@export var acceleration := 3.2
@export var brake_deceleration := 6.0
@export var turn_rate := 1.15
@export var turret_speed := 55.0
@export var gun_speed := 25.0
@export var fire_cooldown := 0.9

@onready var model: Node3D = get_node_or_null("Model")

var controls_enabled := false
var throttle := 0.0
var steer := 0.0
var turret_yaw := 0.0
var gun_elevation := 0.0
var _drive_speed := 0.0
var _reset_was_down := false
var _fire_was_down := false
var _next_fire := 0
var _spawn_transform := Transform3D.IDENTITY

func _ready() -> void:
	can_sleep = false
	_spawn_transform = global_transform

func adapter_ready() -> bool:
	return is_instance_valid(model) and model.get("initialized") == true

func bind_world(_world: Node) -> bool:
	return is_instance_valid(model)

func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		throttle = 0.0
		steer = 0.0
		_drive_speed = 0.0
		_fire_was_down = false
		if is_instance_valid(model):
			model.set_drive(0.0, 0.0)

func restore_parked(pose: Transform3D) -> void:
	set_controls_enabled(false)
	set_physics_process(false)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = pose
	_spawn_transform = pose

func reset_tank() -> void:
	if freeze:
		return
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	throttle = 0.0
	steer = 0.0
	_drive_speed = 0.0
	if is_instance_valid(model):
		model.set_drive(0.0, 0.0)

func can_park(_frame: int) -> bool:
	return not freeze and linear_velocity.length() < 0.25 and absf(angular_velocity.y) < 0.15

func set_turret_state(yaw_degrees: float, elevation_degrees: float) -> void:
	turret_yaw = wrapf(yaw_degrees, -180.0, 180.0)
	gun_elevation = clampf(elevation_degrees, -5.0, 25.0)
	if is_instance_valid(model):
		model.set_turret_angles(turret_yaw, gun_elevation)

func status_text() -> String:
	return "BMX-42 · %.0f km/h · W/S drive · A/D steer · arrows aim · LMB fire · E exit" % (linear_velocity.length() * 3.6)

func _physics_process(delta: float) -> void:
	if freeze:
		return
	var reset_down := Input.is_key_pressed(KEY_R)
	if controls_enabled and reset_down and not _reset_was_down:
		reset_tank()
	_reset_was_down = reset_down
	if global_position.y < -20.0:
		reset_tank()
		return
	_read_controls(delta)
	_drive(delta)
	_aim(delta)
	_fire()

func _read_controls(delta: float) -> void:
	var throttle_target := 0.0
	var steer_target := 0.0
	if controls_enabled:
		if Input.is_key_pressed(KEY_W):
			throttle_target = 1.0
		elif Input.is_key_pressed(KEY_S):
			throttle_target = -1.0
		if Input.is_key_pressed(KEY_A):
			steer_target = 1.0
		elif Input.is_key_pressed(KEY_D):
			steer_target = -1.0
	throttle = move_toward(throttle, throttle_target, 1.6 * delta)
	steer = move_toward(steer, steer_target, 3.0 * delta)

func _drive(delta: float) -> void:
	var forward := global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var grounded := _grounded()
	var target := throttle * (max_forward_speed if throttle >= 0.0 else max_reverse_speed)
	var braking := not controls_enabled or Input.is_key_pressed(KEY_SPACE)
	if braking:
		target = 0.0
	# Track the commanded speed separately from the post-contact velocity: a
	# resting 42 t hull's static friction cancels each frame's small velocity
	# step, so ramping from the measured speed would never build momentum.
	_drive_speed = move_toward(_drive_speed, target, (brake_deceleration if braking else acceleration) * delta)
	var next := _drive_speed
	if grounded:
		var planar := forward * next
		linear_velocity = Vector3(planar.x, linear_velocity.y, planar.z)
		var turn := steer * turn_rate * clampf(absf(next) / 2.5, 0.25, 1.0)
		angular_velocity.y = move_toward(angular_velocity.y, turn, 6.0 * delta)
	else:
		angular_velocity.y = move_toward(angular_velocity.y, 0.0, 4.0 * delta)
	if is_instance_valid(model):
		var half_turn := angular_velocity.y * 1.4
		var left_track := clampf(next + half_turn, -8.0, 8.0)
		var right_track := clampf(next - half_turn, -8.0, 8.0)
		model.set_drive(left_track, right_track)

func _grounded() -> bool:
	var ray := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.4,
		global_position - Vector3.UP * 2.0,
		1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and global_position.y - hit.position.y < 1.6

func _aim(delta: float) -> void:
	if not controls_enabled:
		return
	var yaw_input := float(int(Input.is_key_pressed(KEY_LEFT)) - int(Input.is_key_pressed(KEY_RIGHT)))
	var elevation_input := float(int(Input.is_key_pressed(KEY_UP)) - int(Input.is_key_pressed(KEY_DOWN)))
	if absf(yaw_input) < 0.01 and absf(elevation_input) < 0.01:
		return
	set_turret_state(turret_yaw + yaw_input * turret_speed * delta, gun_elevation + elevation_input * gun_speed * delta)

func _fire() -> void:
	var fire_down := controls_enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not fire_down:
		_fire_was_down = false
		return
	if _fire_was_down or Time.get_ticks_msec() < _next_fire:
		return
	_fire_was_down = true
	if is_instance_valid(model) and model.fire():
		_next_fire = Time.get_ticks_msec() + int(fire_cooldown * 1000.0)
