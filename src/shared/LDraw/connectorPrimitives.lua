--!strict

-- The curated table of LDraw connector primitives: which primitive names
-- mark connections, and each one's geometry convention. See PARTS_INDEX.md
-- for representative parts per category and survey notes.
--
-- IMPORTANT: primitive names in this area are traps — exact names matter:
--   axlehole.dat  = axle-shaped HOLE segment
--   axlehol8.dat  = axle SHAFT surface ("Technic Axle Perimeter")
--   axlehol2.dat  = edge lines only (not a connector)
-- so classification is by exact name (plus the stud prefix families, which
-- are safe).
--
-- Geometry conventions (verified against the library):
--   "mouth"     Point connector at the transform origin on the part
--               surface; mates along transformed -Y (out of the part).
--               Studs, and peghole mouths (paired into through-holes by
--               findConnections).
--   "rim"       Free end at transform*(0,-4,0) (stud3/stud4 underside
--               tubes/pins placed with negative Y scale).
--   "segmentY"  Element spanning local Y in [0, 1], scaled by the
--               placement to its real length (axle shafts, axle holes).
--   "shaftNegY" Element extending along local -Y from the origin with a
--               FIXED length (Technic pin halves; "Pin 1.0" = 20 LDU).
--   "segmentYFixed" Element spanning local Y in [0, length] with a FIXED
--               length, placed unscaled (axle end caps).
--   "axisY"     Fixed-size element gripping along local +Y (clips), at
--               the origin plus the spec's fixed local offset.
--   "cavity"    Open box primitive (open face at local y=0, origin at the
--               open face center, +-1 extents). When placed at stud-pocket
--               size (see isSocketCavity) the opening is an anti-stud
--               pocket — this is how 1x1 parts and clip plates, which have
--               no stud3/stud4 tube, get their underside socket.
--   "ballAt"    Ball-joint element centered at the primitive origin
--               (joint8socket* grip a ball at their origin; joint8ball's
--               own sphere also sits at its origin, so male balls come
--               from the geometric sphere rule instead). Direction is
--               meaningless for ball joints (rotation-free mate).
--   "span"      Element spanning a FIXED local range [spanMin, spanMax]
--               along the local `axis` ("Y" or "Z"), placed unscaled
--               (bush sleeves span local Z, connhole spans local Y).
--   "capNegY"   Blind-end cap of a hole: flat surface at local y=0 with
--               the hole extending along local -Y. Emits a short oneSided
--               segment that MERGES with the adjacent hole segments,
--               propagating the open-side direction (axl5end + bush =
--               one blind axle hole).

export type Geometry =
	"mouth" | "rim" | "segmentY" | "segmentYFixed" | "shaftNegY" | "axisY" | "cavity" | "ballAt"
	| "span" | "capNegY"

export type Spec = {
	type: string, -- Types.ConnectionType
	geometry: Geometry,
	length: number?, -- LDU, for fixed-length geometries
	offset: Vector3?, -- local offset from the primitive origin
	axis: string?, -- "Y" | "Z", for "span"
	spanMin: number?, -- for "span"
	spanMax: number?, -- for "span"
	oneSided: boolean?, -- blind female bore marker (capNegY)
}

local kSpecs: { [string]: Spec } = {}

local function add(names: { string }, spec: Spec)
	for _, name in names do
		kSpecs[name .. ".dat"] = spec
	end
end

-- Technic pin holes (mouth at each face; through-holes get paired).
add(
	{ "peghole", "peghole2", "peghole3", "peghole4", "peghole5", "peghole6", "npeghole" },
	{ type = "PegHole", geometry = "mouth" }
)

-- Axle-shaped holes (scaled unit segments). "Hole ... Perimeter" names
-- (axlNhol8 for N >= 2) are hole WALLS = female; bare "Axle Perimeter"
-- (axlehol8) is the male shaft — see the axle shaft table below.
add(
	{ "axlehole", "axl2hole", "axl3hole", "axl4hole", "axl5hole", "axlehol4", "axlehol5", "axl2hol8", "axl3hol8", "axl5hol8", "axlehol6", "axl3hol6" },
	{ type = "AxleHole", geometry = "segmentY" }
)

-- Blind-end caps of axle holes ("... End Surface"): the hole extends
-- along the cap's local -Y; merging joins the cap segment with the
-- adjacent hole/bush segments into one oneSided hole.
add(
	{ "axl2end", "axl3end", "axl5end" },
	{ type = "AxleHole", geometry = "capNegY", length = 4, oneSided = true }
)

-- Bush sleeves: through axle holes along local Z. bush.dat adds a collar
-- on the +Z side (its bore continues to z=10); parts complete the rest
-- with undetectable ring geometry, so lengths run slightly short.
add({ "bush0" }, { type = "AxleHole", geometry = "span", axis = "Z", spanMin = -6, spanMax = 6 })
add({ "bush" }, { type = "AxleHole", geometry = "span", axis = "Z", spanMin = -6, spanMax = 10 })

-- Technic connector pin hole as a single through segment (unlike
-- peghole mouths, which get paired).
add({ "connhole" }, { type = "PegHole", geometry = "span", axis = "Y", spanMin = -10, spanMax = 10 })

-- Axle shafts (scaled unit segments), plus the 2.5 LDU end caps (placed
-- unscaled) so merged lengths cover the full physical axle — required for
-- flush positioning in holes.
add(
	{ "axle", "axlehol8", "axles" },
	{ type = "Axle", geometry = "segmentY" }
)
add({ "axleend", "axleend2" }, { type = "Axle", geometry = "segmentYFixed", length = 2.5 })

