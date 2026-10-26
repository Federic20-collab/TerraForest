# SPDX-License-Identifier: 0BSD
extends "res://vehicle_demo/scripts/car.gd"
const STREAMING_ADAPTER=preload("res://addons/vehicle_runtime/vehicle_streaming.gd")
const HANDBRAKE_PIVOT_YAW_DEG:=48.0
const HANDBRAKE_PIVOT_SPEED:=1.5
var driving_policy: RefCounted
var suspension: RefCounted
var visual_damage: RefCounted
var accessories: RefCounted
var streaming: RefCounted
var contact_physics_frame: int=-1
var profile_setup:=false
var setup_timings: Dictionary={}
var visual_timings: Dictionary={}
func _build_runtime_body_visuals() -> void:
	var begin:=Time.get_ticks_usec() if profile_setup else 0
	super._build_runtime_body_visuals()
	if profile_setup: visual_timings["body_us"]=Time.get_ticks_usec()-begin
func _bind_wheel_visual(visual: MeshInstance3D,source_name: String) -> void:
	var begin:=Time.get_ticks_usec() if profile_setup else 0
	super._bind_wheel_visual(visual,source_name)
	if profile_setup: visual_timings[source_name]=Time.get_ticks_usec()-begin
func _bind_driver_door_visual() -> void:
	var begin:=Time.get_ticks_usec() if profile_setup else 0
	super._bind_driver_door_visual()
	if profile_setup: visual_timings["door_us"]=Time.get_ticks_usec()-begin
func bind_streamed_world(terrain: Node,structures: Node=null) -> bool:
	if streaming!=null and streaming.waiting: return false
	if not is_instance_valid(terrain): return false
	if streaming!=null and is_instance_valid(streaming.terrain):
		var old: Node=streaming.terrain
		if old.has_signal("reload_started") and old.reload_started.is_connected(_stream_reload_started):
			old.reload_started.disconnect(_stream_reload_started)
	streaming=STREAMING_ADAPTER.new()
	streaming.terrain=terrain;streaming.structures=structures
	streaming.structures_required=structures!=null
	if terrain.has_signal("reload_started"):
		terrain.reload_started.connect(_stream_reload_started)
	return true
func _stream_reload_started() -> void:
	streaming.discard_motion(self)
	_drive_speed=0.0;_normal_mode=false;_physics_override_time=0.0
	if driving_policy!=null: driving_policy.reset()
	_reset_accessory_motion()
func _physics_process(delta: float) -> void:
	if streaming!=null and not streaming.update(self,driving_policy,delta):
		_update_reset() # Keep recovery input available while world loading holds motion.
		return
	super._physics_process(delta)
	# Recheck after controls change speed, before the physics integration step.
	if streaming!=null: streaming.update(self,driving_policy,delta)
func _ready() -> void:
	var begin:=Time.get_ticks_usec() if profile_setup else 0
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	driving_policy=ClassDB.instantiate("NativeDrivingPolicy")
	suspension=ClassDB.instantiate("NativeVehicleSuspension")
	if not suspension.configure_gravity(float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))*gravity_scale):
		push_error("Vehicle suspension gravity is outside supported range")
	visual_damage=ClassDB.instantiate("NativeVehicleDamage")
	accessories=ClassDB.instantiate("NativeVehicleAccessories")
	var native_done:=Time.get_ticks_usec() if profile_setup else 0
	super._ready()
	var visuals_done:=Time.get_ticks_usec() if profile_setup else 0
	if not accessories.configure(_accessory_mounts,PackedFloat32Array(_accessory_profiles)):
		push_error("Vehicle accessory configuration failed")
	for ray in wheel_rays: ray.enabled=false # Native pass explicitly updates once.
	# Runtime visuals retain shared mesh/material resources. The hidden import
	# hierarchy was only a setup template and needs no per-vehicle scene nodes.
	model_instance.queue_free()
	model_instance=null
	if profile_setup:
		setup_timings={"native_us":native_done-begin,"visuals_us":visuals_done-native_done,"finalize_us":Time.get_ticks_usec()-visuals_done,"visual_parts":visual_timings}
func _reset_accessory_motion() -> void:
	if accessories!=null: accessories.reset(linear_velocity,angular_velocity)
func _update_accessory_motion(delta: float) -> void:
	accessories.step(global_basis,linear_velocity,angular_velocity,delta,accessory_motion_enabled,accessory_motion_strength)
func _build_dented_mesh(visual: MeshInstance3D,world_point: Vector3,dent_direction: Vector3,radius: float,depth: float) -> ArrayMesh:
	return visual_damage.dent(visual.mesh,visual.global_transform,world_point,dent_direction,radius,depth)
func _update_wheel_contacts() -> void:
	var samples: PackedFloat32Array=suspension.sample_and_apply(self,wheel_rays)
	grounded_wheels=0;loaded_wheels=0
	if samples.size()!=40:
		set_physics_process(false);push_error("Vehicle suspension contacts unavailable");return
	# Temporary compatibility adapter for the original visual/telemetry scripts.
	for i in 4:
		var offset:=i*10
		_contact_active[i]=samples[offset]>0;_load_active[i]=samples[offset+1]>0
		_spring_lengths[i]=samples[offset+2];_normal_forces[i]=samples[offset+3]
		_contact_points[i]=Vector3(samples[offset+4],samples[offset+5],samples[offset+6])
		_contact_normals[i]=Vector3(samples[offset+7],samples[offset+8],samples[offset+9])
		if _contact_active[i]: grounded_wheels+=1
		if _load_active[i]: loaded_wheels+=1
	contact_physics_frame=Engine.get_physics_frames()
