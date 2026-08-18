--!strict

-- Integration: real findConnections output for curated part PAIRS fed
-- straight into the snap solver, asserting the assembled placement.
-- Catches hand-derived curation frame errors (wrong position, flipped
-- axis, mismatched length) that per-part count specs can't see.
--
-- findSnapPlacement is space-agnostic, so both sides stay in LDraw
-- part space (no Roblox conversion involved).

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.Parent.LDraw.LDrawLibrary)
local findConnections = require(script.Parent.Parent.LDraw.findConnections)
local findSnapPlacement = require(script.Parent.findSnapPlacement)

local function toConnectors(connections: { any }): { any }
	local connectors = {}
	for _, connection in connections do
		table.insert(connectors, {
			kind = connection.type,
			position = connection.position,
			direction = connection.direction,
			length = connection.length,
			oneSided = connection.oneSided,
			radius = connection.radius,
		})
	end
	return connectors
end

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	-- Each case: drag part, world part (at identity), expected drag
	-- origin position after snapping from a slightly-offset start.
	local kCases: { { name: string, drag: string, world: string, expected: Vector3 } } = {
		{
			name = "oven door seats on the stove (same authored frame)",
			drag = "843.dat",
			world = "841.dat",
			expected = Vector3.new(0, 0, 0),
		},
		{
			name = "cupboard door hangs in cabinet 4532",
			drag = "4533.dat",
			world = "4532.dat",
			expected = Vector3.new(24, 4, -17),
		},
		{
			name = "drawer slides home in cabinet 2 (top slot)",
			drag = "3.dat",
			world = "2.dat",
			expected = Vector3.new(0, 8, 0),
		},
		{
			name = "door 3644 hangs in frame 30179",
			drag = "3644.dat",
			world = "30179.dat",
			expected = Vector3.new(32, 4, 6),
		},
		{
			name = "track straights join end to end",
			drag = "53401.dat",
			world = "53401.dat",
			expected = Vector3.new(320, 0, 0),
		},
		{
			name = "homemaker door hangs in cupboard 837 (near side)",
			drag = "838.dat",
			world = "837.dat",
			expected = Vector3.new(0, 0, 0),
		},
		{
			name = "shutter hangs on window 3853's lower tab",
			drag = "3856.dat",
			world = "3853.dat",
			expected = Vector3.new(-40, -0.5, -12),
		},
		{
			name = "monorail straights join end to end",
			drag = "2670.dat",
			world = "2670.dat",
			expected = Vector3.new(160, 0, 0),
		},
		{
			name = "coaster curve joins a straight (no rotation end)",
			drag = "25061.dat",
			world = "25059.dat",
			expected = Vector3.new(160, 0, -240),
		},
		{
			name = "tyre seats on its rim (radius-gated)",
			drag = "3641.dat",
			world = "4624.dat",
			expected = Vector3.new(0, 0, 0),
		},
		{
			-- Ramp's level end onto a straight's +x end: ramp origin
			-- lands at (160+10, 0, 0).
			name = "coaster ramp joins a straight at ground level",
			drag = "26561.dat",
			world = "25059.dat",
			expected = Vector3.new(170, 0, 0),
		},
		{
			-- Sliding mate: start with no offset along the bar axis
			-- (the solver correctly preserves along-axis position).
			name = "hinge hook arm latches over the base bar",
			drag = "2651.dat",
			world = "2650.dat",
			expected = Vector3.new(-8.8, 8, 0),
			startOffset = Vector3.new(3, -2, 0),
		},
		{
			-- Both parts put their click pivot at local (30,10,0), so
			-- with identity rotation the origins coincide (the physical
			-- assembly adds a 180-degree yaw, which the solver leaves
			-- to the user). Verifies the dimple-center pivots mate.
			name = "click finger locks into the fork at the dimple",
			drag = "30364.dat",
			world = "30365.dat",
			expected = Vector3.new(0, 0, 0),
			startOffset = Vector3.new(0, -2, 1),
		},
	}

	for _, case in kCases do
		t.test(case.name, function()
			local world = toConnectors(findConnections(library, case.world) :: any)
			local drag = toConnectors(findConnections(library, case.drag) :: any)
			local start = CFrame.new(case.expected + ((case :: any).startOffset or Vector3.new(3, -2, 1)))
			local snap = findSnapPlacement(start, drag :: any, world :: any, 10) :: any
			t.expect(snap).toBeTruthy()
			local position = snap.cframe.Position
			t.expect(position.X).toBeCloseTo(case.expected.X, 0.01)
			t.expect(position.Y).toBeCloseTo(case.expected.Y, 0.01)
			t.expect(position.Z).toBeCloseTo(case.expected.Z, 0.01)
		end)
	end
end
