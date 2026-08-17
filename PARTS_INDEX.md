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
| Minifig core | 973c01 (torso+arms+hands: FOUR-joint composite — shoulders about the lateral axis at (+-15.552, 9, 0), wrists about the hand transforms' Z axes; 973/arms redirect to it, neck Stud at the torso TOP plane y=0 so heads seat flush per the official assembly convention), 3626b/a (head: bottom neck Pocket + real stud2a top stud), 3820 (hand: inverted r4 cylo C-grip = BarHole; standalone-importable), 3815c01 (hips+legs: two-joint composite; foot Pocket per leg), 3624-style hats (stud4 tube grips the head stud) | overrides + cylo bore keying + multi-joint composites (transforms from the official 973c01 assembly) | Stud/Pocket/BarHole/Composite |
| Stud-in-pinhole | any stud + any technic hole; minifig head on the tall neck post | "mouth" mate rule: Stud<->PegHole — the stud locks to the nearer hole mouth pointing inward | Stud<->PegHole |
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
| Minifig hands/arms | 983/3820 (hand), 973c01 (torso+arms composite) | Hand grip C-shape reads as BarHole; shoulders/wrists are composite joints | BarHole / Composite |
| Minifig hips/legs | 3815c01 composite (3815+3816+3817) | Bespoke geometry; per-leg hinge joints in the composite | Composite |
| Minifig headgear | 3624, 3833, hair family | `stud4*` grip tube recessed in the brim; "Minifig" parts are exempt from the anti-stud boundary rule | Tube (socket via center grip) |
| Hinge plates/bars (finger rows) | 4275a/4276a, 2433, 2923 | `h1.dat` (2 fingers) / `h2.dat` (3 fingers): pivot along local Z through (0,10,0); self-mates | HingeFinger |
| Hand-built finger rows | 2440 radar, 3314/3433/2347 excavator, 2348/2349 sunroof | Curated 40-72 LDU rows (partOverrides) | HingeFinger |
| Click-lock hinges | 30364/30365, 44301/44302, 30633 canopy | `clh1/2/3/6/6d/6u/8/9/12/13` single fingers vs `clh4/5/7/10/11/14` fork halves (coincident pairs merge); axis local Z | ClickFinger <-> ClickFork |
| Arm-scale fingers (grab jaws) | 412/3612, 4220 family, 795/4221 curated | `arm1/arm2/arm3` rows, axis local Y at (0,0,-10) | ArmFinger (self-mates) |
| Classic pin hinges (doors/windows/shutters) | 671+670, 3644+30179, 2657+2656, 3853+3856, 838+837, 4533/4535+4532/4534, 841+843 stove | `bump5000` nubs auto-detect (span -0.5..0 local Y); `42205s01`/`2656s01` hole subparts keyed; rods/bores curated per part | HingePin <-> HingeSocket |
| Roadsigns | 745/746 base + 3350 sign | r2 neck/clamp (curated); signs stack on their own r2 posts | HingePin <-> HingeSocket |
| Turntables / swivels | 3403c01, 30516c01, 73983 (2429+2430), 2855c virtual | Composite assemblies with vertical Hinge joints | Composite |
| Ball joints | 3183a family, 2736 towball, joint8 sockets | r8 spheres / inverted r8 cup cylinders / `joint8socket*` | Towball <-> TowballSocket |
| Transmission slip | 6538a + 6539 | Curated (partOverrides) | SlipAxle <-> SlipRing |
| Tyres and rims | 3641+4624, 11209+11208, aliases | Description-keyed ("Wheel Rim W x D" / "Tyre S/ O x D", trailing number = fit diameter in mm, axis Z at origin); connections carry a mating radius the solver gates on | TyreBore <-> RimSeat |
| Wheel pins | 4870, 2926, 21445 + 30027 rims | `wpin*` shafts (local -Y, ~12 LDU) vs `wpinhole`/`wpinhol2` bores; old hand-built rim bores read BarHole, which WheelPin also mates | WheelPin <-> WheelHole/BarHole |
| Magnets | 2607/2609/30159 holder combos | Casing `2959b.dat` pole faces at z=+-8.5 (all combos nest through 2959bc01) | Magnet (self-mates, point rule) |
| Drawers / slides | 2+3, 4532+4536, 850/851a/852, 420/421 | Curated rail/groove lines along the slide axis; equal lengths lock at the closed/nested position | SlideRail <-> SlideGroove |
| Train track | 74746/74747 (9V), 53401/53400 (RC), 2861/2859 switches, 32087 crossing | Curated TrackEnds (centerline, outward); curves are 22.5 deg of R=800 | TrackEnd (self-mates, point rule) |
| Roller coaster track | 25059/26022/25061, ramps 26559/26560/26561 | Curated ends; clip pins sit 10 LDU inside each abutment plane (ring-search calibrated) | CoasterEnd (self-mates) |
| Monorail track | 2670/2671/2672, ramps 2677+2678 | Curated ends (genderless); ramp halves lap-join via vertical pegs | MonoEnd / MonoRampJoint |
| Friends minidolls | 92198 head, 1006030 torso, 1015152 hips, legs variants | Neck/hips are r4 bar-standard (auto); legs hinge subpart `1023035s02` keyed (axis X knuckle); foot subparts `1023035s04`/`25727s03` keyed as Pockets (stud pitch) | Bar/BarHole + MinidollHinge + Pocket |
| Ladders | 15118/11299/4207a rungs, 850-852/420/421 slides, 4000 pivot | Rungs are r4 bars (curated rows); sections slide; pivot is a bar | Bar / SlideRail+Groove |
| Hinge hook (crane latch) | 2650 + 2651 | r4 bar on the base, C-jaw clip on the arm | Bar <-> Clip |

## Audit status

Three disjoint 1000-part audit samples (sets/audit_parts*.txt) show no
remaining undetected connection systems. Partner-less parts (mate never
made as an LDraw part): 2874 sliding door, 4318 boat mast, 27448 flat
turntable base. See AUDIT.md for the full history.

## Useful survey commands

```bash
# Fast lookups: grep part_index.tsv (see CLAUDE.md), regenerate with
#   python scripts/build_part_index.py
# What is a primitive?          head -1 p/<name>.dat
# What does a part reference?   python scripts/probe_part.py <num> [filter]
# Raw-geometry parts:           python scripts/flatten_verts.py <num> --rings <axis> <r>
# Which parts use a primitive?  grep <name>.dat part_index.tsv
```
