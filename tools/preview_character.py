#!/usr/bin/env python3
"""Offline preview renderer for the generated character GLBs.

The cloud sandbox has no GPU, so Godot can only run headless here. This is a
tiny software rasterizer (numpy + zlib only) that reads a GLB, applies the skin
in a given animation pose and writes a PNG contact sheet, so proportions and
silhouette can be judged before anything is shipped.

    python3 tools/preview_character.py models/hero.glb refs/preview_hero.png
"""

import json
import math
import struct
import sys
import zlib

import numpy as np

TYPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPES = {5120: "<i1", 5121: "<u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}


def load_glb(path):
    data = open(path, "rb").read()
    assert struct.unpack("<I", data[:4])[0] == 0x46546C67, "not a GLB"
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blob = data[bin_start:]
    return doc, blob


def accessor(doc, blob, idx):
    a = doc["accessors"][idx]
    bv = doc["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    comps = TYPES[a["type"]]
    arr = np.frombuffer(blob, dtype=DTYPES[a["componentType"]],
                        count=a["count"] * comps, offset=off)
    return arr.reshape(a["count"], comps)


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0.0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0.0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ])


def local_matrix(node):
    t = node.get("translation", [0.0, 0.0, 0.0])
    m = np.eye(4)
    if "rotation" in node:
        m = quat_mat(node["rotation"])
    m[0, 3], m[1, 3], m[2, 3] = t
    return m


def sample_rotation(doc, blob, anim, node_idx, time):
    for ch in anim["channels"]:
        if ch["target"]["node"] != node_idx or ch["target"]["path"] != "rotation":
            continue
        s = anim["samplers"][ch["sampler"]]
        times = accessor(doc, blob, s["input"]).reshape(-1)
        quats = accessor(doc, blob, s["output"])
        if time <= times[0]:
            return quats[0]
        if time >= times[-1]:
            return quats[-1]
        for i in range(len(times) - 1):
            if times[i] <= time <= times[i + 1]:
                t = (time - times[i]) / max(1e-6, times[i + 1] - times[i])
                q0, q1 = quats[i], quats[i + 1]
                if float(np.dot(q0, q1)) < 0.0:
                    q1 = -q1
                q = q0 * (1 - t) + q1 * t
                return q / (np.linalg.norm(q) or 1.0)
    return None


