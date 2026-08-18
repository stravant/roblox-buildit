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
| Minifig articulation | ~124 | PARTLY DONE: torso neck Stud, head Pocket/top stud, hand C-grip (cylo bore), hips+legs two-joint composite, hats via tubes, stud-in-pinhole "mouth" mate rule. Friends minidolls: head neck-bore/hair-stud and torso neck-pin/hip-receivers all auto-detect via the r4 bar rules; hips 1015152's D-posts curated. Friends legs: the shared thin-hinge knuckle subpart (1023035s02) is keyed as MinidollHinge, covering all 26 thin-hinge variants against hips 1015152's fork. Remaining: minifig arms (wrist sockets, print-variant-heavy), integral-arm figures (15/17), thick-hinge legs family (different subpart, same approach when surveyed), minidoll hand grips (deep subparts, unverified). |
| Doors/windows/shutters | ~25 of zero-bucket | IN PROGRESS: HingePin/HingeSocket pair added. Done: bump5000 nubs auto-detect as HingePin, correct span (791, 2657, 3853 tabs); female hole subparts 42205s01 (frames 42205/51239/6798 + cupboard 2656 top) and 2656s01 (cupboard bottom) keyed as oneSided HingeSockets; door 671 rod + frame 670 sockets curated; shutter 3856 hook recesses curated. Also done: 3644+30179 (classic 1x4x6 rod/bores), 60623+60596 (newer 1x4x6 short pins), 2042+2043 cupboard (side-rail bump/well stacks, mixed polarity). Also done: 4131+4130 (2x4x5 capped rod/bores), 4072+4071 (2x6x7 rod/corner rails). MOSTLY DONE — auto-coverage: any bump5000 part reads as HingePin (2049 Fabuland shutter, 2400 curved door, 2657, 791...); 42205s01 hole subpart covers its 4 frame users. Parked: 791's frame (unidentified, maybe never made as a separate part), 821a Mursten garage door = SLIDING channel (new joint class), Fabuland house blocks (unofficial u-parts). |
| Finger hinges on arms/brackets | ~10 | DONE (primitive-covered): HingeFinger (h1/h2, 73 parts), ClickFinger/ClickFork (clh family, locking hinges incl. 44301/44302), ArmFinger (arm1/2/3, grab-jaw arm pieces). Not covered: hand-built fingers on 795 and grab jaw 4221 (rare, curate on demand); finger-count interleave validation (2+2 currently allowed). |
| Tyres/wheels | ~15 | DONE (description-keyed): TyreBore/RimSeat pair derived from official part names ("Wheel Rim 6.4 x 8" seats "Tyre 6/ 50 x 8" — trailing number = fit diameter in mm, axis Z at origin). Connections carry a mating `radius`; the snap solver only mates radius-compatible pairs (0.15 stud tolerance). Combo "... with Tyre ..." parts get neither. Not covered: old-style tyre names without the S/O x D pattern ("Tyre Smooth Old Style..."), curate/extend the pattern on demand. |
| Ladders/rails/misc | rest | Magnets DONE: self-mating Magnet point pair on casing 2959b's pole faces (z=+-8.5); covers all holder combos (2607/2609/30159/train base) via the 2959bc01 nesting. Remaining case-by-case: modern ladder 15118/11299 hand-built back clips (subparts s04/s05, curate on demand), train drive rods 505/506 crank pin holes, roadsign fingers. |
| ~~2855/2856 turntable~~ | done | Virtual assembly support added to compositeParts (inline segment list + transforms); 2855c imports as a two-segment composite. |
| ~~3491/3613/3730/3779 towball sockets~~ | done | Curated (approximate cup centers from housing geometry). |

## Zero-connector shortlist (Aug 2026 full re-audit, 156/1000)

Most are legitimately connectionless (glass panes, capes, food,
minifig accessories that wrap/drape). Headgear was the big fixable
family (now handled via the wearable boundary-rule exemption).
Genuinely remaining, by family:

- Hand-built finger hinges: ~~2440 radar, excavator 3314/3433/2347,
  2348/2349 sunroof, 795/4221 arm pieces, 4315 roof holder~~ (all
  done — 4315's bumps mount roof 2349's barrel ends; the glass was a
  red herring). ~~2650/2651 hinge hook~~ (plain Bar/Clip, no new
  class needed). Parked: 654 joining ring (652c01 composite segment,
  joint handled there), 4318 boat mast (mating deck part
  unidentified).
- Doors/drawers: ~~4536 drawer~~, ~~4533/4535 doors + 4532/4534
  bores~~ (vertex analysis found the full-height r2 rod; the old
  "double-barrel" reading was wrong), ~~838/843 Homemaker~~ (838
  done; 843 stove door pending). Parked: drawer 3 (cabinet
  unidentified), 2874 sliding door, 821a Mursten garage door.
- Ladders: ALL DONE — 420/421 + 850/851a/852 slides, 15118/11299/
  4207a rungs as bars, 4000 pivot bar.
- Misc: ~~745/746/3350 roadsigns~~, ~~4788 paddle wheel~~ (hand-built
  axle cross bore). Remaining: 2686 monorail wheel chassis (mates the
  motor assembly, out of connector scope).
- Train track family: ~~9V switches 2861/2859~~, ~~coaster ramps
  26559/26560/26561~~ (clip pins located by ring search, calibrated
  against the straights). Remaining: coaster lift/chain sections.

## Known limitations (non-connector)

- 9V switches 2861/2859 exceed the EditableMesh triangle limit at
  import (large uncertified geometry imports double-sided). Their
  connectors are correct; the mesh build needs either BFC-certified
  reauthoring upstream or a decimation pass. Exempted in the
  testSetCoverage import sweep.

## Notes

- 3937 (hinge base) shows zero connectors in RAW audit output by design:
  it redirects to the 3937c01 composite at import time.
- 3183a also reads 3 incidental short Bars (its slot edges are r4 rods);
  physically clippable, left as-is.
- The audit list intentionally skips printed variants, stickers, Duplo,
  and baseplates.
