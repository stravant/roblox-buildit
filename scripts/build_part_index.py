#!/usr/bin/env python3
"""
Builds part_index.tsv: one row per ldraw/parts/*.dat with the metadata
needed for fast curation lookups (grep the TSV instead of scanning 22k
part files).

Columns (tab-separated):
    id | org | description | moved_to | keywords | refs | size_x,y,z

- org: !LDRAW_ORG type (Part, Shortcut, Alias, Moved, ...)
- moved_to: target for "~Moved to X" parts
- keywords: flattened !KEYWORDS lines (includes BrickLink alternate ids)
- refs: unique referenced file basenames (subparts + primitives), so
  "which parts use primitive X" is a grep
- size: approximate bbox from top-level face vertices and ref origins

Usage:
    python scripts/build_part_index.py
Then e.g.:
    grep -i "shutter"  part_index.tsv
    grep "bump5000"    part_index.tsv     (parts using a primitive)
    grep -i "x547"     part_index.tsv     (BrickLink alternate ids)
"""

import os
import re

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ldraw", "parts")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "part_index.tsv")


def scan_part(path):
    desc = ""
    org = ""
    moved_to = ""
    keywords = []
    refs = set()
    mn = [1e9] * 3
    mx = [-1e9] * 3
    first = True
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                t = ln.split()
                if not t:
                    continue
                if t[0] == "0":
                    if first and len(t) > 1 and not t[1].startswith("!"):
                        desc = ln.strip()[2:].strip()
                    elif len(t) > 2 and t[1] == "!LDRAW_ORG":
                        org = t[2]
                    elif len(t) > 1 and t[1] == "!KEYWORDS":
                        keywords.append(" ".join(t[2:]))
                elif t[0] == "1" and len(t) >= 15:
                    name = " ".join(t[14:]).lower().replace("\\", "/").split("/")[-1]
                    refs.add(name)
                    try:
                        p = [float(t[2]), float(t[3]), float(t[4])]
                        for j in range(3):
                            mn[j] = min(mn[j], p[j])
                            mx[j] = max(mx[j], p[j])
                    except ValueError:
                        pass
                elif t[0] in ("3", "4"):
                    n = int(t[0])
                    try:
                        for i in range(n):
                            p = [float(t[2 + i * 3]), float(t[3 + i * 3]), float(t[4 + i * 3])]
                            for j in range(3):
                                mn[j] = min(mn[j], p[j])
                                mx[j] = max(mx[j], p[j])
                    except (ValueError, IndexError):
                        pass
                first = False
    except OSError:
        return None
    m = re.match(r"~?Moved to (\S+)", desc)
    if m:
        moved_to = m.group(1)
    size = ""
    if mx[0] > mn[0] - 1:
        size = ",".join(str(round(mx[j] - mn[j])) for j in range(3))
    return desc, org, moved_to, " ".join(keywords), " ".join(sorted(refs)), size


def main():
    rows = []
    for name in sorted(os.listdir(BASE)):
        if not name.endswith(".dat"):
            continue
        result = scan_part(os.path.join(BASE, name))
        if result is None:
            continue
        desc, org, moved_to, keywords, refs, size = result
        rows.append("\t".join([name[:-4], org, desc, moved_to, keywords, refs, size]))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# id\torg\tdescription\tmoved_to\tkeywords\trefs\tsize_xyz\n")
        f.write("\n".join(rows) + "\n")
    print(f"wrote {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