-- Technic pin halves: full pin shapes extending -Y from the base collar.
-- "Pin 1.0" = one module (20 LDU), "0.5" = 10, "2.0" = 40.
add(
	{ "connect", "connect2", "connect5", "connect6", "connect7", "connect8", "connect10" },
	{ type = "TechnicPin", geometry = "shaftNegY", length = 20 }
)
add({ "connect3", "connect4" }, { type = "TechnicPin", geometry = "shaftNegY", length = 10 })
add(
	{ "confric", "confric2", "confric4", "confric5", "confric6", "confric8", "confric9", "confric10", "confric11", "confric12" },
	{ type = "TechnicPin", geometry = "shaftNegY", length = 20 }
)
add({ "confric3" }, { type = "TechnicPin", geometry = "shaftNegY", length = 40 })

-- Vertical clips (grip a vertical bar along local Y). The primitive origin
-- is the mount point at the part edge; the gripped bar's center sits one
-- half module (10 LDU) out along the clip's local -Z — i.e. at the center
-- of the neighboring stud cell, so a clipped bar lines up with a bar
-- mounted one stud in front. The horizontal clip family (clip3+) has
-- per-primitive orientations - not handled yet.
add(
	{ "clip1", "clip2", "clip9" },
	{ type = "Clip", geometry = "axisY", length = 8, offset = Vector3.new(0, 0, -10) }
)
-- Free-standing C-clip (no mount stem): grip center at the origin.
add({ "clip12" }, { type = "Clip", geometry = "axisY", length = 8 })

-- Open cavity boxes: stud-pocket sized placements read as underside
-- sockets (see isSocketCavity).
add({ "box5", "box4t" }, { type = "Pocket", geometry = "cavity" })

-- Classic pin-hinge system: shutters and old doors/windows hinge on tiny
-- r~2 pins. bump5000 ("Bump 1.0 x 0.5", r1 h0.5, extending local -Y)
-- is the pin nub primitive, scaled by placement (typically 2-2.5).
add({ "bump5000" }, { type = "HingePin", geometry = "span", axis = "Y", spanMin = -0.5, spanMax = 0 })

-- Figure Friends foot: the shared foot subpart is placed at stud
-- pitch (x=+-10 in every legs part), so its grip recess centers on
-- the placement origin — minidolls stand on adjacent studs. axisY
-- puts the socket direction at local +Y (down).
add({ "1023035s04" }, { type = "Pocket", geometry = "axisY" })
add({ "25727s03" }, { type = "Pocket", geometry = "axisY" }) -- thick-hinge legs' foot underside

-- Figure Friends legs hinge: the shared "Legs Thin Hinge" subpart
-- (raw-geometry knuckle barrel, r2.5 along X at (0, -46.4, 2.7)) is
-- placed by every thin-hinge legs variant (26 parts); it snaps into
-- the hips piece's bore and self-mates as MinidollHinge.
add({ "1023035s02" }, {
	type = "MinidollHinge",
	geometry = "axisX",
	offset = Vector3.new(0, -46.4, 2.7),
	length = 6,
})

-- Classic wheel mounts: wpin* ("Wheel Holding Pin", r4.3 shaft with
-- retention flange, extending local -Y) snaps into wpinhole/wpinhol2
-- notched hub bores. Old rims with hand-built bores read as BarHole
-- instead, so WheelPin partners both (see findSnapPlacement).
add({ "wpin", "wpin2", "wpin2a", "wpin3", "wpin4", "wpin5a", "wpin5e" }, {
	type = "WheelPin",
	geometry = "shaftNegY",
	length = 12,
})
add({ "wpinhole", "wpinhol2" }, {
	type = "WheelHole",
	geometry = "axisY",
	offset = Vector3.new(0, -4, 0),
	length = 8,
})

