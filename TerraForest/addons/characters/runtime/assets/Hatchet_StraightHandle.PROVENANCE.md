# Supplied hatchet source

The project owner supplied `Hatchet_StraightHandle.glb` at the repository root on
2026-11-16 as a replacement for the built-in axe visual. It was copied unchanged to
this folder for the Godot import used by item 2 (Hatchet).

- Size: 22,962,372 bytes
- SHA-256: `a125796d9b9690a9d46f0eb6d1843287cd685e45e81e2f30c0c7da90db9481f4`
- Author/tool provenance: supplied by the project owner; the file records glTF
  Blender I/O v5.3.43, one static mesh, one material and three embedded 4K
  textures. It contains no skin, rig or animations.
- Runtime use: the static mesh is attached to the existing `Weapon_Axe` bone in
  `human_view.gd`, so the existing FP_Axe idle/walk/swing clips drive it. The
  world pickup `art/drops/2.res` is baked from the same held mesh at 35 cm, with
  its maps capped at 1K for the small drop.

Terms: no license statement or author metadata is embedded in the supplied file.
It is retained as an existing user-supplied asset and is not relicensed by this
repository's CC0/0BSD defaults. The new adapter, drop bake changes and test code
are original 0BSD work. A maintainer should record the asset's source terms in
the license inventory if it is admitted beyond this owner-provided replacement.