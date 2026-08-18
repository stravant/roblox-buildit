--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local AssemblyGraph = require(script.Parent.AssemblyGraph)

type WorldConnector = AssemblyGraph.WorldConnector

local kUp = Vector3.new(0, 1, 0)
local kDown = Vector3.new(0, -1, 0)

-- A 2-wide brick unit: two studs up top, two sockets underneath, at
-- grid pitch 1, brick height 1.2 (proportions don't matter, only that
-- stacked connectors coincide).
local kBrickHeight = 1.2

local function brick(id: string, x: number, level: number): AssemblyGraph.UnitInput
	local y = level * kBrickHeight
	local connectors: { WorldConnector } = {}
	for _, dx in { -0.5, 0.5 } do
		table.insert(connectors, {
			kind = "Stud",
			position = Vector3.new(x + dx, y + kBrickHeight, 0),
			direction = kUp,
		})
		table.insert(connectors, {
			kind = "Socket",
			position = Vector3.new(x + dx, y + kBrickHeight, 0) - Vector3.new(0, kBrickHeight, 0),
			direction = kDown,
		})
	end
	return { id = id, connectors = connectors }
end

local function sorted(ids: { any }): { any }
	local copy = table.clone(ids)
	table.sort(copy, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return copy
end

return function(t: TestTypes.TestContext)
	-- The 2-3-2 pyramid: bottom row at x {0, 1}? No - rows must overlap
	-- half a brick so each upper brick bridges two lower ones:
	-- bottom two at x = 1, 3; middle three at x = 0, 2, 4; top two at
	-- x = 1, 3. (Middle bricks each catch one stud of each neighbor
	-- below/above.)
	local function pyramid(): AssemblyGraph.AssemblyGraph
		return AssemblyGraph.build({
			brick("bottom1", 1, 0),
			brick("bottom3", 3, 0),
			brick("mid0", 0, 1),
			brick("mid2", 2, 1),
			brick("mid4", 4, 1),
			brick("top1", 1, 2),
			brick("top3", 3, 2),
		})
	end

	t.test("pyramid edges: each middle brick touches its neighbors", function()
		local graph = pyramid()
		t.expect(graph:edge("mid2", "bottom1")).toBeTruthy()
		t.expect(graph:edge("mid2", "bottom3")).toBeTruthy()
		t.expect(graph:edge("mid2", "top1")).toBeTruthy()
		t.expect(graph:edge("mid2", "top3")).toBeTruthy()
		t.expect(graph:edge("mid2", "mid0")).toBe(nil)
		t.expect(graph:edge("bottom1", "top1")).toBe(nil)
	end)

	t.test("dragging the middle brick up takes the top row", function()
		local graph = pyramid()
		local moving = sorted(graph:partition("mid2", kUp))
		t.expect(table.concat(moving, ",")).toBe("mid2,top1,top3")
	end)

	t.test("dragging the middle brick down takes the bottom row", function()
		local graph = pyramid()
		local moving = sorted(graph:partition("mid2", kDown))
		t.expect(table.concat(moving, ",")).toBe("bottom1,bottom3,mid2")
	end)

	t.test("dragging sideways takes the whole assembly", function()
		local graph = pyramid()
		local moving = graph:partition("mid2", Vector3.new(1, 0, 0))
		t.expect(#moving).toBe(7)
	end)

	t.test("dragging a top brick up takes only itself", function()
		local graph = pyramid()
		local moving = graph:partition("top1", kUp)
		t.expect(#moving).toBe(1)
	end)

	t.test("removing a unit drops its edges", function()
		local graph = pyramid()
		graph:removeUnit("top1")
		t.expect(graph:edge("mid2", "top1")).toBe(nil)
		local moving = sorted(graph:partition("mid2", kUp))
		t.expect(table.concat(moving, ",")).toBe("mid2,top3")
	end)

	-- Liftarms joined by loose pins. A pin is a fastener unit: two
	-- TechnicPin halves; each liftarm has PegHoles. Pin half length ==
	-- hole length -> locked axially, hinge remains.
	local function liftarmScene(pinAxes: { { position: Vector3, axis: Vector3 } })
		local units: { AssemblyGraph.UnitInput } = {}
		local armA: { WorldConnector } = {}
		local armB: { WorldConnector } = {}
		for _, pin in pinAxes do
			table.insert(armA, {
				kind = "PegHole",
				position = pin.position - pin.axis * 0.5,
				direction = pin.axis,
				length = 1,
			})
			table.insert(armB, {
				kind = "PegHole",
				position = pin.position + pin.axis * 0.5,
				direction = pin.axis,
				length = 1,
			})
			table.insert(units, {
				id = `pin{#units}`,
				connectors = {
					{
						kind = "TechnicPin",
						position = pin.position - pin.axis * 0.5,
						direction = pin.axis,
						length = 1,
					},
					{
						kind = "TechnicPin",
						position = pin.position + pin.axis * 0.5,
						direction = pin.axis,
						length = 1,
					},
					-- Real pins are hollow: the interior bar bore must not
					-- disqualify them from fastener classification.
					{
						kind = "BarHole",
						position = pin.position,
						direction = pin.axis,
						length = 2,
					},
				},
			})
		end
		table.insert(units, { id = "armA", connectors = armA })
		table.insert(units, { id = "armB", connectors = armB })
		return AssemblyGraph.build(units)
	end

	local kAxisZ = Vector3.new(0, 0, 1)

	t.test("one pin between liftarms plans a hinge", function()
		local graph = liftarmScene({ { position = Vector3.zero, axis = kAxisZ } })
		local plan = graph:physicsPlan()
		t.expect(#plan.constraints).toBe(1)
		t.expect(plan.constraints[1].kind).toBe("Hinge")
		-- Fastener absorbed: 3 units in 2 clusters.
		t.expect(#plan.clusters).toBe(2)
	end)

	t.test("two offset pins weld the liftarms rigid", function()
		local graph = liftarmScene({
			{ position = Vector3.zero, axis = kAxisZ },
			{ position = Vector3.new(3, 0, 0), axis = kAxisZ },
		})
		local plan = graph:physicsPlan()
		t.expect(#plan.constraints).toBe(0)
		t.expect(#plan.clusters).toBe(1)
	end)

	t.test("two collinear pins still hinge", function()
		local graph = liftarmScene({
			{ position = Vector3.zero, axis = kAxisZ },
			{ position = Vector3.new(0, 0, 4), axis = kAxisZ },
		})
		local plan = graph:physicsPlan()
		t.expect(#plan.constraints).toBe(1)
		t.expect(plan.constraints[1].kind).toBe("Hinge")
	end)

	t.test("stud stacks weld into one cluster", function()
		local graph = pyramid()
		local plan = graph:physicsPlan()
		t.expect(#plan.clusters).toBe(1)
		t.expect(#plan.constraints).toBe(0)
		t.expect(#plan.clusters[1]).toBe(7)
	end)

	t.test("bar sliding in a clip plans a cylindrical constraint", function()
		local graph = AssemblyGraph.build({
			{
				id = "wand",
				connectors = {
					{ kind = "Bar", position = Vector3.zero, direction = kAxisZ, length = 4 },
				},
			},
			{
				id = "clipPlate",
				connectors = {
					{ kind = "Clip", position = Vector3.new(0, 0, 1), direction = kAxisZ, length = 0.4 },
				},
			},
		})
		local plan = graph:physicsPlan()
		t.expect(#plan.constraints).toBe(1)
		t.expect(plan.constraints[1].kind).toBe("Cylindrical")
	end)

	t.test("bar drags out of the clip along its axis only", function()
		local graph = AssemblyGraph.build({
			{
				id = "wand",
				connectors = {
					{ kind = "Bar", position = Vector3.zero, direction = kAxisZ, length = 4 },
				},
			},
			{
				id = "clipPlate",
				connectors = {
					{ kind = "Clip", position = Vector3.new(0, 0, 1), direction = kAxisZ, length = 0.4 },
				},
			},
		})
		t.expect(#graph:partition("wand", kAxisZ)).toBe(1)
		t.expect(#graph:partition("wand", -kAxisZ)).toBe(1)
		t.expect(#graph:partition("wand", kUp)).toBe(2)
	end)

	t.test("scales: 2000-brick wall builds and partitions", function()
		-- 40 columns x 50 rows of offset brickwork. Spatial hashing
		-- keeps this O(N * local density); an all-pairs build would be
		-- 4M mate checks and show up as seconds here.
		local units: { AssemblyGraph.UnitInput } = {}
		for row = 0, 49 do
			local offset = if row % 2 == 1 then 1 else 0
			for column = 0, 39 do
				table.insert(units, brick(`w{row}_{column}`, column * 2 + offset, row))
			end
		end
		local clock = os.clock()
		local graph = AssemblyGraph.build(units)
		local buildSeconds = os.clock() - clock

		clock = os.clock()
		local movingUp = graph:partition("w25_20", kUp)
		local partitionSeconds = os.clock() - clock

		-- Everything above the picked brick's support cone comes along.
		t.expect(#movingUp > 1).toBe(true)
		t.expect(#movingUp < 2000).toBe(true)
		local wholeWall = graph:partition("w25_20", Vector3.new(1, 0, 0))
		t.expect(#wholeWall).toBe(2000)
		-- Generous budget: catches quadratic regressions, not noise.
		t.expect(buildSeconds < 5).toBe(true)
		t.expect(partitionSeconds < 0.5).toBe(true)

		local planClock = os.clock()
		local plan = graph:physicsPlan()
		t.expect(#plan.clusters).toBe(1)
		t.expect(os.clock() - planClock < 2).toBe(true)
	end)

	t.test("chunk: picked brick keeps its studs side, breaks its sockets side", function()
		local graph = pyramid()
		-- Regardless of drag direction: what's ON mid2's studs comes,
		-- what mid2's sockets sit on stays.
		local moving = sorted(graph:partitionChunk("mid2"))
		t.expect(table.concat(moving, ",")).toBe("mid2,top1,top3")
		-- Chains upward: bottom1 carries mid0/mid2, which carry the top
		-- row; bottom3 and mid4 are reached only through THEIR studs
		-- holding others, not the other way, so they stay.
		local fromBottom = sorted(graph:partitionChunk("bottom1"))
		t.expect(table.concat(fromBottom, ",")).toBe("bottom1,mid0,mid2,top1,top3")
		-- A top brick carries nothing.
		t.expect(#graph:partitionChunk("top1")).toBe(1)
	end)

	t.test("assembly: full connected component", function()
		local graph = pyramid()
		t.expect(#graph:partitionAssembly("mid2")).toBe(7)
		t.expect(#graph:partitionAssembly("top1")).toBe(7)
	end)

	t.test("axle through a pin hole: loose in chunk, carried in assembly", function()
		local kAxisZ2 = Vector3.new(0, 0, 1)
		local graph = AssemblyGraph.build({
			{
				id = "axle",
				connectors = {
					{ kind = "Axle", position = Vector3.zero, direction = kAxisZ2, length = 4 },
				},
			},
			{
				id = "technicBrick",
				connectors = {
					{ kind = "PegHole", position = Vector3.new(0, 0, 0.5), direction = kAxisZ2, length = 1 },
				},
			},
			{
				id = "gear",
				connectors = {
					{ kind = "AxleHole", position = Vector3.new(0, 0, -1), direction = kAxisZ2, length = 1 },
				},
			},
		})
		-- The keyed gear is captive on the axle; the round pin hole spins
		-- and slides freely, so the technic brick only comes along in
		-- assembly mode.
		local chunk = sorted(graph:partitionChunk("axle"))
		t.expect(table.concat(chunk, ",")).toBe("axle,gear")
		local assembly = sorted(graph:partitionAssembly("axle"))
		t.expect(table.concat(assembly, ",")).toBe("axle,gear,technicBrick")
	end)

	t.test("physicsJoints: single pin welds to one arm, hinges the other", function()
		local graph = liftarmScene({ { position = Vector3.zero, axis = kAxisZ } })
		local joints = graph:physicsJoints()
		t.expect(#joints.welds).toBe(1)
		t.expect(#joints.constraints).toBe(1)
		t.expect(joints.constraints[1].kind).toBe("Hinge")
	end)

	t.test("physicsJoints: two offset pins become two offset hinges", function()
		local graph = liftarmScene({
			{ position = Vector3.zero, axis = kAxisZ },
			{ position = Vector3.new(3, 0, 0), axis = kAxisZ },
		})
		local joints = graph:physicsJoints()
		-- Each pin welds to one arm and hinges the other; the two offset
		-- hinge lines make the pair rigid through the solver.
		t.expect(#joints.welds).toBe(2)
		t.expect(#joints.constraints).toBe(2)
	end)

	t.test("keyed axle in an axle hole is prismatic, not cylindrical", function()
		local kAxisZ2 = Vector3.new(0, 0, 1)
		local graph = AssemblyGraph.build({
			{
				id = "axle",
				connectors = {
					{ kind = "Axle", position = Vector3.zero, direction = kAxisZ2, length = 4 },
				},
			},
			{
				id = "gear",
				connectors = {
					{ kind = "AxleHole", position = Vector3.new(0, 0, 1), direction = kAxisZ2, length = 1 },
				},
			},
		})
		local joints = graph:physicsJoints()
		t.expect(#joints.constraints).toBe(1)
		t.expect(joints.constraints[1].kind).toBe("Prismatic")
	end)

	t.test("physicsJoints: axle welds to its keyed gear, spins in round holes", function()
		local kAxisZ2 = Vector3.new(0, 0, 1)
		local graph = AssemblyGraph.build({
			{
				id = "axle",
				connectors = {
					{ kind = "Axle", position = Vector3.zero, direction = kAxisZ2, length = 6 },
				},
			},
			{
				id = "gear",
				connectors = {
					{ kind = "AxleHole", position = Vector3.new(0, 0, 2), direction = kAxisZ2, length = 1 },
				},
			},
			{
				id = "brickA",
				connectors = {
					{ kind = "PegHole", position = Vector3.new(0, 0, -1), direction = kAxisZ2, length = 1 },
				},
			},
			{
				id = "brickB",
				connectors = {
					{ kind = "PegHole", position = Vector3.new(0, 0, 1), direction = kAxisZ2, length = 1 },
				},
			},
		})
		local joints = graph:physicsJoints()
		-- Degree-3 fastener: welded to the most-constrained neighbor
		-- (the keyed gear), articulated against the two round holes.
		t.expect(#joints.welds).toBe(1)
		t.expect(joints.welds[1].b).toBe("gear")
		t.expect(#joints.constraints).toBe(2)
		for _, constraint in joints.constraints do
			t.expect(constraint.kind).toBe("Cylindrical")
		end
	end)

	t.test("physicsJoints: stud pyramid is all welds", function()
		local graph = pyramid()
		local joints = graph:physicsJoints()
		t.expect(#joints.constraints).toBe(0)
		t.expect(#joints.welds > 0).toBe(true)
	end)

	t.test("gear meshes detect at the pitch radius sum", function()
		local kAxisZ2 = Vector3.new(0, 0, 1)
		local function gear(id: string, partNumber: string, x: number, z: number?): AssemblyGraph.UnitInput
			return {
				id = id,
				partNumber = partNumber,
				connectors = {
					{
						kind = "AxleHole",
						position = Vector3.new(x, 0, z or 0),
						direction = kAxisZ2,
						length = 0.4,
					},
				},
			}
		end
		-- 8t (pitch r 0.5) meshing 24t (pitch r 1.5): centers 2 apart.
		local meshing = AssemblyGraph.build({
			gear("small", "3647", 0),
			gear("big", "3648", 2),
		})
		local meshes = meshing:gearMeshes()
		t.expect(#meshes).toBe(1)
		t.expect(meshes[1].teethA + meshes[1].teethB).toBe(32)

		-- Too far apart: no mesh.
		local apart = AssemblyGraph.build({
			gear("small", "3647", 0),
			gear("big", "3648", 2.6),
		})
		t.expect(#apart:gearMeshes()).toBe(0)

		-- Offset along the axis beyond tooth overlap: no mesh.
		local offset = AssemblyGraph.build({
			gear("small", "3647", 0),
			gear("big", "3648", 2, 1.5),
		})
		t.expect(#offset:gearMeshes()).toBe(0)
	end)

	t.test("two separated towballs hinge about the line through them", function()
		local graph = AssemblyGraph.build({
			{
				id = "wishbone",
				connectors = {
					{ kind = "Towball", position = Vector3.zero, direction = kUp },
					{ kind = "Towball", position = Vector3.new(0, 0, 2), direction = kUp },
				},
			},
			{
				id = "hub",
				connectors = {
					{ kind = "TowballSocket", position = Vector3.zero, direction = kDown },
					{ kind = "TowballSocket", position = Vector3.new(0, 0, 2), direction = kDown },
				},
			},
		})
		local plan = graph:physicsPlan()
		t.expect(#plan.constraints).toBe(1)
		t.expect(plan.constraints[1].kind).toBe("Hinge")
		t.expect(math.abs(plan.constraints[1].axis.Z)).toBeCloseTo(1)
	end)
end