-- Classic finger hinges: h1 ("Hinge Plate 2 Fingers") and h2 ("3
-- Fingers") are the standard finger-row primitives (73 parts). The
-- pivot line runs along local Z through (0, 10, 0) (nubs at z=+-6);
-- 2- and 3-finger rows interleave, so the type mates with itself.
add({ "h1", "h2" }, {
	type = "HingeFinger",
	geometry = "axisZ",
	offset = Vector3.new(0, 10, 0),
	length = 16,
})

-- Arm-piece finger hinges (grab jaws, robot arms): arm1 ("Hinge Arm 2
-- Finger") and arm2 ("3 Finger") rows interleave like h1/h2 but at
-- arm scale; pivot line along local Y through (0, 0, -10).
add({ "arm1", "arm2", "arm3" }, {
	type = "ArmFinger",
	geometry = "axisY",
	offset = Vector3.new(0, 0, -10),
	length = 12,
})

-- Click-lock hinges (modern locking finger hinges): single fingers
-- (clh1 family) click between fork prongs (clh4 family, placed as two
-- halves at the same origin — they merge to one connector). Pivot axis
-- = local Z through the primitive origin.
add({ "clh1", "clh2", "clh3", "clh6", "clh8", "clh9", "clh12", "clh13" }, {
	type = "ClickFinger",
	geometry = "axisZ",
	length = 4,
})
add({ "clh4", "clh5", "clh7", "clh10", "clh11", "clh14" }, {
	type = "ClickFork",
	geometry = "axisZ",
	length = 4,
})

-- The matching female side: "Corner Stud for Window/Door, Hole for Bump"
-- (subpart shared by door/window frames 42205, 51239, 6798 and cupboard
-- 2656). Bore r2.5 at local (2, 0..4, 5), mouth on the +Y face (the
-- door's upward pin enters from below the top rail).
add({ "42205s01" }, {
	type = "HingeSocket",
	geometry = "span",
	axis = "Y",
	offset = Vector3.new(2, 0, 5),
	spanMin = 0,
	spanMax = 4,
	oneSided = true,
})

-- Cupboard 2656's bottom-rail counterpart: r2.5 well at local
-- (8, -8..0, -5), mouth on the -Y face (upward-opening).
add({ "2656s01" }, {
	type = "HingeSocket",
	geometry = "span",
	axis = "Y",
	offset = Vector3.new(8, 0, -5),
	spanMin = 0,
	spanMax = -8,
	oneSided = true,
})

-- Ball joint sockets (joint-8 system: mixel/CCBS-style sockets). The
-- classic towball socket plate (3183) and some hand-built balls (30082,
-- 30396) have no keyable primitives - see PARTS_INDEX.md gaps.
add(
	{ "joint8socket1", "joint8socket2", "joint8socket3" },
	{ type = "TowballSocket", geometry = "ballAt" }
)

local connectorPrimitives = {}

-- Per-PART connector overrides, for parts whose connectors are hand-built
-- from raw geometry with nothing keyable (applied in ADDITION to normal
-- detection). Keys are normalized file references.
export type Override = {
	type: string,
	position: Vector3,
	direction: Vector3,
	length: number?,
	oneSided: boolean?,
}

connectorPrimitives.partOverrides = {
	-- Gear 24 tooth with 3 axleholes: the center axle hole is a raw rect
	-- cross (the four r6 pin-hole bores detect normally; two of them also
	-- carry axle ribs, not modeled).
	["3648a.dat"] = {
		{
			type = "AxleHole",
			position = Vector3.zero,
			direction = Vector3.new(0, 0, 1),
			length = 15.6,
		},
	},
	-- Transmission slip interface: the driving ring (6539) rides splined
	-- on the OUTSIDE of the axle joiner (6538a) and slides axially to
	-- engage gears on either side. The joiner keeps its internal AxleHole
	-- from normal detection; the override adds the external slip surface.
	["6538a.dat"] = {
		{
			type = "SlipAxle",
			position = Vector3.zero,
			direction = Vector3.new(0, 0, 1),
			length = 40,
		},
	},
	-- Ring length is FUNCTIONAL, not geometric (the ring body is 40 like
	-- the joiner): 24 gives the +-8 LDU shift travel of the real gearbox.
	["6539.dat"] = {
		{
			type = "SlipRing",
			position = Vector3.zero,
			direction = Vector3.new(0, 0, 1),
			length = 24,
		},
	},
	-- Classic towball socket plates (rect-wall cups, nothing keyable):
	-- gripped ball center measured from the wall pair at (+-9.8, 4, -18).
	["3183a.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, 4, -18), direction = Vector3.new(0, -1, 0) },
	},
	["3183b.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, 4, -18), direction = Vector3.new(0, -1, 0) },
	},
	["3183c.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, 4, -18), direction = Vector3.new(0, -1, 0) },
	},
	-- More classic towball sockets (bespoke raw-quad cups; positions are
	-- curated approximations from the housing geometry — the ball mate is
	-- rotation-free so only position matters).
	["3730.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, 4, -29), direction = Vector3.new(0, 0, -1) },
	},
	["3779.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, -10, 0), direction = Vector3.new(0, -1, 0) },
	},
	["3491.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(-46, 4, 0), direction = Vector3.new(-1, 0, 0) },
	},
	["3613.dat"] = {
		{ type = "TowballSocket", position = Vector3.new(0, 0, -14), direction = Vector3.new(0, 0, -1) },
	},
	-- Classic Container Drawers 4x4x4 (part 2) + Drawer 4x4x2 (part 3):
	-- two stacked slots, drawer slides on Z and locks flush.
	["3.dat"] = {
		{
			type = "SlideRail",
			position = Vector3.new(0, 20, 0),
			direction = Vector3.new(0, 0, 1),
			length = 72,
		},
	},
	["2.dat"] = {
		{
			type = "SlideGroove",
			position = Vector3.new(0, 28, 0),
			direction = Vector3.new(0, 0, 1),
			length = 72,
		},
		{
			type = "SlideGroove",
			position = Vector3.new(0, 68, 0),
			direction = Vector3.new(0, 0, 1),
			length = 72,
		},
	},
	-- Container Cupboard 2x3x2 drawer slide: the drawer tray rides the
	-- cupboard cavity along Z; equal lengths lock at the closed
	-- position. (SlideRail/SlideGroove is the generic sliding class —
	-- future drawers, sliding doors, and ladder sections reuse it.)
	["4536.dat"] = {
		{
			type = "SlideRail",
			position = Vector3.new(0, 4, -2),
			direction = Vector3.new(0, 0, 1),
			length = 36,
		},
	},
	["4532.dat"] = {
		{
			type = "SlideGroove",
			position = Vector3.new(0, 32, -2),
			direction = Vector3.new(0, 0, 1),
			length = 36,
		},
		-- Door hinge bores at both front corners (door hangs either side).
		{
			type = "HingeSocket",
			position = Vector3.new(24, 22, -17),
			direction = Vector3.new(0, -1, 0),
			length = 37,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-24, 22, -17),
			direction = Vector3.new(0, -1, 0),
			length = 37,
		},
	},
	-- Cupboard doors: full-height r2 hinge rod on the door edge
	-- (located by vertex-ring analysis; 30125 aliases 4533).
	["4533.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 18, 0),
			direction = Vector3.new(0, -1, 0),
			length = 37,
		},
	},
	["4535.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 42, 0),
			direction = Vector3.new(0, -1, 0),
			length = 85,
		},
	},
	-- Container Cupboard 2x3x4: same corner bores, taller.
	["4534.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(24, 46, -17),
			direction = Vector3.new(0, -1, 0),
			length = 85,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-24, 46, -17),
			direction = Vector3.new(0, -1, 0),
			length = 85,
		},
	},
	-- Fire ladder 2.4x13 sections: the narrow top section (852) nests
	-- and slides inside the bottom section (850)'s rails, both 260
	-- long on axis X. The half-length rail leaves +-65 of slide so
	-- extension positions snap too.
	["850.dat"] = {
		{
			type = "SlideGroove",
			position = Vector3.new(0, -15, 0),
			direction = Vector3.new(1, 0, 0),
			length = 260,
		},
	},
	["852.dat"] = {
		{
			type = "SlideRail",
			position = Vector3.new(0, -15, 0),
			direction = Vector3.new(1, 0, 0),
			length = 130,
		},
	},
	-- Train track ends: one abstract TrackEnd per end (centerline, at
	-- rail level, pointing outward). Ends mate face-to-face like
	-- magnets, so any track joins any track; the physical peg/slot
	-- detail is irrelevant to snapping. 2865 (9V alias) nests through
	-- 74746 and inherits.
	["74746.dat"] = {
		{ type = "TrackEnd", position = Vector3.new(160, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(-160, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	["53401.dat"] = {
		{ type = "TrackEnd", position = Vector3.new(160, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(-160, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	-- Curved tracks (9V 74747 / RC 53400): 22.5 degrees of an R=800
	-- arc, authored symmetric about Z — ends at +-11.25 degrees.
	-- (chord/2 = 800 sin 11.25 = 156.07; sagitta = 800 (1 - cos 11.25)
	-- = 15.37.) 2867 (9V alias) nests through 74747 and inherits.
	["74747.dat"] = {
		{
			type = "TrackEnd",
			position = Vector3.new(156.07, 0, -15.37),
			direction = Vector3.new(0.98079, 0, -0.19509),
		},
		{
			type = "TrackEnd",
			position = Vector3.new(-156.07, 0, -15.37),
			direction = Vector3.new(-0.98079, 0, -0.19509),
		},
	},
	["53400.dat"] = {
		{
			type = "TrackEnd",
			position = Vector3.new(156.07, 0, -15.37),
			direction = Vector3.new(0.98079, 0, -0.19509),
		},
		{
			type = "TrackEnd",
			position = Vector3.new(-156.07, 0, -15.37),
			direction = Vector3.new(-0.98079, 0, -0.19509),
		},
	},
	-- Monorail track: genderless MonoEnd per end (both ends place the
	-- same mirrored end subpart). Curve 2672 is a quarter circle of
	-- R=560 about (-400, 0, -400). The ramp halves lap-join via
	-- vertical pegs (MonoRampJoint: upper's pegs drop onto lower's
	-- seat), and each half also has one level MonoEnd at its origin.
	["2670.dat"] = {
		{ type = "MonoEnd", position = Vector3.new(80, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "MonoEnd", position = Vector3.new(-80, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	["2671.dat"] = {
		{ type = "MonoEnd", position = Vector3.new(320, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "MonoEnd", position = Vector3.new(-320, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	["2672.dat"] = {
		{ type = "MonoEnd", position = Vector3.new(-400, 0, 160), direction = Vector3.new(-1, 0, 0) },
		{ type = "MonoEnd", position = Vector3.new(160, 0, -400), direction = Vector3.new(0, 0, -1) },
	},
	["2677.dat"] = {
		{ type = "MonoEnd", position = Vector3.new(0, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "MonoRampJoint", position = Vector3.new(630, -95, 0), direction = Vector3.new(0, -1, 0) },
	},
	["2678.dat"] = {
		{ type = "MonoEnd", position = Vector3.new(0, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "MonoRampJoint", position = Vector3.new(630, 145, 0), direction = Vector3.new(0, 1, 0) },
	},
	-- 9V switches: two track-lengths of through line plus a 22.5-degree
	-- R800 branch (authored sleeper frames match the plain curve's
	-- geometry exactly). Left (2861) branches toward +z, right (2859)
	-- toward -z; the c01 assemblies inherit through nesting.
	["2861.dat"] = {
		{ type = "TrackEnd", position = Vector3.new(320, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(-320, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{
			type = "TrackEnd",
			position = Vector3.new(333.85, 0, 259.1),
			direction = Vector3.new(0.92388, 0, 0.38268),
		},
	},
	["2859.dat"] = {
		{ type = "TrackEnd", position = Vector3.new(320, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(-320, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{
			type = "TrackEnd",
			position = Vector3.new(333.85, 0, -259.1),
			direction = Vector3.new(0.92388, 0, -0.38268),
		},
	},
	-- 9V level crossing: four track ends.
	["32087.dat"] = {
		{ type = "TrackEnd", position = Vector3.new(160, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(-160, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "TrackEnd", position = Vector3.new(0, 0, 160), direction = Vector3.new(0, 0, 1) },
		{ type = "TrackEnd", position = Vector3.new(0, 0, -160), direction = Vector3.new(0, 0, -1) },
	},
	-- Roller coaster track: its clip joint is genderless but not
	-- compatible with train rails, so it gets its own self-mating end
	-- type. Ends at the abutment plane on the centerline (the physical
	-- clip pin sits 10 LDU inside).
	["25059.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(160, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "CoasterEnd", position = Vector3.new(-160, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	["26022.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(80, 0, 0), direction = Vector3.new(1, 0, 0) },
		{ type = "CoasterEnd", position = Vector3.new(-80, 0, 0), direction = Vector3.new(-1, 0, 0) },
	},
	-- 90-degree R12 curve: arc center at the origin, spanning the
	-- positive quadrant from (240,0,0) to (0,0,240).
	["25061.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(240, 0, 0), direction = Vector3.new(0, 0, -1) },
		{ type = "CoasterEnd", position = Vector3.new(0, 0, 240), direction = Vector3.new(-1, 0, 0) },
	},
	-- Coaster ramps: end frames located from the clip pins (which sit
	-- 10 LDU inside each abutment plane at track-surface level, the
	-- same convention the straights calibrate). Level end at (-10,0),
	-- raised end 144 up. Both S-ramps share the same end frames.
	["26561.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(-10, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "CoasterEnd", position = Vector3.new(150, 144, 0), direction = Vector3.new(1, 0, 0) },
	},
	["26559.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(-10, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "CoasterEnd", position = Vector3.new(310, 144, 0), direction = Vector3.new(1, 0, 0) },
	},
	["26560.dat"] = {
		{ type = "CoasterEnd", position = Vector3.new(-10, 0, 0), direction = Vector3.new(-1, 0, 0) },
		{ type = "CoasterEnd", position = Vector3.new(310, 144, 0), direction = Vector3.new(1, 0, 0) },
	},
	-- Fabuland Paddle Wheeler Wheel: hand-built axle cross bore
	-- through the full hub width.
	["4788.dat"] = {
		{
			type = "AxleHole",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, 0, 1),
			length = 35,
		},
	},
	-- Old arm pieces with hand-built fingers (vertex-ring located):
	-- 795's two-finger knuckle and 4221 grab jaw's single finger both
	-- pivot on Y-axis barrels; they interleave the arm1/arm2 system.
	["795.dat"] = {
		{
			type = "ArmFinger",
			position = Vector3.new(0, 0, -3),
			direction = Vector3.new(0, -1, 0),
			length = 12,
		},
	},
	["4221.dat"] = {
		{
			type = "ArmFinger",
			position = Vector3.new(1.5, -2.25, -1.5),
			direction = Vector3.new(0, -1, 0),
			length = 10.5,
		},
	},
	-- Ladder 4x15.6 with Semi-Circular Pivot: the pivot is an r4 bar
	-- along Z at the origin.
	["4000.dat"] = {
		{
			type = "Bar",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, 0, 1),
			length = 41,
		},
	},
	-- Homemaker stove: oven door 843 folds down on an r2 rod along X
	-- at its bottom edge; stove 841's grip arcs sit at the same
	-- coordinates (both authored in the assembled frame).
	["843.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 57.5, -42),
			direction = Vector3.new(1, 0, 0),
			length = 71,
		},
	},
	["841.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(0, 57.5, -42),
			direction = Vector3.new(1, 0, 0),
			length = 71,
		},
	},
	-- Homemaker cupboard: door 838's hinge edge is a full-height r1.5
	-- rod; cabinet 837 has corner bores on both sides (reversible).
	["838.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(-34, 46, -36),
			direction = Vector3.new(0, -1, 0),
			length = 87.5,
		},
	},
	["837.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(34, 46, -36),
			direction = Vector3.new(0, -1, 0),
			length = 87.5,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-34, 46, -36),
			direction = Vector3.new(0, -1, 0),
			length = 87.5,
		},
	},
	-- Modern ladder 2.6x16: the r4 round rungs are the connection
	-- surface — clips grab them and minifig hands grip them. Six main
	-- rungs on the back plane plus recessed end rungs.
	["15118.dat"] = (function()
		local rungs = {}
		for _, x in { -100, -60, -20, 20, 60, 100 } do
			table.insert(rungs, {
				type = "Bar",
				position = Vector3.new(x, 0, 0),
				direction = Vector3.new(0, 0, 1),
				length = 37.5,
			})
		end
		for _, x in { -140, 140 } do
			table.insert(rungs, {
				type = "Bar",
				position = Vector3.new(x, -4, 0),
				direction = Vector3.new(0, 0, 1),
				length = 37.5,
			})
		end
		return rungs
	end)(),
	-- Classic roadsign system: bases carry an r2 x 3 neck under the
	-- knob; sign clamps grip any r2 rod — the base neck or another
	-- sign's post (signs stack). Reuses the HingePin/HingeSocket pair.
	["745.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, -7.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 3,
		},
	},
	["746.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, -7.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 3,
		},
	},
	["3350.dat"] = {
		-- The full r2 post doubles as a stacking pin.
		{
			type = "HingePin",
			position = Vector3.new(0, -50.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 115,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(0, 5.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 3,
		},
	},
	-- Ladder 2.6x14 with Stops: five rungs (stops at the ends are not
	-- grippable).
	["4207a.dat"] = (function()
		local rungs = {}
		for _, x in { -80, -40, 0, 40, 80 } do
			table.insert(rungs, {
				type = "Bar",
				position = Vector3.new(x, 0, 0),
				direction = Vector3.new(0, 0, 1),
				length = 37.5,
			})
		end
		return rungs
	end)(),
	-- Ladder 2.6x16 with Handrails: same six main rungs as 15118 (the
	-- handrails are flat-profiled, not grippable bars).
	["11299.dat"] = (function()
		local rungs = {}
		for _, x in { -100, -60, -20, 20, 60, 100 } do
			table.insert(rungs, {
				type = "Bar",
				position = Vector3.new(x, 0, 0),
				direction = Vector3.new(0, 0, 1),
				length = 37.5,
			})
		end
		return rungs
	end)(),
	-- Classic 2x12 extension ladder: top section 421 (28 wide) slides
	-- inside bottom 420 (36 wide), 240 long on axis X.
	["420.dat"] = {
		{
			type = "SlideGroove",
			position = Vector3.new(0, -10, 0),
			direction = Vector3.new(1, 0, 0),
			length = 240,
		},
	},
	["421.dat"] = {
		{
			type = "SlideRail",
			position = Vector3.new(0, -10, 0),
			direction = Vector3.new(1, 0, 0),
			length = 120,
		},
	},
	-- Middle section (851a, 33 wide): rides inside 850 AND receives
	-- 852 — both interfaces, so middles also stack on each other.
	["851a.dat"] = {
		{
			type = "SlideRail",
			position = Vector3.new(0, -15, 0),
			direction = Vector3.new(1, 0, 0),
			length = 130,
		},
		{
			type = "SlideGroove",
			position = Vector3.new(0, -15, 0),
			direction = Vector3.new(1, 0, 0),
			length = 260,
		},
	},
	-- Car sunroof hinge: glass 2348 hinges along its rear edge into
	-- roof frame 2349's knuckle row. Matched lengths lock the glass
	-- centered; swing about the hinge line is the free DOF.
	["2348a.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
	},
	["2348b.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
	},
	-- The roof's knuckle barrel doubles as the mount: holder plate
	-- 4315's inward bumps (auto-detected HingePins at x=+-36) enter
	-- the barrel's bore ends.
	["2349a.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 4, 36),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(0, 4, 36),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
	},
	["2349b.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 4, 36),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(0, 4, 36),
			direction = Vector3.new(1, 0, 0),
			length = 72,
		},
	},
	-- Hand-built finger hinges (pre-h1/h2 era, all 40-wide rows that
	-- interleave with each other and the h1/h2 plate system):
	-- Hinge 1x2 Base: knuckles at (+-16..20, 10, 0), axis X.
	["3937.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 10, 0),
			direction = Vector3.new(1, 0, 0),
			length = 40,
		},
	},
	-- Hinge 6x3 Radar/Blade/Spoiler: knuckles at (0, 6, +-16..20), axis Z.
	["2440.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 6, 0),
			direction = Vector3.new(0, 0, 1),
			length = 40,
		},
	},
	-- Excavator Arm 2x6x2: tip finger row, axis Z.
	["3314.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(79.57, -38.97, 0),
			direction = Vector3.new(0, 0, 1),
			length = 40,
		},
	},
	-- Excavator Bucket 5x3: hinge row at (-24, 14, 0), axis Z.
	["3433.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(-24, 14, 0),
			direction = Vector3.new(0, 0, 1),
			length = 40,
		},
	},
	-- Excavator Bucket 6x3: hinge row at the origin, axis X.
	["2347.dat"] = {
		{
			type = "HingeFinger",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(1, 0, 0),
			length = 40,
		},
	},
	-- Figure Friends Hips (thin hinge): vertical r4 D-posts at x=+-4
	-- (half-shell + flat back, so the bar rule can't see them) snap
	-- into the torso's r4 receiver bores.
	["1015152.dat"] = {
		{
			type = "Bar",
			position = Vector3.new(4, -15.9, -0.3),
			direction = Vector3.new(0, -1, 0),
			length = 9,
		},
		{
			type = "Bar",
			position = Vector3.new(-4, -15.9, -0.3),
			direction = Vector3.new(0, -1, 0),
			length = 9,
		},
		-- The legs hinge fork: inverted r2.5 bore along X at the origin.
		{
			type = "MinidollHinge",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(1, 0, 0),
			length = 6,
		},
	},
	-- Magnet Cylindrical Casing: pole faces at z=+-8.5 (axis Z). Every
	-- magnet holder combo nests through 2959bc01 -> 2959b, so this one
	-- override covers the whole train-coupling magnet system. Magnets
	-- mate face-to-face (point rule, anti-parallel).
	["2959b.dat"] = {
		{ type = "Magnet", position = Vector3.new(0, 0, 8.5), direction = Vector3.new(0, 0, 1) },
		{ type = "Magnet", position = Vector3.new(0, 0, -8.5), direction = Vector3.new(0, 0, -1) },
	},
	-- Door 1x6x10: the hinge edge is a full-height r2.5 rod (half
	-- cylinder + hemisphere caps at x=-46.5, y -6..-219).
	["671.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(-46.5, -112.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 213,
		},
	},
	-- Window 1x2x3 Shutter: hook recesses (in 3856s02) that cap onto the
	-- window frame's bump tabs (3853's bump5000 pins at y=4 and 64).
	-- Length matches the bump so each pair locks axially, leaving only
	-- swing about the hinge axis.
	["3856.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(0, 4, 0),
			direction = Vector3.new(0, -1, 0),
			length = 1,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(0, 64, 0),
			direction = Vector3.new(0, -1, 0),
			length = 1,
		},
	},
	-- Container Cupboard 2x6x7 Door: outward end pins (auto-detected
	-- bumps at y=+-25) modeled as one pin line so the cupboard socket
	-- locks the door centered.
	["2043.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, -1, 0),
			length = 52,
		},
	},
	-- Container Cupboard 2x6x7: hinge stacks on both side rails (top
	-- hole boss + bottom well at x=+-52, z=-16); pin-line socket seats
	-- the door center at y=138.
	["2042.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(52, 138, -16),
			direction = Vector3.new(0, -1, 0),
			length = 52,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-52, 138, -16),
			direction = Vector3.new(0, -1, 0),
			length = 52,
		},
	},
	-- Door 1x4x6 Grooved: segmented r2 hinge rod along the door's edge
	-- (spans y 0..136 with small gaps), modeled as one pin.
	["3644.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 68, 0),
			direction = Vector3.new(0, -1, 0),
			length = 136,
		},
	},
	-- Door 1x4x6 Frame Type 1: r2 pivot bores at all four corners,
	-- paired at z=+-6 so the door can hang opening either way. One
	-- rod-length socket per corner line locks the door's rod centered.
	["30179.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(32, 72, 6),
			direction = Vector3.new(0, -1, 0),
			length = 136,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(32, 72, -6),
			direction = Vector3.new(0, -1, 0),
			length = 136,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-32, 72, 6),
			direction = Vector3.new(0, -1, 0),
			length = 136,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-32, 72, -6),
			direction = Vector3.new(0, -1, 0),
			length = 136,
		},
	},
	-- Door 1x4x6 with Stud Handle (newer mold): short r2.5 end pins at
	-- y 6..8 and 132..134 on the hinge edge, modeled as one pin line.
	["60623.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(-1, 70, 0),
			direction = Vector3.new(0, -1, 0),
			length = 128,
		},
	},
	-- Door 1x4x6 Frame (newer mold): r2.5 bores top (0..4) and bottom
	-- (136..140) at both sides, single z=5 line.
	["60596.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(32, 70, 5),
			direction = Vector3.new(0, -1, 0),
			length = 132,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-32, 70, 5),
			direction = Vector3.new(0, -1, 0),
			length = 132,
		},
	},
	-- Door 2x6x7 with Four Panes: r2.5 capped hinge rod on the door
	-- edge, spanning y -75..75 about the centered origin.
	["4072.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 0, 0),
			direction = Vector3.new(0, -1, 0),
			length = 150,
		},
	},
	-- Door 2x6x7 Frame: r2 corner rails (y 14..160 at x=+-48, z=-10)
	-- with retention nubs grip the door rod; matched length seats the
	-- rod between the top rail (y=12) and the sill.
	["4071.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(48, 87, -10),
			direction = Vector3.new(0, -1, 0),
			length = 150,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-48, 87, -10),
			direction = Vector3.new(0, -1, 0),
			length = 150,
		},
	},
	-- Door 2x4x5: r2.5 hinge rod (y 0..104 core + squashed hemisphere
	-- caps) along the door edge.
	["4131.dat"] = {
		{
			type = "HingePin",
			position = Vector3.new(0, 52, 0),
			direction = Vector3.new(0, -1, 0),
			length = 106.5,
		},
	},
	-- Door 2x4x5 Frame: r2 corner bores at (+-28, 4..8 / 112..116, -14).
	-- Matched length seats the door rod's caps in both bores.
	["4130.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(28, 60, -14),
			direction = Vector3.new(0, -1, 0),
			length = 106.5,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-28, 60, -14),
			direction = Vector3.new(0, -1, 0),
			length = 106.5,
		},
	},
	-- Door 1x6x10 Frame: retention posts at both corner pairs bracket
	-- the door rod's tips — the frame grips the rod at its ends, and
	-- either side can carry the door. Same length as the rod so the
	-- axial rule locks the mate centered.
	["670.dat"] = {
		{
			type = "HingeSocket",
			position = Vector3.new(46.5, -112.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 213,
		},
		{
			type = "HingeSocket",
			position = Vector3.new(-46.5, -112.5, 0),
			direction = Vector3.new(0, -1, 0),
			length = 213,
		},
	},
	-- Tile 1x1 with Clip: hand-built C-clip (5-16 arc prongs at z=+-4,
	-- radius 4, arc center y=-6): grips a horizontal bar along Z.
	["2555.dat"] = {
		{ type = "Clip", position = Vector3.new(0, -6, 0), direction = Vector3.new(0, 0, 1), length = 8 },
	},
	-- Minifig torso: the neck post is a plain r6 (stud-radius) post.
	-- The Stud sits at the TORSO TOP plane (y=0), not the collar: a
	-- head's bottom pocket then seats flush at y=0, matching the
	-- official LDraw assembly convention (head origin at torso -24).
	["973.dat"] = {
		{ type = "Stud", position = Vector3.zero, direction = Vector3.new(0, -1, 0) },
	},
	-- Minifig legs: one stud-cell socket under each foot.
	["3816.dat"] = {
		{ type = "Pocket", position = Vector3.new(-10, 28, 0), direction = Vector3.new(0, 1, 0) },
	},
	["3817.dat"] = {
		{ type = "Pocket", position = Vector3.new(10, 28, 0), direction = Vector3.new(0, 1, 0) },
	},
	-- Minifig head (modern id; 3626/3626a flatten through here or share
	-- the construction): deep r6 neck bore opening at the bottom (y=24).
	-- The top stud is a real stud2a primitive and detects normally.
	["3626b.dat"] = {
		{ type = "Pocket", position = Vector3.new(0, 24, 0), direction = Vector3.new(0, 1, 0) },
	},
	["3626a.dat"] = {
		{ type = "Pocket", position = Vector3.new(0, 24, 0), direction = Vector3.new(0, 1, 0) },
	},
} :: { [string]: { Override } }

