--!strict

-- Lateral bore-span refinement from actual mesh geometry. Curated
-- primitive spans under-cover when a part completes its bore with raw
-- (unkeyable) geometry: 3713's bush.dat only accounts for the sleeve
-- section, but the bore runs on through the base collar, so the
-- connector sits short and off-center - and grid snapping lands parts
-- off-station along axles.
--
-- The bore leaves a reliable footprint in the flattened mesh: the bore
-- wall and the mouth edge rings all lie within the bore radius of the
-- axis (3713's collar-end mouth is a vertex ring at r=6 right at the
-- true end). For each axial bore connector, collect triangles lying
-- WHOLLY inside the radial band and extend the span outward through
-- CONTIGUOUS coverage (gap-limited, so unrelated geometry crossing
-- near the axis - a perpendicular pin hole's wall - cannot stretch
-- it). Spans only ever grow; the primitive span is the trusted core.

local Types = require(script.Parent.Types)

-- Radial band (LDU) that bore-wall and mouth-edge geometry lives
-- within: bore radius (~6 for both axle bores and pin holes) plus
-- margin, but below mouth chamfer outer edges (~7.5+).
local kBoreBand: { [string]: number } = {
	AxleHole = 7,
	PegHole = 7,
}

-- Coverage gaps up to this (LDU) still count as contiguous (seams
-- between primitive sections; sub-LDU modeling slop).
local kGapMax = 2

local function refineBoreSpans(mesh: Types.FlatMesh, connections: { Types.Connection })
	for _, connection in connections do
		local band = kBoreBand[connection.type]
		if band == nil or connection.length == nil then
			continue
		end
		if connection.direction.Magnitude < 1e-6 then
			continue
		end
		local axis = connection.direction.Unit
		local center = connection.position

		-- Coverage intervals (along the axis, relative to the connector
		-- center) from triangles fully inside the radial band.
		local intervals: { { min: number, max: number } } = {}
		for _, triangle in mesh.triangles do
			local minZ = math.huge
			local maxZ = -math.huge
			local inBand = true
			for _, vertex in { triangle.a, triangle.b, triangle.c } do
				local delta = vertex - center
				local z = delta:Dot(axis)
				local radial = (delta - axis * z).Magnitude
				if radial > band then
					inBand = false
					break
				end
				minZ = math.min(minZ, z)
				maxZ = math.max(maxZ, z)
			end
			if inBand then
				table.insert(intervals, { min = minZ, max = maxZ })
			end
		end

		-- Grow the span through contiguous coverage.
		local half = (connection.length :: number) / 2
		local low = -half
		local high = half
		local changed = true
		while changed do
			changed = false
			for _, interval in intervals do
				if interval.min <= high + kGapMax and interval.max >= low - kGapMax then
					if interval.max > high then
						high = interval.max
						changed = true
					end
					if interval.min < low then
						low = interval.min
						changed = true
					end
				end
			end
		end

		if high - low > (connection.length :: number) + 1e-3 then
			connection.length = high - low
			connection.position = center + axis * ((low + high) / 2)
		end
	end
end

return refineBoreSpans
