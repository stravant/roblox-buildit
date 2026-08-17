--!strict

-- Shared types for the LDraw library.
--
-- Coordinate conventions: All geometry is kept in LDraw part space until
-- explicitly converted (see RobloxConvert). LDraw units (LDU): 1 brick module
-- (stud-to-stud spacing) = 20 LDU, brick height = 24 LDU, plate height = 8 LDU.
-- LDraw is right-handed with -Y as "up" (studs point in -Y).

-- A type-1 line: reference to a subfile with a (possibly scaled/mirrored)
-- affine transform.
export type SubfileRef = {
	colorCode: number,
	transform: CFrame,
	fileName: string, -- normalized: lowercase, forward slashes
	invert: boolean, -- preceded by 0 BFC INVERTNEXT
}

export type Triangle = {
	colorCode: number,
	a: Vector3,
	b: Vector3,
	c: Vector3,
}

export type Quad = {
	colorCode: number,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
}

export type Line = {
	colorCode: number,
	a: Vector3,
	b: Vector3,
}

export type ParsedFile = {
	description: string?, -- first comment line of the file
	name: string?, -- 0 Name: header
	fileType: string?, -- 0 !LDRAW_ORG header (Part, Subpart, Primitive, ...)
	-- true = BFC CERTIFY, false = BFC NOCERTIFY, nil = no BFC statement.
	-- Triangles/quads in certified files are normalized to CCW winding
	-- (viewed from outside) at parse time.
	certified: boolean?,
	subfiles: { SubfileRef },
	triangles: { Triangle },
	quads: { Quad },
	-- Type 2 edge lines: drawn along SHARP edges (authoring intent).
	lines: { Line },
	-- Type 5 conditional lines (endpoints only, control points dropped):
	-- drawn along SMOOTH edges of curved surfaces.
	condLines: { Line },
	parseErrorCount: number,
}

-- Returns file content for a library-relative path like "parts/3001.dat" or
-- "p/stud.dat", or nil if no such file exists.
export type FileProvider = (path: string) -> string?

export type FlatTriangle = {
	colorCode: number,
	a: Vector3,
	b: Vector3,
	c: Vector3,
}

export type FlatEdge = {
	a: Vector3,
	b: Vector3,
}

export type FlatMesh = {
	triangles: { FlatTriangle },
	-- Transformed type 2 / type 5 lines: authoritative sharp/smooth edge
	-- markings for normal generation.
	sharpEdges: { FlatEdge },
	smoothEdges: { FlatEdge },
	-- True if any geometry came from a non-BFC-certified file (that geometry
	-- is emitted double-sided since its winding is unknown).
	hasUncertified: boolean,
	missingFiles: { string },
	boundsMin: Vector3,
	boundsMax: Vector3,
}

-- Raw connectors discovered in a part's composition tree:
--  - Stud: male stud on top ("stud.dat" family)
--  - Tube: hollow underside tube ("stud4*"), grips 4 studs at (+-10, +-10)
--  - Pin: solid underside stud tube ("stud3*") on 1-wide parts
--  - PegHole: Technic pin hole (through-holes are one connector at the
--    hole center with length = depth)
--  - AxleHole: axle-shaped hole (center + axis + length)
--  - Axle: axle shaft (center + axis + length)
--  - TechnicPin: Technic pin half (center + axis + length)
--  - Bar: radius-4 rod/grip (center + axis + length)
--  - Clip: clip that grips a Bar (position + grip axis + length)
--  - Pocket: stud-sized open cavity (1x1 undersides, clip plates) —
--    consumed by deriveSockets, not annotated directly
--  - HollowStud: the bar-sized bore of a hollow stud (stud2*), accepts a
--    Bar down the stud axis
--  - BarHole: bar-sized through-bore (inverted radius-4 cylinder), e.g.
--    the hollow center of a Technic pin
--  - Towball / TowballSocket: ball joint halves (radius-8 sphere /
--    joint8socket cup) — mate position-only, rotation free
--  - SlipAxle / SlipRing: the transmission slip interface (driving ring
--    riding splined on an axle joiner) — curated via partOverrides
--  - HingePin / HingeSocket: the classic tiny-pin hinge system (shutter
--    nubs, door hinge rods r~2-3 vs frame holes/channels)
export type ConnectionType =
	"Stud" | "Tube" | "Pin" | "PegHole" | "AxleHole" | "Axle" | "TechnicPin" | "Bar" | "Clip"
	| "Pocket" | "HollowStud" | "BarHole" | "Towball" | "TowballSocket" | "SlipAxle" | "SlipRing"
	| "HingePin" | "HingeSocket" | "HingeFinger" | "ClickFinger" | "ClickFork" | "ArmFinger"
	| "TyreBore" | "RimSeat" | "Magnet" | "WheelPin" | "WheelHole"
	| "SlideRail" | "SlideGroove" | "TrackEnd" | "CoasterEnd" | "MonoEnd" | "MonoRampJoint"
	| "MinidollHinge"

export type Connection = {
	type: ConnectionType,
	primitive: string, -- e.g. "stud.dat" (directory stripped)
	-- Point connectors (Stud/Tube/Pin, unpaired PegHole mouths): point on
	-- the mating plane. Axial connectors: center of the element.
	-- (Part space, LDU.)
	position: Vector3,
	-- Point connectors: unit vector OUT of the part toward the mating part.
	-- Axial connectors: the element axis (sign arbitrary - they mate in
	-- either orientation).
	direction: Vector3,
	transform: CFrame, -- full accumulated transform of the primitive ref
	-- Extent along `direction` for axial connectors (LDU); nil for point
	-- connectors and blind (unpaired) PegHole mouths.
	length: number?,
	-- Mating radius (LDU) for size-keyed interfaces (TyreBore/RimSeat):
	-- candidates only mate when radii agree within tolerance.
	radius: number?,
	-- Axial female connectors that are open only toward `direction` (blind
	-- bores like hollow studs): a mating element enters from that side and
	-- bottoms out at the far end.
	oneSided: boolean?,
}

-- A derived "anti-stud" cell: a place on the part where a stud of another
-- part can be gripped. Derived from Tube/Pin connections.
export type Socket = {
	position: Vector3, -- center of the stud-sized cell on the mating plane
	direction: Vector3, -- points OUT of the part (down for an upright brick)
}

-- Input cell for region coalescing: one stud or one anti-stud cell.
export type RegionCell = {
	kind: string, -- "Stud" | "Socket"
	position: Vector3,
	direction: Vector3,
}

-- A rectangular grid of same-kind connection cells, the compact
-- representation used for annotation (one region instead of MxN cells).
-- The general model is connection type + frame + dimension: stud fields
-- have discrete counts at a fixed pitch; future extended connectors
-- (bars, axles) will carry a continuous length along an axis instead.
export type ConnectionRegion = {
	kind: string, -- "Stud" | "Socket"
	-- Region center. YVector = mating direction (toward the mating part),
	-- XVector/ZVector = the grid axes.
	frame: CFrame,
	countX: number, -- cells along frame XVector
	countZ: number, -- cells along frame ZVector
	pitch: number, -- distance between adjacent cells (LDU; 20 = one module)
}

export type ColorDef = {
	code: number,
	name: string,
	color: Color3,
	edge: Color3?,
	alpha: number?, -- 0-255, LDraw convention (255 = opaque); nil = opaque
}

return {}
