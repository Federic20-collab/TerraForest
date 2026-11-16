# Boat demo

A standalone scene that places the supplied `Boat_6K_Geometry_Review.glb` in a
demo lake and drives it with an arcade buoyancy controller. It does not depend on
the car's suspension, the native vehicle addon, or a saved world.

Run `launchers/legacy/Launch Boat Demo.cmd`, or:

```
godot --path TerraForest res://boat_demo/main.tscn
```

The launcher performs a headless asset import into the existing project `.godot`
cache, then opens the scene fullscreen at 1920x1080, 60 FPS and the demo's
120 Hz physics. It creates no saved world, export or additional generated output.

## Controls

- `W` / `Up`: throttle. `S` / `Down`: reverse.
- `A` / `Left`, `D` / `Right`: rudder; `D` steers right and `A` steers left.
- `Space`: idle (throttle to zero).
- `R`: reset to the dock.

## Model and materials

The GLB is imported unchanged at 6x scene scale (about 6.0 m long, 2.5 m beam),
rotated so the bow is the vehicle's +Z forward direction. Its seven authored
materials and 82 mesh parts are used as imported. The visual is offset upward so
the model's own interior stays above the waterline; no extra hull or floor
geometry is added. See `PROVENANCE.md`.

## Water and buoyancy

`scripts/water_surface.gd` and `scripts/water.gdshader` share one three-wave
height field. Eight hull-bottom probes sample it each physics tick and apply
spring/damper forces with the project gravity (20 m/s²). Thrust acts at the
outboard motor position, rudder yaw is speed-scaled, and water drag/righting keep
the boat planing without capsizing. The hull also emits a speed-scaled foam wake,
bow spray and stern spray at the sampled waterline. The demo water is a visual height field, not
the streamed world's volumetric lake runtime.

## Main world vehicle pack

The boat is also the second built-in vehicle provider, `terraforest.boat.v1`, in
`addons/vehicle_runtime/ranger.module.json`. Spawn it from the Developer vehicle
pack while aiming along open water. `scenes/boat_world.tscn` extends the demo
controller: buoyancy samples the streamed world's volumetric lake surface instead
of the demo wave field, placement picks the lake surface and rejects shallow or
obstructed water, `E` enters and exits, and exiting over water puts the player in
the water to swim. The world host owns persistence and disables the demo `R`
reset. The 82 model parts are baked once into `assets/Boat.world.res` (seven
surfaces) so the native parked prototype stays inside its 64-part limit; the
source GLB is unchanged.

## Check

```
python tools/run_godot_check.py boat_demo_smoke --headless --timeout 60 --require BOAT_SMOKE
python tools/run_godot_check.py vehicle_boat_pack --headless --timeout 90 --require VEHICLE_BOAT_PACK
python tools/run_godot_check.py vehicle_boat_world --headless --timeout 240 --require VEHICLE_BOAT_WORLD -- --vehicle-fleet
```

The demo check asserts the boat settles with all eight probes wet and upright, the
bow faces +Z, throttle covers more than 10 m above 20 km/h, the wake is emitting,
and right rudder turns the bow right while the hull stays upright. The pack check covers registration, adapter
acceptance, placement, controls, camera and parking. The world check authors a
real lake, spawns and enters the boat, drives it on the actual lake surface,
exits into the water and captures a versioned fleet snapshot.

## Remaining limits

Multiplayer authority and sustained populated-world performance are not qualified
here. The world check uses a temporary authored lake; natural ocean/lake
navigation across a full saved world still relies on the same lake runtime.
