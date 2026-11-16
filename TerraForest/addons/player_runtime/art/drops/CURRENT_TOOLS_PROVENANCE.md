# Current pickaxe and hatchet drop meshes

`1.res` is a refreshed version of the existing pickaxe pickup asset, extracted
from the same Human R11 equipment currently used by held tools and inventory
icons. `2.res` now uses the project owner's supplied
`Hatchet_StraightHandle.glb` held mesh, attached to the existing Human R11
`Weapon_Axe` bone. This is maintenance of those existing representations, not an
independent license grant.

Source: `addons/characters/runtime/assets/Human.r11.glb`, SHA-256
`0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8`.
It is the user-supplied R11 repost recorded in
`addons/characters/Human_R11_Complete_Repost/README.txt`. The equipment materials
declare CC0-1.0 in their embedded glTF metadata. Retain the inherited character
notices and qualifications in `addons/characters/LICENSE.txt`,
`addons/characters/README.md` and inventory record GAP-002; this conversion does
not resolve the inherited provenance review or relicense third-party rights.

Hatchet source: `addons/characters/runtime/assets/Hatchet_StraightHandle.glb`,
SHA-256 `a125796d9b9690a9d46f0eb6d1843287cd685e45e81e2f30c0c7da90db9481f4`.
See the asset's `Hatchet_StraightHandle.PROVENANCE.md`; it is user-supplied and
has no embedded license statement. The 35 cm drop caps its 4K maps at 1K; the
held equipment keeps the imported 4K maps.

Original AI-assisted bake code: `tools/tool_drop_bake.gd` and
`tools/bake_tool_drops.gd`, under 0BSD. `current_tool.gdshader` is original 0BSD
rendering code. Existing Godot is used as an external build tool. No external
model, texture, code snippet or image was imported for this correction.

Each asset preserves the current model's complete tool geometry, wood texture
and normal detail, with per-vertex base color, roughness and metallic properties
merged into one batchable surface. Player geometry, skinning and animation are
excluded. The existing 35 cm normalization and item/save identities are retained.
Exact input/output hashes and source triangle counts are recorded in
`current_tools.bake.json`. Launch/export preflight checks and rebuilds these
assets even when icon textures are already current.

Original-size follow-up, 2026-11-04: `authored_scale` and `authored_size` metadata
retain pre-normalization dimensions. The same preflight annotates existing
`3.res`, `4.res`, `5.res`, `6.res` without changing their geometry/materials:
hammer/shovel/torch dimensions come from their already-used `Hammer.glb`,
`Shovel.glb`, `Torch.glb` equipment scenes; assembly-tool dimensions come from the
existing `tool_view.gd` procedural preview. Exact source/import/output hashes are
in the receipt. These assets keep their existing source notices and terms. The
default-on original-size runtime option scales native instance transforms and
matching physics bounds; compact geometry remains available without duplicate
vertex buffers, per-item scene nodes or a save-format change.