-- Classify a normalized reference name ("s/3001s01.dat", "stud.dat", ...).
function connectorPrimitives.classify(fileName: string): Spec?
	local base = fileName:match("([^/]+)$") or fileName
	local exact = kSpecs[base]
	if exact ~= nil then
		return exact
	end
	-- Stud families are safe to match by prefix (stug* stud groups don't
	-- collide: recursion expands them to individual studs).
	if base:match("%.dat$") ~= nil then
		if base:sub(1, 5) == "stud3" then
			return { type = "Pin", geometry = "rim" }
		elseif base:sub(1, 5) == "stud4" then
			return { type = "Tube", geometry = "rim" }
		elseif base:sub(1, 4) == "stud" then
			return { type = "Stud", geometry = "mouth" }
		end
	end
	return nil
end

-- Bars have no dedicated primitive: they are plain radius-4 cylinders (the
-- LEGO bar/grip standard). The same radius keys the FEMALE side: a
-- radius-4 cylinder rendered inside-out (BFC-inverted) is a bar-sized
-- bore, e.g. the hollow center of a Technic pin. Checked against the
-- accumulated transform; the caller supplies the accumulated inversion.
local kBarCylinders: { [string]: boolean } = {
	["4-4cyli.dat"] = true,
	["4-4cylc.dat"] = true,
}
local kBarRadiusMin = 3.8
local kBarRadiusMax = 4.2
local kBarMinLength = 8

