# Parts Index

Curated representative parts per connection category, with the LDraw
primitives that mark each connection. The LDraw data has no category
index of its own — parts are just .dat files composing shared primitives —
so this file is the reference for which parts to test against and which
primitives mark which connector. The machine-readable version of the
primitive table is `src/shared/LDraw/connectorPrimitives.lua`.

Primitive naming is full of traps; verify against the actual file
descriptions (`head -1 p/<name>.dat`) before extending the table:
`axlehole.dat` = axle-shaped HOLE, but `axlehol8.dat` = axle SHAFT surface
("Technic Axle Perimeter"), and `axlehol2.dat` is only edge lines.

## Handled categories

| Category | Representative parts | Primitives | Connector |
|---|---|---|---|
| Brick | 3001 (2x4), 3005 (1x1), 3003 (2x2) | `stud.dat` top; `stud4*` tubes / `stud3*` pins underside | Stud grid / Socket grid |
| Plate | 3020 (2x4), 3024 (1x1), 3623 (1x3), 3832 (2x10) | same as brick | Stud grid / Socket grid |
| Hollow-stud parts | 3700, 3957 (antenna base) | `stud2*` hollow studs | Stud (male; bar-in-stud NOT modeled) |
| Technic brick | 3700 (1x2, 1 hole), 3701 (1x4, 3 holes) | `peghole*` mouth per face, paired into through-holes | PegHole (axis + depth) |
| Technic axle | 3704 (axle 2), 32062 (axle 2 notched), 4519 (axle 3) | `axle.dat`, `axlehol8.dat` shaft segments (ends `axleend*` excluded, so length reads ~5 LDU short) | Axle (axis + length) |
| Technic pin | 2780 (friction, 2 halves), 3673 (frictionless) | `connect*.dat`, `confric*.dat` pin halves (1.0 = 20 LDU, 0.5 = 10, 2.0 = 40) | TechnicPin per half |
| Gear / axle hole | 3647 (gear 8 tooth) | `axlehole.dat`, `axl2hole`-`axl5hole` scaled segments | AxleHole (axis + length) |
| Bar / rod | 30374 (bar 4L), 3957 (antenna shaft) | none — geometric: `4-4cyli`/`4-4cylc` at radius 4, length >= 8 | Bar (axis + length) |
| Clip (vertical) | 4085c (plate 1x1 w/ clip), 2555 (tile w/ clip) | `clip1.dat`, `clip2.dat` (grip center ~8 LDU out along local -Z from the mount origin) | Clip (grips a Bar along local Y) |
| 1x1 underside pockets | 3005, 3024, 4085c | `box5.dat`/`box4t.dat` cavity boxes at stud-pocket size (half-extents 5.5-10.5 LDU; larger placements are wall shells and ignored) | Socket via Pocket |

## Known gaps (not yet handled)

| Category | Representative parts | Why |
|---|---|---|
| Round 1x1 underside pockets | 4073, 3062 | Pocket walls are cylinders, not box5/box4t cavity boxes |
| Technic bush | 3713 | Axle hole built from raw chords/rects, no `axlehole` primitive |
| Horizontal clips | 4623 (plate 1x1 w/ horiz. clip), 48729 | `clip3`-`clip16` have per-primitive orientations; needs per-name table entries |
| Bar-into-hollow-stud | 3957 antenna into 4070 etc. | Hollow studs (`stud2*`) accept bars; needs a female "HollowStud" facet on stud2 |
| Minifig neck/head | 973 (torso), 3626 (head) | Neck post/head socket are bespoke geometry, no primitives |
| Minifig hands/arms | 983/3820 (hand), 981/982 (arms) | Hand grip is a C-shape of raw geometry (functionally a Clip); wrist/arm sockets bespoke |
| Minifig hips/legs | 970, 971/972 | Bespoke geometry |
| Hinges, turntables, ball joints | 3937/3938, 3679/3680, towballs | Paired special geometry, no shared connector primitives |
| Wheels/tyres | 4624 + 3641 | Rim/tyre interface is its own system |

## Useful survey commands

```bash
# What is a primitive?          head -1 p/<name>.dat
# What does a part reference?   grep -E "^1" parts/<num>.dat
# Which parts use a primitive?  grep -lE "^1 .*<name>\.dat" parts/*.dat | head
```
