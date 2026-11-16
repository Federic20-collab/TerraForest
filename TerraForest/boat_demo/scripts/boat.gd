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
@export var max_thrust_newtons := 6400.0
@export var reverse_thrust_newtons := 2000.0
@export var throttle_slew_rate := 3.0
@export var steer_rate := 3.2
@export var max_yaw_rate := 1.0
@export var yaw_response := 5200.0
@export var buoyancy_probe_area := 0.15
@export var water_density := 1000.0
@export var forward_drag := 26.0
@export var lateral_drag := 1200.0
@export var vertical_drag := 1500.0
@export var idle_brake := 1200.0
@export var righting_strength := 14000.0
@export var roll_damping := 4800.0
@export var gravity := 20.0
@export var allow_reset := true

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
var _wake_trail: MeshInstance3D
var _trail_mesh := ArrayMesh.new()
var _trail_points: Array[Vector3] = []
var _trail_tick := 0
var _bow_spray: GPUParticles3D
var _stern_spray: Array[GPUParticles3D] = []
var _foam_mesh: QuadMesh


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 20.0))
	water = get_node_or_null(water_path) as BoatWaterSurface
	_spawn_transform = global_transform
	can_sleep = false
	sleeping = false
	_build_water_effects()


func _physics_process(delta: float) -> void:
	var reset_down := Input.is_key_pressed(KEY_R)
	if allow_reset and reset_down and not _reset_was_down:
		reset_boat()
	_reset_was_down = reset_down
	if allow_reset and global_position.y < -20.0:
		reset_boat()
	_update_controls(delta)
	_apply_water_forces()
	_update_telemetry()
	_update_effects()


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled


## Override in host-driven variants to sample the world's real water runtime.
func _water_height_at(point: Vector3) -> float:
	return water.height_at(point) if water != null else NAN


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
		# Godot's positive Y yaw turns +Z toward +X, which is screen-left from the
		# chase camera. D must therefore produce a negative steering value.
		steer_target = float(int(left) - int(right))
	throttle = move_toward(throttle, throttle_target, throttle_slew_rate * delta)
	steering = move_toward(steering, steer_target, steer_rate * delta)


func _apply_water_forces() -> void:
	var height := _water_height_at(global_position)
	if not is_finite(height):
		water_height = 0.0
		wet_probes = 0
		speed_kph = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length() * 3.6
		speed_knots = speed_kph / 1.852
		return
	water_height = height
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