func _apply_suspension_forces() -> void:
	pass # Applied by the native contact pass exactly once per physics tick.
func _apply_vehicle_motion(throttle: float,reverse_brake: float,handbrake: bool,parked: bool,delta: float) -> void:
	handbrake_active=handbrake;drive_force_newtons=0;target_yaw_rate_degrees=0
	_burnout_visual_speed=0.0
	var supported:=_has_drive_support()
	var held_speed:=linear_velocity.slide(_support_normal()).length()
	if handbrake and supported and held_speed<HANDBRAKE_PIVOT_SPEED:
		_burnout_visual_speed=clampf(throttle-reverse_brake,-1.0,1.0)*26.0
	if not _normal_mode or handbrake or _physics_override_time>0:
		normal_drive_locked=false
		var free_throttle:=0.0 if handbrake else throttle
		var free_reverse:=0.0 if handbrake else reverse_brake
		driving_policy.apply_free(self,_support_normal(),free_throttle,free_reverse,handbrake,parked,_has_drive_support())
		# A locked, supported vehicle can pivot in place with A/D. Translation
		# stays zero; only yaw is written, and the wheels keep their burnout spin.
		var pivot_steer:=_steer_fraction
		var pivot_drive:=throttle-reverse_brake
		if handbrake and supported and held_speed<HANDBRAKE_PIVOT_SPEED and absf(pivot_drive)>0.05 and absf(pivot_steer)>0.05:
			var up:=_support_normal()
			linear_velocity=up*linear_velocity.dot(up)
			angular_velocity=up*deg_to_rad(HANDBRAKE_PIVOT_YAW_DEG)*clampf(pivot_steer,-1.0,1.0)
			target_yaw_rate_degrees=rad_to_deg(angular_velocity.dot(up))
		return
	_update_drive_speed_state(throttle,reverse_brake,parked,delta)
	target_yaw_rate_degrees=rad_to_deg(driving_policy.apply_grounded(self,_support_normal(),_drive_speed))
	normal_drive_locked=true
func _apply_body_stability() -> void:
	roll_degrees=driving_policy.stabilize(self,_support_normal(),_has_drive_support(),loaded_wheels)
func _update_ground_state(handbrake: bool,delta: float) -> void:
	var was_normal:=_normal_mode
	super._update_ground_state(handbrake,delta)
	if not was_normal and _normal_mode: driving_policy.reset()
func reset_vehicle() -> void:
	super.reset_vehicle()
	if driving_policy!=null: driving_policy.reset()
	if streaming!=null: streaming.discard_motion(self)
func restore_parked(pose: Transform3D) -> void:
	set_controls_enabled(false);set_physics_process(false)
	contact_physics_frame=-1
	_spawn_transform=pose
	reset_vehicle()
	global_transform=pose # Interactive reset adds clearance; saved poses are exact.
	if streaming!=null: streaming.restore_parked(self)
	else: freeze=true
	repair_visual_damage()
	if is_instance_valid(_door_tween): _door_tween.kill()
	driver_door_open=false;driver_door_hinge.rotation.y=0
	grounded_wheels=0;loaded_wheels=0;speed_kph=0
	for i in WHEEL_COUNT:
		_contact_active[i]=false;_load_active[i]=false;_normal_forces[i]=0
	_update_wheel_visuals(0)
func _update_steering(input_amount: float,delta: float) -> void:
	var speed_for_limit:=absf(_drive_speed) if _normal_mode else linear_velocity.slide(_support_normal()).length()
	var state: Vector3=driving_policy.steering(input_amount,speed_for_limit,delta)
	_steering_angle=state.x;_held_steer_cap=state.y;_steer_fraction=state.z
	_curvature_state=tan(_steering_angle)/WHEELBASE
	steering_degrees=rad_to_deg(_steering_angle);steering_limit_degrees=rad_to_deg(_held_steer_cap)
	commanded_turn_radius=0.0 if absf(_curvature_state)<0.00001 else 1.0/absf(_curvature_state)
	_update_ackermann_angles()
func _update_drive_speed_state(throttle: float,reverse_brake: float,parked: bool,delta: float) -> void:
	var result: Vector2=driving_policy.speed(_drive_speed,throttle,reverse_brake,parked,boost_amount,delta)
	_drive_speed=result.x;drive_force_newtons=result.y*mass
	if not parked and absf(throttle)<0.05 and absf(reverse_brake)<0.05:
		var up:=_support_normal()
		var body_forward:=global_transform.basis.z.slide(up)
		if body_forward.length_squared()>0.0001:
			body_forward=body_forward.normalized()
			var gravity:=Vector3.DOWN*float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))*gravity_scale
			var downhill:=gravity-up*gravity.dot(up)
			_drive_speed=clampf(_drive_speed+downhill.dot(body_forward)*delta,-MAX_REVERSE_SPEED,MAX_FORWARD_SPEED)
