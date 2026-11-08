import bpy
import math
from mathutils import Euler

def make_mat(name, rgb, rough=0.8, metal=0.0, alpha=1.0, emit_rgb=None, emit_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = rough
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metal
        if alpha < 1.0 and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emit_rgb and emit_str > 0.0:
            for k in ["Emission Color", "Emission"]:
                if k in bsdf.inputs:
                    bsdf.inputs[k].default_value = (emit_rgb[0], emit_rgb[1], emit_rgb[2], 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat

def create_base_rig(rig_name):
    arm_data = bpy.data.armatures.new(rig_name + "Data")
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='EDIT')
    bones_spec = [
        ("Root", (0, 0, 0), (0, 0, 0.85), None),
        ("Spine", (0, 0, 0.85), (0, 0, 1.48), "Root"),
        ("Head", (0, 0, 1.48), (0, 0, 1.88), "Spine"),
        ("Arm_R", (-0.36, 0, 1.42), (-0.62, -0.25, 1.05), "Spine"),
        ("Arm_L", (0.36, 0, 1.42), (0.58, -0.20, 1.10), "Spine"),
    ]
    for b_name, head_p, tail_p, parent_name in bones_spec:
        b = arm_data.edit_bones.new(b_name)
        b.head = head_p
        b.tail = tail_p
        if parent_name:
            b.parent = arm_data.edit_bones[parent_name]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm_obj

def add_part(parts_list, prim_fn, kwargs, loc, rot_deg, scale, mat, bone_name):
    prim_fn(**kwargs, location=loc, rotation=tuple(math.radians(a) for a in rot_deg))
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    parts_list.append(obj)

def bake_standard_combat_anims(arm_obj):
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    anims = {
        "idle": [
            (1, {"Root": (0,0,0), "Spine": (4,0,0), "Head": (-4,5,0), "Arm_R": (-18,0,-12), "Arm_L": (10,0,12)}),
            (12, {"Root": (0,0,0), "Spine": (8,0,0), "Head": (-8,-5,0), "Arm_R": (-12,0,-16), "Arm_L": (18,0,18)}),
            (24, {"Root": (0,0,0), "Spine": (4,0,0), "Head": (-4,5,0), "Arm_R": (-18,0,-12), "Arm_L": (10,0,12)}),
        ],
        "slash_up": [
            (1, {"Spine": (18,0,-18), "Head": (-10,0,10), "Arm_R": (55,0,-35), "Arm_L": (-20,0,25)}),
            (6, {"Spine": (-22,0,22), "Head": (12,0,-12), "Arm_R": (-115,0,25), "Arm_L": (35,0,-15)}),
            (14, {"Spine": (4,0,0), "Head": (-4,0,0), "Arm_R": (-18,0,-12), "Arm_L": (10,0,12)}),
        ],
        "slash_down": [
            (1, {"Spine": (-24,0,0), "Head": (15,0,0), "Arm_R": (-125,0,0), "Arm_L": (-45,0,0)}),
            (6, {"Spine": (32,0,0), "Head": (-18,0,0), "Arm_R": (78,0,0), "Arm_L": (40,0,0)}),
            (14, {"Spine": (4,0,0), "Head": (-4,0,0), "Arm_R": (-18,0,-12), "Arm_L": (10,0,12)}),
        ],
        "slash_side": [
            (1, {"Spine": (8,0,-35), "Head": (0,0,25), "Arm_R": (10,45,-75), "Arm_L": (-15,0,30)}),
            (6, {"Spine": (12,0,42), "Head": (0,0,-30), "Arm_R": (-35,-45,75), "Arm_L": (25,0,-20)}),
            (14, {"Spine": (4,0,0), "Head": (-4,0,0), "Arm_R": (-18,0,-12), "Arm_L": (10,0,12)}),
        ],
        "guard_sway": [
            (1, {"Spine": (10,15,-15), "Head": (-8,-10,10), "Arm_R": (-45,35,-55), "Arm_L": (-35,-25,45)}),
            (6, {"Spine": (10,-15,15), "Head": (-8,10,-10), "Arm_R": (-45,-25,-35), "Arm_L": (-35,25,25)}),
            (12, {"Spine": (10,15,-15), "Head": (-8,-10,10), "Arm_R": (-45,35,-55), "Arm_L": (-35,-25,45)}),
        ]
    }
    for name, keyframes in anims.items():
        act = bpy.data.actions.new(name=name)
        act.use_fake_user = True
        arm_obj.animation_data.action = act
        if hasattr(arm_obj.animation_data, "action_slot") and hasattr(act, "slots") and len(act.slots) > 0:
            arm_obj.animation_data.action_slot = act.slots[0]
        for pb in arm_obj.pose.bones:
            pb.rotation_mode = 'XYZ'
        for frame, pose_dict in keyframes:
            bpy.context.scene.frame_set(frame)
            for b_name, rot_deg in pose_dict.items():
                pb = arm_obj.pose.bones[b_name]
                pb.rotation_euler = Euler(tuple(math.radians(a) for a in rot_deg), 'XYZ')
                pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        try:
            track = arm_obj.animation_data.nla_tracks.new()
            track.name = name
            track.strips.new(name=name, start=1, action=act)
        except Exception:
            pass

# ==========================================
# 1. BUILD PLAYER HERO (models/hero.glb)
# ==========================================
bpy.ops.wm.read_factory_settings(use_empty=True)
mat_obsidian = make_mat("ObsidianCloak", (0.04, 0.04, 0.06), 0.9)
mat_void = make_mat("VoidFace", (0.005, 0.005, 0.01), 1.0)
mat_ash = make_mat("AshVestment", (0.88, 0.86, 0.82), 0.8)
mat_iron = make_mat("TarnishedIron", (0.14, 0.14, 0.18), 0.5, 0.6)
mat_eye = make_mat("CrimsonEye", (1.0, 0.15, 0.22), 0.2, 0.0, 1.0, (1.0, 0.15, 0.22), 4.5)

hero_rig = create_base_rig("HeroRig")
h_parts = []
add_part(h_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 12, "radius1": 0.58, "radius2": 0.28, "depth": 1.15}, (0, 0, 0.58), (0, 0, 0), (1.0, 0.78, 1.0), mat_obsidian, "Root")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (0, -0.22, 0.78), (0, 0, 0), (0.26, 0.08, 1.15), mat_ash, "Spine")
add_part(h_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 10, "radius1": 0.30, "radius2": 0.44, "depth": 0.68}, (0, 0, 1.20), (0, 0, 0), (1.0, 0.72, 1.0), mat_obsidian, "Spine")
add_part(h_parts, bpy.ops.mesh.primitive_uv_sphere_add, {"segments": 10, "ring_count": 8, "radius": 0.22}, (-0.40, 0, 1.42), (0, -20, 0), (1.1, 0.85, 0.75), mat_iron, "Spine")
add_part(h_parts, bpy.ops.mesh.primitive_uv_sphere_add, {"segments": 10, "ring_count": 8, "radius": 0.22}, (0.40, 0, 1.42), (0, 20, 0), (1.1, 0.85, 0.75), mat_iron, "Spine")
add_part(h_parts, bpy.ops.mesh.primitive_uv_sphere_add, {"segments": 12, "ring_count": 10, "radius": 0.19}, (0, 0, 1.66), (0, 0, 0), (0.92, 0.95, 1.08), mat_void, "Head")
add_part(h_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 10, "radius1": 0.28, "radius2": 0.04, "depth": 0.48}, (0, 0.04, 1.74), (-14, 0, 0), (1.0, 1.05, 1.0), mat_obsidian, "Head")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (-0.068, -0.175, 1.66), (0, 12, 0), (0.055, 0.02, 0.018), mat_eye, "Head")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (0.068, -0.175, 1.66), (0, -12, 0), (0.055, 0.02, 0.018), mat_eye, "Head")
add_part(h_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.24, "minor_radius": 0.022, "major_segments": 16, "minor_segments": 6}, (0, 0, 1.76), (8, 0, 0), (1.0, 1.0, 1.0), mat_iron, "Head")
for i in range(7):
    ang = math.radians(-90 + i * 30)
    add_part(h_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 4, "radius1": 0.025, "radius2": 0.002, "depth": 0.22}, (math.sin(ang) * 0.24, -math.cos(ang) * 0.24, 1.85), (0, 0, math.degrees(ang)), (1.0, 1.0, 1.0), mat_iron, "Head")
