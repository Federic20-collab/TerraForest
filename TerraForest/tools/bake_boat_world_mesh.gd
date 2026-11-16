# SPDX-License-Identifier: 0BSD
extends SceneTree

## Builds the one-part world boat visual from the authored demo scene. The
## standalone scene keeps its 82 imported mesh parts; the vehicle pack and its
## parked MultiMesh prototype must stay within the native 64-part limit.

const SOURCE := "res://boat_demo/scenes/boat.tscn"
const OUTPUT := "res://boat_demo/assets/Boat.world.res"
const RECEIPT := "res://boat_demo/assets/Boat.world.bake.json"


func _initialize() -> void:
	call_deferred("run")


func _sha256(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func run() -> void:
	var packed: PackedScene = load(SOURCE)
	var boat := packed.instantiate()
	root.add_child(boat)
	await process_frame
	var groups: Dictionary = {}
	var order: Array[int] = []
	var parts := 0
	for mesh_instance: MeshInstance3D in boat.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			continue
		parts += 1
		# Bake the authored visual transform (scale and heading) into the one-part
		# mesh so the world scene can use it at identity scale.
		var transform := mesh_instance.global_transform
		for surface in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.material_override
			if material == null:
				material = mesh_instance.mesh.surface_get_material(surface)
			var key := material.get_instance_id() if material != null else 0
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool": tool, "material": material}
				order.append(key)
			groups[key]["tool"].append_from(mesh_instance.mesh, surface, transform)
	var merged := ArrayMesh.new()
	merged.resource_name = "BoatWorld"
	var vertices := 0
	for key in order:
		var tool: SurfaceTool = groups[key]["tool"]
		var arrays := tool.commit_to_arrays()
		vertices += arrays[Mesh.ARRAY_VERTEX].size()
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		merged.surface_set_material(merged.get_surface_count() - 1, groups[key]["material"])
	var error := ResourceSaver.save(merged, OUTPUT)
	if error != OK:
		push_error("Boat world mesh save failed: %d" % error)
		quit(1)
		return
	var source_bytes := FileAccess.get_file_as_bytes("res://boat_demo/assets/Boat_6K_Geometry_Review.glb")
	var output_bytes := FileAccess.get_file_as_bytes(OUTPUT)
	var receipt := {
		"source": SOURCE,
		"output": OUTPUT,
		"engine": Engine.get_version_info().string,
		"source_parts": parts,
		"output_surfaces": merged.get_surface_count(),
		"output_vertices": vertices,
		"source_sha256": _sha256(source_bytes),
		"output_sha256": _sha256(output_bytes),
		"output_bytes": output_bytes.size(),
	}
	var file := FileAccess.open(RECEIPT, FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt, "  ") + "\n")
	file.close()
	print("BOAT_WORLD_BAKE ", JSON.stringify(receipt))
	boat.free()
	quit(0)
