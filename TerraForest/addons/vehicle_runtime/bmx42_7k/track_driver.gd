extends RefCounted
## Visual drivetrain only. It adds no meshes and does not simulate vehicle dynamics.
## Rigid-weighted tread bones and wheel phase use the same traveled distance.
## Each track is one skinned draw surface; the controller adds no rendered vertices.

var asset: Node3D
var drive_space: Node3D
var model_to_drive := Transform3D.IDENTITY
var tracks: Array[Dictionary] = []
var wheels: Array[Dictionary] = []
var speeds := {"Left": 0.0, "Right": 0.0}
var distances := {"Left": 0.0, "Right": 0.0}
var configured := false
var configuration_errors: Array[String] = []

func configure(owner: Node3D, contract: Dictionary) -> void:
	asset = owner
	drive_space = owner.get_component(StringName(contract.get("vehicle_rig", "Vehicle_Rig")))
	if not drive_space: drive_space = owner.model
	model_to_drive = drive_space.global_transform.affine_inverse() * owner.model.global_transform
	var blender_coordinates: bool = contract.get("coordinate_space", "blender_world") == "blender_world"
	tracks.clear()
	wheels.clear()
	configuration_errors.clear()
	var seen_sides: Dictionary = {}
	var seen_bones: Dictionary = {}
	for source in contract.get("tracks", []):
		var side := String(source.get("side", ""))
		if side not in ["Left", "Right"] or seen_sides.has(side): configuration_errors.append("Each track must have a distinct Left/Right side.")
		seen_sides[side] = true
		var samples: Array[Dictionary] = []
		for sample in source.get("samples", []):
			var p := _vector(sample["position"], blender_coordinates)
			var q := _quaternion(sample["rotation_quaternion"], blender_coordinates)
			var local_frame := model_to_drive * Transform3D(Basis(q), p)
			samples.append({"distance": float(sample["distance"]), "frame": local_frame})
		var length := float(source.get("length", 0.0))
		if samples.size() < 3 or length <= 0.0:
			configuration_errors.append("Track " + side + " needs at least three path samples and a positive length.")
			continue
		var valid_path := true
		for index in range(1, samples.size()):
			if float(samples[index]["distance"]) <= float(samples[index - 1]["distance"]): valid_path = false
		var first_frame: Transform3D = samples[0]["frame"]
		var final_frame: Transform3D = samples[-1]["frame"]
		if absf(float(samples[0]["distance"])) > 0.0001 or absf(float(samples[-1]["distance"]) - length) > 0.0001: valid_path = false
		if not first_frame.is_equal_approx(final_frame): valid_path = false
		if not valid_path:
			configuration_errors.append("Track " + side + " path must increase from 0 to length and close to its first frame.")
			continue
		var track := {"side": side, "length": length, "samples": samples, "links": [], "motion_sign": float(source.get("motion_sign", 1.0))}
		var links: Array[Dictionary] = []
		for link in source.get("links", []):
			var distance := float(link["distance"])
			if link.has("bone_name"):
				var skeleton := _find_skeleton(owner.model, String(link["bone_name"]))
				if not skeleton:
					configuration_errors.append("Missing tread bone: " + String(link["bone_name"]))
					continue
				var bone := skeleton.find_bone(String(link["bone_name"]))
				var bone_key := str(skeleton.get_instance_id()) + ":" + str(bone)
				if seen_bones.has(bone_key): configuration_errors.append("Duplicate tread bone: " + String(link["bone_name"]))
				seen_bones[bone_key] = true
				var rest_frame := drive_space.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone)
				# Blender bone axes may differ from the tread's local tangent frame.
				# Keep that fixed bind-space offset rather than assuming an axis convention.
				var bind_offset := sample(track, distance).affine_inverse() * rest_frame
				links.append({"skeleton": skeleton, "bone": bone, "bone_name": String(link["bone_name"]), "parent_bone": skeleton.get_bone_parent(bone), "distance": distance, "bind_offset": bind_offset})
			else:
				var node: Node3D = owner.get_component(StringName(link.get("name", "")))
				if node: links.append({"node": node, "distance": distance})
				else: configuration_errors.append("Missing rigid tread node: " + String(link.get("name", "")))
		if links.size() != source.get("links", []).size(): configuration_errors.append("Incomplete tread link resolution on " + side)
		if samples.size() >= 3 and not links.is_empty():
			track["links"] = links
			tracks.append(track)
	for source in contract.get("wheels", []):
		var node: Node3D = owner.get_component(StringName(source["name"]))
		if not node:
			configuration_errors.append("Missing wheel: " + String(source["name"]))
			continue
		if float(source["radius"]) <= 0.0: configuration_errors.append("Wheel radius must be positive: " + String(source["name"]))
		var axis := _vector(source.get("axis", [0.0, 1.0, 0.0]), blender_coordinates).normalized()
		if source.get("axis_space", "canonical") == "canonical":
			axis = node.global_transform.basis.inverse() * owner.model.global_transform.basis * axis
		wheels.append({"node": node, "side": String(source["side"]), "radius": float(source["radius"]), "axis": axis.normalized(), "rest": node.transform, "angle": 0.0, "rotation_sign": float(source.get("rotation_sign", 1.0))})
	configured = configuration_errors.is_empty() and tracks.size() == 2 and not wheels.is_empty() and wheels.size() == contract.get("wheels", []).size()
	if not configured: push_error("BMX42 drivetrain contract: " + "; ".join(configuration_errors))