def world_matrices(doc, blob, anim_name=None, time=0.0):
    nodes = doc["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    anim = None
    if anim_name:
        for a in doc.get("animations", []):
            if a["name"] == anim_name:
                anim = a
    local = []
    for i, n in enumerate(nodes):
        node = dict(n)
        if anim is not None:
            q = sample_rotation(doc, blob, anim, i, time)
            if q is not None:
                node["rotation"] = list(q)
        local.append(local_matrix(node))
    world = [None] * len(nodes)

    def resolve(i):
        if world[i] is not None:
            return world[i]
        m = local[i]
        if i in parent:
            m = resolve(parent[i]) @ m
        world[i] = m
        return m

    for i in range(len(nodes)):
        resolve(i)
    return world


def gather(doc, blob, anim_name, time):
    """Returns [(tris_world, color)], pos+normal per triangle corner."""
    world = world_matrices(doc, blob, anim_name, time)
    out = []
    for node in doc["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        skin = doc["skins"][node["skin"]]
        joints = skin["joints"]
        ibm = accessor(doc, blob, skin["inverseBindMatrices"]).astype(np.float64)
        skin_mats = []
        for j_i, j_node in enumerate(joints):
            m = world[j_node] @ ibm[j_i].reshape(4, 4).T
            skin_mats.append(m)
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            attrs = prim["attributes"]
            pos = accessor(doc, blob, attrs["POSITION"]).astype(np.float64)
            nrm = accessor(doc, blob, attrs["NORMAL"]).astype(np.float64)
            jt = accessor(doc, blob, attrs["JOINTS_0"]).astype(np.int32)
            wt = accessor(doc, blob, attrs["WEIGHTS_0"]).astype(np.float64)
            idx = accessor(doc, blob, prim["indices"]).reshape(-1).astype(np.int64)
            mats = np.zeros((len(pos), 4, 4))
            for k in range(4):
                for v in range(len(pos)):
                    mats[v] += wt[v, k] * skin_mats[jt[v, k]]
            ph = np.concatenate([pos, np.ones((len(pos), 1))], axis=1)
            sp = np.einsum("vij,vj->vi", mats, ph)[:, :3]
            sn = np.einsum("vij,vj->vi", mats[:, :3, :3], nrm)[:, :3]
            color = doc["materials"][prim["material"]]["pbrMetallicRoughness"]["baseColorFactor"]
            for i in range(0, len(idx), 3):
                a, b, c = idx[i], idx[i + 1], idx[i + 2]
                out.append((sp[[a, b, c]], sn[[a, b, c]], color))
    return out


def render(tris, size, yaw_deg, pitch_deg=0.0, scale=None):
    w, h = size
    img = np.zeros((h, w, 3), dtype=np.float32) + 0.055
    zbuf = np.full((h, w), 1e9, dtype=np.float64)
    cy_, sy_ = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    cp, sp = math.cos(math.radians(pitch_deg)), math.sin(math.radians(pitch_deg))
    ry = np.array([[cy_, 0, sy_], [0, 1, 0], [-sy_, 0, cy_]])
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    rot = rx @ ry
    allp = np.concatenate([t[0] for t in tris], axis=0) @ rot.T
    lo, hi = allp.min(axis=0), allp.max(axis=0)
    if scale is None:
        scale = min(w * 0.82 / max(1e-6, hi[0] - lo[0]), h * 0.90 / max(1e-6, hi[1] - lo[1]))
    cx = (lo[0] + hi[0]) * 0.5
    cyy = (lo[1] + hi[1]) * 0.5
    light = np.array([-0.35, 0.62, -0.70])
    light = light / np.linalg.norm(light)

    for pts, nrm, col in tris:
        p = pts @ rot.T
        n = nrm @ rot.T
        sx = (p[:, 0] - cx) * scale + w * 0.5
        sy = h * 0.5 - (p[:, 1] - cyy) * scale
        z = p[:, 2]
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(w - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(h - 1, math.ceil(sy.max())))
        if x1 < x0 or y1 < y0:
            continue
        den = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
        if abs(den) < 1e-9:
            continue
        xs = np.arange(x0, x1 + 1)
        ys = np.arange(y0, y1 + 1)
        gx, gy = np.meshgrid(xs + 0.5, ys + 0.5)
        l0 = ((sy[1] - sy[2]) * (gx - sx[2]) + (sx[2] - sx[1]) * (gy - sy[2])) / den
        l1 = ((sy[2] - sy[0]) * (gx - sx[2]) + (sx[0] - sx[2]) * (gy - sy[2])) / den
        l2 = 1.0 - l0 - l1
        mask = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        if not mask.any():
            continue
        zz = l0 * z[0] + l1 * z[1] + l2 * z[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        closer = mask & (zz < sub)
        if not closer.any():
            continue
        # Two-band cel ramp with a rim light, same idea as the in-game shader.
        fn = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        nlen = np.linalg.norm(fn)
        if nlen < 1e-9:
            continue
        fn /= nlen
        facing = abs(float(np.dot(fn @ rot.T, [0, 0, -1])))
        ndl = max(0.0, float(np.dot(fn, light))) * (1.0 if float(np.dot(fn, [0, 0, -1])) > 0 else 1.0)
        shade = 1.0 if ndl > 0.42 else 0.55
        rim = 0.30 if facing < 0.30 else 0.0
        rgb = np.array(col[:3]) * shade + rim
        region = img[y0:y1 + 1, x0:x1 + 1]
        region[closer] = rgb
        zbuf[y0:y1 + 1, x0:x1 + 1] = np.where(closer, zz, sub)
    return np.clip(img, 0, 1) ** (1 / 1.05)


def write_png(path, img):
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    hdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", hdr)
                           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main():
    glb = sys.argv[1] if len(sys.argv) > 1 else "models/hero.glb"
    out = sys.argv[2] if len(sys.argv) > 2 else "refs/preview.png"
    doc, blob = load_glb(glb)
    panes = []
    # yaw 0 = the character faces the camera (the model faces -Z).
    for anim, t, yaw, pitch in (("idle", 0.0, 0.0, 0.0), ("idle", 0.0, 38.0, 4.0),
                                ("slash_up", 0.25, 0.0, 0.0)):
        tris = gather(doc, blob, anim, t)
        panes.append(render(tris, (300, 520), yaw, pitch))
    sheet = np.concatenate(panes, axis=1)
    write_png(out, (sheet * 255).astype(np.uint8))
    print("wrote", out)


if __name__ == "__main__":
    main()