func _build_water_effects() -> void:
	# Original procedural foam/quads: unshaded, soft-edged and billboarded so the
	# wake stays readable without importing another texture.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.9))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var foam := GradientTexture2D.new()
	foam.gradient = gradient
	foam.fill = GradientTexture2D.FILL_RADIAL
	foam.fill_from = Vector2(0.5, 0.5)
	foam.fill_to = Vector2(1.0, 0.5)
	foam.width = 64
	foam.height = 64
	var material := StandardMaterial3D.new()
	material.albedo_texture = foam
	material.albedo_color = Color(0.9, 0.96, 1.0, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	_foam_mesh = QuadMesh.new()
	_foam_mesh.size = Vector2.ONE
	_foam_mesh.material = material
	# A flat strip along the stern path reads as foam better than round billboards.
	var trail_material := StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var foam_gradient := Gradient.new()
	foam_gradient.set_color(0, Color(1, 1, 1, 1))
	foam_gradient.set_color(1, Color(1, 1, 1, 0))
	foam_gradient.add_point(0.5, Color(1, 1, 1, 0.35))
	var foam_texture := GradientTexture2D.new()
	foam_texture.gradient = foam_gradient
	foam_texture.width = 64
	foam_texture.height = 64
	foam_texture.fill = GradientTexture2D.FILL_RADIAL
	foam_texture.fill_from = Vector2(0.5, 1.0)
	foam_texture.fill_to = Vector2(0.5, 0.5)
	trail_material.albedo_texture = foam_texture
	trail_material.albedo_color = Color(0.78, 0.9, 0.96, 0.4)
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.disable_receive_shadows = true
	_wake_trail = MeshInstance3D.new()
	_wake_trail.name = "WakeTrail"
	_wake_trail.top_level = true
	_wake_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake_trail.mesh = _trail_mesh
	_wake_trail.material_override = trail_material
	_wake_trail.visible = false
	add_child(_wake_trail)
	_wake_trail.global_transform = Transform3D.IDENTITY
	_bow_spray = _add_spray("BowSpray", 18, 0.65, _foam_mesh)
	_bow_spray.process_material = _spray_material(Vector3(0.6, 0.1, 0.2), Vector3(0, 0.5, -1), 35.0,
		1.6, 2.8, 7.0, 10.0, Vector2(0.08, 0.22), Color(0.86, 0.93, 0.98, 0.4), 0.0, 0.0)
	for side in [-1.0, 1.0]:
		var spray := _add_spray("SternSpray", 100, 0.65, _foam_mesh)
		spray.process_material = _spray_material(Vector3(0.9, 0.15, 0.5), Vector3(side * 0.55, 0.25, -1), 20.0,
			0.8, 1.8, 2.0, 3.5, Vector2(0.08, 0.25), Color(0.88, 0.94, 1.0, 0.4), 0.0, 0.0)
		_stern_spray.append(spray)


func _add_spray(node_name: String, amount: int, lifetime: float, mesh: QuadMesh) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.draw_pass_1 = mesh
	particles.visibility_aabb = AABB(Vector3(-24, -8, -24), Vector3(48, 16, 48))
	add_child(particles)
	return particles


func _spray_material(extents: Vector3, direction: Vector3, spread: float,
		velocity_min: float, velocity_max: float, gravity_min: float, gravity_max: float,
		scale: Vector2, color: Color, damping_min: float, damping_max: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = velocity_min
	process.initial_velocity_max = velocity_max
	process.gravity = Vector3(0, -1.0, 0) * (gravity_min + gravity_max) * 0.5
	process.scale_min = scale.x
	process.scale_max = scale.y
	process.color = color
	process.damping_min = damping_min
	process.damping_max = damping_max
	return process


func _update_effects() -> void:
	if _wake_trail == null:
		return
	var wet := wet_probes >= 2 and is_finite(water_height)
	var speed := absf(forward_speed)
	_bow_spray.emitting = wet and speed > 3.5
	for spray in _stern_spray:
		spray.emitting = wet and speed > 2.5
	var flat := Vector3(global_basis.z.x, 0.0, global_basis.z.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var surface := water_height + 0.08
	_bow_spray.global_position = Vector3(global_position.x + flat.x * 2.7, surface + 0.12, global_position.z + flat.z * 2.7)
	for index in _stern_spray.size():
		var side := -0.95 if index == 0 else 0.95
		var origin := Vector3(global_position.x - flat.x * 2.0, surface + 0.05, global_position.z - flat.z * 2.0)
		_stern_spray[index].global_position = origin + Vector3(flat.z, 0.0, -flat.x) * side
	if wet and speed > 1.0:
		var stern := Vector3(global_position.x - flat.x * 2.5, water_height + 0.04, global_position.z - flat.z * 2.5)
		if _trail_points.is_empty() or _trail_points[-1].distance_to(stern) > 0.3:
			_trail_points.append(stern)
			while _trail_points.size() > 12:
				_trail_points.pop_front()
	elif not _trail_points.is_empty():
		_trail_points.pop_front()
	_trail_tick = (_trail_tick + 1) % 3
	if _trail_tick == 0:
		_rebuild_wake_trail()


func _rebuild_wake_trail() -> void:
	_trail_mesh.clear_surfaces()
	var count := _trail_points.size()
	if count < 3:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Two diverging foam edges. The oldest point is the far tail, so the spread
	# widens as index approaches zero.
	var offsets: Array[float] = [-1.0, 1.0]
	var widths: Array[float] = [0.3, 0.3]
	var strengths: Array[float] = [0.1, 0.1]
	var bands := offsets.size()
	vertices.resize(count * 3 * bands)
	normals.resize(count * 3 * bands)
	colors.resize(count * 3 * bands)
	uvs.resize(count * 3 * bands)
	for index in count:
		var previous := _trail_points[maxi(index - 1, 0)]
		var next := _trail_points[mini(index + 1, count - 1)]
		var tangent := next - previous
		tangent.y = 0.0
		tangent = tangent.normalized() if tangent.length_squared() > 0.0001 else Vector3.FORWARD
		var side := Vector3(tangent.z, 0.0, -tangent.x)
		var age := float(index) / float(count - 1)
		var center := _trail_points[index]
		var spread := lerpf(1.15, 0.35, age) + sin(age * 9.0 + Time.get_ticks_msec() * 0.002) * 0.05
		for band in bands:
			var base := (index * bands + band) * 3
			var middle := center + side * (offsets[band] * spread)
			var width := widths[band] * lerpf(1.4, 0.55, age)
			vertices[base] = middle - side * width
			vertices[base + 1] = middle
			vertices[base + 2] = middle + side * width
			uvs[base] = Vector2(0.0, age)
			uvs[base + 1] = Vector2(0.5, age)
			uvs[base + 2] = Vector2(1.0, age)
			for offset in 3:
				normals[base + offset] = Vector3.UP
			var alpha := strengths[band] * lerpf(0.0, 1.0, age)
			colors[base] = Color(1, 1, 1, 0)
			colors[base + 1] = Color(1, 1, 1, alpha)
			colors[base + 2] = Color(1, 1, 1, 0)
	for index in count - 1:
		for band in bands:
			var base := (index * bands + band) * 3
			var next_base := ((index + 1) * bands + band) * 3
			for offset: int in [0, 1, 4, 0, 4, 3, 1, 2, 5, 1, 5, 4]:
				var local: int = offset % 3
				var row: int = 1 if offset >= 3 else 0
				indices.append((base if row == 0 else next_base) + local)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func effects_active() -> bool:
	return not _trail_points.is_empty() or (_bow_spray != null and _bow_spray.emitting)


func _update_telemetry() -> void:
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	speed_kph = horizontal.length() * 3.6
	speed_knots = speed_kph / 1.852
	var height := _water_height_at(global_position)
	draft = maxf(0.0, height - (global_position.y + HULL_BOTTOM)) if is_finite(height) else 0.0


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
