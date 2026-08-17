--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local findSnapPlacement = require(script.Parent.findSnapPlacement)

-- Connector layout of an imported 2x4 brick (part-local, pivot at bbox
-- center, size 4 x 1.4 x 2): studs on the stud base plane y=+0.5, sockets
-- on the bottom face y=-0.7.
local function brickConnectors(): { any }
	local connectors = {}
	for _, x in { -1.5, -0.5, 0.5, 1.5 } do
		for _, z in { -0.5, 0.5 } do
			table.insert(connectors, {
				kind = "Stud",
				position = Vector3.new(x, 0.5, z),
				direction = Vector3.new(0, 1, 0),
			})
			table.insert(connectors, {
				kind = "Socket",
				position = Vector3.new(x, -0.7, z),
				direction = Vector3.new(0, -1, 0),
			})
		end
	end
	return connectors
end

local function toWorld(connectors: { any }, cframe: CFrame): { any }
	local world = {}
	for _, connector in connectors do
		table.insert(world, {
			kind = connector.kind,
			position = cframe:PointToWorldSpace(connector.position),
			direction = cframe:VectorToWorldSpace(connector.direction),
		})
	end
	return world
end

-- A brick resting on the ground (bottom at y=0) has its center at y=0.7;
-- a brick stacked directly on it has its center at y=1.9.
local kGroundBrick = CFrame.new(0, 0.7, 0)
local kStackedY = 1.9