add_part(h_parts, bpy.ops.mesh.primitive_cylinder_add, {"vertices": 8, "radius": 0.085, "depth": 0.52}, (-0.48, -0.12, 1.22), (28, -28, 0), (1.0, 1.0, 1.0), mat_obsidian, "Arm_R")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (-0.62, -0.55, 1.45), (55, 0, 0), (0.06, 0.24, 2.25), mat_obsidian, "Arm_R")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (-0.62, -0.62, 1.48), (55, 0, 0), (0.03, 0.06, 2.28), mat_ash, "Arm_R")
add_part(h_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (-0.62, -0.22, 1.02), (55, 0, 0), (0.22, 0.56, 0.09), mat_iron, "Arm_R")
add_part(h_parts, bpy.ops.mesh.primitive_cylinder_add, {"vertices": 8, "radius": 0.08, "depth": 0.48}, (0.46, -0.10, 1.24), (24, 24, 0), (1.0, 1.0, 1.0), mat_obsidian, "Arm_L")
add_part(h_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.26, "minor_radius": 0.025, "major_segments": 16, "minor_segments": 6}, (0.62, -0.32, 1.18), (70, 0, 20), (1.0, 1.0, 1.0), mat_eye, "Arm_L")

bpy.ops.object.select_all(action='DESELECT')
for p in h_parts: p.select_set(True)
bpy.context.view_layer.objects.active = h_parts[0]
bpy.ops.object.join()
h_mesh = bpy.context.active_object
h_mesh.name = "SeinenHeroMesh"
h_mesh.parent = hero_rig
h_mod = h_mesh.modifiers.new(name="Armature", type='ARMATURE')
h_mod.object = hero_rig
bake_standard_combat_anims(hero_rig)
bpy.ops.export_scene.gltf(filepath="models/hero.glb", export_format='GLB', export_animations=True)