-- Bore segments may be tiny arc fragments (slotted pins chop the bore
-- into pieces as short as ~1.5 LDU); stray fragments are culled after
-- merging instead (BarHoles shorter than kBarMinLength are dropped).
local kBoreMinSegmentLength = 1

local function isBarRadius(transform: CFrame, minLength: number): boolean
	local radiusX = transform.XVector.Magnitude
	local radiusZ = transform.ZVector.Magnitude
	return radiusX >= kBarRadiusMin
		and radiusX <= kBarRadiusMax
		and radiusZ >= kBarRadiusMin
		and radiusZ <= kBarRadiusMax
		and transform.YVector.Magnitude >= minLength
end

connectorPrimitives.kBarMinLength = kBarMinLength

-- A cavity box placement produces a GRID of anti-stud pocket cells when
-- its interior is stud-pitched: from a single 1x1 pocket (clip plates,
-- 1x1 bricks: half-extents ~6-10) up to multi-cell underside grips (a
-- 1x2 tile's inner box5 is 16x6 half-extents -> 2x1 cells; a 2x4 brick's
-- interior shell is 36x16 -> 4x2 cells that dedup against its
-- tube-derived sockets). Returns cell counts along local X/Z, or nil for
-- non-pocket cavities.
local kCavityDepthMax = 26 -- brick height + slack
local kCavityMaxCellsPerAxis = 6

