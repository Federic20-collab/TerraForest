# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks := 0
var failures := 0
var view: Node3D
var skeleton: Skeleton3D
var hatchet_attachment: BoneAttachment3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func pose(clip: String, time: float) -> void:
	view.animation_player.play(view.clips[clip], 0)
	view.animation_player.seek(time, true)
	view.animation_player.pause()
	view.animation_player.advance(0)
	skeleton.force_update_all_bone_transforms()
	if is_instance_valid(hatchet_attachment):
		hatchet_attachment.on_skeleton_update()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.6
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("364756")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 1.68, 0)
	camera.fov = 75
	camera.near = .04
	camera.current = true
	view = preload("res://addons/characters/runtime/human_view.gd").new()
	camera.add_child(view)
	view.set_process(false)
	skeleton = view.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	view.equip(2)

	var built_in_axe: MeshInstance3D
	var hatchet_mesh: MeshInstance3D
	for mesh: MeshInstance3D in view.meshes:
		var label := String(mesh.name).to_lower().replace("_", ".")
		if label == "equipment.axe":
			built_in_axe = mesh
		elif label == "equipment.hatchet":
			hatchet_mesh = mesh
	check(hatchet_mesh != null, "supplied hatchet is attached to the held-tool rig")
	check(built_in_axe != null and not built_in_axe.visible, "old built-in axe is hidden while item 2 is equipped")
	if hatchet_mesh == null:
		await finish()
		return
	check(hatchet_mesh.visible, "hatchet is visible for the axe item")
	check(hatchet_mesh.mesh.get_surface_count() == 1, "hatchet keeps its authored single surface")
	var material := hatchet_mesh.get_active_material(0) as StandardMaterial3D
	check(material != null and material.albedo_texture != null and material.normal_texture != null, "hatchet retains base, normal and ORM detail")
	var ancestor: Node = hatchet_mesh.get_parent()
	while ancestor != null and not ancestor is BoneAttachment3D:
		ancestor = ancestor.get_parent()
	hatchet_attachment = ancestor as BoneAttachment3D
	check(hatchet_attachment != null and String(hatchet_attachment.bone_name) == "Weapon_Axe", "hatchet rides the authored Weapon_Axe bone")
	var bounds: AABB = hatchet_mesh.global_transform * hatchet_mesh.mesh.get_aabb()
	check(bounds.size.y > .5 and bounds.size.y < .9 and bounds.size.x < .5, "hatchet is scaled to the existing axe grip and frame")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://reports/hatchet_asset")
		pose("FP_Axe_Idle", 0)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://reports/hatchet_asset/idle.png") == OK, "idle hatchet capture saves")
		pose("FP_Axe_Swing", 34.0 / 60.0)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://reports/hatchet_asset/swing.png") == OK, "swing hatchet capture saves")
	pose("FP_Axe_Idle", 0)
	var start: Transform3D = hatchet_mesh.global_transform
	pose("FP_Axe_Swing", 34.0 / 60.0)
	var moved: Transform3D = hatchet_mesh.global_transform
	check(start.origin.distance_to(moved.origin) > .02 or start.basis.get_rotation_quaternion().angle_to(moved.basis.get_rotation_quaternion()) > .02,
		"hatchet follows the existing axe animation without a second rig")
	view.equip(1)
	check(not hatchet_mesh.visible, "switching to the pickaxe hides the hatchet")
	view.equip(2)
	check(hatchet_mesh.visible, "equipping the axe restores the hatchet")
	view.equip(0)
	check(not hatchet_mesh.visible, "empty hands hide the hatchet")
	await finish()

func finish() -> void:
	if is_instance_valid(view):
		view.queue_free()
		await process_frame
	print("HATCHET_ASSET checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
