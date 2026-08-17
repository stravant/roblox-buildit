--!strict

-- Coalesces individual connection cells (studs / anti-stud sockets) into
-- maximal rectangular grid regions, so annotation is "type + frame +
-- dimension" instead of one marker per cell (a 2x4 brick's studs become a
-- single 4x2 region; a baseplate's 32x32 field becomes one region instead
-- of 1024).
--
-- Cells group by: kind, mating direction (snapped to an axis), the plane
-- they sit on, and their lattice residual (so the offset stud of a jumper
-- plate can't merge with on-grid neighbors). Within a group, maximal
-- rectangles are extracted greedily (L-shaped fields become 2 regions).
-- Cells whose direction doesn't align with a coordinate axis (angled
-- parts) fall back to 1x1 regions.

local Types = require(script.Parent.Types)

local kPitch = 20 -- LDU per stud-grid module
local kAxisDotMin = 0.9999
local kResidualEpsilon = 0.5 -- LDU

local kAxes = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

-- Canonical tangent axes (grid axes) for each snapped direction, chosen so
-- grouping is deterministic. Signs don't matter: regions are centered and
-- symmetric.
local function tangentAxes(direction: Vector3): (Vector3, Vector3)
	if math.abs(direction.Y) > 0.5 then
		return Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
	elseif math.abs(direction.X) > 0.5 then
		return Vector3.new(0, 0, 1), Vector3.new(0, 1, 0)
	else
		return Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)
	end
end

local function frameFor(position: Vector3, direction: Vector3, tangent1: Vector3): CFrame
	return CFrame.fromMatrix(position, tangent1, direction, tangent1:Cross(direction))
end

-- Fallback frame for cells with a non-axis-aligned direction.
local function arbitraryFrame(position: Vector3, direction: Vector3): CFrame
	local reference = if math.abs(direction.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local tangent = reference:Cross(direction).Unit
	return frameFor(position, direction, tangent)
end

type Group = {
	kind: string,
	direction: Vector3,
	tangent1: Vector3,
	tangent2: Vector3,
	cells: { Types.RegionCell },
}

local function coalesceRegions(cells: { Types.RegionCell }): { Types.ConnectionRegion }
	local regions: { Types.ConnectionRegion } = {}
	local groups: { [string]: Group } = {}

	for _, cell in cells do
		local snapped: Vector3? = nil
		for _, axis in kAxes do
			if cell.direction:Dot(axis) > kAxisDotMin then
				snapped = axis
				break
			end
		end
		if snapped == nil then
			table.insert(regions, {
				kind = cell.kind,
				frame = arbitraryFrame(cell.position, cell.direction),
				countX = 1,
				countZ = 1,
				pitch = kPitch,
			})
			continue
		end
		local direction = snapped :: Vector3

		local tangent1, tangent2 = tangentAxes(direction)
		local plane = cell.position:Dot(direction)
		local u = cell.position:Dot(tangent1)
		local v = cell.position:Dot(tangent2)
		local key = string.format(
			"%s|%d,%d,%d|%d|%d,%d",
			cell.kind,
			direction.X, direction.Y, direction.Z,
			math.round(plane / kResidualEpsilon),
			-- Lattice residual: cells only merge if they share a 20 LDU grid.
			math.round((u % kPitch) / kResidualEpsilon) % (kPitch // kResidualEpsilon),
			math.round((v % kPitch) / kResidualEpsilon) % (kPitch // kResidualEpsilon)
		)
		local group = groups[key]
		if group == nil then
			group = {
				kind = cell.kind,
				direction = direction,
				tangent1 = tangent1,
				tangent2 = tangent2,
				cells = {},
			}
			groups[key] = group
		end
		table.insert(group.cells, cell)
	end

	-- Deterministic group order.
	local sortedKeys = {}
	for key in groups do
		table.insert(sortedKeys, key)
	end
	table.sort(sortedKeys)

	for _, key in sortedKeys do
		local group = groups[key]

		-- Lattice coordinates relative to the group minimum.
		local minU = math.huge
		local minV = math.huge
		for _, cell in group.cells do
			minU = math.min(minU, cell.position:Dot(group.tangent1))
			minV = math.min(minV, cell.position:Dot(group.tangent2))
		end
		local occupied: { [string]: Types.RegionCell } = {}
		local latticeList: { { u: number, v: number } } = {}
		for _, cell in group.cells do
			local u = math.round((cell.position:Dot(group.tangent1) - minU) / kPitch)
			local v = math.round((cell.position:Dot(group.tangent2) - minV) / kPitch)
			local cellKey = u .. "," .. v
			if occupied[cellKey] == nil then
				occupied[cellKey] = cell
				table.insert(latticeList, { u = u, v = v })
			end
		end
		table.sort(latticeList, function(lhs, rhs)
			if lhs.v ~= rhs.v then
				return lhs.v < rhs.v
			else
				return lhs.u < rhs.u
			end
		end)

		-- Greedy maximal rectangle extraction.
		for _, seed in latticeList do
			local seedKey = seed.u .. "," .. seed.v
			if occupied[seedKey] == nil then
				continue -- already consumed by an earlier rectangle
			end

			local width = 1
			while occupied[(seed.u + width) .. "," .. seed.v] ~= nil do
				width += 1
			end
			local height = 1
			while true do
				local rowComplete = true
				for du = 0, width - 1 do
					if occupied[(seed.u + du) .. "," .. (seed.v + height)] == nil then
						rowComplete = false
						break
					end
				end
				if not rowComplete then
					break
				end
				height += 1
			end

			local positionSum = Vector3.zero
			for du = 0, width - 1 do
				for dv = 0, height - 1 do
					local cellKey = (seed.u + du) .. "," .. (seed.v + dv)
					positionSum += (occupied[cellKey] :: Types.RegionCell).position
					occupied[cellKey] = nil
				end
			end
			local center = positionSum / (width * height)

			table.insert(regions, {
				kind = group.kind,
				frame = frameFor(center, group.direction, group.tangent1),
				countX = width,
				countZ = height,
				pitch = kPitch,
			})
		end
	end

	return regions
end

return coalesceRegions
