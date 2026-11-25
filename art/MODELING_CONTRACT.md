# Hand-Crafted Character Contract

Everything in this file is extracted from the code that actually runs, not from a
design doc. If a hand-made Blender character satisfies this list, it drops into
the game with no code changes.

Sources of truth, in order:

| What | Where |
|---|---|
| Gate 3b assertions | `character_test.gd` (`BONES`, `CLIPS`, `SLOTS`) |
| Engine bone use | `character_body_3d.gd` (`_attach_hitbox_to_skeleton`, `_update_spring_bone_jiggle`, `_setup_physical_ragdoll`) |
| Reference rig + palette | `tools/build_character.py` (`JOINTS`, `PAL`, `ANIMS`) |
| Export settings | `build_models.py` (`export_glb`), `art/export_handcrafted.py` |
| Cel shader | `character_body_3d.gd` (`_setup_materials`, `base_code`) |

## 1. Bones

Six names are **hard requirements** — the engine looks them up by string:

| Bone | Parent | Read by | If missing |
|---|---|---|---|
| `Root` | — | ragdoll root, movement | character sinks or slides |
| `Spine` | `Hips` (or `Root`) | ragdoll | no torso ragdoll |
| `Head` | `Neck` (or `Spine`) | SDF face basis, ragdoll | face shading sticks to one angle |
| `Arm_L` | `Chest` (or `Spine`) | ragdoll | arm drops out of the ragdoll list |
| `Arm_R` | `Chest` (or `Spine`) | **sword hitbox attachment** | the sword stops following the arm |
| `Veil_Back` | `Chest` (or `Spine`) | **cloak spring jiggle** | the cape goes rigid |

Reference rig from `tools/build_character.py`, T-pose, metres, feet on `y = 0`,
facing **-Z** (Godot forward):

```
Root ─ Hips ─┬─ Spine ─ Chest ─┬─ Neck ─ Head
             │                 ├─ Arm_L ─ Elbow_L ─ Hand_L
             │                 ├─ Arm_R ─ Elbow_R ─ Hand_R
             │                 └─ Veil_Back, Veil_L, Veil_R
             ├─ Hip_L ─ Knee_L ─ Foot_L
             └─ Hip_R ─ Knee_R ─ Foot_R
```

Extra bones are welcome and ignored. Renaming any of the six is not.

## 2. `Slot_` nodes — modular outfit switching

Five slots, each shipped as **separate mesh objects** named
`Slot_<Slot>_<STYLE>`, where `<STYLE>` is `HERO` or `VEIL`.
`apply_modular_clothing_slots()` hides everything except the active style.

| Slot prefix | Example node | Purpose |
|---|---|---|
| `Slot_HeadMask_` | `Slot_HeadMask_HERO` | mask / veil / anime face shell |
| `Slot_VeilCloak_` | `Slot_VeilCloak_HERO` | back cloak, spring-driven |
| `Slot_UpperGarb_` | `Slot_UpperGarb_HERO` | chest, shoulders, coat |
| `Slot_LowerSkirt_` | `Slot_LowerSkirt_HERO` | skirt, legs, greaves |
| `Slot_Weapon_` | `Slot_Weapon_HERO` | sword / rapier / halo |

Gate 3b accepts a slot if **either** suffix exists (`Slot_HeadMask_HERO` or
`Slot_HeadMask_VEIL`). Extra suffix nodes (e.g. `Slot_HeadMask_HERO_Brim`) are
fine — they are hidden with their parent prefix.

## 3. Animation clips

Five clips, exact lowercase names, on an `AnimationPlayer` (GLB animations
import as an `AnimationPlayer` automatically):

| Clip | Used for |
|---|---|
| `idle` | breathing loop, cloak sway |
| `slash_up` | rising cut |
| `slash_down` | overhead cut |
| `slash_side` | horizontal cut |
| `guard_sway` | block / parry stance |

Reference timing is 24 fps: `idle` 1→24, the three slashes 1→14, `guard_sway`
1→12. Any timing imports fine; the code cross-fades by name.

In Blender: either set the action on the armature or push it to an NLA track —
`art/export_handcrafted.py` accepts either, and refuses to export a build that is
missing one.

## 4. Triangle budgets (mobile)

The shipped characters are deliberately tiny — measured from the committed GLBs:

| Model | Triangles | Meshes | Nodes | Animations |
|---|---|---|---|---|
| `models/hero.glb` | 980 | 29 | 51 | 5 |
| `models/boss_veil.glb` | 940 | 27 | 49 | 5 |

