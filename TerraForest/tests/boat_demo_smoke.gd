# SPDX-License-Identifier: 0BSD
extends SceneTree

## Standalone boat demo check: the imported boat must settle on the water
## height field, accelerate under throttle and change heading under rudder,
## while remaining upright and floating.

func _initialize() -> void:
	call_deferred("run")


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _heading(node: Node3D) -> float:
	var forward := node.global_transform.basis.z
	return atan2(forward.x, forward.z)


func run() -> void:
	var packed: PackedScene = load("res://boat_demo/main.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	var boat: BoatVehicle = scene.get_node("Boat")
	var water: BoatWaterSurface = scene.get_node("Water")
	var bow := boat.find_child("Bow_Metal_Shoe*", true, false) as Node3D
	var motor := boat.find_child("Motor_Cowling*", true, false) as Node3D
	var bow_local_z := boat.to_local(bow.global_position).z if bow != null else 0.0
	var motor_local_z := boat.to_local(motor.global_position).z if motor != null else 0.0
	var facing := bow_local_z > 1.0 and motor_local_z < -1.0
	for tick in 360:
		await physics_frame
	var rest_position := boat.global_position
	var rest_speed := boat.linear_velocity.length()
	var upright := boat.global_basis.y.dot(Vector3.UP)
	var settled := absf(boat.draft) > 0.05 and boat.draft < 0.6 \
		and boat.wet_probes == boat.probe_total() \
		and upright > 0.98 and rest_speed < 0.6 \
		and absf(rest_position.y - 0.23) < 0.35 \
		and facing \
		and is_finite(water.height_at(rest_position))
	var settled_record := {
		"y": rest_position.y, "speed": rest_speed, "upright": upright,
		"draft": boat.draft, "wet": boat.wet_probes, "facing": facing,
		"bow_local_z": bow_local_z, "motor_local_z": motor_local_z,
	}
	_press(KEY_W, true)
	for tick in 360:
		await physics_frame
	var driven_position := boat.global_position
	var driven_distance := Vector2(driven_position.x - rest_position.x, driven_position.z - rest_position.z).length()
	var driven_speed := boat.speed_kph
	var driving := driven_distance > 10.0 and driven_speed > 20.0 and driven_position.y > -1.0 \
		and boat.global_basis.y.dot(Vector3.UP) > 0.9
	_press(KEY_W, false)
	_press(KEY_A, true)
	var heading_before := _heading(boat)
	for tick in 240:
		await physics_frame
	_press(KEY_A, false)
	var heading_change := wrapf(_heading(boat) - heading_before, -PI, PI)
	var turning := absf(heading_change) > 0.12 and boat.global_basis.y.dot(Vector3.UP) > 0.9 \
		and boat.wet_probes >= 4
	var record := {
		"settled": settled, "driving": driving, "turning": turning,
		"rest": settled_record,
		"driven_distance": driven_distance, "driven_kph": driven_speed,
		"heading_change": heading_change, "wet_after_turn": boat.wet_probes,
	}
	print("BOAT_SMOKE ", JSON.stringify(record))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.save_png("res://reports/boat_demo.png")
		print("BOAT_SCREENSHOT res://reports/boat_demo.png")
	scene.queue_free()
	await process_frame
	quit(0 if settled and driving and turning else 1)