# ==========================================================
# 2. BUILD GILDED VEIL CATHEDRAL BOSS (models/boss_veil.glb)
# ==========================================================
bpy.ops.wm.read_factory_settings(use_empty=True)
mat_navy_silk = make_mat("MidnightVestment", (0.05, 0.07, 0.14), 0.75)
mat_void_neck = make_mat("VoidFace", (0.01, 0.01, 0.015), 1.0)
mat_gold_mask = make_mat("GildedFiligree", (0.95, 0.74, 0.22), 0.25, 0.9, 1.0, (0.85, 0.55, 0.10), 1.2)
mat_lace_veil = make_mat("CathedralVeil", (0.96, 0.93, 0.86), 0.65, 0.0, 0.85, (0.98, 0.90, 0.72), 0.45)
mat_lily_white = make_mat("PorcelainLily", (0.98, 0.97, 0.94), 0.4, 0.0, 1.0, (1.0, 0.95, 0.85), 0.6)

boss_rig = create_base_rig("BossVeilRig")
b_parts = []

# Flowing Cathedral Dress & Midnight Gown (Root & Spine)
add_part(b_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 16, "radius1": 0.68, "radius2": 0.24, "depth": 1.22}, (0, 0, 0.61), (0, 0, 0), (1.0, 0.82, 1.0), mat_navy_silk, "Root")
add_part(b_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 12, "radius1": 0.24, "radius2": 0.36, "depth": 0.62}, (0, 0, 1.18), (0, 0, 0), (0.95, 0.72, 1.0), mat_navy_silk, "Spine")

# Gold Filigree Chest & Collar Trim (Spine)
add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.24, "minor_radius": 0.025, "major_segments": 16, "minor_segments": 6}, (0, -0.02, 1.40), (18, 0, 0), (1.0, 0.8, 1.0), mat_gold_mask, "Spine")
add_part(b_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (0, -0.21, 1.12), (0, 0, 0), (0.12, 0.05, 0.55), mat_gold_mask, "Spine")

# White Ruffled Victorian Epaulettes / Shoulder Frills (Spine)
for side in [-1, 1]:
    add_part(b_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 12, "radius1": 0.28, "radius2": 0.12, "depth": 0.22}, (side * 0.38, 0, 1.38), (0, side * -32, 0), (1.1, 0.9, 1.0), mat_lily_white, "Spine")
    add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.22, "minor_radius": 0.018, "major_segments": 14, "minor_segments": 6}, (side * 0.36, 0, 1.44), (0, side * -28, 0), (1.0, 0.85, 1.0), mat_gold_mask, "Spine")

# Dark Inner Head & High Collar (Head)
add_part(b_parts, bpy.ops.mesh.primitive_uv_sphere_add, {"segments": 12, "ring_count": 10, "radius": 0.175}, (0, 0, 1.66), (0, 0, 0), (0.90, 0.92, 1.1), mat_void_neck, "Head")

