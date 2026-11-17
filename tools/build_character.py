#!/usr/bin/env python3
"""Sasti Sparkling Zero — character mesh generator (no Blender required).

Writes models/hero.glb and models/boss_veil.glb straight from Python: vertices,
normals, UVs, the 4-channel NPR vertex colours the cel shader reads, skin
weights, a bone hierarchy and five baked animations.

Why this exists: build_models.py needs a Blender install, and the cloud sandbox
cannot run one (no libXrender). This file is pure stdlib, so the models are
reproducible anywhere `python3 tools/build_character.py` runs — CI included.

Art direction (locked from the user's reference board): Dark Seinen Ink. Black
ink silhouette, ash-grey cloth, bone-white edge, one crimson accent. Every shape
is chosen to read as a silhouette at 60 m on a phone.

Engine contract this file must keep (see character_body_3d.gd):
  * joints named Root/Spine/Head/Arm_L/Arm_R/Veil_Back at minimum
      - Arm_R      -> _attach_hitbox_to_skeleton()
      - Veil_Back  -> _update_spring_bone_jiggle()
      - Spine/Head/Arm_R/Arm_L/Veil_Back -> _setup_physical_ragdoll()
  * mesh nodes named Slot_<Slot>_<STYLE> so apply_modular_clothing_slots() can
    hide everything except the active style (HERO / VEIL)
  * animations: idle, slash_up, slash_down, slash_side, guard_sway
  * material names matched by _apply_seinen_shader_to_glb()
"""

import json
import math
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")

# ---------------------------------------------------------------------------
#  Palette. Keys are matched case-insensitively against the GLB material name.
#  (r, g, b, a) is the albedo written into the material; the cel shader reads
#  R as shadow bias, G as outline weight, B as spec mask, A as anime-face flag.
# ---------------------------------------------------------------------------
PAL = {
    "obsidiancloak":   ((0.055, 0.055, 0.072, 1.0), (0.35, 1.00, 0.15, 0.0)),
    "ashvestment":     ((0.760, 0.740, 0.700, 1.0), (0.62, 0.80, 0.00, 0.0)),
    "tarnishediron":   ((0.140, 0.145, 0.170, 1.0), (0.50, 1.00, 1.00, 0.0)),
    "voidface":        ((0.010, 0.010, 0.016, 1.0), (0.00, 0.00, 0.00, 0.0)),
    "crimsoneye":      ((1.000, 0.090, 0.130, 1.0), (1.00, 0.00, 0.00, 0.0)),
    "gildedfiligree":  ((0.850, 0.680, 0.240, 1.0), (0.50, 0.35, 1.00, 0.0)),
    "porcelainlily":   ((0.900, 0.880, 0.845, 1.0), (0.60, 0.80, 0.00, 0.0)),
    "cathedralveil":   ((0.820, 0.800, 0.740, 0.86), (0.70, 0.20, 0.00, 0.0)),
}

