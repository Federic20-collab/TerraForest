# Vehicle source and license

The user supplied and authored the code and Vehicle.glb in
Godot_Vehicle_Driving_Test_FRESH_HEADLESS_REIMPORT_FIXED.zip, and explicitly
declared both their own 0BSD work in this chat on 2026-10-03.
Archive SHA-256: f38fc00ecd7a95ecd43c6beaf70f744f797dd862d656cb0d69822cf682cc82a0.
LICENSE.txt records the 0BSD terms. godot-cpp retains its separate MIT notice
inside the native addon, as with the other TerraForest native dependencies.

`assets/Vehicle.parked.res` is an offline derived version of that same model,
using the existing runtime transforms/materials. It retains **0BSD**, not the
prospective CC0 default. `assets/Vehicle.parked.bake.json` records source/output
hashes and the engine version. Original 0BSD code in
`addons/vehicle_runtime/native/vehicle_prototype.cpp` consolidates static opaque
parts and reuses their imported LOD indices; no external asset or dependency was
added. `tools/bake_vehicle_prototype.gd` refreshes it before export when stale.

Original scripts remain as a behavior reference. Resource paths were relocated
under vehicle_demo; car.tscn uses car_native.gd, which overrides steering and
longitudinal policy with NativeDrivingPolicy. NativeVehicleSuspension owns
wheel-contact sampling and spring forces; effects reuse its samples. Impact
recovery and interaction retain the original behavior; damage deformation and accessory springs now run in native helpers.
The isolated demo preserves 120 Hz physics and uses TerraForest's fullscreen
1920x1080 Forward+ rendering for comparison. The vehicle also integrates into the streamed main world through vehicle_runtime, with parked-pose persistence and collision readiness checks. It is not yet qualified for fleets or multiplayer.

## City vehicle additions (2026-11-20)

The user supplied `assets/city/Taxi.glb` (SHA-256
`523d57d71d9f75a3f0b207bca493b874997d0dfe738441452ad39b71c02c55d8`) and
`assets/city/Ambulance.glb` (SHA-256
`9d67008959130bed6623baee8c2319b5385e518bddc42c7bfa92208e351aec50`), plus
`assets/city/FireTRUCK.glb` (SHA-256
`396372e442919674e35d58c35f120adb6ca6f7ccaa6adac215a631c44583afcb`),
`assets/city/Police.glb` (SHA-256
`e9fae2c66640bd52b53479d5779cf6d3687eb5b9e68174c7761ba32e269327fd`),
`assets/city/Train.glb` (SHA-256
`5fa5875a0be6d3c2018bacfbf4e71df54b806796331f64834df22e11bd5c5882`), and
`assets/city/AirCraft.glb` (SHA-256
`e0b83b5283a78a8aa7ebf849efde53c422131ff11b86328e4010d646bc7b0207`), from
their local Downloads folder and requested their integration as spawnable
TerraForest vehicles. These originals are single full meshes with embedded
base-color and metallic-roughness PNGs; they contain no animation, skin or
separate wheel/door nodes, so their static-shell integration adds no wheel or
door animation. FireTruck and Train use their own larger placement footprints.
Police and Train are ground-driven; AirCraft has a dedicated arcade flight
controller at a 10 m authored wingspan. No rail-following controller was added.

On 2026-11-22 the user supplied animated remakes
`assets/city/Taxi_Full_Remake.glb` (SHA-256
`0ebbae6c8c9053d0ae747feac04a158a4bd1ddc5627b44d91ced5308eb67bda8`) and
`assets/city/PoliceMesh.glb` (SHA-256
`17b009b349d859e2b5b69cfb9219ad0a0993ec0daf9559efdad39867d827ed2a`).
The Taxi and Police providers now use those authored wheel/steer/door
hierarchies. The game drives wheel spin and steering from suspension/velocity,
opens the driver door on entry and closes it shortly afterward or on exit, and
adds red/blue beacon lights plus a looping siren to Police while driving. The
Taxi's disassembly/reassembly clip is a showcase animation and is not played
while driving. Their parked/far representation is merged by material into
compact static parts to stay within the native 64-part limit.

`assets/city/police_siren.wav` (SHA-256
`d57eb1bb6f44622f8be1e5d15d2d2f8745aa1ca7c4b9fbbb47e764d6f85e8b0d`) is an
original procedurally generated two-tone loop created
for TerraForest on 2026-11-22; it is not derived from a third-party recording.
`scripts/police_siren.gd` is original 0BSD code; the WAV follows the project
CC0-1.0 asset default. `GAP-005` applies to the user-supplied GLBs and their
textures, not this generated siren.

No separate asset license text was embedded in any GLB and the integration
request did not state one. `license_inventory.json` `GAP-005` records that pending
asset-specific rights evidence. The integration is retained at the maintainer's
direction; existing 0BSD controller code is reused unchanged and no third-party
dependency was added.

