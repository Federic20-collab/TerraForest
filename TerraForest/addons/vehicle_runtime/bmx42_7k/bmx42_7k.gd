extends Node3D
## Reference-guided exterior game asset. No ballistics or physical drivetrain simulation.

signal action_started(clip: StringName)
signal action_finished(clip: StringName)
signal assembly_changed

const TRACK_DRIVER = preload("res://addons/vehicle_runtime/bmx42_7k/track_driver.gd")
const CONTRACT_PATH := "res://addons/vehicle_runtime/bmx42_7k/track_contract.json"
static var filtered_material_cache: Dictionary = {}
static var mipmapped_texture_cache: Dictionary = {}

@export var create_collisions := true
@export var muzzle_flash_enabled := true
@export_range(0.1, 3.0, 0.05) var playback_speed := 1.0

var model: Node3D
var animation_player: AnimationPlayer
var active_clip: StringName = &""
var initialized := false
var parts: Dictionary = {}
var rest_transforms: Dictionary = {}
var detached: Dictionary = {}
var animation_bindings: Array[Dictionary] = []
var animation_time_origins: Dictionary = {}
var live_fire_target: Node3D
var hatch_tween: Tween
var render_meshes: Array[MeshInstance3D] = []
var skeletons: Array[Skeleton3D] = []
var generated_colliders: Array[CollisionObject3D] = []
var flash_root: Node3D
var contract: Dictionary = {}
var track_driver = TRACK_DRIVER.new()
var manual_drive := false
var headlights_enabled := true
var headlight_materials: Array[BaseMaterial3D] = []
var headlight_lights: Array[SpotLight3D] = []

func _ready() -> void:
	model = get_node_or_null("Model") as Node3D
	if not model:
		push_error("BMX42_7K: imported Model node is missing.")
		return
	if FileAccess.file_exists(CONTRACT_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
		if parsed is Dictionary: contract = parsed
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_cache_parts(model)
	_prepare_texture_filtering()
	if animation_player:
		animation_player.stop()
		for library_name in animation_player.get_animation_library_list():
			var local_library: AnimationLibrary = animation_player.get_animation_library(library_name).duplicate(true)
			animation_player.remove_animation_library(library_name)
			animation_player.add_animation_library(library_name, local_library)
		for clip in animation_player.get_animation_list():
			var loop_clip: bool = String(clip) in contract.get("loop_clips", []) or contract.get("clips", {}).get(String(clip), {}).get("loop", false)
			var animation := animation_player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_LINEAR if loop_clip else Animation.LOOP_NONE
			var first_key := INF
			for track in animation.get_track_count():
				if animation.track_get_key_count(track) > 0: first_key = minf(first_key, animation.track_get_key_time(track, 0))
			var authored: Dictionary = contract.get("clips", {}).get(String(clip), {})
			# Godot inserts a rest key at zero for immutable tracks. The authored
			# duration identifies Blender's initial-frame offset without using it.
			if authored.has("duration"): first_key = maxf(0.0, animation.length - float(authored["duration"]))
			animation_time_origins[clip] = first_key if is_finite(first_key) else 0.0
		_cache_animation_bindings()
		animation_player.animation_finished.connect(_on_action_finished)
	_restore_attached_rest()
	track_driver.configure(self, contract)
	if create_collisions: _build_colliders()
	_build_flash()
	_prepare_headlights()
	initialized = true

func _cache_parts(node: Node) -> void:
	if node is Node3D:
		parts[StringName(node.name)] = node
		rest_transforms[node] = node.transform
	if node is MeshInstance3D and node.mesh: render_meshes.append(node)
	if node is Skeleton3D: skeletons.append(node)
	for child in node.get_children(): _cache_parts(child)

func _prepare_texture_filtering() -> void:
	for instance in render_meshes:
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface) as BaseMaterial3D
			if not source: continue
			var material_key := source.resource_path if not source.resource_path.is_empty() else str(source.get_instance_id())
			if not filtered_material_cache.has(material_key):
				var filtered := source.duplicate() as BaseMaterial3D
				filtered.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_EMISSION]:
					var texture: Texture2D = source.get_texture(slot)
					if not texture: continue
					var texture_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
					if not mipmapped_texture_cache.has(texture_key):
						var image: Image = texture.get_image()
						if image and not image.has_mipmaps():
							var result := image.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL)
							if result != OK:
								push_error("BMX42_7K: could not generate texture mipmaps.")
								continue
							var mip_texture := ImageTexture.create_from_image(image)
							mip_texture.resource_name = texture.resource_name
							mip_texture.set_meta("source_texture_path", texture.resource_path)
							mip_texture.set_meta("normal_mipmaps_renormalized", slot == BaseMaterial3D.TEXTURE_NORMAL)
							mipmapped_texture_cache[texture_key] = mip_texture
						else: mipmapped_texture_cache[texture_key] = texture
					filtered.set_texture(slot, mipmapped_texture_cache[texture_key])
				filtered_material_cache[material_key] = filtered
			instance.set_surface_override_material(surface, filtered_material_cache[material_key])

