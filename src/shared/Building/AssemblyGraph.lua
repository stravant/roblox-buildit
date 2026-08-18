--!strict

-- The assembly connection graph: which units are connected to which,
-- through which engaged connector mates. Serves two queries:
--
--  1. DRAG PARTITION - when a unit is picked up and dragged along a
--     direction, which connected units must come along? An edge lets
--     the neighbor stay behind only when EVERY mate on it separates
--     along the drag direction (a stud pulls off along the stud axis
--     only; a bar slides out along its axis; magnets and balls release
--     any way). Anything else drags the neighbor with you, LEGO style:
--     lifting the middle brick of a stacked wall takes the bricks above
--     and leaves the ones below; dragging it down takes the ones below.
--
--  2. PHYSICS PLAN - fold each edge's mates into a rigid-motion
--     archetype (Fixed / Hinge about a line / Cylindrical about a line
--     / Ball about a point), then cluster Fixed edges into rigid bodies
--     and emit constraints for the articulated edges. Fastener units
--     (pins, axles, bars - parts whose every connector is a male rod)
--     joining exactly two structural units are absorbed: their two
--     hinge lines combine into a single virtual mate between the
--     structural pair, so two offset pins weld a liftarm pair rigid
--     while a single pin (or two collinear pins) leaves a hinge.
--
-- The graph is pure data over WORLD-SPACE connectors; a thin collector
-- (collectUnits) builds the inputs from workspace units. Construction
-- uses a spatial hash over connector positions (axial connectors are
-- inserted along their whole span), so building is O(N * local
-- density) - no all-pairs work. Units are drag units: a composite
-- Model is ONE node; its internal joints stay out of the graph.

local mates = require(script.Parent.mates)
local getConnectors = require(script.Parent.getConnectors)

export type WorldConnector = mates.MateConnector

export type UnitInput = {
	id: any,
	connectors: { WorldConnector },
}

export type Edge = {
	a: any,
	b: any,
	mates: { mates.Mate }, -- oriented: separationsA belongs to unit `a`
}

export type Archetype = {
	kind: "Fixed" | "Hinge" | "Cylindrical" | "Ball",
	position: Vector3?,
	axis: Vector3?,
}

export type Constraint = {
	kind: "Hinge" | "Cylindrical" | "Ball",
	a: any,
	b: any,
	position: Vector3,
	axis: Vector3,
}

export type PhysicsPlan = {
	-- Rigid clusters of unit ids (welded together at apply time).
	clusters: { { any } },
	-- Constraints between units in different clusters.
	constraints: { Constraint },
}

-- Drag direction must be within 60 degrees of a mate's separation
-- direction for the mate to release (matches the snap alignment cone).
local kSeparationDot = 0.5

-- Spatial hash cell size (studs). Mates engage within kMatedEpsilon,
-- but axial connectors interact anywhere along their span, so segments
-- are inserted into every cell they cross.
local kCellSize = 2

-- Units whose every connector is one of these male rod kinds act as
-- fasteners when they join exactly two structural units.
local kFastenerKinds: { [string]: boolean } = {
	TechnicPin = true,
	Axle = true,
	Bar = true,
	WheelPin = true,
	HingePin = true,
}

local AssemblyGraph = {}
AssemblyGraph.__index = AssemblyGraph

export type AssemblyGraph = typeof(setmetatable(
	{} :: {
		units: { [any]: UnitInput },
		-- adjacency[idA][idB] = shared Edge (same table both ways)
		adjacency: { [any]: { [any]: Edge } },
		hash: { [string]: { { unit: any, connector: WorldConnector } } },
	},
	AssemblyGraph
))

local function cellKey(x: number, y: number, z: number): string
	return `{x},{y},{z}`
end

local function cellsForConnector(connector: WorldConnector): { string }
	local halfSpan = (connector.length or 0) / 2 + mates.kMatedEpsilon
	local from = connector.position - connector.direction * halfSpan
	local to = connector.position + connector.direction * halfSpan
	local minCorner = from:Min(to)
	local maxCorner = from:Max(to)
	local keys = {}
	for x = math.floor(minCorner.X / kCellSize), math.floor(maxCorner.X / kCellSize) do
		for y = math.floor(minCorner.Y / kCellSize), math.floor(maxCorner.Y / kCellSize) do
			for z = math.floor(minCorner.Z / kCellSize), math.floor(maxCorner.Z / kCellSize) do
				table.insert(keys, cellKey(x, y, z))
			end
		end
	end
	return keys
