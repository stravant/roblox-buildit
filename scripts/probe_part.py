#!/usr/bin/env python3
"""Print the top-level subfile references of a part, grouped by primitive,
with placement origins and rotation rows. Usage:

    python scripts/probe_part.py 670 [name-filter]
"""

import os
import sys

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ldraw")


def find(name):
    for sub in ("parts", "p"):
        p = os.path.join(BASE, sub, name)
        if os.path.exists(p):
            return p
    raise SystemExit(f"not found: {name}")


def main():
    part = sys.argv[1]
    if not part.endswith(".dat"):
        part += ".dat"
    filt = sys.argv[2].lower() if len(sys.argv) > 2 else None
    refs = {}
    for ln in open(find(part), encoding="utf-8", errors="replace"):
        t = ln.split()
        if t and t[0] == "1" and len(t) >= 15:
            name = t[14].lower().replace("\\", "/").split("/")[-1]
            if filt and filt not in name:
                continue
            nums = [float(x) for x in t[2:14]]
            refs.setdefault(name, []).append(nums)
    for name, places in sorted(refs.items()):
        print(f"{name} x{len(places)}")
        for nums in places[:10]:
            o = tuple(round(v, 2) for v in nums[:3])
            r = tuple(round(v, 3) for v in nums[3:])
            print(f"   at {o}  rot {r}")
        if len(places) > 10:
            print(f"   ... {len(places) - 10} more")


if __name__ == "__main__":
    main()
