# Connection Coverage Audit (1000 parts)

Method: `sets/audit_parts.txt` holds 1000 common parts (bare-numbered,
category-filtered, numerically sorted = classic era). The gated
`zzAudit.spec.lua` runs full detection over all of them (~70s) and logs
per-part connector counts; `zzAuditSheet.spec.lua` renders a marker-
annotated contact sheet for visual checks (screenshot via CaptureService
— currently failing environment-wide with multiple Studio instances
open; the sheet scene is left in the runtests place for direct viewing).
Re-run: create `sets/audit_enable.txt`, `python runtests.py zzAudit`,
delete the enable file.

## Fixed as a result of this audit

- **Tile/shell underside grips** (biggest win): cavity boxes now produce
  a GRID of pocket cells (up to 6 per axis, stud-pitched, depth <= 26),
  instead of only 1x1 pockets. Tiles (3069b, 3070a...), hinge bases, and
  every plate/brick interior shell now derive underside sockets; shell
  cells dedup against tube-derived sockets. 196/1000 parts now carry
  pocket cells; 419/1000 derive sockets.
- **Hinge & turntable composites**: 3937c01 (Hinge 1x2, horizontal axis,
  approximate knuckle position), 652c01 (Hinge Brick 1x8: male + female
  + joining ring, vertical axis), 3680c01/c02 (Turntable 2x2), 3403c01
  (Turntable 4x4). Segment ids redirect to the assemblies.
- **Clip variants**: clip9 (thin C-clip, 4085a) joins the vertical clip
  family; clip12 (free-standing thick C-clip, 4081a/3628) grips at its
  origin. 2555's hand-built clip is a partOverride. A Clip's own inner
  r4 arc no longer doubles as a phantom BarHole (coaxial suppression).
- **Classic towball sockets**: 3183a/b/c curated (ball center measured
  from the rect wall pair at (+-9.8, 4, -18)).

## Remaining buckets (in rough priority order)

| Bucket | Count | Notes / recommendation |
|---|---|---|
| Minifig articulation | ~124 | PARTLY DONE: torso neck Stud, head Pocket/top stud, hand C-grip (cylo bore), hips+legs two-joint composite, hats via tubes, stud-in-pinhole "mouth" mate rule. Remaining: arms (wrist sockets, shoulder joints — torso+arm assemblies are print-variant-heavy), integral-arm figures (15/17), Friends figures. |
| Doors/windows/shutters | ~25 of zero-bucket | IN PROGRESS: HingePin/HingeSocket pair added. Done: bump5000 nubs auto-detect as HingePin, correct span (791, 2657, 3853 tabs); female hole subparts 42205s01 (frames 42205/51239/6798 + cupboard 2656 top) and 2656s01 (cupboard bottom) keyed as oneSided HingeSockets; door 671 rod + frame 670 sockets curated; shutter 3856 hook recesses curated. Also done: 3644+30179 (classic 1x4x6 rod/bores), 60623+60596 (newer 1x4x6 short pins), 2042+2043 cupboard (side-rail bump/well stacks, mixed polarity). Remaining: 791's mating frame (old 1x3x5 window — hand-built holes?), 821a Mursten garage door = SLIDING channel (new joint class, skipped), 4071/4130 2-wide door frames, 2400/24054 curved doors, Fabuland shutter 2049's frames. |
| Finger hinges on arms/brackets | ~10 | 412/795 "Arm Piece with N Fingers", exo-force style. Finger knuckles are hand-built; per-family overrides or a finger-stack composite concept. |
| Tyres/wheels | ~15 | Tyre<->rim interface is its own system (Tyre/Rim pair); wheels' axle/pin holes mostly already detect. |
| Ladders/rails/misc | rest | 420/421 ladder clutch, train drive rods (crank pins = Bar candidates), magnet holders (Magnet pair?), roadsign fingers. Case-by-case. |
| ~~2855/2856 turntable~~ | done | Virtual assembly support added to compositeParts (inline segment list + transforms); 2855c imports as a two-segment composite. |
| ~~3491/3613/3730/3779 towball sockets~~ | done | Curated (approximate cup centers from housing geometry). |

## Notes

- 3937 (hinge base) shows zero connectors in RAW audit output by design:
  it redirects to the 3937c01 composite at import time.
- 3183a also reads 3 incidental short Bars (its slot edges are r4 rods);
  physically clippable, left as-is.
- The audit list intentionally skips printed variants, stickers, Duplo,
  and baseplates.