end

function AssemblyGraph.new(): AssemblyGraph
	return setmetatable({
		units = {},
		adjacency = {},
		hash = {},
	}, AssemblyGraph) :: AssemblyGraph
end

function AssemblyGraph.build(units: { UnitInput }): AssemblyGraph
	local graph = AssemblyGraph.new()
	for _, unit in units do
		graph:addUnit(unit)
	end
	return graph
end

-- Insert a unit and compute its engaged mates against existing units.
function AssemblyGraph.addUnit(self: AssemblyGraph, unit: UnitInput)
	assert(self.units[unit.id] == nil, "unit already in graph")
	self.units[unit.id] = unit
	self.adjacency[unit.id] = self.adjacency[unit.id] or {}

	-- Collect candidate partners from the hash, then test engagement.
	local tested: { [any]: { [WorldConnector]: boolean } } = {}
	for _, connector in unit.connectors do
		for _, key in cellsForConnector(connector) do
			local bucket = self.hash[key]
			if bucket ~= nil then
				for _, entry in bucket do
					if entry.unit == unit.id then
						continue
					end
					local seen = tested[entry.unit]
					if seen == nil then
						seen = {}
						tested[entry.unit] = seen
					end
					if seen[entry.connector] then
						continue
					end
					seen[entry.connector] = true
					local mate = mates.check(connector, entry.connector)
					if mate ~= nil then
						self:_addMate(unit.id, entry.unit, mate)
					end
				end
			end
		end
		-- A connector may pair with several others (a long bar through
		-- many clips), so the tested-set is per OTHER connector, reset
		-- per own connector.
		table.clear(tested)
	end

	for _, connector in unit.connectors do
		for _, key in cellsForConnector(connector) do
			local bucket = self.hash[key]
			if bucket == nil then
				bucket = {}
				self.hash[key] = bucket
			end
			table.insert(bucket, { unit = unit.id, connector = connector })
		end
	end
end

function AssemblyGraph.removeUnit(self: AssemblyGraph, id: any)
	local unit = self.units[id]
	if unit == nil then
		return
	end
	for _, connector in unit.connectors do
		for _, key in cellsForConnector(connector) do
			local bucket = self.hash[key]
			if bucket ~= nil then
				for index = #bucket, 1, -1 do
					if bucket[index].unit == id then
						table.remove(bucket, index)
					end
				end
				if #bucket == 0 then
					self.hash[key] = nil
				end
			end
		end
	end
	for otherId in self.adjacency[id] or {} do
		local otherAdjacency = self.adjacency[otherId]
		if otherAdjacency ~= nil then
			otherAdjacency[id] = nil
		end
	end
	self.adjacency[id] = nil
	self.units[id] = nil
end

function AssemblyGraph._addMate(self: AssemblyGraph, idA: any, idB: any, mate: mates.Mate)
	local edge = self.adjacency[idA][idB]
	if edge == nil then
		edge = { a = idA, b = idB, mates = {} }
		self.adjacency[idA][idB] = edge
		self.adjacency[idB] = self.adjacency[idB] or {}
		self.adjacency[idB][idA] = edge
	end
	if edge.a == idA then
		table.insert(edge.mates, mate)
	else
		-- Edge stored with the opposite orientation: flip the mate's
		-- A-side separation directions.
		local flipped: { Vector3 }? = nil
		if mate.separationsA ~= nil then
			flipped = {}
			for _, direction in mate.separationsA :: { Vector3 } do
				table.insert(flipped :: { Vector3 }, -direction)
			end
		end
		table.insert(edge.mates, {
			class = mate.class,
			aKind = mate.bKind,
			bKind = mate.aKind,
			position = mate.position,
			axis = mate.axis,
			slide = mate.slide,
			separationsA = flipped,
		})
	end
end

function AssemblyGraph.edge(self: AssemblyGraph, idA: any, idB: any): Edge?
	local adjacency = self.adjacency[idA]
	return if adjacency ~= nil then adjacency[idB] else nil
end

-- Does this edge release when the side `movingId` is dragged along
-- `direction`? Only when EVERY mate separates that way.
local function edgeReleases(edge: Edge, movingId: any, direction: Vector3): boolean
	local movingIsA = edge.a == movingId
	for _, mate in edge.mates do
		local separations = mate.separationsA
		if separations == nil then
			continue -- releases in any direction
		end
		local releases = false
		for _, separation in separations :: { Vector3 } do
			local aligned = if movingIsA then separation else -separation
			if direction:Dot(aligned) >= kSeparationDot then
				releases = true
				break
			end
		end
		if not releases then
			return false
		end
	end
	return true
