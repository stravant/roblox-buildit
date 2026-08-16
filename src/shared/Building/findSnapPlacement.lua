--!strict
--!native

-- Pure snap solver for the build tool.
--
-- Given the dragged part's connectors (part-local), the world connectors of
-- the existing assembly, and the ghost's current (unsnapped) CFrame, finds
-- the placement that mates a compatible connector pair (Stud <-> Socket,
-- directions opposed) while moving the part the least, then reports every
-- connector pair that ends up mated under that placement (for
-- visualization).
--
-- The candidate placement keeps the ghost's rotation: only translation is
-- solved, so the caller controls orientation (e.g. yaw stepping with R).

local getConnectors = require(script.Parent.getConnectors)

type Connector = getConnectors.Connector

export type WorldConnector = {
	kind: getConnectors.ConnectorKind,
	position: Vector3, -- world
	direction: Vector3, -- world unit, points toward the mating part
	part: BasePart?,
	attachment: Attachment?,
}

export type SnapResult = {
	cframe: CFrame,
	-- Connector pairs mated under `cframe`, as indices into the input lists.
	matchedPairs: { { dragIndex: number, worldIndex: number } },
}

-- Directions must be anti-parallel (a stud points up into a socket that
-- points down at it).
local kDirectionDotMax = -0.99
-- How close two mated connectors must be under the final placement.
local kMatedEpsilon = 0.05

local function isCompatible(a: string, b: string): boolean
	return (a == "Stud" and b == "Socket") or (a == "Socket" and b == "Stud")
end

local function findSnapPlacement(
	ghostCFrame: CFrame,
	dragConnectors: { Connector },
	worldConnectors: { WorldConnector },
	maxSnapDistance: number
): SnapResult?
	local rotation = ghostCFrame.Rotation
	local bestDistance = maxSnapDistance
	local bestCFrame: CFrame? = nil

	for _, world in worldConnectors do
		for _, drag in dragConnectors do
			if not isCompatible(drag.kind, world.kind) then
				continue
			end
			local dragDirection = rotation:VectorToWorldSpace(drag.direction)
			if dragDirection:Dot(world.direction) > kDirectionDotMax then
				continue
			end
			local dragPosition = ghostCFrame:PointToWorldSpace(drag.position)
			local distance = (dragPosition - world.position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				bestCFrame = rotation + (world.position - rotation:VectorToWorldSpace(drag.position))
			end
		end
	end

	if bestCFrame == nil then
		return nil
	end
	local snappedCFrame = bestCFrame :: CFrame

	local matchedPairs: { { dragIndex: number, worldIndex: number } } = {}
	for dragIndex, drag in dragConnectors do
		local dragPosition = snappedCFrame:PointToWorldSpace(drag.position)
		local dragDirection = snappedCFrame:VectorToWorldSpace(drag.direction)
		for worldIndex, world in worldConnectors do
			if
				isCompatible(drag.kind, world.kind)
				and (dragPosition - world.position).Magnitude <= kMatedEpsilon
				and dragDirection:Dot(world.direction) <= kDirectionDotMax
			then
				table.insert(matchedPairs, { dragIndex = dragIndex, worldIndex = worldIndex })
				break
			end
		end
	end

	return {
		cframe = snappedCFrame,
		matchedPairs = matchedPairs,
	}
end

return findSnapPlacement
