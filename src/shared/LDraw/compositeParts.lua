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
	type: string, -- "Hinge" (rotates about axis) | "Slider" (translates along axis)
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
	-- Classic vehicle hinge plates (pivot pin 313 + top 314d/e + base):
	-- refs order in the assemblies is pin(1), top(2), base(3); the top
	-- swings about the pin's rod line at the assembly origin, axis X.
	["3149dc01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0), segments = { 3, 2 } },
		},
	},
	["3149ec01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0), segments = { 3, 2 } },
		},
	},
	["3324dc01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0), segments = { 3, 2 } },
		},
	},
	["3324ec01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0), segments = { 3, 2 } },
		},
	},
	-- Turntable 4x4 dimpled/round variants: vertical swivel like 3403c01.
	["3404cc01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	["3404ec01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Train coupling hook on plate 3x2: the hook swings about the
	-- vertical axis through its round base mount. Both authored poses
	-- share the joint.
	["3176c01-f1.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 9.5, -29.5), axis = Vector3.new(0, -1, 0) },
		},
	},
	["3176c01-f2.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 9.5, -29.5), axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Crane slope brick: the hook (3136) dangles from the molded arm's
	-- tip and swings across the arm.
	["3135c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, -19, 63), axis = Vector3.new(1, 0, 0) },
		},
	},
	-- Container Cupboard 2x6x7 with both doors: each door swings on its
	-- side rail's vertical hinge line (doors are refs 2 and 3).
	["2042c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(-52, 0, -16), axis = Vector3.new(0, -1, 0), segments = { 1, 2 } },
			{ type = "Hinge", position = Vector3.new(52, 0, -16), axis = Vector3.new(0, -1, 0), segments = { 1, 3 } },
		},
	},
	-- Shock absorber 2x1x2.333 (spring 70864 + piston 2606 + body
	-- 2605): the piston slides vertically; the spring stays with the
	-- body segment visually.
	["2605c01.dat"] = {
		joints = {
			{ type = "Slider", position = Vector3.new(0, 0, 10), axis = Vector3.new(0, -1, 0), segments = { 3, 2 } },
		},
	},
	-- Modern pneumatic cylinders (body + piston rod, both authored
	-- poses): the rod slides along the cylinder axis.
	["19475-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	["19475-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	["19476-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	["19476-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	["19478-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	["19478-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0) } },
	},
	-- Train level crossing gates (base 814 + crossbar 815c0x): the
	-- crossbar swings 90 degrees about X through its mount at (0,-28,0)
	-- (closed lies flat, open stands up — both authored poses).
	["814c01-f1.dat"] = {
		joints = { { type = "Hinge", position = Vector3.new(0, -28, 0), axis = Vector3.new(1, 0, 0) } },
	},
	["814c01-f2.dat"] = {
		joints = { { type = "Hinge", position = Vector3.new(0, -28, 0), axis = Vector3.new(1, 0, 0) } },
	},
	["814c02-f1.dat"] = {
		joints = { { type = "Hinge", position = Vector3.new(0, -28, 0), axis = Vector3.new(1, 0, 0) } },
	},
	["814c02-f2.dat"] = {
		joints = { { type = "Hinge", position = Vector3.new(0, -28, 0), axis = Vector3.new(1, 0, 0) } },
	},
	-- Technic shock absorbers: rod slides in the cylinder, spring stays
	-- with the cylinder segment. 9L: cylinder(1) rod(2); 6.5L: rod(1)
	-- cylinder(2).
	["41475-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 1, 2 } } },
	},
	["41475-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 1, 2 } } },
	},
	["41838.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 2, 1 } } },
	},
	-- Technic linear actuators: the piston assembly extends along Z
	-- from the body; the axle bush input coupling stays with the body.
	["40918-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, 0, 1), segments = { 2, 3 } } },
	},
	["40918-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, 0, 1), segments = { 2, 3 } } },
	},
	["43097-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, 0, 1), segments = { 2, 3 } } },
	},
	["43097-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, 0, 1), segments = { 2, 3 } } },
	},
	-- Forklift 2x7: the forks (1) ride the mast rails (2) vertically;
	-- the chain detail stays with the mast.
	["3430c00-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 2, 1 } } },
	},
	["3430c00-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 2, 1 } } },
	},
	-- Classic 2x2 pneumatics (piston rod 337 + cap/cylinder/base body,
	-- pumps add a spring): the rod slides on the vertical axis; the
	-- joint links cylinder(3) to rod(1) and the other pieces stay with
	-- the body.
	["127c01-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	["127c01-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	["127c02-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	["127c02-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	["127c03-f1.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	["127c03-f2.dat"] = {
		joints = { { type = "Slider", position = Vector3.zero, axis = Vector3.new(0, -1, 0), segments = { 3, 1 } } },
	},
	-- Pneumatic valve: the lever toggles +-30 degrees about the X axis
	-- through the origin (all three authored positions).
	["19474-f1.dat"] = {
		joints = { { type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0) } },
	},
	["19474-f2.dat"] = {
		joints = { { type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0) } },
	},
	["19474-f3.dat"] = {
		joints = { { type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0) } },
	},
	-- Tipper Bucket 8x12 (click hinge plate 44570 + bucket 18926): the
	-- bucket tips on the plate's clh fork line, which lands on the X
	-- axis through the assembly origin.
	["19001.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(1, 0, 0) },
		},
	},
	-- Container lifting grab: two identical halves scissor about the
	-- vertical pivot at the origin (all three authored poses).
	["2648c01-f1.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	["2648c01-f2.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	["2648c01-f3.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.zero, axis = Vector3.new(0, -1, 0) },
		},
	},
	-- Car steering: the wheel spins on its tilted column (axis = the
	-- wheel placement's local Y in assembly space).
	["3829c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, -26.32, -0.24), axis = Vector3.new(0, 0.6, -0.8) },
		},
	},
	["30640c01.dat"] = {
		joints = {
			{
				type = "Hinge",
				position = Vector3.new(0, -19.799, 11.515),
				axis = Vector3.new(0, 0.707107, -0.707107),
			},
		},
	},
	-- Hinge 1 x 2 (3937 base + 3938 top): tilts about the horizontal
	-- axis through the finger knuckle line at (0, 10, 0) — the tndis
	-- knuckle discs sit at (+-16..20, 10, 0) in the base's frame.
	["3937c01.dat"] = {
		joints = {
			{ type = "Hinge", position = Vector3.new(0, 10, 0), axis = Vector3.new(1, 0, 0) },
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
			{ type = "Hinge", position = Vector3.new(0, 16, 0), axis = Vector3.new(1, 0, 0), segments = { 1, 2 } },
			{ type = "Hinge", position = Vector3.new(0, 16, 0), axis = Vector3.new(1, 0, 0), segments = { 1, 3 } },
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
	-- 313/314d are shared by the 2x5 and 2x9 hinge plates; redirect to
	-- the more common 2x5.
	["313.dat"] = "3149dc01.dat",
	["314d.dat"] = "3149dc01.dat",
	["314e.dat"] = "3149ec01.dat",
	["3149d.dat"] = "3149dc01.dat",
	["3149e.dat"] = "3149ec01.dat",
	["3324d.dat"] = "3324dc01.dat",
	["3324e.dat"] = "3324ec01.dat",
	["3829.dat"] = "3829c01.dat",
	["3829a.dat"] = "3829c01.dat",
	["3828.dat"] = "3829c01.dat",
	["30640.dat"] = "30640c01.dat",
	["30663.dat"] = "30640c01.dat",
	["30640c02.dat"] = "30640c01.dat",
	["3404c.dat"] = "3404cc01.dat",
	["3404bc01.dat"] = "3404cc01.dat",
	["3404cc02.dat"] = "3404cc01.dat",
	["3404e.dat"] = "3404ec01.dat",
	["3404dc01.dat"] = "3404ec01.dat",
	["3176.dat"] = "3176c01-f1.dat",
	["3135.dat"] = "3135c01.dat",
	["3136.dat"] = "3135c01.dat",
	["3135c02.dat"] = "3135c01.dat",
	["3135c03.dat"] = "3135c01.dat",
	["2042c02.dat"] = "2042c01.dat",
	["2042c03.dat"] = "2042c01.dat",
	-- 44570 stays standalone (general hinge plate); only the bucket
	-- redirects into the tipper assembly.
	["18926.dat"] = "19001.dat",
	["19001p01.dat"] = "19001.dat",
	["2648c01.dat"] = "2648c01-f2.dat",
	["2605.dat"] = "2605c01.dat",
	["2606.dat"] = "2605c01.dat",
	["19466c01.dat"] = "19478-f1.dat",
	["19467c01.dat"] = "19478-f1.dat",
	["127.dat"] = "127c01-f1.dat",
	["128.dat"] = "127c01-f1.dat",
	["337.dat"] = "127c01-f1.dat",
	["4701.dat"] = "127c01-f1.dat",
	["814.dat"] = "814c01-f1.dat",
	["815c01.dat"] = "814c01-f1.dat",
	["815c02.dat"] = "814c02-f1.dat",
	["2909.dat"] = "41475-f1.dat",
	["2910.dat"] = "41475-f1.dat",
	["4254.dat"] = "41838.dat",
	["4255.dat"] = "41838.dat",
	["3430.dat"] = "3430c00-f2.dat",
	["3431.dat"] = "3430c00-f2.dat",
	["3430c01-f1.dat"] = "3430c00-f1.dat",
	["3430c02-f1.dat"] = "3430c00-f1.dat",
	["3430c03-f1.dat"] = "3430c00-f1.dat",
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