end

-- Kind pairs that are LOOSE: freely rotating/sliding connections with
-- no clutch (an axle spinning in a round pin hole, a bar through a
-- pin's bore). These hold nothing when handling parts — only "move
-- assembly" carries them.
local kLoosePairs: { [string]: { [string]: boolean } } = {
	Axle = { PegHole = true },
	PegHole = { Axle = true },
	Bar = { BarHole = true, AxleHole = true },
	BarHole = { Bar = true },
	AxleHole = { Bar = true },
}

local function mateIsLoose(mate: mates.Mate): boolean
	local partners = kLoosePairs[mate.aKind]
	return partners ~= nil and partners[mate.bKind] == true
end

-- Chunk rule for one mate: does it carry the neighbor when the
-- `movingIsA` side is dragged?
--  - Loose pairs never carry.
--  - Stud-type mates (point/mouth) carry only what sits on the MOVING
--    side's studs: the picked part's sockets always break away from
--    what's underneath, its studs always keep what's stacked on them.
--  - Faces (magnets/track ends) lift apart: never carry.
--  - Everything else engaged (pins, clips, hinges, balls, slides)
--    is captive with clutch: always carries.
local function mateCarriesInChunk(mate: mates.Mate, movingIsA: boolean): boolean
	if mateIsLoose(mate) then
		return false
	end
	if mate.class == "point" or mate.class == "mouth" then
		local movingKind = if movingIsA then mate.aKind else mate.bKind
		return movingKind == "Stud"
	end
	if mate.class == "face" then
		return false
	end
	return true
end

-- "Move chunk": everything reachable through carrying mates. The
-- picked unit's studs (and captive joints like pins/clips/hinges)
-- carry; its sockets break; loose spin/slide fits stay behind.
function AssemblyGraph.partitionChunk(self: AssemblyGraph, id: any): { any }
	local moving: { [any]: boolean } = { [id] = true }
	local queue = { id }
	while #queue > 0 do
		local current = table.remove(queue) :: any
		for otherId, edge in self.adjacency[current] or {} do
			if moving[otherId] then
				continue
			end
			local movingIsA = edge.a == current
			for _, mate in edge.mates do
				if mateCarriesInChunk(mate, movingIsA) then
					moving[otherId] = true
					table.insert(queue, otherId)
					break
				end
			end
		end
	end
	local result = {}
	for unitId in moving do
		table.insert(result, unitId)
	end
	return result
end

-- "Move assembly": the full connected component, every engaged mate
-- counts (axles through holes, frictionless spins, magnets, all of it).
function AssemblyGraph.partitionAssembly(self: AssemblyGraph, id: any): { any }
	local moving: { [any]: boolean } = { [id] = true }
	local queue = { id }
	while #queue > 0 do
		local current = table.remove(queue) :: any
		for otherId in self.adjacency[current] or {} do
			if not moving[otherId] then
				moving[otherId] = true
				table.insert(queue, otherId)
			end
		end
	end
	local result = {}
	for unitId in moving do
		table.insert(result, unitId)
	end
	return result
end

-- The set of units that must move together when `id` is dragged along
-- `direction` (unit vector). Returns an array including `id`.
function AssemblyGraph.partition(self: AssemblyGraph, id: any, direction: Vector3): { any }
	local moving: { [any]: boolean } = { [id] = true }
	local queue = { id }
	while #queue > 0 do
		local current = table.remove(queue) :: any
		for otherId, edge in self.adjacency[current] or {} do
			if moving[otherId] then
				continue
			end
			if not edgeReleases(edge, current, direction) then
				moving[otherId] = true
				table.insert(queue, otherId)
			end
		end
	end
	local result = {}
	for unitId in moving do
		table.insert(result, unitId)
	end
	return result
end

--------------------------------------------------------------------------
-- Physics planning
--------------------------------------------------------------------------

local kLineEpsilon = 0.1

local function sameLine(p1: Vector3, d1: Vector3, p2: Vector3, d2: Vector3): boolean
	if math.abs(d1:Dot(d2)) < mates.kAxisDotMin then
		return false
	end
	local delta = p2 - p1
	local perpendicular = delta - d1 * delta:Dot(d1)
	return perpendicular.Magnitude <= kLineEpsilon
end

local function pointOnLine(point: Vector3, p: Vector3, d: Vector3): boolean
	local delta = point - p
	local perpendicular = delta - d * delta:Dot(d)
	return perpendicular.Magnitude <= kLineEpsilon
end

local kFixed: Archetype = { kind = "Fixed" }

local function mateArchetype(mate: mates.Mate): Archetype
	if mate.class == "point" or mate.class == "face" then
		-- A single stud cell can physically rotate, but rigid is the
		-- sane default for building; grid regions of 2+ cells become
		-- Fixed through intersection anyway.
		return kFixed
	elseif mate.class == "ball" then
		return { kind = "Ball", position = mate.position }
	elseif mate.class == "mouth" then
		return { kind = "Hinge", position = mate.position, axis = mate.axis }
	else -- axial
		if mate.slide > mates.kMatedEpsilon then
			return { kind = "Cylindrical", position = mate.position, axis = mate.axis }
		end
		return { kind = "Hinge", position = mate.position, axis = mate.axis }
	end
end

-- Intersect two rigid-motion freedoms: the result allows only motion
-- both allow.
local function intersectArchetypes(x: Archetype, y: Archetype): Archetype
	if x.kind == "Fixed" or y.kind == "Fixed" then
		return kFixed
	end
	if x.kind == "Ball" and y.kind == "Ball" then
		local px = x.position :: Vector3
		local py = y.position :: Vector3
		if (px - py).Magnitude <= kLineEpsilon then
			return x
		end
		-- Two separated ball joints hinge about the line through both.
		return { kind = "Hinge", position = px, axis = (py - px).Unit }
	end
	if x.kind == "Ball" then
		x, y = y, x -- normalize: ball second
	end
	if y.kind == "Ball" then
		-- Line joint + ball: the ball pins translation at its point; if
		-- that point lies on the line, rotation about the line remains.
		if pointOnLine(y.position :: Vector3, x.position :: Vector3, x.axis :: Vector3) then
			return { kind = "Hinge", position = x.position, axis = x.axis }
		end
		return kFixed
	end
	-- Both are line joints (Hinge/Cylindrical).
	if not sameLine(x.position :: Vector3, x.axis :: Vector3, y.position :: Vector3, y.axis :: Vector3) then
		return kFixed
	end
	if x.kind == "Cylindrical" and y.kind == "Cylindrical" then
		return { kind = "Cylindrical", position = x.position, axis = x.axis }
	end
	return { kind = "Hinge", position = x.position, axis = x.axis }
end

local function foldArchetype(matesList: { mates.Mate }): Archetype
	local result: Archetype? = nil
	for _, mate in matesList do
		local archetype = mateArchetype(mate)
		result = if result == nil then archetype else intersectArchetypes(result :: Archetype, archetype)
		if (result :: Archetype).kind == "Fixed" then
			return kFixed
		end
	end
	return result or kFixed
end

AssemblyGraph.foldArchetype = function(_self: AssemblyGraph, edge: Edge): Archetype
	return foldArchetype(edge.mates)
end

local function isFastener(unit: UnitInput): boolean
	if #unit.connectors == 0 then
		return false
	end
	for _, connector in unit.connectors do
		if not kFastenerKinds[connector.kind] then
			return false
		end
	end
	return true
end

function AssemblyGraph.physicsPlan(self: AssemblyGraph): PhysicsPlan
	-- Union-find over rigid connections.
	local parent: { [any]: any } = {}
	local function find(id: any): any
		while parent[id] ~= nil and parent[id] ~= id do
			parent[id] = parent[parent[id]] or parent[id]
			id = parent[id]
		end
		return if parent[id] == nil then id else id
	end
	local function union(idA: any, idB: any)
		local rootA, rootB = find(idA), find(idB)
		if rootA ~= rootB then
			parent[rootA] = rootB
		end
	end
	for id in self.units do
		parent[id] = id
	end

	-- Pass 1: absorb fasteners joining exactly two structural units.
	-- The fastener welds to one side; its two edge archetypes combine
	-- into a virtual mate between the structural pair (two offset pins
	-- between liftarms therefore intersect to Fixed = weld; a single
	-- pin, or two collinear pins, stay a hinge).
	local virtualPairs: { { a: any, b: any, archetype: Archetype } } = {}
	local absorbedEdges: { [Edge]: boolean } = {}
	for id, unit in self.units do
		if not isFastener(unit) then
			continue
		end
		local neighbors = {}
		for otherId in self.adjacency[id] or {} do
			table.insert(neighbors, otherId)
		end
		if #neighbors ~= 2 then
			continue
		end
		local edgeA = self.adjacency[id][neighbors[1]]
		local edgeB = self.adjacency[id][neighbors[2]]
		local throughArchetype = intersectArchetypes(foldArchetype(edgeA.mates), foldArchetype(edgeB.mates))
		absorbedEdges[edgeA] = true
		absorbedEdges[edgeB] = true
		union(id, neighbors[1]) -- fastener rides with one side
		if throughArchetype.kind == "Fixed" then
			union(neighbors[1], neighbors[2])
		else
			table.insert(virtualPairs, { a = neighbors[1], b = neighbors[2], archetype = throughArchetype })
		end
	end

	-- Pass 2: fold remaining direct edges.
	local articulated: { { a: any, b: any, archetype: Archetype } } = {}
	local seenEdges: { [Edge]: boolean } = {}
	for _, adjacency in self.adjacency do
		for _, edge in adjacency do
			if seenEdges[edge] or absorbedEdges[edge] then
				continue
			end
			seenEdges[edge] = true
			local archetype = foldArchetype(edge.mates)
			if archetype.kind == "Fixed" then
				union(edge.a, edge.b)
			else
				table.insert(articulated, { a = edge.a, b = edge.b, archetype = archetype })
			end
		end
	end

	-- Pass 3: virtual pairs from fasteners; combine multiples between
	-- the same structural pair (two separate collinear pins still fold).
	local virtualByPair: { [string]: { a: any, b: any, archetype: Archetype } } = {}
	for _, pair in virtualPairs do
		local key = if tostring(pair.a) < tostring(pair.b)
			then `{tostring(pair.a)}|{tostring(pair.b)}`
			else `{tostring(pair.b)}|{tostring(pair.a)}`
		local existing = virtualByPair[key]
		if existing == nil then
			virtualByPair[key] = pair
		else
			existing.archetype = intersectArchetypes(existing.archetype, pair.archetype)
		end
	end
	for _, pair in virtualByPair do
		if pair.archetype.kind == "Fixed" then
			union(pair.a, pair.b)
		else
			table.insert(articulated, pair)
		end
	end

	-- Emit clusters and the constraints that still separate them.
	local clusterMembers: { [any]: { any } } = {}
	for id in self.units do
		local root = find(id)
		local members = clusterMembers[root]
		if members == nil then
			members = {}
			clusterMembers[root] = members
		end
		table.insert(members, id)
	end
	local clusters = {}
	for _, members in clusterMembers do
		table.insert(clusters, members)
	end

	local constraints: { Constraint } = {}
	for _, pair in articulated do
		if find(pair.a) == find(pair.b) then
			continue -- frozen by a rigid path elsewhere
		end
		local archetype = pair.archetype
		table.insert(constraints, {
			kind = archetype.kind :: "Hinge" | "Cylindrical" | "Ball",
			a = pair.a,
			b = pair.b,
			position = archetype.position :: Vector3,
			axis = (archetype.axis :: Vector3?) or Vector3.yAxis,
		})
	end

	return { clusters = clusters, constraints = constraints }
end

--------------------------------------------------------------------------
-- Workspace collection
--------------------------------------------------------------------------

-- Build UnitInputs from placed units (BaseParts or composite Models
-- carrying connector attachments), converting connectors to world space.
function AssemblyGraph.collectUnits(units: { Instance }): { UnitInput }
	local inputs = {}
	for _, unit in units do
		local connectors: { WorldConnector } = {}
		local parts = if unit:IsA("BasePart") then { unit } else unit:GetDescendants()
		for _, part in parts :: { Instance } do
			if not part:IsA("BasePart") then
				continue
			end
			for _, connector in getConnectors(part) do
				table.insert(connectors, {
					kind = connector.kind,
					position = part.CFrame:PointToWorldSpace(connector.position),
					direction = part.CFrame:VectorToWorldSpace(connector.direction),
					length = connector.length,
					oneSided = connector.oneSided,
					radius = connector.radius,
				})
			end
		end
		table.insert(inputs, { id = unit, connectors = connectors })
	end
	return inputs
end

return AssemblyGraph