function connectorPrimitives.cavityCells(transform: CFrame): (number?, number?)
	if transform.YVector.Magnitude > kCavityDepthMax then
		return nil, nil
	end
	local function cells(halfExtent: number): number?
		if halfExtent < 5.5 then
			return nil
		elseif halfExtent <= 10.5 then
			return 1
		end
		local count = math.round(halfExtent / 10)
		if count < 2 or count > kCavityMaxCellsPerAxis then
			return nil
		end
		-- Cell centers must land on the stud grid.
		if math.abs(halfExtent - count * 10) > 4.5 then
			return nil
		end
		return count
	end
	local cellsX = cells(transform.XVector.Magnitude)
	local cellsZ = cells(transform.ZVector.Magnitude)
	if cellsX == nil or cellsZ == nil then
		return nil, nil
	end
	return cellsX, cellsZ
end

-- Male bar: full cylinders only, right-side out.
function connectorPrimitives.isBarSegment(fileName: string, transform: CFrame): boolean
	local base = fileName:match("([^/]+)$") or fileName
	if not kBarCylinders[base] then
		return false
	end
	return isBarRadius(transform, kBarMinLength)
end

-- Female bar bore: any cylinder section at bar radius, including partial
-- arcs (slotted pin bores are built from sections like 3-8cyli) and open
-- cylinders (cylo: minifig hand C-grips and other hand-built clips wrap
-- a bar with an inverted r4 cylo arc). Only meaningful when the
-- accumulated rendering is inverted.
function connectorPrimitives.isBoreCylinder(fileName: string, transform: CFrame): boolean
	local base = fileName:match("([^/]+)$") or fileName
	if
		base:match("^%d+%-%d+cyli%.dat$") == nil
		and base:match("^%d+%-%d+cylc%.dat$") == nil
		and base:match("^%d+%-%d+cylo%.dat$") == nil
	then
		return false
	end
	return isBarRadius(transform, kBoreMinSegmentLength)
