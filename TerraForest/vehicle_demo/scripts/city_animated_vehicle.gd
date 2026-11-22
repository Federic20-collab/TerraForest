# SPDX-License-Identifier: 0BSD
extends "res://vehicle_demo/scripts/car_native.gd"

## Animated city vehicle: keeps the authored model hierarchy so the supplied
## wheel assemblies and doors remain live. Physics, suspension and persistence
## stay on the existing Ranger controller; only the visual pivots are rebound.

var _model_wheel_bases: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _door_close_serial := 0

func _find_model_node(names: Array) -> Node3D:
	if model_instance == null: return null
	for node_name: String in names:
		var node := model_instance.find_child(node_name, true, false)
		if node is Node3D: return node
	return null

func _bind_model_wheels() -> void:
	var steer_names := [
		["Steer FL", "Wheel_Assembly_FL"],
		["Steer FR", "Wheel_Assembly_FR"],
		["Spin RL", "Wheel_Assembly_RL"],
		["Spin RR", "Wheel_Assembly_RR"],
	]
	var spin_names := [
		["Spin FL", "Wheel_Assembly_FL"],
		["Spin FR", "Wheel_Assembly_FR"],
		["Spin RL", "Wheel_Assembly_RL"],
		["Spin RR", "Wheel_Assembly_RR"],
	]
	for index in 4:
		var steer := _find_model_node(steer_names[index])
		var spin := _find_model_node(spin_names[index])
		if steer == null or spin == null: continue
		wheel_steer_pivots[index] = steer
		wheel_spin_pivots[index] = spin
		_model_wheel_bases[index] = steer.position

func _bind_model_door() -> void:
	var door := _find_model_node(["Door_Front_L", "Front door L"])
	if door == null: return
	driver_door_hinge = door
	driver_door_hinge.rotation.y = 0.0
	driver_door_visual.mesh = null

func _update_wheel_visuals(delta: float) -> void:
	if not model_hierarchy_visuals:
		super._update_wheel_visuals(delta)
		return
	for index in 4:
		var steer: Node3D = wheel_steer_pivots[index]
		var spin: Node3D = wheel_spin_pivots[index]
		if not is_instance_valid(steer) or not is_instance_valid(spin): continue
		steer.position = _model_wheel_bases[index]
		var steer_angle: float = _wheel_steer_angle(index)
		var wheel_forward: Vector3 = Basis(global_transform.basis.y.normalized(), steer_angle) * global_transform.basis.z.normalized()
		var wheel_speed: float = linear_velocity.dot(wheel_forward)
		if _contact_active[index]:
			wheel_speed = get_velocity_at_world_point(_contact_points[index]).dot(wheel_forward)
		_wheel_spin_angles[index] = wrapf(_wheel_spin_angles[index] + (wheel_speed / WHEEL_RADIUS) * delta, -PI, PI)
		if steer == spin:
			steer.rotation = Vector3(_wheel_spin_angles[index], steer_angle, 0.0)
		else:
			steer.rotation.y = steer_angle
			spin.rotation.x = _wheel_spin_angles[index]

func set_controls_enabled(enabled: bool) -> void:
	var was_enabled := controls_enabled
	super.set_controls_enabled(enabled)
	if not model_hierarchy_visuals or not is_instance_valid(driver_door_hinge): return
	if enabled:
		if not was_enabled:
			_door_close_serial += 1
			open_driver_door()
			_close_door_after_entry(_door_close_serial)
	else:
		_door_close_serial += 1
		close_driver_door()

func _close_door_after_entry(serial: int) -> void:
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(self) or serial != _door_close_serial or not controls_enabled: return
	close_driver_door()
