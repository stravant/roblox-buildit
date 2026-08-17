--!strict

-- Derives "anti-stud" sockets (stud-sized cells on a part's underside that
-- can grip a stud) from the raw Tube/Pin connections found by
-- findConnections.
--
-- A tube sits at the center of 4 surrounding cells (offsets (+-10, +-10) in
-- its local grid); a pin sits between 2 cells. Since a pin is rotationally
-- symmetric we can't tell its neighbor axis from the transform alone, so we
-- generate candidates on both axes and reject the ones that fall outside
-- the part's footprint (the mesh bounds, inset by 1 LDU) — for a 1xN part
-- the sideways candidates land exactly on the bounds edge and get culled.
--
-- 1x1 parts are covered too: square 1x1 pockets are box5 cavities
-- (Pocket connections), and round 1x1s grip via their stud4-family
-- base tube's center socket.

local Types = require(script.Parent.Types)

local kCellOffset = 10 -- half the 20 LDU stud grid pitch
local kBoundsInset = 1

local function deriveSockets(connections: { Types.Connection }, mesh: Types.FlatMesh?): { Types.Socket }
	local mSockets: { Types.Socket } = {}
	local mSeen: { [string]: boolean } = {}

	local function tryAdd(position: Vector3, direction: Vector3)
		if mesh ~= nil then
			-- Reject candidates outside the part footprint. Only test axes
			-- roughly perpendicular to the socket direction: along the
			-- direction the position sits ON the mating face plane.
			local axes = {
				{ position.X, direction.X, mesh.boundsMin.X, mesh.boundsMax.X },
				{ position.Y, direction.Y, mesh.boundsMin.Y, mesh.boundsMax.Y },
				{ position.Z, direction.Z, mesh.boundsMin.Z, mesh.boundsMax.Z },
			}
			for _, axis in axes do
				local value, dirComponent, minBound, maxBound = axis[1], axis[2], axis[3], axis[4]
				if math.abs(dirComponent) < 0.5 then
					if value < minBound + kBoundsInset or value > maxBound - kBoundsInset then
						return
					end
				end
			end
		end
		local key = string.format(
			"%d,%d,%d:%d,%d,%d",
			math.round(position.X * 2), math.round(position.Y * 2), math.round(position.Z * 2),
			math.round(direction.X * 100), math.round(direction.Y * 100), math.round(direction.Z * 100)
		)
		if not mSeen[key] then
			mSeen[key] = true
			table.insert(mSockets, { position = position, direction = direction })
		end
	end

	for _, connection in connections do
		-- Stud-sized cavities (1x1 undersides, clip plates) are sockets
		-- directly, no neighbor expansion.
		if connection.type == "Pocket" then
			tryAdd(connection.position, connection.direction)
			continue
		end
		if connection.type ~= "Tube" and connection.type ~= "Pin" then
			continue
		end
		-- The tube/pin local X/Z axes (normalized — placements often carry
		-- scale) span the stud grid around the connector.
		local right = connection.transform.XVector
		local forward = connection.transform.ZVector
		if right.Magnitude < 1e-6 or forward.Magnitude < 1e-6 then
			continue
		end
		right = right.Unit * kCellOffset
		forward = forward.Unit * kCellOffset

		if connection.type == "Tube" then
			tryAdd(connection.position + right + forward, connection.direction)
			tryAdd(connection.position + right - forward, connection.direction)
			tryAdd(connection.position - right + forward, connection.direction)
			tryAdd(connection.position - right - forward, connection.direction)
			-- The tube's inside is stud-sized too: gripping a single stud
			-- centered in the tube (offset/"jumper" placements, and the
			-- whole connection for 1x1 round-bottom parts like antennas).
			tryAdd(connection.position, connection.direction)
		else -- Pin: neighbors along one (unknown) axis; bounds filtering culls the phantom pair
			tryAdd(connection.position + right, connection.direction)
			tryAdd(connection.position - right, connection.direction)
			tryAdd(connection.position + forward, connection.direction)
			tryAdd(connection.position - forward, connection.direction)
		end
	end

	table.sort(mSockets, function(lhs, rhs)
		if lhs.position.Y ~= rhs.position.Y then
			return lhs.position.Y < rhs.position.Y
		elseif lhs.position.X ~= rhs.position.X then
			return lhs.position.X < rhs.position.X
		else
			return lhs.position.Z < rhs.position.Z
		end
	end)

	return mSockets
end

return deriveSockets
