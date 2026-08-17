--!strict

-- Composite parts: assemblies of separate rigid meshes that are always
-- used together and drag as ONE unit, but keep their segments separate
-- with curated articulation info so the eventual joint graph can rotate
-- them (hinges, swivels, turntables).
--
-- Keyed by the LDraw Shortcut assembly file that places the segments
-- (e.g. 73983 = Hinge Plate 1x4 Complete = 2429 base + 2430 top, both at
-- identity with the swivel boss at the assembly origin). `resolve`
-- redirects the individual segment ids (and legacy assembly ids) to the
-- assembly, since the halves are never used separately.

export type Joint = {
	type: string, -- "Hinge"
	position: Vector3, -- assembly space (LDU)
	axis: Vector3, -- articulation axis (LDraw space, unit)
	-- Segment indices (1-based, assembly ref order) this joint connects;
	-- nil = all segments. Multi-joint composites (minifig legs) have
	-- independent joints sharing an axis.
	segments: { number }?,
}

export type VirtualSegment = {
	ref: string,
	transform: CFrame, -- assembly space (LDraw)
}

export type Composite = {
	joints: { Joint },
	-- Virtual assembly: for pairs with no LDraw assembly file, the
	-- segments and transforms are curated inline; `name`/`partNumber`
	-- label the imported Model.
	segments: { VirtualSegment }?,
	name: string?,
	partNumber: string?,
}

local compositeParts = {}

compositeParts.composites = {
	-- Hinge Plate 1 x 4 (2429 base + 2430 top): swivel about the vertical
	-- axis through the round boss at the assembly origin.
	["73983.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Turntable 4 x 4 x 2 Locking (30516 grooved base + 30658 top):
	-- swivel about the vertical center axis.
	["30516c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 8, 0), axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Hinge 1 x 2 (3937 base + 3938 top): tilts about a horizontal axis
	-- through the finger knuckle (axis position approximate: knuckle
	-- center sits above the base plate at the joint line).
	["3937c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, -8, 0), axis = Vector3.new(1, 0, 0) },
		},
	},
	-- Hinge Brick 1 x 8 (652 male + 653 female + 654 joining ring):
	-- swivels about the vertical axis at the assembly origin.
	["652c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Turntable 2 x 2 Plate (3680 base + 3679 top).
	["3680c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Turntable 4 x 4 (3403 base + 3404 top).
	["3403c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Minifig hips and legs (3815 hips + 3816 right + 3817 left): each
	-- leg swings independently about the shared hip pin axis at y=12.
	["3815c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 12, 0), axis = Vector3.new(1, 0, 0), segments = { 1, 2 } },
			{ type = "Hinge", position = Vector3.new(0, 12, 0), axis = Vector3.new(1, 0, 0), segments = { 1, 3 } },
		},
	},
	-- Minifig torso with arms and hands (973 + 3818 + 3819 + 2x 3820):
	-- shoulders swing about the lateral axis at the arm mount points;
	-- hands spin about their wrist axes (the hand transforms' Z columns
	-- from the official 973c01 assembly).
	["973c01.dat"] = {
		joints = {
			-- Shoulder pins tilt with the torso's sloped sides: the axis
			-- is the arm transform's X column, not world X.
			{ type = "Hinge", position = Vector3.new(-15.552, 9, 0), axis = Vector3.new(0.985, 0.17, 0), segments = { 1, 2 } },
			{ type = "Hinge", position = Vector3.new(15.552, 9, 0), axis = Vector3.new(0.985, -0.17, 0), segments = { 1, 3 } },
			{
				type = "Hinge",
				position = Vector3.new(-23.6904, 26.774, -9.8982),
				axis = Vector3.new(0.1202, -0.6964, 0.707),
				segments = { 2, 4 },
			},
			{
				type = "Hinge",
				position = Vector3.new(23.6904, 26.774, -9.8982),
				axis = Vector3.new(-0.1202, -0.6964, 0.707),
				segments = { 3, 5 },
			},
		},
	},
	-- Technic Turntable Type 1 (2855 top + 2856 bottom): no LDraw
	-- assembly file exists — a VIRTUAL assembly. Both parts share the
	-- origin (the top's lower ring nests in the bottom's collar) and
	-- spin about the vertical axis.
	["virtual:2855.dat"] = {
		name = "Technic Turntable Type 1",
		partNumber = "2855c",
		segments = {
			{ ref = "2855.dat", transform = CFrame.identity },
			{ ref = "2856.dat", transform = CFrame.identity },
		},
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 7, 0), axis = Vector3.new(0, -1, 0) },
		},
	},
} :: { [string]: Composite }

local kRedirects: { [string]: string } = {
	["2429.dat"] = "73983.dat",
	["2430.dat"] = "73983.dat",
	["2429c01.dat"] = "73983.dat",
	["3937.dat"] = "3937c01.dat",
	["3938.dat"] = "3937c01.dat",
	["652.dat"] = "652c01.dat",
	["653.dat"] = "652c01.dat",
	["654.dat"] = "652c01.dat",
	["3679.dat"] = "3680c01.dat",
	["3680.dat"] = "3680c01.dat",
	["3680c02.dat"] = "3680c01.dat",
	["3403.dat"] = "3403c01.dat",
	["3404.dat"] = "3403c01.dat",
	["30516.dat"] = "30516c01.dat",
	["30658.dat"] = "30516c01.dat",
	["30516c02.dat"] = "30516c01.dat",
	["3815.dat"] = "3815c01.dat",
	["3816.dat"] = "3815c01.dat",
	["3817.dat"] = "3815c01.dat",
	["970.dat"] = "3815c01.dat",
	["971.dat"] = "3815c01.dat",
	["972.dat"] = "3815c01.dat",
	["970c00.dat"] = "3815c01.dat",
	["973.dat"] = "973c01.dat",
	["3818.dat"] = "973c01.dat",
	["3819.dat"] = "973c01.dat",
	["981.dat"] = "973c01.dat",
	["982.dat"] = "973c01.dat",
	["2855.dat"] = "virtual:2855.dat",
	["2856.dat"] = "virtual:2855.dat",
}

local function normalize(ref: string): string
	return (ref:lower():gsub("\\", "/"))
end

-- Resolve a ref to the composite assembly it belongs to (or itself).
function compositeParts.resolve(ref: string): string
	local normalized = normalize(ref)
	return kRedirects[normalized] or normalized
end

function compositeParts.get(ref: string): Composite?
	return compositeParts.composites[normalize(ref)]
end

return compositeParts
