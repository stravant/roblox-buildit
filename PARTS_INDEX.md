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
| Bar bore (hole through a pin, etc.) | 2780, 3673 | INVERTED radius-4 cylinder sections (INVERTNEXT accumulation only — mirroring flips winding, not concavity); pin primitives get an interior-only scan; fragmented slotted bores merge with a 9 LDU gap tolerance, then sub-8 LDU leftovers are culled | BarHole (axis + length, mates Bar) |
| Gear / axle hole | 3647 (gear 8 tooth) | `axlehole.dat`, `axl2hole`-`axl5hole`, `axlehol4/5` (open-side walls), `axl2/3/5hol8` ("Hole ... Perimeter" = female; bare "Axle Perimeter" `axlehol8` = male!) | AxleHole (axis + length) |
| Bush / sleeve axle hole | 3713 (bush), 6553 (axle hub, hole perpendicular to its axle) | `bush.dat` (local Z -6..10), `bush0.dat` (local Z +-6) | AxleHole through |
| Blind axle hole | 3651 (pin/bush connector w/ 2 studs) | `axl2end`/`axl3end`/`axl5end` "End Surface" caps (hole extends along cap local -Y); the cap's short oneSided segment merges with adjacent hole/bush segments | AxleHole with OneSided |
| Connector pin hole | 3651 | `connhole.dat` (20 LDU through segment along local Y) | PegHole |
| Gear tooth-built axle holes | 4019 (gear 16t), 6135, 2712 (rotor) | `axlehol6`/`axl3hol6` "Hole Tooth" segments (4x rotated per hole) | AxleHole |
| Hand-carved pin bores | 3648a (gear 24t 3-axlehole: 4 pin holes) | geometric: INVERTED radius-6 cylinder sections, merged, sub-6 culled | PegHole |
| Hand-built connectors (curated) | 3648a center axle hole | `connectorPrimitives.partOverrides` per-part table (raw rect cross, nothing keyable) | per entry |
| Composite hinge | 2429+2430 via 73983 (Hinge Plate 1x4 Complete) | LDraw Shortcut assembly + curated joint in `compositeParts.lua` (both halves' swivel boss at the assembly origin, vertical axis). Imports as a Model of jointed segments; segment ids redirect to the assembly | Composite (Model + JointPivot attachments) |
| Transmission slip interface | 6538a (axle joiner) + 6539 (driving ring) | partOverrides: SlipAxle on the joiner's outside (40 LDU, additive with its internal AxleHole), SlipRing on the ring with a FUNCTIONAL 24 LDU length so the axial slide gives the real +-8 LDU shift travel | SlipAxle<->SlipRing (axial) |
| Interior gear posts | 6573 (differential: planet gear post) | boundary rule: Pin/Tube whose free rim is NOT on the part surface isn't an anti-stud; solid interior stud3 reads as a short r4 Bar (Bar<->AxleHole mates the bevel gear onto it) | Bar |
| Bar / rod | 30374 (bar 4L), 3957 (antenna shaft) | none — geometric: `4-4cyli`/`4-4cylc` at radius 4, length >= 8 | Bar (axis + length) |
| Clip (vertical) | 4085c (plate 1x1 w/ clip), 2555 (tile w/ clip) | `clip1.dat`, `clip2.dat` (grip center ~8 LDU out along local -Z from the mount origin) | Clip (grips a Bar along local Y) |
| Underside pockets (1x1 up to grids) | 3005, 3024, 4085c, tiles (3069b/3070a), hinge bases | `box5.dat`/`box4t.dat` cavity boxes produce stud-pitched CELL GRIDS (up to 6x6, depth <= 26 LDU); interior shells of bricks/plates emit cells that dedup with tube-derived sockets | Socket via Pocket |
| Hinges & turntables (composite) | 3937+3938 (Hinge 1x2), 652+653+654 (Hinge Brick 1x8), 3679+3680 (Turntable 2x2), 3403+3404 (Turntable 4x4) | LDraw assemblies 3937c01/652c01/3680c01/3403c01 + curated joints in compositeParts.lua | Composite Models |
| Towball | 3184 (plate 1x4 w/ ball), 2736 (axle towball), 2508 | geometric: `N-Msphe` sphere sections at uniform radius 8, ball center = placement origin (also catches `joint8ball` via recursion) | Towball (position-only mate, rotation free) |
| Ball socket (joint-8) | 14418, 14704 (plates w/ socket) | `joint8socket1/2/3.dat`, gripped ball center = primitive origin (verified by sphere-fitting the cup: 440/606 verts at r 7-9) | TowballSocket |
| Ball socket (cylindrical cup) | 2739a (steering link 6L) | geometric: INVERTED radius-8 cylinder segments >= 8 LDU (ball center = segment center); candidates coaxial with a PegHole/AxleHole are suppressed (pin holes have r8 channel sections) | TowballSocket |

## Known gaps (not yet handled)

| Category | Representative parts | Why |
|---|---|---|
| Round 1x1 underside pockets | 4073, 3062 | Pocket walls are cylinders, not box5/box4t cavity boxes |
| Classic towball socket | 3183 (plate 1x4 w/ socket) | Socket is two flexible rect walls, no keyable primitive or sphere |
| Hand-built towballs | 30082, 30396, 30395 | Ball/socket modeled from raw quads, no sphere primitives (candidates for partOverrides) |
| 3648a's two ribbed axle holes | 3648a | Two of its four diagonal pin holes carry axle ribs (rect-built); they detect as PegHole only — an axle still mates via Axle<->PegHole |
| 4143 full bore depth | 4143 (bevel gear 14t) | Only 4 of ~8 LDU of the bore uses `axlehole`; the rest is face geometry, so the slide range is conservative |
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
