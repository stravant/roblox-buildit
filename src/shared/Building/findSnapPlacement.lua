--!strict
--!native

-- Pure snap solver for the build tool.
--
-- Given the dragged part's connectors (part-local), the world connectors of
-- the existing assembly, and the ghost's current (unsnapped) CFrame, finds
-- the placement that mates a compatible connector pair, then reports every
-- connector pair that ends up mated under that placement (for
-- visualization).
--
-- Candidate choice: fewest remaining degrees of freedom first, translation
-- distance as the tiebreaker. A point mate (stud in socket, 0 DOF) beats
-- an axial slide (bar in clip, 1 DOF) even when the axial target is
-- closer; an axial mate whose lengths match (pin clicked into a peghole)
-- locks fully and counts as 0 DOF too.
--
-- Two mating rules:
--   Point (Stud <-> Socket): positions coincide, directions anti-parallel.
--   Axial (TechnicPin <-> PegHole, Axle <-> AxleHole, Bar <-> Clip): axes
--     parallel (either sign), centers on the same line, with the dragged
--     element free to slide along the axis by up to half the length
--     difference (a 2-long axle in a 1-long hole slides +-0.5; equal
--     lengths lock centered, which is how pins click in).
--
-- The candidate placement keeps the ghost's rotation: only translation is
-- solved, so the caller controls orientation (e.g. yaw stepping with R).

local getConnectors = require(script.Parent.getConnectors)

type Connector = getConnectors.Connector

export type WorldConnector = {
	kind: getConnectors.ConnectorKind,
	position: Vector3, -- world
	direction: Vector3, -- world unit, points toward the mating part
	length: number?, -- extent along direction (axial connectors)
	oneSided: boolean?, -- blind female bore, open only toward `direction`
	part: BasePart?,
	attachment: Attachment?,
}

export type SnapResult = {
	cframe: CFrame,
	-- Connector pairs mated under `cframe`, as indices into the input lists.
	matchedPairs: { { dragIndex: number, worldIndex: number } },
}

-- Point mates: directions must be anti-parallel (a stud points up into a
-- socket that points down at it). Axial mates: |dot| must exceed the
-- threshold (sign-free).
local kDirectionDotMax = -0.99
local kAxisDotMin = 0.99
-- How close two mated connectors must be under the final placement.
local kMatedEpsilon = 0.05

-- Axles fit through pin holes too (loose/rotating, but a valid build
-- connection), and bars insert into hollow studs.
local kAxialPartners: { [string]: { [string]: boolean } } = {
	TechnicPin = { PegHole = true },
	PegHole = { TechnicPin = true, Axle = true },
	Axle = { AxleHole = true, PegHole = true },
	AxleHole = { Axle = true },
	Bar = { Clip = true, HollowStud = true },
	Clip = { Bar = true },
	HollowStud = { Bar = true },
}

type MateRule = "point" | "axial"

local function mateRule(a: string, b: string): MateRule?
	if (a == "Stud" and b == "Socket") or (a == "Socket" and b == "Stud") then
		return "point"
	end
	local partners = kAxialPartners[a]
	if partners ~= nil and partners[b] then
		return "axial"
	end
	return nil
end

-- The dragged element may slide along the axis by half the length
-- difference before it would poke out of / lose its partner.
local function slideRange(lengthA: number?, lengthB: number?): number
	return math.abs((lengthA or 0) - (lengthB or 0)) / 2
end

-- One-sided (blind bore) mating interval: position of the male element's
-- center along the female's OPEN direction, from bottomed-out flush at the
-- bore floor (sMin) to half-engaged in the bore (sMax).
local function oneSidedInterval(maleLength: number, femaleLength: number): (number, number)
	local sMin = (maleLength - femaleLength) / 2
	return sMin, math.max(sMin, maleLength / 2)
end