# Curved Ornate Gold Filigree Faceless Mask Plate (Head)
add_part(b_parts, bpy.ops.mesh.primitive_cylinder_add, {"vertices": 12, "radius": 0.19, "depth": 0.36}, (0, -0.08, 1.67), (8, 0, 0), (0.86, 0.52, 1.05), mat_gold_mask, "Head")
# Etched Filigree Relief Ribs on Mask
for r_z in [1.56, 1.64, 1.72, 1.79]:
    add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.165, "minor_radius": 0.014, "major_segments": 12, "minor_segments": 6}, (0, -0.09, r_z), (10, 0, 0), (0.88, 0.55, 1.0), mat_gold_mask, "Head")
# Central Vertical Gold Crest on Mask
add_part(b_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (0, -0.185, 1.67), (8, 0, 0), (0.025, 0.04, 0.39), mat_gold_mask, "Head")

# White Porcelain Lilies & Floral Cluster on Left Temple + Dangling Earring (Head)
for f_pos in [(0.17, -0.10, 1.76), (0.19, -0.05, 1.70), (0.16, -0.12, 1.64), (0.14, -0.14, 1.54)]:
    add_part(b_parts, bpy.ops.mesh.primitive_ico_sphere_add, {"subdivisions": 1, "radius": 0.048}, f_pos, (15, 25, 10), (1.2, 0.6, 1.2), mat_lily_white, "Head")

# Translucent White Lace Bridal/Cathedral Veil Draping Back & Over Shoulders (Head)
add_part(b_parts, bpy.ops.mesh.primitive_cone_add, {"vertices": 14, "radius1": 0.56, "radius2": 0.22, "depth": 0.95}, (0, 0.12, 1.48), (-18, 0, 0), (1.05, 0.95, 1.0), mat_lace_veil, "Head")
add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.23, "minor_radius": 0.025, "major_segments": 16, "minor_segments": 6}, (0, -0.02, 1.82), (25, 0, 0), (0.95, 1.05, 1.0), mat_lace_veil, "Head")

# Right Arm & Ornate Golden Ritual Rapier / Scimitar (Arm_R)
add_part(b_parts, bpy.ops.mesh.primitive_cylinder_add, {"vertices": 8, "radius": 0.07, "depth": 0.50}, (-0.46, -0.12, 1.22), (28, -24, 0), (1.0, 1.0, 1.0), mat_navy_silk, "Arm_R")
add_part(b_parts, bpy.ops.mesh.primitive_cube_add, {"size": 1.0}, (-0.60, -0.58, 1.46), (55, 0, 0), (0.035, 0.12, 2.35), mat_gold_mask, "Arm_R")
add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.18, "minor_radius": 0.025, "major_segments": 14, "minor_segments": 6}, (-0.60, -0.22, 1.02), (35, 90, 0), (1.0, 1.0, 1.0), mat_gold_mask, "Arm_R")

# Left Arm & Floating Golden Cathedral Halo (Arm_L)
add_part(b_parts, bpy.ops.mesh.primitive_cylinder_add, {"vertices": 8, "radius": 0.07, "depth": 0.48}, (0.44, -0.10, 1.24), (24, 24, 0), (1.0, 1.0, 1.0), mat_navy_silk, "Arm_L")
add_part(b_parts, bpy.ops.mesh.primitive_torus_add, {"major_radius": 0.30, "minor_radius": 0.022, "major_segments": 20, "minor_segments": 6}, (0.60, -0.32, 1.20), (70, 0, 20), (1.0, 1.0, 1.0), mat_gold_mask, "Arm_L")

bpy.ops.object.select_all(action='DESELECT')
for p in b_parts: p.select_set(True)
bpy.context.view_layer.objects.active = b_parts[0]
bpy.ops.object.join()
b_mesh = bpy.context.active_object
b_mesh.name = "BossVeilMesh"
b_mesh.parent = boss_rig
b_mod = b_mesh.modifiers.new(name="Armature", type='ARMATURE')
b_mod.object = boss_rig
bake_standard_combat_anims(boss_rig)
bpy.ops.export_scene.gltf(filepath="models/boss_veil.glb", export_format='GLB', export_animations=True)
print("BOTH_MODELS_EXPORTED_SUCCESSFULLY")
