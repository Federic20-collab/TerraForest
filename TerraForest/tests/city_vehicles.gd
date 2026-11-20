# SPDX-License-Identifier: 0BSD
extends SceneTree

## Static-shell city vehicle providers: full-mesh Taxi/Ambulance/FireTruck/Police/Train/AirCraft scenes must load,
## keep the proven chassis/suspension layout, expose one parked render part, and
## present their authored dimensions on the established forward axis.

const Packs = preload("res://addons/vehicle_runtime/vehicle_packs.gd")
const VEHICLES := {
	"terraforest.taxi.v1": {"name": "Taxi", "length": 4.7, "height": 1.772, "half_length": 2.60},
	"terraforest.ambulance.v1": {"name": "Ambulance", "length": 5.411, "height": 2.528, "half_length": 2.60},
	"terraforest.firetruck.v1": {"name": "FireTruck", "length": 6.413, "height": 2.768, "half_length": 3.20},
	"terraforest.police.v1": {"name": "Police", "length": 4.808, "height": 1.725, "half_length": 2.60},
	"terraforest.train.v1": {"name": "Train", "length": 6.408, "height": 2.659, "half_length": 3.20},
	"terraforest.aircraft.v1": {"name": "AirCraft", "length": 6.511, "height": 1.998, "half_length": 3.20},
}
var failures := 0

func check(passed: bool, label: String) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void:
	run.call_deferred()

func local_visual_bounds(body: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inverse := body.global_transform.affine_inverse()
	for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null or not node.is_visible_in_tree(): continue
		var box: AABB = (inverse * node.global_transform) * node.mesh.get_aabb()
		if first: result = box; first = false
		else: result = result.merge(box)
	return result

func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var packs := Packs.new()
	check(packs.prepare(false), "built-in vehicle manifest prepares")
	for kind: String in VEHICLES:
		var expected: Dictionary = VEHICLES[kind]
		check(packs.vehicles.has(kind) and packs.vehicles[kind].name == expected.name, "provider registered: " + kind)
		check(packs.request(kind), "scene request accepted: " + expected.name)
		var deadline := Time.get_ticks_msec() + 30000
		while not packs.ready(kind) and Time.get_ticks_msec() < deadline:
			await process_frame
		var scene: PackedScene = packs.take(kind)
		check(scene != null, "scene loads: " + expected.name)
		if scene == null: continue
		var body: RigidBody3D = scene.instantiate()
		root.add_child(body)
		await process_frame
		var label: String = expected.name
		check(body.get_node_or_null("ChassisCollision") != null, label + " keeps one chassis collision proxy")
		check(body.get_node_or_null("VehicleVisual/RuntimeBody") != null, label + " builds the shared runtime body")
		check(body.wheel_rays.size() == 4 and body.wheel_rays.all(func(ray: RayCast3D): return ray != null), label + " keeps four suspension rays")
		check(body.driving_policy != null and body.streaming == null, label + " loads the native driving policy before world install")
		var bounds := local_visual_bounds(body)
		check(absf(bounds.size.z - expected.length) < 0.08, label + " faces +Z at authored length " + str(snappedf(bounds.size.z, 0.01)))
		check(absf(bounds.size.y - expected.height) < 0.08, label + " authored height " + str(snappedf(bounds.size.y, 0.01)))
		check(bounds.position.y < -0.75 and bounds.position.y > -0.9, label + " mesh bottom sits at the suspension ride height " + str(snappedf(bounds.position.y, 0.01)))
		var adapter: RefCounted = load(packs.vehicles[kind].adapter).new()
		check(adapter.accepts(body), label + " accepts the standard vehicle adapter")
		check(adapter.collision(body) != null, label + " adapter exposes its parked chassis collision")
		check(is_equal_approx(adapter.half_length(), expected.half_length), label + " uses its size-aware placement footprint")
		var parts: Array = []
		for node: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
			if node.mesh != null and node.is_visible_in_tree():
				parts.append({"mesh": node.mesh, "transform": body.global_transform.affine_inverse() * node.global_transform, "material": node.material_override})
		check(parts.size() == 1, label + " presents one full-mesh parked prototype part")
		check(adapter.parked_render_parts(body, parts) == parts, label + " keeps the exact full mesh for distant parking")
		body.free()
		await process_frame
	packs.finish()
	print("CITY_VEHICLES failures=", failures)
	quit(1 if failures else 0)
