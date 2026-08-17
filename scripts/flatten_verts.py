#!/usr/bin/env python3
"""
Flatten a part's full reference tree to raw vertices (no BFC handling —
positions only), then optionally search for cylinder-like vertex rings.

Usage:
    python scripts/flatten_verts.py 15118                 # bbox summary
    python scripts/flatten_verts.py 15118 --rings X 4     # r4 rings about X-parallel axes
    python scripts/flatten_verts.py 15118 --rings Y 2.5

Ring search reports clusters of vertices equidistant (within tolerance)
from a candidate axis, grid-searching the two perpendicular coordinates.
"""

import math
import os
import sys

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ldraw")


def find(name):
    name = name.lower().replace("\\", "/").split("/")[-1]
    for sub in ("p", "parts", os.path.join("parts", "s"), os.path.join("p", "48")):
        p = os.path.join(BASE, sub, name)
        if os.path.exists(p):
            return p
    return None


def mat_mul(m, v):
    return (
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2] + m[9],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2] + m[10],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2] + m[11],
    )


def compose(m, n):
    # m applied after n: rows of m times columns of n, translation folded in.
    a = [0.0] * 12
    for r in range(3):
        for c in range(3):
            a[r * 3 + c] = sum(m[r * 3 + k] * n[k * 3 + c] for k in range(3))
        a[9 + r] = sum(m[r * 3 + k] * n[9 + k] for k in range(3)) + m[9 + r]
    return a


IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]


def flatten(name, transform=None, depth=0, out=None):
    if out is None:
        out = []
    if depth > 20:
        return out
    if transform is None:
        transform = IDENT
    path = find(name)
    if path is None:
        return out
    for ln in open(path, encoding="utf-8", errors="replace"):
        t = ln.split()
        if not t:
            continue
        if t[0] == "1" and len(t) >= 15:
            nums = [float(x) for x in t[2:14]]
            sub = [
                nums[3], nums[4], nums[5],
                nums[6], nums[7], nums[8],
                nums[9], nums[10], nums[11],
                nums[0], nums[1], nums[2],
            ]
            flatten(" ".join(t[14:]), compose(transform, sub), depth + 1, out)
        elif t[0] in ("3", "4"):
            n = int(t[0])
            try:
                for i in range(n):
                    v = tuple(float(x) for x in t[2 + i * 3:5 + i * 3])
                    out.append(mat_mul(transform, v))
            except (ValueError, IndexError):
                pass
    return out


def main():
    part = sys.argv[1]
    if not part.endswith(".dat"):
        part += ".dat"
    verts = flatten(part)
    xs = sorted(v[0] for v in verts)
    ys = sorted(v[1] for v in verts)
    zs = sorted(v[2] for v in verts)
    print(f"{len(verts)} verts  bbox x {xs[0]:.1f}..{xs[-1]:.1f}  y {ys[0]:.1f}..{ys[-1]:.1f}  z {zs[0]:.1f}..{zs[-1]:.1f}")
    if len(sys.argv) > 3 and sys.argv[2] == "--rings":
        axis = sys.argv[3].upper()
        radius = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
        ai = "XYZ".index(axis)
        b1, b2 = [i for i in range(3) if i != ai]
        lo1, hi1 = min(v[b1] for v in verts), max(v[b1] for v in verts)
        lo2, hi2 = min(v[b2] for v in verts), max(v[b2] for v in verts)
        best = []
        step = 0.5
        c1 = lo1
        while c1 <= hi1:
            c2 = lo2
            while c2 <= hi2:
                ring = [v for v in verts if abs(math.hypot(v[b1] - c1, v[b2] - c2) - radius) < 0.25]
                if len(ring) >= 16:
                    spans = sorted(v[ai] for v in ring)
                    best.append((len(ring), c1, c2, spans[0], spans[-1]))
                c2 += step
            c1 += step
        best.sort(reverse=True)
        reported = []
        for count, c1, c2, s0, s1 in best:
            if any(abs(c1 - r[1]) < 2 and abs(c2 - r[2]) < 2 for r in reported):
                continue
            reported.append((count, c1, c2))
            print(f"r{radius} ring axis {axis}: {'xyz'[b1]}={c1:.1f} {'xyz'[b2]}={c2:.1f}  count {count}  {axis.lower()} span {s0:.1f}..{s1:.1f}")
            if len(reported) >= 8:
                break


if __name__ == "__main__":
    main()