return function(t: TestTypes.TestContext)
	local kMaxSnap = 1.25

	t.test("snaps an aligned stack and mates all 8 pairs", function()
		local world = toWorld(brickConnectors(), kGroundBrick)
		local ghost = CFrame.new(0.2, 2.0, -0.1)
		local snap = findSnapPlacement(ghost, brickConnectors() :: any, world, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, kStackedY, 0))
		t.expect(#snap.matchedPairs).toBe(8)
	end)

	t.test("snaps an offset stack with partial overlap", function()
		local world = toWorld(brickConnectors(), kGroundBrick)
		local ghost = CFrame.new(1.2, 2.0, 0)
		local snap = findSnapPlacement(ghost, brickConnectors() :: any, world, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(1, kStackedY, 0))
		-- 3x2 stud overlap when shifted one module along the length.
		t.expect(#snap.matchedPairs).toBe(6)
	end)

	t.test("solves translation only, keeping the ghost rotation", function()
		local world = toWorld(brickConnectors(), kGroundBrick)
		local rotation = CFrame.Angles(0, math.pi / 2, 0)
		local ghost = rotation + Vector3.new(0.1, 2.0, 0)
		local snap = findSnapPlacement(ghost, brickConnectors() :: any, world, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, kStackedY, 0))
		t.expect(snap.cframe.XVector).toBeCloseTo(rotation.XVector)
		-- Crossed 2x4s overlap in a 2x2 patch.
		t.expect(#snap.matchedPairs).toBe(4)
	end)

	t.test("returns nil when nothing is in range", function()
		local world = toWorld(brickConnectors(), kGroundBrick)
		local ghost = CFrame.new(0, 8, 0)
		t.expect(findSnapPlacement(ghost, brickConnectors() :: any, world, kMaxSnap)).toBeFalsy()
	end)

	t.test("requires anti-parallel directions", function()
		local world = { { kind = "Stud", position = Vector3.new(0, 1.2, 0), direction = Vector3.new(0, 1, 0) } }
		local sideways = {
			{ kind = "Socket", position = Vector3.new(0, -0.7, 0), direction = Vector3.new(1, 0, 0) },
		}
		local snap = findSnapPlacement(CFrame.new(0, 1.9, 0), sideways :: any, world :: any, kMaxSnap)
		t.expect(snap).toBeFalsy()
	end)

	t.test("requires compatible kinds (no stud-to-stud)", function()
		local world = { { kind = "Stud", position = Vector3.new(0, 1.2, 0), direction = Vector3.new(0, 1, 0) } }
		local studDown = {
			{ kind = "Stud", position = Vector3.new(0, -0.7, 0), direction = Vector3.new(0, -1, 0) },
		}
		local snap = findSnapPlacement(CFrame.new(0, 1.9, 0), studDown :: any, world :: any, kMaxSnap)
		t.expect(snap).toBeFalsy()
	end)

	-- Axial mating (lengths in Roblox studs; 1 module = 1).

	t.test("axle slides in an axle hole within the length difference", function()
		local world = {
			{ kind = "AxleHole", position = Vector3.new(0, 5, 0), direction = Vector3.new(1, 0, 0), length = 1 },
		}
		local axle = {
			{ kind = "Axle", position = Vector3.zero, direction = Vector3.new(1, 0, 0), length = 2 },
		}
		-- Within range: along-axis offset preserved, perpendicular snapped out.
		local snap = findSnapPlacement(CFrame.new(0.3, 5.2, -0.1), axle :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0.3, 5, 0))
		t.expect(#snap.matchedPairs).toBe(1)

		-- Beyond range: clamped to +-(2-1)/2.
		local clamped = findSnapPlacement(CFrame.new(1.1, 5.2, 0), axle :: any, world :: any, kMaxSnap) :: any
		t.expect(clamped).toBeTruthy()
		t.expect(clamped.cframe.Position).toBeCloseTo(Vector3.new(0.5, 5, 0))
		t.expect(#clamped.matchedPairs).toBe(1)
	end)

	t.test("axial mating accepts either axis sign", function()
		local world = {
			{ kind = "AxleHole", position = Vector3.new(0, 5, 0), direction = Vector3.new(1, 0, 0), length = 1 },
		}
		local flipped = {
			{ kind = "Axle", position = Vector3.zero, direction = Vector3.new(-1, 0, 0), length = 2 },
		}
		local snap = findSnapPlacement(CFrame.new(0, 5.2, 0), flipped :: any, world :: any, kMaxSnap)
		t.expect(snap).toBeTruthy()
	end)

	t.test("pin locks centered in a through peghole (equal lengths)", function()
		local world = {
			{ kind = "PegHole", position = Vector3.new(2, 3, 0), direction = Vector3.new(0, 0, 1), length = 1 },
		}
		local pin = {
			{ kind = "TechnicPin", position = Vector3.new(0.5, 0, 0), direction = Vector3.new(0, 0, 1), length = 1 },
		}
		local snap = findSnapPlacement(CFrame.new(1.4, 3.2, 0.4), pin :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		-- Pin connector must land exactly at the hole center.
		t.expect(snap.cframe:PointToWorldSpace(Vector3.new(0.5, 0, 0))).toBeCloseTo(Vector3.new(2, 3, 0))
		t.expect(#snap.matchedPairs).toBe(1)
	end)

	t.test("clip slides along a long bar", function()
		local world = {
			{ kind = "Bar", position = Vector3.new(0, 2, 0), direction = Vector3.new(0, 1, 0), length = 4 },
		}
		local clip = {
			{ kind = "Clip", position = Vector3.zero, direction = Vector3.new(0, 1, 0), length = 0.4 },
		}
		local snap = findSnapPlacement(CFrame.new(0.2, 3, 0), clip :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, 3, 0))

		-- Past the bar end: clamped to the end of the slide range.
		local clamped = findSnapPlacement(CFrame.new(0.2, 4.5, 0), clip :: any, world :: any, kMaxSnap) :: any
		t.expect(clamped).toBeTruthy()
		t.expect(clamped.cframe.Position).toBeCloseTo(Vector3.new(0, 3.8, 0))
	end)

	t.test("axle mates with a peghole (slides through)", function()
		local world = {
			{ kind = "PegHole", position = Vector3.new(0, 5, 0), direction = Vector3.new(0, 0, 1), length = 1 },
		}
		local axle = {
			{ kind = "Axle", position = Vector3.zero, direction = Vector3.new(0, 0, 1), length = 2 },
		}
		local snap = findSnapPlacement(CFrame.new(0.1, 5.2, 0.3), axle :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, 5, 0.3))
		t.expect(#snap.matchedPairs).toBe(1)
	end)

	t.test("bar inserts into a hollow stud and seats flush at the bore floor", function()
		-- Bore center at y=1.3, depth 0.2 (real bore: 4 LDU): floor at 1.2.
		local world = {
			{
				kind = "HollowStud",
				position = Vector3.new(0, 1.3, 0),
				direction = Vector3.new(0, 1, 0),
				length = 0.2,
				oneSided = true,
			},
		}
		local bar = {
			{ kind = "Bar", position = Vector3.new(0, 2, 0), direction = Vector3.new(0, 1, 0), length = 4 },
		}
		local snap = findSnapPlacement(CFrame.new(0.2, 1.5, 0.1), bar :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		-- Perpendicular alignment onto the stud axis; vertical slide kept.
		local barCenter = snap.cframe:PointToWorldSpace(Vector3.new(0, 2, 0))
		t.expect(barCenter.X).toBeCloseTo(0)
		t.expect(barCenter.Z).toBeCloseTo(0)
		t.expect(#snap.matchedPairs).toBe(1)

		-- Pushed down hard: clamps with the bar's end at the bore floor
		-- (bar center = floor + half length = 1.2 + 2 = 3.2), never lower.
		local seated = findSnapPlacement(CFrame.new(0.2, 0, 0.1), bar :: any, world :: any, kMaxSnap) :: any
		t.expect(seated).toBeTruthy()
		local seatedCenter = seated.cframe:PointToWorldSpace(Vector3.new(0, 2, 0))
		t.expect(seatedCenter).toBeCloseTo(Vector3.new(0, 3.2, 0))
	end)

	t.test("prefers a 0-DOF point mate over a closer 1-DOF axial mate", function()
		local world = {
			{ kind = "Socket", position = Vector3.new(0, 5, 0), direction = Vector3.new(0, -1, 0) },
			{ kind = "Clip", position = Vector3.new(1.1, 4.4, 0), direction = Vector3.new(0, 0, 1), length = 0.4 },
		}
		local drag = {
			{ kind = "Stud", position = Vector3.new(0, 0.5, 0), direction = Vector3.new(0, 1, 0) },
			{ kind = "Bar", position = Vector3.new(1, 0, 0), direction = Vector3.new(0, 0, 1), length = 2 },
		}
		-- Bar-to-clip is closer (0.3) than stud-to-socket (~0.41), but the
		-- stud mate removes more freedom and must win.
		local snap = findSnapPlacement(CFrame.new(0.4, 4.4, 0), drag :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, 4.5, 0))
		t.expect(#snap.matchedPairs).toBe(1)
		t.expect(snap.matchedPairs[1].dragIndex).toBe(1)
		t.expect(snap.matchedPairs[1].worldIndex).toBe(1)
	end)

	t.test("equal-length axial locks count as 0 DOF", function()
		-- A peghole with both a sliding axle option and a locking pin
		-- option: the pin (equal lengths, no slide) wins even though the
		-- axle connector is closer.
		local world = {
			{ kind = "PegHole", position = Vector3.new(0, 5, 0), direction = Vector3.new(0, 0, 1), length = 1 },
		}
		local drag = {
			{ kind = "Axle", position = Vector3.new(0, 0.2, 0), direction = Vector3.new(0, 0, 1), length = 2 },
			{ kind = "TechnicPin", position = Vector3.new(0, -0.3, 0), direction = Vector3.new(0, 0, 1), length = 1 },
		}
		local snap = findSnapPlacement(CFrame.new(0, 5, 0.4), drag :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		-- Pin connector lands exactly at the hole center.
		t.expect(snap.cframe:PointToWorldSpace(Vector3.new(0, -0.3, 0))).toBeCloseTo(Vector3.new(0, 5, 0))
	end)

	t.test("bar slides through a pin's bar hole", function()
		local world = {
			{ kind = "BarHole", position = Vector3.new(0, 3, 0), direction = Vector3.new(1, 0, 0), length = 2 },
		}
		local bar = {
			{ kind = "Bar", position = Vector3.zero, direction = Vector3.new(1, 0, 0), length = 4 },
		}
		local snap = findSnapPlacement(CFrame.new(0.4, 3.2, 0.1), bar :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		-- Through-hole: symmetric slide, along-axis position preserved.
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0.4, 3, 0))
		t.expect(#snap.matchedPairs).toBe(1)
	end)

	t.test("towball mates a socket at any rotation", function()
		local world = {
			{ kind = "TowballSocket", position = Vector3.new(2, 3, 1), direction = Vector3.new(0, 0, 1) },
		}
		local ball = {
			{ kind = "Towball", position = Vector3.new(0.5, 0, 0), direction = Vector3.new(0, 1, 0) },
		}
		-- Arbitrary rotation: ball joints ignore direction entirely.
		local rotation = CFrame.Angles(0.3, 1.1, 0.7)
		local ghost = rotation + Vector3.new(1.8, 2.9, 0.9)
		local snap = findSnapPlacement(ghost, ball :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe:PointToWorldSpace(Vector3.new(0.5, 0, 0))).toBeCloseTo(Vector3.new(2, 3, 1))
		t.expect(#snap.matchedPairs).toBe(1)
	end)

	t.test("point mates outrank ball mates", function()
		local world = {
			{ kind = "Socket", position = Vector3.new(0, 5, 0), direction = Vector3.new(0, -1, 0) },
			{ kind = "TowballSocket", position = Vector3.new(1.1, 4.5, 0), direction = Vector3.new(0, 1, 0) },
		}
		local drag = {
			{ kind = "Stud", position = Vector3.new(0, 0.5, 0), direction = Vector3.new(0, 1, 0) },
			{ kind = "Towball", position = Vector3.new(1, 0, 0), direction = Vector3.new(0, 1, 0) },
		}
		-- The ball target is closer, but the stud's 0-DOF lock wins.
		local snap = findSnapPlacement(CFrame.new(0.3, 4.4, 0), drag :: any, world :: any, kMaxSnap) :: any
		t.expect(snap).toBeTruthy()
		t.expect(snap.cframe.Position).toBeCloseTo(Vector3.new(0, 4.5, 0))
	end)

	t.test("axial axes must be parallel", function()
		local world = {
			{ kind = "AxleHole", position = Vector3.new(0, 5, 0), direction = Vector3.new(1, 0, 0), length = 1 },
		}
		local crossways = {
			{ kind = "Axle", position = Vector3.zero, direction = Vector3.new(0, 0, 1), length = 2 },
		}
		local snap = findSnapPlacement(CFrame.new(0, 5.1, 0), crossways :: any, world :: any, kMaxSnap)
		t.expect(snap).toBeFalsy()
	end)
end
