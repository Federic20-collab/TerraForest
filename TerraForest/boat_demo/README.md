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
- `A` / `Left`, `D` / `Right`: rudder and steering.
- `Space`: idle (throttle to zero).
- `R`: reset to the dock.

## Model and materials

The GLB is imported unchanged at 4x scene scale (about 4.0 m long, 1.7 m beam),
rotated so the bow is the vehicle's +Z forward direction. Its seven authored
materials and 82 mesh parts are used as imported. See `PROVENANCE.md`.

## Water and buoyancy

`scripts/water_surface.gd` and `scripts/water.gdshader` share one three-wave
height field. Eight hull-bottom probes sample it each physics tick and apply
spring/damper forces with the project gravity (20 m/s²). Thrust acts at the
outboard motor position, rudder yaw is speed-scaled, and water drag/righting keep
the boat planing without capsizing. The demo water is a visual height field, not
the streamed world's volumetric lake runtime.

## Check

```
python tools/run_godot_check.py boat_demo_smoke --headless --timeout 60 --require BOAT_SMOKE
```

The check asserts the boat settles with all eight probes wet and upright, the bow
faces +Z, throttle covers more than 10 m above 20 km/h, and rudder changes heading
while the hull stays upright. The most recent passing run is
`reports/checks/20261116T180058848632Z`.

## Remaining limits

This is a single-scene boat, not a vehicle-pack provider: main-world placement,
entry/exit, persistence, fleet activation, multiplayer authority, collision with
the streamed terrain/water runtime and sustained populated-world performance are
not implemented or qualified here.
