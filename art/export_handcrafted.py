#!/usr/bin/env python3
"""Hand-crafted Blender source -> game-ready GLB for Sasti Sparkling Zero.

Runs INSIDE Blender 5.2 LTS, never with plain python3:

    blender --background art/hero_handcrafted.blend \
        --python art/export_handcrafted.py -- --out models/hero.glb

Arguments after the "--":

    --out PATH          output .glb (default: models/<blend name>.glb)
    --check-only        validate the contract, print the checklist, export nothing
    --smooth-normals    run proxy_smooth_normals() before export
    --allow-missing     export even when the checklist has failures (default: refuse)
    --name NAME         override the character style suffix (HERO / VEIL)

The checklist mirrors verify.sh gate 3b (character_test.gd) exactly. If this
script passes, the GLB drops into the game without a "the sword stopped
following the arm" bug hunt. The authoritative contract lives in
art/MODELING_CONTRACT.md - keep both in sync with character_test.gd.

Never write a .blend into models/: Godot imports it as a mesh and the mobile
build ships garbage. art/.gdignore keeps the sources out of the import scan.
"""

import argparse
import os
import sys

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
#  Contract - these four lists are copied from character_test.gd / the engine.
# ---------------------------------------------------------------------------
REQUIRED_BONES = ["Root", "Spine", "Head", "Arm_L", "Arm_R", "Veil_Back"]
REQUIRED_SLOT_PREFIXES = [
    "Slot_HeadMask_",
    "Slot_VeilCloak_",
    "Slot_UpperGarb_",
    "Slot_LowerSkirt_",
    "Slot_Weapon_",
]
REQUIRED_CLIPS = ["idle", "slash_up", "slash_down", "slash_side", "guard_sway"]

# Safe neutral for an unpainted mesh: normal shadow bias, full outline weight,
# no toe specular, no SDF face. Matches paint_vertex_channels()'s default.
NEUTRAL_COLOR = (0.5, 1.0, 0.0, 0.0)


# ---------------------------------------------------------------------------
#  Scene queries
# ---------------------------------------------------------------------------
def armatures():
    return [o for o in bpy.data.objects if o.type == 'ARMATURE']


def bone_names():
    names = set()
    for arm in armatures():
        for b in arm.data.bones:
            names.add(b.name)
    return names


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == 'MESH']


def object_names():
    return set(o.name for o in bpy.data.objects)


def clip_names():
    names = set(a.name for a in bpy.data.actions)
    for o in bpy.data.objects:
        ad = o.animation_data
        if not ad:
            continue
        if ad.action:
            names.add(ad.action.name)
        for track in ad.nla_tracks:
            names.add(track.name)
            for strip in track.strips:
                if strip.action:
                    names.add(strip.action.name)
                names.add(strip.name)
    return names


# ---------------------------------------------------------------------------
#  Contract checklist
# ---------------------------------------------------------------------------
class Checklist:
    def __init__(self):
        self.failures = 0

    def section(self, title):
        print("[contract] %s" % title)

    def ok(self, label):
        print("  ok    %s" % label)

    def missing(self, label, hint=""):
        self.failures += 1
        print("  MISS  %s%s" % (label, ("  <- " + hint) if hint else ""))

    def finish(self):
        print("[contract] %d problem(s)" % self.failures)
        return self.failures == 0


def validate(check, style):
    bones = bone_names()
    check.section("bones (%d required)" % len(REQUIRED_BONES))
    if not armatures():
        check.missing("an Armature object", "character_body_3d.gd needs a Skeleton3D")
    for name in REQUIRED_BONES:
        if name in bones:
            check.ok(name)
        else:
            hint = "Arm_R drives the sword hitbox, Veil_Back the cloak spring"
            check.missing(name, hint if name in ("Arm_R", "Veil_Back") else "")

    check.section("Slot_ nodes (style suffix %s)" % style)
    names = object_names()
    for prefix in REQUIRED_SLOT_PREFIXES:
        wanted = prefix + style
        if wanted in names:
            check.ok(wanted)
        else:
            near = sorted(n for n in names if n.startswith(prefix))
            check.missing(wanted, ("found " + ", ".join(near)) if near else "no node with this prefix")

    check.section("animation clips")
    clips = clip_names()
    for clip in REQUIRED_CLIPS:
        if clip in clips:
            check.ok(clip)
        else:
            check.missing(clip, "export the action or push it to an NLA track")

    check.section("meshes")
    meshes = mesh_objects()
    if not meshes:
        check.missing("at least one mesh object")
    for obj in meshes:
        if obj.data and len(obj.data.loops) > 0:
            check.ok("%s (%d verts)" % (obj.name, len(obj.data.vertices)))
        else:
            check.missing("%s has no geometry" % obj.name)

    check.section("export hygiene")
    if os.path.basename(bpy.data.filepath).endswith(".blend") and "models" in bpy.data.filepath.replace("\\", "/").split("/"):
        check.missing("the .blend lives inside models/", "move it to art/")
    else:
        check.ok("source .blend is outside models/")
    if len(armatures()) == 1:
        check.ok("exactly one armature")
    else:
        check.missing("%d armatures" % len(armatures()), "Godot expects one Skeleton3D per character")
    return check.finish()