func get_component(component_name: StringName) -> Node3D:
	var candidate: Node3D = parts.get(component_name)
	return candidate if is_instance_valid(candidate) else null

func available_animations() -> PackedStringArray:
	var result := PackedStringArray()
	if animation_player:
		for clip in animation_player.get_animation_list():
			if clip != &"RESET": result.append(clip)
	return result

func play_clip(clip: StringName) -> bool:
	if not animation_player or not animation_player.has_animation(clip): return false
	_cancel_hatch_tween()
	live_fire_target = null
	_refresh_animation_bindings()
	manual_drive = false
	track_driver.reset()
	animation_player.stop()
	_restore_attached_rest()
	active_clip = clip
	animation_player.speed_scale = playback_speed
	animation_player.play(clip)
	animation_player.advance(0.0)
	action_started.emit(clip)
	return true

func clip_time_origin(clip: StringName) -> float:
	return float(animation_time_origins.get(clip, 0.0))

func fire(burst: bool = false) -> bool:
	## Live cosmetic recoil: preserves driving, aim and hatch motion.
	var clip: StringName = &"Fire_Burst_3" if burst else &"Fire_Single"
	var recoil := get_component(StringName(contract.get("gun_recoil_node", "Gun_Recoil")))
	if not animation_player or not animation_player.has_animation(clip) or not recoil or not model.is_ancestor_of(recoil): return false
	if is_instance_valid(live_fire_target) and animation_player.is_playing(): return false
	animation_player.stop(true)
	live_fire_target = recoil
	_refresh_animation_bindings()
	active_clip = clip
	animation_player.speed_scale = playback_speed
	animation_player.play(clip)
	animation_player.advance(0.0)
	animation_player.seek(clip_time_origin(clip), true)
	action_started.emit(clip)
	return true

func fire_burst() -> bool:
	return fire(true)