Recommended ceiling for hand-crafted replacements, so the LOW tier still hits
45–60 fps on an Adreno 618:

| Asset | Budget |
|---|---|
| Hero body (all slots combined) | ≤ 6,000 tris |
| Boss body | ≤ 6,000 tris |
| Any single prop / weapon | ≤ 1,500 tris |
| Bones | ≤ 24 (every extra bone is per-vertex skin work) |

Spend the budget on silhouette, not on surface detail: the cel shader flattens
everything into 2–3 bands, so a 12k-tri hand 100% invisible.

## 5. `COLOR.rgba` vertex-paint cheat sheet

The cel shader reads one `COLOR` attribute per corner, named **`Col`**, type
`BYTE_COLOR`, domain `CORNER`. All four channels do something:

| Channel | Meaning | 0.0 | 0.5 | 1.0 |
|---|---|---|---|---|
| **R** | shadow threshold bias | permanent shadow | normal cel cut | permanent lit |
| **G** | outline weight | no outline (eyes, inner face) | — | full silhouette ink |
| **B** | specular / MatCap metallic mask | no toe spec (cloth, veil) | — | keeps spec (iron, gold, visor) |
| **A** | SDF face switch | normal cel shading | — | **> 0.5 enables the SDF anime face** |

Unpainted meshes default to `RGBA(0.5, 1.0, 0.0, 0.0)` — normal shadow, full
outline, no spec, no SDF face. `art/export_handcrafted.py` fills exactly that
default into a missing or still-untouched layer and leaves hand-painted layers
alone.

Reference values, straight from `tools/build_character.py`'s `PAL`:

| Material | R | G | B | A | Reads as |
|---|---|---|---|---|---|
| `ObsidianCloak` | 0.35 | 1.00 | 0.15 | 0.0 | deep black cloth, strong ink |
| `AshVestment` | 0.62 | 0.80 | 0.00 | 0.0 | matte ash grey |
| `TarnishedIron` | 0.50 | 1.00 | 1.00 | 0.0 | metal with a toe spec |
| `VoidFace` | 0.00 | 0.00 | 0.00 | 0.0 | unlit void, no outline |
| `CrimsonEye` | 1.00 | 0.00 | 0.00 | 0.0 | always lit accent, no ink |
| `GildedFiligree` | 0.50 | 0.35 | 1.00 | 0.0 | thin gold trim, metallic |
| `PorcelainLily` | 0.60 | 0.80 | 0.00 | 0.0 | bright porcelain |
| `CathedralVeil` | 0.70 | 0.20 | 0.00 | 0.0 | near-white, barely inked |
| `AnimeFaceSkin` | 0.50 | 0.00 | 0.00 | **1.0** | SDF-shaded face |

Notes:

- **A > 0.5 needs UVs.** The SDF path samples the face texture with the mesh's
  `UV`, mirrored by head yaw. No UVs = a smeared face.
- **G = 0** is what keeps eyes and inner-mouth rims from growing an outline.
- The R channel only bites once Tab 8's **Vertex Shadow Bias** is above 0; the
  shipped look deliberately keeps it at 0.

## 6. Workflow

```bash
# 1. Model in Blender 5.2 LTS. Save the source in art/, never in models/.
#    art/.gdignore stops Godot from importing .blend files.

# 2. Validate the contract without exporting (fast, safe):
blender --background art/hero_handcrafted.blend \
    --python art/export_handcrafted.py -- --check-only

# 3. Export with proxy-smoothed normals:
blender --background art/hero_handcrafted.blend \
    --python art/export_handcrafted.py -- \
    --out models/hero_handcrafted.glb --smooth-normals --name HERO

# 4. Re-import and check the gate:
GODOT_BIN=/path/to/Godot bash verify.sh
```

The exporter prints a per-item checklist (`ok` / `MISS`) before it writes
anything, and **refuses to export** when a required bone, slot or clip is
missing. `--allow-missing` overrides that for work-in-progress meshes.

## 7. Hard rules

- No `.blend` file inside `models/` — `verify.sh` gate 2b fails the build.
- `art/.gdignore` must exist — also gate 2b.
- One armature per character; Godot expects a single `Skeleton3D`.
- The `.glb` must be self-contained (no external textures) — mobile builds ship
  only what is in the export filter.
- Material names are matched **case-insensitively** against the palette above;
  an unmatched material falls back to plain cel shading.
