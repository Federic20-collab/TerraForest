# Boat source and license

The project owner supplied `Boat_6K_Geometry_Review.glb` at the repository root on
2026-11-16 for integration into TerraForest. It was copied unchanged to
`assets/Boat_6K_Geometry_Review.glb` for this demo.

- Size: 322,996 bytes
- SHA-256: `2245e43a1889eea7430dd45d59951afac737e1e43198b5c876a530b0f810b919`
- Author: project owner (user-supplied original asset)
- Tool provenance in the file: glTF Blender I/O v5.3.43, scene
  `Boat - 6K Source-Matched Retopology`, 82 meshes, seven authored materials,
  no images and no animations.
- Geometry in the file: about 1.0 x 0.295 x 0.423 m (X = boat length, bow at -X),
  imported at 6x in `scenes/boat.tscn` (about 6.0 x 1.8 x 2.5 m).

Terms: the asset is recorded as a new original asset under the repository's
CC0-1.0 default. New code in this folder (scripts, shader, scenes, test) is
original 0BSD work. No third-party textures or other material are included.

The source GLB remains at the repository root as supplied; the copy under
`assets/` is the version referenced by the Godot scene and covered by this record.

The main-world pack uses `assets/Boat.world.res`, a consolidated copy baked from
that unchanged source by `tools/bake_boat_world_mesh.gd`: seven surfaces, 5,976
vertices, SHA-256
`ee1002144a3fdc7a8596f0146156e076825f481752caa2c77ae4ec318d03c5c6`. The bake
record is `assets/Boat.world.bake.json`.