func _find_skeleton(root: Node, bone_name: String) -> Skeleton3D:
	if root is Skeleton3D and root.find_bone(bone_name) >= 0: return root
	for child in root.get_children():
		var found := _find_skeleton(child, bone_name)
		if found: return found
	return null

func _vector(value: Array, blender: bool) -> Vector3:
	return Vector3(value[0], value[2], -value[1]) if blender else Vector3(value[0], value[1], value[2])

func _quaternion(value: Array, blender: bool) -> Quaternion:
	# Contract stores Blender w,x,y,z; Godot-native contract stores x,y,z,w.
	return Quaternion(value[1], value[3], -value[2], value[0]).normalized() if blender else Quaternion(value[0], value[1], value[2], value[3]).normalized()

func set_speeds(left: float, right: float) -> void:
	speeds["Left"] = left
	speeds["Right"] = right

func reset() -> void:
	set_speeds(0.0, 0.0)
	distances = {"Left": 0.0, "Right": 0.0}
	for wheel in wheels: wheel["angle"] = 0.0

func advance(delta: float) -> void:
	if not configured: return
	for side in ["Left", "Right"]:
		distances[side] += float(speeds[side]) * delta
	for track in tracks:
		var length: float = track["length"]
		for link in track["links"]:
			var distance: float = fposmod(float(link["distance"]) + float(distances[track["side"]]) * float(track["motion_sign"]), length)
			var desired_frame := drive_space.global_transform * sample(track, distance)
			if link.has("skeleton"):
				var skeleton: Skeleton3D = link["skeleton"]
				if not is_instance_valid(skeleton) or not asset.model.is_ancestor_of(skeleton): continue
				var pose: Transform3D = skeleton.global_transform.affine_inverse() * desired_frame * link["bind_offset"]
				if int(link["parent_bone"]) >= 0:
					pose = skeleton.get_bone_global_pose(link["parent_bone"]).affine_inverse() * pose
				# Local poses avoid a dirty global-pose recalculation per tread bone.
				skeleton.set_bone_pose(link["bone"], pose)
			else:
				var node: Node3D = link["node"]
				if is_instance_valid(node) and asset.model.is_ancestor_of(node): node.global_transform = desired_frame
	for wheel in wheels:
		var node: Node3D = wheel["node"]
		wheel["angle"] = fposmod(float(distances[wheel["side"]]) * float(wheel["rotation_sign"]) / maxf(0.001, wheel["radius"]), TAU)
		if not is_instance_valid(node) or not asset.model.is_ancestor_of(node): continue
		var rest: Transform3D = wheel["rest"]
		node.transform = Transform3D(rest.basis * Basis(wheel["axis"], wheel["angle"]), rest.origin)

func sample(track: Dictionary, distance: float) -> Transform3D:
	var samples: Array = track["samples"]
	var low := 0
	var high := samples.size() - 2
	while low < high:
		var middle: int = (low + high + 1) / 2
		if float(samples[middle]["distance"]) <= distance: low = middle
		else: high = middle - 1
	var a: Dictionary = samples[low]
	var b: Dictionary = samples[low + 1]
	var amount := clampf((distance - float(a["distance"])) / maxf(0.000001, float(b["distance"]) - float(a["distance"])), 0.0, 1.0)
	var frame_a: Transform3D = a["frame"]
	var frame_b: Transform3D = b["frame"]
	return Transform3D(Basis(frame_a.basis.get_rotation_quaternion().slerp(frame_b.basis.get_rotation_quaternion(), amount)), frame_a.origin.lerp(frame_b.origin, amount))

func status() -> Dictionary:
	var bones := 0
	var nodes := 0
	for track in tracks:
		for link in track["links"]:
			if link.has("skeleton"): bones += 1
			else: nodes += 1
	return {"configured": configured, "configuration_errors": configuration_errors.duplicate(), "speeds": speeds.duplicate(), "distances": distances.duplicate(), "track_sides": tracks.size(), "links": bones + nodes, "rigid_tread_bones": bones, "rigid_tread_nodes": nodes, "wheels": wheels.size(), "render_vertices_added": 0}