# ---------------------------------------------------------------------------
#  Skeleton. Bind pose is a T-pose in metres, feet on y = 0, facing -Z (Godot).
# ---------------------------------------------------------------------------
JOINTS = [
    # name,        parent,        world position
    ("Root",       None,          (0.00, 0.00, 0.00)),
    ("Hips",       "Root",        (0.00, 0.98, 0.00)),
    ("Spine",      "Hips",        (0.00, 1.14, 0.00)),
    ("Chest",      "Spine",       (0.00, 1.40, 0.00)),
    ("Neck",       "Chest",       (0.00, 1.56, 0.00)),
    ("Head",       "Neck",        (0.00, 1.66, 0.00)),
    ("Arm_L",      "Chest",       (0.20, 1.48, 0.00)),
    ("Elbow_L",    "Arm_L",       (0.52, 1.48, 0.00)),
    ("Hand_L",     "Elbow_L",     (0.84, 1.48, 0.00)),
    ("Arm_R",      "Chest",       (-0.20, 1.48, 0.00)),
    ("Elbow_R",    "Arm_R",       (-0.52, 1.48, 0.00)),
    ("Hand_R",     "Elbow_R",     (-0.84, 1.48, 0.00)),
    ("Hip_L",      "Hips",        (0.11, 0.94, 0.00)),
    ("Knee_L",     "Hip_L",       (0.13, 0.52, 0.00)),
    ("Foot_L",     "Knee_L",      (0.13, 0.07, 0.00)),
    ("Hip_R",      "Hips",        (-0.11, 0.94, 0.00)),
    ("Knee_R",     "Hip_R",       (-0.13, 0.52, 0.00)),
    ("Foot_R",     "Knee_R",      (-0.13, 0.07, 0.00)),
    ("Veil_Back",  "Chest",       (0.00, 1.42, 0.10)),
    ("Veil_L",     "Chest",       (0.17, 1.42, 0.07)),
    ("Veil_R",     "Chest",       (-0.17, 1.42, 0.07)),
]
JIDX = {name: i for i, (name, _p, _w) in enumerate(JOINTS)}


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vlen(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def vnorm(a):
    n = vlen(a) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def basis_from(axis):
    """Two unit vectors perpendicular to `axis`.

    For a vertical axis u is +X and v is +Z, so `squash` flattens a torso
    front-to-back instead of shrinking shoulder width.
    """
    a = vnorm(axis)
    if abs(a[1]) > 0.9:
        u = (1.0, 0.0, 0.0)
        return u, vnorm(vcross(a, u))
    up = (0.0, 1.0, 0.0)
    u = vnorm(vcross(up, a))
    v = vnorm(vcross(a, u))
    return u, v


# ---------------------------------------------------------------------------
#  A tiny mesh accumulator. One Part == one primitive == one material.
# ---------------------------------------------------------------------------
class Part:
    def __init__(self, name, mat):
        self.name = name
        self.mat = mat
        self.pos = []
        self.nor = []
        self.uv = []
        self.weights = []   # list of ((joint, weight), ...) per vertex
        self.idx = []

    def vert(self, p, w, uv=(0.0, 0.0)):
        self.pos.append(p)
        self.nor.append([0.0, 0.0, 0.0])
        self.uv.append(uv)
        self.weights.append(w)
        return len(self.pos) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    def quad(self, a, b, c, d):
        self.idx += [a, b, c, a, c, d]

    def finish_normals(self):
        acc = [[0.0, 0.0, 0.0] for _ in self.pos]
        for i in range(0, len(self.idx), 3):
            a, b, c = self.idx[i], self.idx[i + 1], self.idx[i + 2]
            n = vcross(vsub(self.pos[b], self.pos[a]), vsub(self.pos[c], self.pos[a]))
            for v in (a, b, c):
                acc[v][0] += n[0]
                acc[v][1] += n[1]
                acc[v][2] += n[2]
        for i, n in enumerate(acc):
            self.nor[i] = vnorm(n) if vlen(n) > 1e-9 else (0.0, 1.0, 0.0)


def w1(joint):
    return ((JIDX[joint], 1.0),)


def w2(ja, jb, t):
    t = max(0.0, min(1.0, t))
    return ((JIDX[ja], 1.0 - t), (JIDX[jb], t))


def tube(part, p0, p1, r0, r1, wa, wb, seg=10, cap0=True, cap1=True, squash=1.0):
    """Tapered cylinder from p0 to p1. Squash flattens the cross-section."""
    axis = vsub(p1, p0)
    u, v = basis_from(axis)
    ring0, ring1 = [], []
    for i in range(seg):
        ang = 2.0 * math.pi * i / seg
        d = vadd(vmul(u, math.cos(ang)), vmul(v, math.sin(ang) * squash))
        ring0.append(part.vert(vadd(p0, vmul(d, r0)), wa))
        ring1.append(part.vert(vadd(p1, vmul(d, r1)), wb))
    for i in range(seg):
        n = (i + 1) % seg
        part.quad(ring0[i], ring0[n], ring1[n], ring1[i])
    if cap0:
        c = part.vert(p0, wa)
        for i in range(seg):
            part.tri(c, ring0[(i + 1) % seg], ring0[i])
    if cap1:
        c = part.vert(p1, wb)
        for i in range(seg):
            part.tri(c, ring1[i], ring1[(i + 1) % seg])
    return ring0, ring1


def box(part, center, size, w, rot_y=0.0):
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    ca, sa = math.cos(rot_y), math.sin(rot_y)
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                x, y, z = sx * hx, sy * hy, sz * hz
                pts.append((center[0] + x * ca - z * sa, center[1] + y, center[2] + x * sa + z * ca))
    # index order: (sx,sy,sz) -> 0..7
    def p(sx, sy, sz):
        return pts[(sx + 1) // 2 * 4 + (sy + 1) // 2 * 2 + (sz + 1) // 2]
    v = {k: part.vert(pt, w) for k, pt in zip(
        [(sx, sy, sz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], pts)}
    part.quad(v[(-1, -1, 1)], v[(1, -1, 1)], v[(1, 1, 1)], v[(-1, 1, 1)])    # +Z
    part.quad(v[(1, -1, -1)], v[(-1, -1, -1)], v[(-1, 1, -1)], v[(1, 1, -1)])  # -Z
    part.quad(v[(1, -1, 1)], v[(1, -1, -1)], v[(1, 1, -1)], v[(1, 1, 1)])    # +X
    part.quad(v[(-1, -1, -1)], v[(-1, -1, 1)], v[(-1, 1, 1)], v[(-1, 1, -1)])  # -X
    part.quad(v[(-1, 1, 1)], v[(1, 1, 1)], v[(1, 1, -1)], v[(-1, 1, -1)])    # +Y
    part.quad(v[(-1, -1, -1)], v[(1, -1, -1)], v[(1, -1, 1)], v[(-1, -1, 1)])  # -Y
    return v


def quad_face(part, p0, p1, p2, p3, w, uv_scale=1.0):
    """A single double-sided-looking quad (drawn twice, flipped) with real UVs."""
    a = part.vert(p0, w, (0.0, 0.0))
    b = part.vert(p1, w, (uv_scale, 0.0))
    c = part.vert(p2, w, (uv_scale, uv_scale))
    d = part.vert(p3, w, (0.0, uv_scale))
    part.quad(a, b, c, d)
    a2 = part.vert(p0, w, (0.0, 0.0))
    b2 = part.vert(p1, w, (uv_scale, 0.0))
    c2 = part.vert(p2, w, (uv_scale, uv_scale))
    d2 = part.vert(p3, w, (0.0, uv_scale))
    part.quad(d2, c2, b2, a2)


def ribbon(part, pts, half_widths, thickness, wa, wb, taper_tip=True):
    """A hanging cloth panel: a thin slab following a polyline of (x, y, z)."""
    top, bot = [], []
    for i, p in enumerate(pts):
        t = i / max(1, len(pts) - 1)
        # Width runs tangentially around the body; thickness runs outward along
        # the panel's own radius, so neighbouring panels never intersect.
        out = (p[0], 0.0, p[2])
        if vlen(out) < 1e-6:
            out = (0.0, 0.0, 1.0)
        out = vnorm(out)
        u = vcross((0.0, 1.0, 0.0), out)
        if vlen(u) < 1e-6:
            u = (1.0, 0.0, 0.0)
        u = vnorm(u)
        hw = half_widths[i]
        w = w2(wa, wb, t)
        d = vmul(out, thickness)
        top.append((part.vert(vadd(p, vmul(u, -hw)), w), part.vert(vadd(p, vmul(u, hw)), w)))
        bot.append((part.vert(vadd(vadd(p, vmul(u, -hw)), d), w),
                    part.vert(vadd(vadd(p, vmul(u, hw)), d), w)))
    for i in range(len(pts) - 1):
        part.quad(top[i][0], top[i][1], top[i + 1][1], top[i + 1][0])
        part.quad(bot[i + 1][0], bot[i + 1][1], bot[i][1], bot[i][0])
        part.quad(top[i][0], top[i + 1][0], bot[i + 1][0], bot[i][0])
        part.quad(bot[i][1], bot[i + 1][1], top[i + 1][1], top[i][1])
    if taper_tip:
        part.quad(top[-1][0], top[-1][1], bot[-1][1], bot[-1][0])


# ---------------------------------------------------------------------------
#  Body. Shared by both characters; the slots carry the identity.
# ---------------------------------------------------------------------------
def build_body(parts, style):
    cloak = "ObsidianCloak"
    ash = "AshVestment"
    iron = "TarnishedIron"
    dark = "VoidFace"

    # Torso: hips -> chest loft.
    tube(parts(cloak, "torso_lo"), (0, 0.92, 0), (0, 1.16, 0), 0.155, 0.170,
         w1("Hips"), w2("Hips", "Spine", 0.5), seg=12, squash=0.62)
    tube(parts(cloak, "torso_hi"), (0, 1.16, 0), (0, 1.46, 0), 0.170, 0.195,
         w2("Hips", "Spine", 0.5), w1("Chest"), seg=12, squash=0.62, cap0=False)
    tube(parts(cloak, "torso_neck"), (0, 1.46, 0), (0, 1.58, 0), 0.115, 0.075,
         w1("Chest"), w1("Neck"), seg=10, squash=0.85, cap0=False)

    # Shoulder yoke: flares out over the deltoids, which is what stops the
    # silhouette reading as a bell with no shoulders.
    tube(parts(ash, "yoke"), (0, 1.55, 0.0), (0, 1.395, 0.0), 0.135, 0.245,
         w1("Chest"), w1("Chest"), seg=12, squash=0.72, cap0=False, cap1=False)

    # Arms (bind = T-pose).
    for side, sx, arm, elb, hand in (
            ("L", 1.0, "Arm_L", "Elbow_L", "Hand_L"),
            ("R", -1.0, "Arm_R", "Elbow_R", "Hand_R")):
        tube(parts(iron, "upperarm_" + side), (sx * 0.20, 1.48, 0), (sx * 0.52, 1.48, 0),
             0.078, 0.062, w1(arm), w1(elb), seg=8)
        tube(parts(iron, "forearm_" + side), (sx * 0.52, 1.48, 0), (sx * 0.80, 1.48, 0),
             0.062, 0.046, w1(elb), w1(hand), seg=8)
        box(parts(dark, "hand_" + side), (sx * 0.865, 1.48, 0), (0.085, 0.10, 0.075), w1(hand))

    # Legs.
    for side, sx, hip, knee, foot in (
            ("L", 1.0, "Hip_L", "Knee_L", "Foot_L"),
            ("R", -1.0, "Hip_R", "Knee_R", "Foot_R")):
        tube(parts(cloak, "thigh_" + side), (sx * 0.11, 0.96, 0), (sx * 0.13, 0.52, 0),
             0.105, 0.080, w1(hip), w1(knee), seg=10)
        tube(parts(iron, "shin_" + side), (sx * 0.13, 0.52, 0), (sx * 0.13, 0.10, 0),
             0.080, 0.058, w1(knee), w1(foot), seg=10)
        box(parts(iron, "boot_" + side), (sx * 0.13, 0.055, -0.035), (0.15, 0.11, 0.30), w1(foot))

    # Head core: a faceless void, jaw slightly narrower than the cranium.
    tube(parts(dark, "skull"), (0, 1.60, 0.01), (0, 1.86, 0.005), 0.098, 0.092,
         w1("Head"), w1("Head"), seg=12, squash=0.90)
    box(parts(dark, "jaw"), (0.0, 1.635, -0.045), (0.115, 0.11, 0.10), w1("Head"))

    # The single crimson eye slit — the only saturated thing on the character.
    quad_face(parts("CrimsonEye", "eye_L"), (-0.045, 1.70, -0.093), (-0.012, 1.70, -0.093),
              (-0.012, 1.722, -0.093), (-0.045, 1.722, -0.093), w1("Head"), 1.0)
    quad_face(parts("CrimsonEye", "eye_R"), (0.012, 1.70, -0.093), (0.045, 1.70, -0.093),
              (0.045, 1.722, -0.093), (0.012, 1.722, -0.093), w1("Head"), 1.0)


# ---------------------------------------------------------------------------
#  Slots. Each returns a list of (material, Part).
# ---------------------------------------------------------------------------
def slot_head(style):
    if style == "HERO":
        p = Part("Slot_HeadMask_HERO", "ObsidianCloak")
        # Low hood with a crest swept BACK, not a wizard cone: the peak sits
        # behind the skull so the face stays in shadow from the front.
        tube(p, (0, 1.60, 0.015), (0, 1.83, 0.035), 0.128, 0.098, w1("Head"), w1("Head"),
             seg=12, squash=0.95, cap0=False)
        tube(p, (0, 1.80, 0.05), (0, 1.855, 0.235), 0.080, 0.012, w1("Head"), w1("Head"), seg=8)
        # Ragged brim, angled down over the eyes.
        box(p, (0.0, 1.712, -0.088), (0.200, 0.026, 0.095), w1("Head"))
        q = Part("Slot_HeadMask_HERO_Brim", "AshVestment")
        quad_face(q, (-0.125, 1.700, -0.140), (0.125, 1.700, -0.140),
                  (0.095, 1.730, -0.140), (-0.095, 1.730, -0.140), w1("Head"))
        return [(p.mat, p), (q.mat, q)]
    p = Part("Slot_HeadMask_VEIL", "GildedFiligree")
    for i in range(7):
        ang = math.radians(-66.0 + i * 22.0)
        base = (0.075 * math.sin(ang), 1.80, 0.075 * math.cos(ang) - 0.01)
        tip = (0.135 * math.sin(ang), 1.99 + 0.05 * math.cos(ang), 0.135 * math.cos(ang) - 0.02)
        tube(p, base, tip, 0.022, 0.003, w1("Head"), w1("Head"), seg=5)
    v = Part("Slot_HeadMask_VEIL_Dome", "CathedralVeil")
    tube(v, (0, 1.62, 0.03), (0, 1.90, -0.01), 0.125, 0.105, w1("Head"), w1("Head"),
         seg=12, squash=0.92, cap1=True)
    return [(p.mat, p), (v.mat, v)]


def slot_veil(style):
    if style == "HERO":
        p = Part("Slot_VeilCloak_HERO", "ObsidianCloak")
        # High collar first: it frames the head in silhouette.
        tube(p, (0, 1.46, 0.02), (0, 1.62, 0.06), 0.155, 0.195, w1("Chest"), w1("Chest"),
             seg=12, squash=0.80, cap0=False, cap1=False)
        # Six ragged panels, alternating length, so the hem is torn not cut.
        panels = [
            ("Veil_Back", [(0.00, 1.50, 0.13), (0.02, 1.10, 0.17), (0.03, 0.62, 0.20), (0.02, 0.26, 0.22)], 0.20),
            ("Veil_Back", [(-0.13, 1.48, 0.12), (-0.17, 1.06, 0.15), (-0.20, 0.56, 0.18), (-0.19, 0.36, 0.20)], 0.10),
            ("Veil_Back", [(0.14, 1.48, 0.11), (0.18, 1.02, 0.14), (0.21, 0.50, 0.17), (0.20, 0.30, 0.19)], 0.10),
            ("Veil_L", [(0.17, 1.46, 0.06), (0.24, 1.04, 0.08), (0.27, 0.60, 0.09), (0.25, 0.42, 0.10)], 0.12),
            ("Veil_R", [(-0.17, 1.46, 0.06), (-0.24, 1.04, 0.08), (-0.27, 0.58, 0.09), (-0.25, 0.46, 0.10)], 0.12),
        ]
        for j, pts, hw in panels:
            widths = [hw, hw * 1.25, hw * 1.45, hw * 1.30]
            ribbon(p, pts, widths, 0.020, "Chest", j)
        return [(p.mat, p)]
    p = Part("Slot_VeilCloak_VEIL", "CathedralVeil")
    # Long cathedral veil: three broad translucent panels.
    ribbon(p, [(0.00, 1.52, 0.14), (0.00, 1.10, 0.19), (0.00, 0.66, 0.22), (0.00, 0.30, 0.24)],
           [0.26, 0.32, 0.36, 0.30], 0.012, "Chest", "Veil_Back")
    ribbon(p, [(-0.16, 1.48, 0.12), (-0.26, 1.06, 0.15), (-0.32, 0.62, 0.17), (-0.30, 0.34, 0.18)],
           [0.14, 0.18, 0.20, 0.16], 0.012, "Chest", "Veil_Back")
    ribbon(p, [(0.16, 1.48, 0.12), (0.26, 1.06, 0.15), (0.32, 0.60, 0.17), (0.30, 0.38, 0.18)],
           [0.14, 0.18, 0.20, 0.16], 0.012, "Chest", "Veil_Back")
    return [(p.mat, p)]


def q_crimson_sash() -> Part:
    """The one saturated accent on the whole character: a crimson obi."""
    p = Part("Slot_UpperGarb_HERO_Sash", "CrimsonEye")
    box(p, (0.0, 1.02, -0.120), (0.215, 0.055, 0.030), w1("Hips"))
    box(p, (0.0, 1.02, 0.120), (0.215, 0.055, 0.030), w1("Hips"))
    return p


def slot_upper(style):
    if style == "HERO":
        p = Part("Slot_UpperGarb_HERO", "AshVestment")
        # Two narrow chest straps, not a sandwich board.
        for y in (1.32, 1.24):
            box(p, (0.0, y, -0.118), (0.235, 0.020, 0.018), w1("Chest"))
        # One shoulder guard, asymmetric on purpose (reads as a hand-me-down).
        box(p, (0.235, 1.495, 0.0), (0.15, 0.09, 0.19), w1("Arm_L"))
        # Front cloak edges: an open coat, so the crimson sash shows between
        # them. Dark, or they read as a white lab coat over a black robe.
        e = Part("Slot_UpperGarb_HERO_Coat", "ObsidianCloak")
        for sx in (-1.0, 1.0):
            ribbon(e, [(sx * 0.105, 1.46, -0.108), (sx * 0.115, 1.06, -0.128),
                       (sx * 0.125, 0.70, -0.138), (sx * 0.115, 0.40, -0.144)],
                   [0.055, 0.062, 0.058, 0.048], 0.012, "Chest", "Hips")
        q = q_crimson_sash()
        return [(p.mat, p), (q.mat, q), (e.mat, e)]
    p = Part("Slot_UpperGarb_VEIL", "GildedFiligree")
    box(p, (0.0, 1.26, -0.10), (0.30, 0.34, 0.05), w1("Chest"))
    box(p, (-0.24, 1.50, 0.0), (0.20, 0.12, 0.24), w1("Arm_R"))
    box(p, (0.24, 1.50, 0.0), (0.20, 0.12, 0.24), w1("Arm_L"))
    return [(p.mat, p)]


def slot_lower(style):
    if style == "HERO":
        p = Part("Slot_LowerSkirt_HERO", "ObsidianCloak")
        # Short hakama: hem above the knee so the wrapped shins read as legs.
        for side, sx, hip, knee in (("L", 1.0, "Hip_L", "Knee_L"), ("R", -1.0, "Hip_R", "Knee_R")):
            tube(p, (sx * 0.11, 0.98, 0.0), (sx * 0.155, 0.60, 0.01), 0.140, 0.195,
                 w1(hip), w1(knee), seg=10, cap0=False, cap1=False)
        return [(p.mat, p)]
    p = Part("Slot_LowerSkirt_VEIL", "PorcelainLily")
    for side, sx, hip, knee in (("L", 1.0, "Hip_L", "Knee_L"), ("R", -1.0, "Hip_R", "Knee_R")):
        tube(p, (sx * 0.11, 0.98, 0.0), (sx * 0.17, 0.40, 0.01), 0.150, 0.230,
             w1(hip), w1(knee), seg=12, cap0=False, cap1=False)
    return [(p.mat, p)]


def slot_weapon(style):
    # Built along the bind-pose forearm (-X) on purpose: the idle clip rotates
    # Arm_R ~+74 deg about Z, which swings the blade down to a low guard.
    if style == "HERO":
        p = Part("Slot_Weapon_HERO", "TarnishedIron")
        box(p, (-0.90, 1.48, 0.0), (0.20, 0.035, 0.035), w1("Hand_R"))       # grip
        box(p, (-1.02, 1.48, 0.0), (0.02, 0.13, 0.13), w1("Hand_R"))        # tsuba
        blade = Part("Slot_Weapon_HERO_Blade", "AshVestment")
        # 0.72 m: long enough to read as a katana at the low guard without the
        # tip dragging through the floor once Arm_R swings down 74 deg.
        tube(blade, (-1.03, 1.48, 0.0), (-1.75, 1.48, 0.0), 0.056, 0.034,
             w1("Hand_R"), w1("Hand_R"), seg=6, squash=0.24)
        return [(p.mat, p), (blade.mat, blade)]
    p = Part("Slot_Weapon_VEIL", "GildedFiligree")
    box(p, (-0.92, 1.48, 0.0), (0.26, 0.045, 0.045), w1("Hand_R"))
    box(p, (-1.06, 1.48, 0.0), (0.03, 0.20, 0.20), w1("Hand_R"))
    blade = Part("Slot_Weapon_VEIL_Blade", "GildedFiligree")
    tube(blade, (-1.08, 1.48, 0.0), (-1.98, 1.48, 0.0), 0.072, 0.046,
         w1("Hand_R"), w1("Hand_R"), seg=6, squash=0.26)
    return [(p.mat, p), (blade.mat, blade)]


# ---------------------------------------------------------------------------
#  Animations. Keys are joint names; values are (time, euler degrees XYZ).
#  The bind pose is a T-pose, so every clip starts by dropping the arms.
# ---------------------------------------------------------------------------
ARMS_DOWN = {
    "Arm_L": (0, 0, -74), "Arm_R": (0, 0, 74),
    "Elbow_L": (0, 0, -14), "Elbow_R": (0, 0, 14),
}


def merged(*dicts):
    out = {}
    for d in dicts:
        out.update(d)
    return out


ANIMS = {
    "idle": {
        "Spine": [(0.0, (3, 0, 0)), (1.0, (6, 0, 0)), (2.0, (3, 0, 0))],
        "Chest": [(0.0, (0, 0, 0)), (1.0, (2, 0, 0)), (2.0, (0, 0, 0))],
        "Head": [(0.0, (-2, 6, 0)), (1.0, (0, -6, 0)), (2.0, (-2, 6, 0))],
        "Arm_L": [(0.0, (0, 0, -72)), (1.0, (0, 0, -78)), (2.0, (0, 0, -72))],
        "Arm_R": [(0.0, (0, 0, 72)), (1.0, (0, 0, 78)), (2.0, (0, 0, 72))],
        "Elbow_L": [(0.0, (0, 0, -16)), (2.0, (0, 0, -16))],
        "Elbow_R": [(0.0, (0, 0, 16)), (2.0, (0, 0, 16))],
        "Veil_Back": [(0.0, (-4, 0, 0)), (1.0, (-9, 0, 0)), (2.0, (-4, 0, 0))],
        "Veil_L": [(0.0, (0, 0, 4)), (1.0, (0, 0, 8)), (2.0, (0, 0, 4))],
        "Veil_R": [(0.0, (0, 0, -4)), (1.0, (0, 0, -8)), (2.0, (0, 0, -4))],
    },
    "slash_up": {
        "Spine": [(0.0, (14, 0, -10)), (0.25, (-20, 0, 14)), (0.58, (3, 0, 0))],
        "Chest": [(0.0, (10, -14, 0)), (0.25, (-14, 10, 0)), (0.58, (0, 0, 0))],
        "Head": [(0.0, (-6, 0, 6)), (0.25, (8, 0, -6)), (0.58, (-2, 0, 0))],
        "Arm_R": [(0.0, (42, 0, 96)), (0.25, (-58, 0, 34)), (0.58, (0, 0, 74))],
        "Elbow_R": [(0.0, (0, 0, 34)), (0.25, (0, 0, 6)), (0.58, (0, 0, 16))],
        "Arm_L": [(0.0, (0, 0, -58)), (0.25, (0, 0, -96)), (0.58, (0, 0, -72))],
        "Veil_Back": [(0.0, (6, 0, 0)), (0.25, (-24, 0, 0)), (0.58, (-4, 0, 0))],
    },
    "slash_down": {
        "Spine": [(0.0, (-18, 0, 0)), (0.25, (26, 0, 0)), (0.58, (3, 0, 0))],
        "Chest": [(0.0, (-10, 8, 0)), (0.25, (16, -6, 0)), (0.58, (0, 0, 0))],
        "Head": [(0.0, (10, 0, 0)), (0.25, (-14, 0, 0)), (0.58, (-2, 0, 0))],
        "Arm_R": [(0.0, (-86, 0, 30)), (0.25, (52, 0, 84)), (0.58, (0, 0, 74))],
        "Elbow_R": [(0.0, (0, 0, 8)), (0.25, (0, 0, 26)), (0.58, (0, 0, 16))],
        "Arm_L": [(0.0, (0, 0, -94)), (0.25, (0, 0, -50)), (0.58, (0, 0, -72))],
        "Veil_Back": [(0.0, (-16, 0, 0)), (0.25, (14, 0, 0)), (0.58, (-4, 0, 0))],
    },
    "slash_side": {
        "Spine": [(0.0, (4, 0, -26)), (0.25, (6, 0, 28)), (0.58, (3, 0, 0))],
        "Chest": [(0.0, (0, -26, 0)), (0.25, (0, 24, 0)), (0.58, (0, 0, 0))],
        "Head": [(0.0, (0, 18, 0)), (0.25, (0, -20, 0)), (0.58, (-2, 0, 0))],
        "Arm_R": [(0.0, (10, 40, 108)), (0.25, (-16, -46, 46)), (0.58, (0, 0, 74))],
        "Elbow_R": [(0.0, (0, 0, 40)), (0.25, (0, 0, 10)), (0.58, (0, 0, 16))],
        "Arm_L": [(0.0, (0, 0, -86)), (0.25, (0, 0, -62)), (0.58, (0, 0, -72))],
        "Veil_Back": [(0.0, (-6, 0, 18)), (0.25, (-8, 0, -20)), (0.58, (-4, 0, 0))],
    },
    "guard_sway": {
        "Spine": [(0.0, (8, 12, -12)), (0.25, (8, -12, 12)), (0.5, (8, 12, -12))],
        "Chest": [(0.0, (4, 10, 0)), (0.25, (4, -10, 0)), (0.5, (4, 10, 0))],
        "Head": [(0.0, (-6, -8, 6)), (0.25, (-6, 8, -6)), (0.5, (-6, -8, 6))],
        "Arm_R": [(0.0, (-42, 24, 88)), (0.25, (-42, 6, 96)), (0.5, (-42, 24, 88))],
        "Elbow_R": [(0.0, (0, 0, 44)), (0.5, (0, 0, 44))],
        "Arm_L": [(0.0, (-30, -18, -64)), (0.25, (-30, -4, -72)), (0.5, (-30, -18, -64))],
        "Elbow_L": [(0.0, (0, 0, -40)), (0.5, (0, 0, -40))],
        "Veil_Back": [(0.0, (-6, 0, 10)), (0.25, (-6, 0, -10)), (0.5, (-6, 0, 10))],
    },
}


def euler_to_quat(deg):
    x, y, z = (math.radians(a) for a in deg)
    cx, sx = math.cos(x * 0.5), math.sin(x * 0.5)
    cy, sy = math.cos(y * 0.5), math.sin(y * 0.5)
    cz, sz = math.cos(z * 0.5), math.sin(z * 0.5)
    return (
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    )


# ---------------------------------------------------------------------------
#  glTF/GLB writer
# ---------------------------------------------------------------------------
class Glb:
    def __init__(self):
        self.blob = bytearray()
        self.views = []
        self.accessors = []

    def view(self, raw, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        off = len(self.blob)
        self.blob += raw
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.views.append(v)
        return len(self.views) - 1

    def accessor(self, raw, ctype, count, atype, target=None, minmax=None, normalized=False):
        vid = self.view(raw, target)
        a = {"bufferView": vid, "componentType": ctype, "count": count, "type": atype}
        if minmax:
            a["min"], a["max"] = minmax
        if normalized:
            a["normalized"] = True
        self.accessors.append(a)
        return len(self.accessors) - 1


FLOAT, USHORT, UINT = 5126, 5123, 5125


def build_glb(path, parts, style):
    g = Glb()
    materials = []
    mat_index = {}
    mesh_defs = []

    for mat_name, part in parts:
        part.finish_normals()
        key = mat_name
        if key not in mat_index:
            rgb, vcol = PAL[key.lower()]
            materials.append({
                "name": key,
                "pbrMetallicRoughness": {
                    "baseColorFactor": [rgb[0], rgb[1], rgb[2], rgb[3]],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.85,
                },
                "alphaMode": "BLEND" if rgb[3] < 1.0 else "OPAQUE",
                "doubleSided": False,
            })
            mat_index[key] = len(materials) - 1

        pos = [c for p in part.pos for c in p]
        nrm = [c for n in part.nor for c in n]
        uvs = [c for t in part.uv for c in t]
        col = []
        _rgb, rule = PAL[part.mat.lower()]
        for _ in part.pos:
            col += list(rule)
        joints = []
        weights = []
        for w in part.weights:
            js = [0, 0, 0, 0]
            ws = [0.0, 0.0, 0.0, 0.0]
            for i, (j, ww) in enumerate(w[:4]):
                js[i] = j
                ws[i] = ww
            total = sum(ws) or 1.0
            joints += js
            weights += [w / total for w in ws]
        idx = part.idx
        use32 = max(idx) > 65535
        idx_raw = b"".join(struct.pack("<I" if use32 else "<H", i) for i in idx)

        mins = [min(pos[i::3]) for i in range(3)]
        maxs = [max(pos[i::3]) for i in range(3)]
        prim = {
            "attributes": {
                "POSITION": g.accessor(b"".join(struct.pack("<3f", *p) for p in part.pos),
                                       FLOAT, len(part.pos), "VEC3", 34962, (mins, maxs)),
                "NORMAL": g.accessor(b"".join(struct.pack("<3f", *n) for n in part.nor),
                                     FLOAT, len(part.nor), "VEC3", 34962),
                "TEXCOORD_0": g.accessor(b"".join(struct.pack("<2f", *t) for t in part.uv),
                                         FLOAT, len(part.uv), "VEC2", 34962),
                "COLOR_0": g.accessor(b"".join(struct.pack("<4f", *c) for c in
                                               [col[i:i + 4] for i in range(0, len(col), 4)]),
                                      FLOAT, len(part.pos), "VEC4", 34962),
                "JOINTS_0": g.accessor(b"".join(struct.pack("<4H", *j) for j in
                                                [joints[i:i + 4] for i in range(0, len(joints), 4)]),
                                       USHORT, len(part.pos), "VEC4", 34962),
                "WEIGHTS_0": g.accessor(b"".join(struct.pack("<4f", *w) for w in
                                                 [weights[i:i + 4] for i in range(0, len(weights), 4)]),
                                        FLOAT, len(part.pos), "VEC4", 34962),
            },
            "indices": g.accessor(idx_raw, UINT if use32 else USHORT, len(idx), "SCALAR", 34963),
            "material": mat_index[key],
        }
        mesh_defs.append({"name": part.name, "primitives": [prim]})

    # Node graph: skeleton root with joints, then one mesh node per part.
    # JOINTS holds WORLD positions; glTF node translation is relative to parent.
    world = {name: pos for name, _p, pos in JOINTS}
    nodes = []
    joint_node = {}
    for name, parent, worldpos in JOINTS:
        local = worldpos if parent is None else vsub(worldpos, world[parent])
        joint_node[name] = len(nodes)
        nodes.append({"name": name, "translation": [round(c, 6) for c in local]})
    for name, parent, _l in JOINTS:
        if parent is not None:
            nodes[joint_node[parent]].setdefault("children", []).append(joint_node[name])

    ibm = []
    for name, _p, _w in JOINTS:
        wp = world[name]
        # column-major 4x4 identity with translation = -world position
        ibm += [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -wp[0], -wp[1], -wp[2], 1]
    ibm_acc = g.accessor(b"".join(struct.pack("<16f", *ibm[i:i + 16]) for i in range(0, len(ibm), 16)),
                         FLOAT, len(JOINTS), "MAT4")
    skin_idx = 0
    skins = [{
        "name": style + "Skin",
        "joints": [joint_node[n] for n, _p, _w in JOINTS],
        "inverseBindMatrices": ibm_acc,
        "skeleton": joint_node["Root"],
    }]

    mesh_nodes = []
    for part_i, part in enumerate(parts):
        mesh_nodes.append(len(nodes))
        nodes.append({"name": part[1].name, "mesh": part_i, "skin": skin_idx})

    root_children = [joint_node["Root"]] + mesh_nodes
    nodes.append({"name": style.title() + "Rig", "children": root_children})

    # Animations.
    animations = []
    for name, tracks in ANIMS.items():
        samplers = []
        channels = []
        for jname, keys in tracks.items():
            times = [k[0] for k in keys]
            quats = [euler_to_quat(k[1]) for k in keys]
            t_acc = g.accessor(b"".join(struct.pack("<f", t) for t in times), FLOAT, len(times), "SCALAR")
            # glTF quaternions are (x, y, z, w); our euler_to_quat already is.
            q_acc = g.accessor(b"".join(struct.pack("<4f", *q) for q in quats),
                               FLOAT, len(quats), "VEC4")
            samplers.append({"input": t_acc, "output": q_acc, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": joint_node[jname], "path": "rotation"}})
        animations.append({"name": name, "samplers": samplers, "channels": channels})

    doc = {
        "asset": {"version": "2.0", "generator": "sasti build_character.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": mesh_defs,
        "materials": materials,
        "skins": skins,
        "animations": animations,
        "accessors": g.accessors,
        "bufferViews": g.views,
        "buffers": [{"byteLength": len(g.blob)}],
    }

    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    bin_blob = bytes(g.blob)
    while len(bin_blob) % 4:
        bin_blob += b"\x00"
    total = 12 + 8 + len(js) + 8 + len(bin_blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bin_blob), 0x004E4942))
        f.write(bin_blob)
    kb = (len(js) + len(bin_blob)) / 1024.0
    print("wrote %s (%d parts, %d verts, %.0f KB)" % (
        path, len(parts), sum(len(p.pos) for _m, p in parts), kb))


def build(style, path):
    parts = []

    def factory(mat, name):
        part = Part(name, mat)
        parts.append((mat, part))
        return part

    build_body(factory, style)
    for slot in (slot_head, slot_veil, slot_upper, slot_lower, slot_weapon):
        for mat, part in slot(style):
            parts.append((mat, part))
    build_glb(path, parts, style)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build("HERO", os.path.join(OUT_DIR, "hero.glb"))
    build("VEIL", os.path.join(OUT_DIR, "boss_veil.glb"))


if __name__ == "__main__":
    main()