end

-- Pin-hole bores: inverted radius-6 cylinder sections (hand-built pin
-- and axle holes on gears like 3648a carve their bores this way).
-- Fragments merge; leftovers shorter than a useful bore get culled.
local kPinBoreRadiusMin = 5.7
local kPinBoreRadiusMax = 6.3
local kPinBoreMinSegmentLength = 4

function connectorPrimitives.isPinBoreCylinder(fileName: string, transform: CFrame): boolean
	local base = fileName:match("([^/]+)$") or fileName
	if base:match("^%d+%-%d+cyli%.dat$") == nil and base:match("^%d+%-%d+cylc%.dat$") == nil then
		return false
	end
	local radiusX = transform.XVector.Magnitude
	local radiusZ = transform.ZVector.Magnitude
	return radiusX >= kPinBoreRadiusMin and radiusX <= kPinBoreRadiusMax
		and radiusZ >= kPinBoreRadiusMin and radiusZ <= kPinBoreRadiusMax
		and transform.YVector.Magnitude >= kPinBoreMinSegmentLength
end

-- Towball socket cups: INVERTED radius-8 cylinder segments (steering
-- links like 2739a model the cup as a cylindrical pocket the r8 ball
-- seats in; ball center = segment center). Technic pin holes also
-- contain inverted r8 channel sections — findConnections suppresses
-- candidates coaxial with a detected PegHole/AxleHole.
local kSocketCupRadiusMin = 7.6
local kSocketCupRadiusMax = 8.4
local kSocketCupMinLength = 8