local function findSnapPlacement(
	ghostCFrame: CFrame,
	dragConnectors: { Connector },
	worldConnectors: { WorldConnector },
	maxSnapDistance: number
): SnapResult?
	local rotation = ghostCFrame.Rotation
	local bestDegreesOfFreedom = math.huge
	local bestDistance = math.huge
	local bestCFrame: CFrame? = nil

	for _, world in worldConnectors do
		for _, drag in dragConnectors do
			local rule = mateRule(drag.kind, world.kind)
			if rule == nil then
				continue
			end
			local dragDirection = rotation:VectorToWorldSpace(drag.direction)
			local dragPosition = ghostCFrame:PointToWorldSpace(drag.position)

			local targetPosition: Vector3
			local degreesOfFreedom: number
			if rule == "point" then
				if dragDirection:Dot(world.direction) > kDirectionDotMax then
					continue
				end
				targetPosition = world.position
				degreesOfFreedom = 0
			else -- axial
				if math.abs(dragDirection:Dot(world.direction)) < kAxisDotMin then
					continue
				end
				if world.oneSided or drag.oneSided then
					local femaleIsWorld = world.oneSided == true
					local femaleDirection = if femaleIsWorld then world.direction else dragDirection
					local femaleLength = (if femaleIsWorld then world.length else drag.length) or 0
					local maleLength = (if femaleIsWorld then drag.length else world.length) or 0
					local sMin, sMax = oneSidedInterval(maleLength, femaleLength)
					if femaleIsWorld then
						local s = math.clamp((dragPosition - world.position):Dot(femaleDirection), sMin, sMax)
						targetPosition = world.position + femaleDirection * s
					else
						local s = math.clamp((world.position - dragPosition):Dot(femaleDirection), sMin, sMax)
						targetPosition = world.position - femaleDirection * s
					end
					degreesOfFreedom = if sMax > sMin then 1 else 0
				else
					local along = (dragPosition - world.position):Dot(world.direction)
					local range = slideRange(drag.length, world.length)
					targetPosition = world.position
						+ world.direction * math.clamp(along, -range, range)
					degreesOfFreedom = if range > 0 then 1 else 0
				end
			end

			local distance = (dragPosition - targetPosition).Magnitude
			if distance > maxSnapDistance then
				continue
			end
			if
				degreesOfFreedom < bestDegreesOfFreedom
				or (degreesOfFreedom == bestDegreesOfFreedom and distance < bestDistance)
			then
				bestDegreesOfFreedom = degreesOfFreedom
				bestDistance = distance
				bestCFrame = rotation
					+ (ghostCFrame.Position + targetPosition - dragPosition)
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
			local rule = mateRule(drag.kind, world.kind)
			local mated = false
			if rule == "point" then
				mated = (dragPosition - world.position).Magnitude <= kMatedEpsilon
					and dragDirection:Dot(world.direction) <= kDirectionDotMax
			elseif rule == "axial" then
				if math.abs(dragDirection:Dot(world.direction)) >= kAxisDotMin then
					if world.oneSided or drag.oneSided then
						local femaleIsWorld = world.oneSided == true
						local femaleDirection = if femaleIsWorld then world.direction else dragDirection
						local femaleLength = (if femaleIsWorld then world.length else drag.length) or 0
						local maleLength = (if femaleIsWorld then drag.length else world.length) or 0
						local sMin, sMax = oneSidedInterval(maleLength, femaleLength)
						local delta = if femaleIsWorld
							then dragPosition - world.position
							else world.position - dragPosition
						local s = delta:Dot(femaleDirection)
						local perpendicular = (delta - femaleDirection * s).Magnitude
						mated = perpendicular <= kMatedEpsilon
							and s >= sMin - kMatedEpsilon
							and s <= sMax + kMatedEpsilon
					else
						local delta = dragPosition - world.position
						local along = delta:Dot(world.direction)
						local perpendicular = (delta - world.direction * along).Magnitude
						mated = perpendicular <= kMatedEpsilon
							and math.abs(along) <= slideRange(drag.length, world.length) + kMatedEpsilon
					end
				end
			end
			if mated then
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
