# SPDX-License-Identifier: 0BSD
extends "res://addons/vehicle_runtime/city_vehicle_adapter.gd"

## Animated Taxi/Police adapter. The live body keeps its authored wheel and door
## hierarchy, but parked/far representation must stay within the native 64-part
## limit. Merge visible parts by material once, then use those compact parts for
## the parked renderer and horizon.

var _merged_parts: Dictionary = {}

func prepare_resources() -> void:
	pass

func preparation_ready() -> bool:
	return true

func finish_resources() -> void:
	pass

func parked_render_parts(body: RigidBody3D, original: Array) -> Array:
	if original.is_empty(): return original
	var kind := String(body.get_meta("vehicle_kind", "animated"))
	if _merged_parts.has(kind): return _merged_parts[kind]
	var groups: Dictionary = {}
	for part: Variant in original:
		if not part is Dictionary: continue
		var mesh: Mesh = part.get("mesh", null) as Mesh
		if mesh == null: continue
		var xform: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var override: Material = part.get("material", null) as Material
		for surface in mesh.get_surface_count():
			var material: Material = override if override != null else mesh.surface_get_material(surface)
			var key: int = material.get_instance_id() if material != null else 0
			var group: Dictionary
			if groups.has(key):
				group = groups[key]
			else:
				group = {"material": material, "tool": SurfaceTool.new()}
				group.tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = group
			group.tool.append_from(mesh, surface, xform)
	var result: Array = []
	for key: int in groups:
		var group: Dictionary = groups[key]
		var tool: SurfaceTool = group.tool
		if group.material != null:
			tool.set_material(group.material)
		var merged: ArrayMesh = tool.commit()
		if merged != null and merged.get_surface_count() > 0:
			result.append({"mesh": merged, "transform": Transform3D.IDENTITY, "material": null})
	if result.is_empty(): return original
	_merged_parts[kind] = result
	return result