# ---------------------------------------------------------------------------
#  Vertex colours:  R shadow bias / G outline / B spec mask / A SDF face
# ---------------------------------------------------------------------------
def color_layer(obj):
    me = obj.data
    if hasattr(me, "color_attributes"):
        return me.color_attributes.get("Col")
    if hasattr(me, "vertex_colors"):
        return me.vertex_colors.get("Col")
    return None


def is_neutral(layer):
    for d in layer.data:
        c = d.color
        if (abs(c[0] - NEUTRAL_COLOR[0]) > 1e-3 or abs(c[1] - NEUTRAL_COLOR[1]) > 1e-3
                or abs(c[2] - NEUTRAL_COLOR[2]) > 1e-3 or abs(c[3] - NEUTRAL_COLOR[3]) > 1e-3):
            return False
    return True


def ensure_vertex_colors(obj):
    """Create 'Col' if absent, else fill it only while it is still all-neutral.

    Returns 'created', 'filled', 'kept' (hand-painted) or 'skipped'.
    """
    me = obj.data
    if not me or not me.loops:
        return "skipped"
    layer = color_layer(obj)
    created = False
    if layer is None:
        if hasattr(me, "color_attributes"):
            layer = me.color_attributes.new(name="Col", type='BYTE_COLOR', domain='CORNER')
        else:
            layer = me.vertex_colors.new(name="Col")
        created = True
    if not created and not is_neutral(layer):
        return "kept"
    for d in layer.data:
        d.color = NEUTRAL_COLOR
    return "created" if created else "filled"


# ---------------------------------------------------------------------------
#  Proxy smooth normals (ported from build_models.py)
# ---------------------------------------------------------------------------
def proxy_cage_for(obj):
    return bpy.data.objects.get(obj.name + "_ProxyCage")


def proxy_smooth_normals(obj, radius_scale=1.35):
    """DATA_TRANSFER custom normals so a low-poly head/torso shades as one surface."""
    cage = proxy_cage_for(obj)
    made_cage = False
    try:
        if cage is None:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1.0)
            cage = bpy.context.active_object
            cage.name = obj.name + "_NormalProxy"
            dims = obj.dimensions
            cage.location = obj.matrix_world.translation + Vector((0.0, 0.0, float(dims.z) * 0.55))
            cage.scale = (dims.x * 0.75 * radius_scale,
                          dims.y * 0.75 * radius_scale,
                          dims.z * 0.62 * radius_scale)
            bpy.context.view_layer.objects.active = cage
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            made_cage = True

        mod = obj.modifiers.new(name="ProxyNormals", type='DATA_TRANSFER')
        mod.object = cage
        mod.use_loop_data = True
        mod.data_types_loops = {'CUSTOM_NORMAL'}
        mod.loop_mapping = 'NEAREST_POLYNOR'
        with bpy.context.temp_override(object=obj, active_object=obj,
                                       selected_objects=[obj],
                                       selected_editable_objects=[obj]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        print("  proxy normals transferred onto %s" % obj.name)
        return True
    except Exception as exc:
        print("  proxy normal transfer skipped on %s: %s" % (obj.name, exc))
        return False
    finally:
        if made_cage and cage is not None:
            bpy.data.objects.remove(cage, do_unlink=True)


# ---------------------------------------------------------------------------
#  Export (settings match build_models.py's export_glb)
# ---------------------------------------------------------------------------
def export_glb(path):
    base = dict(filepath=path, export_format='GLB', export_animations=True)
    for kwargs in (dict(base, export_vertex_color='ACTIVE'),
                   dict(base, export_vertex_color='MATERIAL'),
                   base):
        try:
            bpy.ops.export_scene.gltf(**kwargs)
            size = os.path.getsize(path) if os.path.exists(path) else 0
            print("EXPORTED: %s (%d bytes)" % (path, size))
            return True
        except TypeError:
            continue
        except Exception as exc:
            print("EXPORT FAILED: %s" % exc)
            return False
    print("EXPORT FAILED: no supported gltf exporter signature")
    return False


# ---------------------------------------------------------------------------
#  Entry point
# ---------------------------------------------------------------------------
def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser(prog="export_handcrafted.py")
    ap.add_argument("--out", default="")
    ap.add_argument("--check-only", action="store_true")
    ap.add_argument("--smooth-normals", action="store_true")
    ap.add_argument("--allow-missing", action="store_true")
    ap.add_argument("--name", default="HERO")
    return ap.parse_args(argv)


def main():
    args = parse_args()
    style = args.name.upper()
    out = args.out
    if not out:
        stem = os.path.splitext(os.path.basename(bpy.data.filepath))[0] or "handcrafted"
        out = os.path.join("models", stem + ".glb")

    print("=== hand-crafted export: %s -> %s ===" % (bpy.data.filepath or "<untitled>", out))
    check = Checklist()
    passed = validate(check, style)

    if not passed and not args.allow_missing:
        print("HANDCRAFTED_EXPORT_BLOCKED: fix the checklist above, or rerun with --allow-missing")
        return 1
    if args.check_only:
        print("HANDCRAFTED_CONTRACT_OK" if passed else "HANDCRAFTED_CONTRACT_FAIL")
        return 0 if passed else 1

    for obj in mesh_objects():
        status = ensure_vertex_colors(obj)
        print("  vertex colours on %s: %s" % (obj.name, status))
        if args.smooth_normals:
            proxy_smooth_normals(obj)

    out_dir = os.path.dirname(os.path.abspath(out))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    if not export_glb(out):
        return 1
    print("HANDCRAFTED_EXPORT_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