func set_hatch_open(amount: float, duration: float = 0.8) -> bool:
	## Interpolates only the authored exterior hinge; no interior machinery is added.
	var hatch := get_component(StringName(contract.get("hatch_node", "Commander_Hatch_Pivot")))
	if not hatch or not model.is_ancestor_of(hatch): return false
	if animation_player and not is_instance_valid(live_fire_target):
		animation_player.stop(true)
		active_clip = &""
		# Leaving a scrubbed full firing preview must not strand the barrel
		# halfway through recoil while the independent hatch control runs.
		var recoil := get_component(StringName(contract.get("gun_recoil_node", "Gun_Recoil")))
		if recoil and model.is_ancestor_of(recoil): recoil.transform = rest_transforms[recoil]
	_cancel_hatch_tween()
	var rest: Transform3D = rest_transforms[hatch]
	var angle := deg_to_rad(float(contract.get("hatch_open_degrees", 68.0)) * clampf(amount, 0.0, 1.0))
	var destination := (rest.basis * Basis(Vector3.BACK, angle)).get_rotation_quaternion()
	if duration <= 0.0: hatch.quaternion = destination
	else:
		hatch_tween = create_tween()
		hatch_tween.tween_property(hatch, "quaternion", destination, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return true

func _cancel_hatch_tween() -> void:
	if hatch_tween and hatch_tween.is_valid(): hatch_tween.kill()
	hatch_tween = null

func _cancel_hatch_if_within(part: Node3D) -> void:
	var hatch := get_component(StringName(contract.get("hatch_node", "Commander_Hatch_Pivot")))
	if hatch and (hatch == part or part.is_ancestor_of(hatch)): _cancel_hatch_tween()

func reset_pose(reattach_parts: bool = true) -> void:
	_cancel_hatch_tween()
	live_fire_target = null
	if animation_player: animation_player.stop()
	manual_drive = false
	track_driver.reset()
	active_clip = &""
	if reattach_parts:
		for part in detached.keys().duplicate():
			if is_instance_valid(part): reattach_component(part.name, true)
	_restore_attached_rest()
	_refresh_animation_bindings()
	if flash_root: flash_root.visible = false
	assembly_changed.emit()

func _restore_attached_rest() -> void:
	for part in rest_transforms:
		if is_instance_valid(part) and (part == model or model.is_ancestor_of(part)): part.transform = rest_transforms[part]
	for skeleton in skeletons:
		if is_instance_valid(skeleton) and model.is_ancestor_of(skeleton): skeleton.reset_bone_poses()

func set_paused(paused: bool) -> void:
	if not animation_player or active_clip.is_empty(): return
	if paused: animation_player.pause()
	else: animation_player.play()

func seek(seconds: float) -> void:
	if animation_player and not active_clip.is_empty(): animation_player.seek(clampf(seconds, 0.0, animation_player.current_animation_length), true)

func set_speed(value: float) -> void:
	playback_speed = clampf(value, 0.1, 3.0)
	if animation_player: animation_player.speed_scale = playback_speed

func set_drive(left_speed: float, right_speed: float) -> bool:
	if not track_driver.configured: return false
	if not manual_drive:
		if is_instance_valid(live_fire_target):
			for wheel in track_driver.wheels:
				var node: Node3D = wheel["node"]
				if model.is_ancestor_of(node): node.transform = wheel["rest"]
			for skeleton in skeletons:
				if model.is_ancestor_of(skeleton): skeleton.reset_bone_poses()
			track_driver.reset()
			manual_drive = true
			track_driver.set_speeds(left_speed, right_speed)
			return true
		var aim_pose: Dictionary = {}
		for name in [contract.get("turret_node", "Turret_Pivot"), contract.get("gun_node", "Gun_Elevation"), contract.get("hatch_node", "Commander_Hatch_Pivot")]:
			var component := get_component(StringName(name))
			if component: aim_pose[component] = component.transform
		if animation_player: animation_player.stop()
		active_clip = &""
		_restore_attached_rest()
		for component in aim_pose: component.transform = aim_pose[component]
		track_driver.reset()
	manual_drive = true
	track_driver.set_speeds(left_speed, right_speed)
	return true

func set_turret_angles(yaw_degrees: float, elevation_degrees: float) -> bool:
	var turret := get_component(StringName(contract.get("turret_node", "Turret_Pivot")))
	var gun := get_component(StringName(contract.get("gun_node", "Gun_Elevation")))
	if not turret or not gun: return false
	if not is_instance_valid(live_fire_target):
		if animation_player: animation_player.stop()
		if not active_clip.is_empty():
			_restore_attached_rest()
			track_driver.reset()
		active_clip = &""
	var limits: Array = contract.get("elevation_limits_degrees", [-5.0, 25.0])
	var turret_rest: Transform3D = rest_transforms[turret]
	var gun_rest: Transform3D = rest_transforms[gun]
	var applied := false
	if model.is_ancestor_of(turret):
		turret.transform = Transform3D(turret_rest.basis * Basis(Vector3.UP, deg_to_rad(yaw_degrees)), turret_rest.origin)
		applied = true
	if model.is_ancestor_of(gun):
		gun.transform = Transform3D(gun_rest.basis * Basis(Vector3.BACK, deg_to_rad(clampf(elevation_degrees, limits[0], limits[1]))), gun_rest.origin)
		applied = true
	return applied

func _on_action_finished(clip: StringName) -> void:
	if flash_root: flash_root.visible = false
	action_finished.emit(clip)

func _cache_animation_bindings() -> void:
	animation_bindings.clear()
	var track_root := animation_player.get_node(animation_player.root_node)
	for clip in animation_player.get_animation_list():
		var animation := animation_player.get_animation(clip)
		for track in animation.get_track_count():
			var target := track_root.get_node_or_null(NodePath(animation.track_get_path(track).get_concatenated_names()))
			animation_bindings.append({"animation": animation, "track": track, "target": target, "enabled": animation.track_is_enabled(track)})

func _refresh_animation_bindings() -> void:
	for binding in animation_bindings:
		var target: Node = binding["target"]
		var attached := is_instance_valid(target) and (target == model or model.is_ancestor_of(target))
		var action_allowed := not is_instance_valid(live_fire_target) or (is_instance_valid(target) and (target == live_fire_target or live_fire_target.is_ancestor_of(target)))
		binding["animation"].track_set_enabled(binding["track"], binding["enabled"] and attached and action_allowed)

func detach_component(component_name: StringName, new_parent: Node3D) -> Node3D:
	var part := get_component(component_name)
	if not part or not new_parent or part == model or part == self or part == new_parent or part.is_ancestor_of(new_parent): return null
	_cancel_hatch_if_within(part)
	if animation_player: animation_player.pause()
	if not detached.has(part):
		detached[part] = {"parent": part.get_parent(), "pose": part.transform}
	part.reparent(new_parent, true)
	_refresh_animation_bindings()
	if animation_player: animation_player.clear_caches()
	assembly_changed.emit()
	return part

func reattach_component(component_name: StringName, assembled: bool = true) -> bool:
	var part := get_component(component_name)
	if not part or not detached.has(part): return false
	var saved: Dictionary = detached[part]
	if not is_instance_valid(saved["parent"]): return false
	_cancel_hatch_if_within(part)
	part.reparent(saved["parent"], false)
	part.transform = rest_transforms[part] if assembled else saved["pose"]
	if assembled:
		for child in rest_transforms:
			if is_instance_valid(child) and part.is_ancestor_of(child): child.transform = rest_transforms[child]
		for skeleton in skeletons:
			if is_instance_valid(skeleton) and (skeleton == part or part.is_ancestor_of(skeleton)): skeleton.reset_bone_poses()
	detached.erase(part)
	_refresh_animation_bindings()
	if animation_player: animation_player.clear_caches()
	assembly_changed.emit()
	return true

func geometry_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for instance in render_meshes:
		if not is_instance_valid(instance) or instance.get_meta("transient_effect", false): continue
		if not model.is_ancestor_of(instance): continue
		var local_bounds: AABB = global_transform.affine_inverse() * instance.global_transform * instance.mesh.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	return bounds

func geometry_statistics() -> Dictionary:
	var result := {"model_vertices": 0, "effect_vertices": 0, "model_triangles": 0, "effect_triangles": 0, "triangles": 0, "mesh_components": 0, "total_vertices": 0}
	for instance in render_meshes:
		if not is_instance_valid(instance) or not instance.mesh: continue
		var effect: bool = instance.get_meta("transient_effect", false)
		if not effect: result["mesh_components"] += 1
		for surface in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: int = arrays[Mesh.ARRAY_VERTEX].size()
			var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
			result["effect_vertices" if effect else "model_vertices"] += vertices
			var triangles := int((indices if indices > 0 else vertices) / 3)
			result["triangles"] += triangles
			result["effect_triangles" if effect else "model_triangles"] += triangles
	result["total_vertices"] = result["model_vertices"] + result["effect_vertices"]
	return result

func set_collision_enabled(enabled: bool) -> void:
	for body in generated_colliders:
		if is_instance_valid(body):
			body.set_deferred("collision_layer", 1 if enabled else 0)
			body.set_deferred("collision_mask", 1 if enabled else 0)

func _build_colliders() -> void:
	for name in contract.get("collision_meshes", ["Hull_Main", "Turret_Main", "Gun_Mantlet"]):
		var part := get_component(StringName(name)) as MeshInstance3D
		if not part or not part.mesh: continue
		var shape: Shape3D = part.mesh.create_convex_shape(true, false)
		if not shape: continue
		shape.margin = 0.002
		var body := AnimatableBody3D.new()
		body.name = String(name) + "_Collision"
		body.sync_to_physics = false
		var collision := CollisionShape3D.new()
		collision.name = "ConvexShape"
		collision.shape = shape
		body.add_child(collision)
		part.add_child(body)
		generated_colliders.append(body)

func _prepare_headlights() -> void:
	for name in contract.get("headlight_nodes", []):
		var part := get_component(StringName(name)) as MeshInstance3D
		if not part or not part.mesh: continue
		for surface in part.mesh.get_surface_count():
			var source := part.get_active_material(surface) as BaseMaterial3D
			if not source: continue
			var local := source.duplicate() as BaseMaterial3D
			local.emission_enabled = headlights_enabled
			local.emission = Color(0.92, 0.90, 0.82)
			local.emission_energy_multiplier = 0.6
			part.set_surface_override_material(surface, local)
			headlight_materials.append(local)
		var beam := SpotLight3D.new()
		beam.name = String(name).replace("_Lens", "_Beam")
		beam.light_color = Color(1.0, 0.96, 0.85)
		beam.light_energy = 1.0
		beam.light_specular = 0.4
		beam.spot_range = 8.0
		beam.spot_angle = 30.0
		beam.spot_attenuation = 1.3
		beam.shadow_enabled = false
		part.add_child(beam)
		var forward := (model.global_basis * Vector3.RIGHT).normalized()
		var up := (model.global_basis * Vector3.UP).normalized()
		beam.global_position = part.global_transform * part.mesh.get_aabb().get_center() + forward * 0.035
		beam.look_at(beam.global_position + (forward - up * 0.10).normalized(), up)
		beam.visible = headlights_enabled
		headlight_lights.append(beam)

func set_headlights(enabled: bool) -> void:
	headlights_enabled = enabled
	for material in headlight_materials: material.emission_enabled = enabled
	for beam in headlight_lights:
		if is_instance_valid(beam): beam.visible = enabled

func _build_flash() -> void:
	var muzzle := get_component(StringName(contract.get("muzzle_node", "Muzzle_Exit")))
	if not muzzle: return
	flash_root = Node3D.new()
	flash_root.name = "CosmeticMuzzleFlash"
	flash_root.visible = false
	var length: float = contract.get("muzzle_flash_length", 0.40)
	var width: float = length * 0.45
	flash_root.position.x = length * 0.5
	muzzle.add_child(flash_root)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
void fragment() {
    float x = UV.x;
    float y = abs(UV.y * 2.0 - 1.0);
    float taper = max(0.0, 1.0 - x);
    float core = max(0.0, 1.0 - y / (0.08 + 0.80 * taper));
    float mask = core * smoothstep(0.0, 0.12, x) * taper;
    ALBEDO = mix(vec3(1.0, 0.28, 0.02), vec3(1.0, 0.94, 0.60), core);
    EMISSION = ALBEDO * 2.0;
    ALPHA = mask * 0.85;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	for index in 2:
		var quad := QuadMesh.new()
		quad.size = Vector2(length, width)
		quad.material = material
		var instance := MeshInstance3D.new()
		instance.name = "FlashQuad" + str(index + 1)
		instance.mesh = quad
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.rotation.x = PI * 0.5 * index
		instance.set_meta("transient_effect", true)
		flash_root.add_child(instance)
		render_meshes.append(instance)

func _process(delta: float) -> void:
	if manual_drive: track_driver.advance(delta)
	if not flash_root: return
	var lit := false
	if muzzle_flash_enabled and animation_player and not active_clip.is_empty():
		var time := animation_player.current_animation_position - clip_time_origin(active_clip)
		var windows: Array = contract.get("flash_windows", {}).get(String(active_clip), [[0.03, 0.10]] if active_clip == &"Fire_Single" else [])
		for window in windows:
			if time >= window[0] and time <= window[1]: lit = true
	flash_root.visible = lit