function connectorPrimitives.isTowballSocketCylinder(fileName: string, transform: CFrame): boolean
	local base = fileName:match("([^/]+)$") or fileName
	if base:match("^%d+%-%d+cyli%.dat$") == nil and base:match("^%d+%-%d+cylc%.dat$") == nil then
		return false
	end
	local radiusX = transform.XVector.Magnitude
	local radiusZ = transform.ZVector.Magnitude
	return radiusX >= kSocketCupRadiusMin and radiusX <= kSocketCupRadiusMax
		and radiusZ >= kSocketCupRadiusMin and radiusZ <= kSocketCupRadiusMax
		and transform.YVector.Magnitude >= kSocketCupMinLength
end

-- Towballs are radius-8 spheres (verified: 3184/2508/2736 and
-- joint8ball all place N-Msphe sections at uniform scale 8, ball center
-- at the placement origin).
local kTowballRadiusMin = 7.6
local kTowballRadiusMax = 8.4

function connectorPrimitives.isTowballSphere(fileName: string, transform: CFrame): boolean
	local base = fileName:match("([^/]+)$") or fileName
	if base:match("^%d+%-%d+sphe%.dat$") == nil then
		return false
	end
	local radiusX = transform.XVector.Magnitude
	local radiusY = transform.YVector.Magnitude
	local radiusZ = transform.ZVector.Magnitude
	return radiusX >= kTowballRadiusMin and radiusX <= kTowballRadiusMax
		and radiusY >= kTowballRadiusMin and radiusY <= kTowballRadiusMax
		and radiusZ >= kTowballRadiusMin and radiusZ <= kTowballRadiusMax
end

return connectorPrimitives
