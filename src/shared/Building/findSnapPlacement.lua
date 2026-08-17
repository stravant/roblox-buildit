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
-- Three mating rules:
--   Point (Stud <-> Socket): positions coincide, directions anti-parallel.
--   Axial (TechnicPin <-> PegHole, Axle <-> AxleHole, Bar <-> Clip): axes
--     parallel (either sign), centers on the same line, with the dragged
--     element free to slide along the axis by up to half the length
--     difference (a 2-long axle in a 1-long hole slides +-0.5; equal
--     lengths lock centered, which is how pins click in).
--   Ball (Towball <-> TowballSocket): centers coincide, NO direction
--     constraint — ball joints mate at any rotation.
--   Mouth (Stud <-> PegHole): a stud inserts into a pin hole's mouth
--     from either end (minifig head on the neck post, and the classic
--     stud-in-technic-hole technique). The stud locks to the nearer
--     mouth, pointing into the hole.
--
-- Candidates whose mating axes are misaligned by up to 60 degrees get a
-- shortest-arc ALIGNMENT ROTATION applied to the whole dragged unit (a
-- bar rotates into a minifig hand's tilted grip; a stud onto a tilted
-- socket). Beyond the cone the candidate is rejected, so perpendicular
-- and upside-down mates never engage. The user's R/T orientation is the
-- starting point the alignment adjusts from.
--
-- `grabPosition` (optional, world): where the user grabbed the dragged
-- unit. Candidates additionally prefer mating connectors near the grab
-- point, so a part held by one end snaps by that end (and symmetric ties
-- resolve toward the cursor).

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
-- connection), bars insert into hollow studs, and bars pass through
-- axle holes (a bevel gear sits on the differential cage's post).
local kAxialPartners: { [string]: { [string]: boolean } } = {
	TechnicPin = { PegHole = true },
	PegHole = { TechnicPin = true, Axle = true },
	Axle = { AxleHole = true, PegHole = true },
	AxleHole = { Axle = true, Bar = true },
	Bar = { Clip = true, HollowStud = true, BarHole = true, AxleHole = true },
	Clip = { Bar = true },
	HollowStud = { Bar = true },
	BarHole = { Bar = true, WheelPin = true },
	WheelPin = { WheelHole = true, BarHole = true },
	WheelHole = { WheelPin = true },
	SlideRail = { SlideGroove = true },
	SlideGroove = { SlideRail = true },
	SlipAxle = { SlipRing = true },
	SlipRing = { SlipAxle = true },
	HingePin = { HingeSocket = true },
	HingeSocket = { HingePin = true },
	HingeFinger = { HingeFinger = true },
	ClickFinger = { ClickFork = true },
	ClickFork = { ClickFinger = true },
	ArmFinger = { ArmFinger = true },
	TyreBore = { RimSeat = true },
	RimSeat = { TyreBore = true },
}

type MateRule = "point" | "axial" | "ball" | "mouth"

local function mateRule(a: string, b: string): MateRule?
	if (a == "Stud" and b == "Socket") or (a == "Socket" and b == "Stud") then
		return "point"
	elseif a == "Magnet" and b == "Magnet" then
		-- Pole faces couple coincident and anti-parallel, same as studs.
		return "point"
	elseif a == "TrackEnd" and b == "TrackEnd" then
		-- Track ends join face-to-face, same shape as magnets.
		return "point"
	elseif a == "CoasterEnd" and b == "CoasterEnd" then
		return "point"
	elseif (a == "Towball" and b == "TowballSocket") or (a == "TowballSocket" and b == "Towball") then
		return "ball"
	elseif (a == "Stud" and b == "PegHole") or (a == "PegHole" and b == "Stud") then
		return "mouth"
	end
	local partners = kAxialPartners[a]
	if partners ~= nil and partners[b] then
		return "axial"
	end
	return nil
end

-- Size-keyed interfaces (TyreBore/RimSeat) carry a mating radius; a
-- candidate pair only mates when both radii agree within tolerance
-- (0.15 studs = 3 LDU covers the mm rounding in official part names).
local kRadiusTolerance = 0.15

local function radiusCompatible(a: { radius: number? }, b: { radius: number? }): boolean
	if a.radius == nil and b.radius == nil then
		return true
	end
	if a.radius == nil or b.radius == nil then
		return false
	end
	return math.abs((a.radius :: number) - (b.radius :: number)) <= kRadiusTolerance
end

-- Both mouths of a hole connector (its segment ends; a bare mouth with
-- no length is its own single mouth).
local function holeMouths(position: Vector3, direction: Vector3, length: number?): (Vector3, Vector3)
	local halfSpan = direction * ((length or 0) / 2)
	return position - halfSpan, position + halfSpan
end

-- The dragged element may slide along the axis by half the length
-- difference before it would poke out of / lose its partner.
local function slideRange(lengthA: number?, lengthB: number?): number
	return math.abs((lengthA or 0) - (lengthB or 0)) / 2
end

-- Secondary scoring weight for distance from the grab point: strong
-- enough to resolve ties toward the cursor, weak enough that a genuinely
-- closer snap still wins.
local kGrabBiasWeight = 0.3

-- Alignment rotation: candidates misaligned by up to this get rotated
-- into place (minifig hand grips sit at ~46 degrees); beyond it they
-- reject, so perpendicular/upside-down mates never engage.
local kMaxAlignmentAngle = math.rad(60)
-- Score penalty per radian of alignment, so an already-aligned candidate
-- beats a rotated one at similar distance.
local kRotationPenaltyWeight = 0.5

-- Shortest-arc rotation taking unit vector `from` onto `to`, or nil if
-- outside the alignment cone.
local function shortestArc(from: Vector3, to: Vector3): (CFrame?, number)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle < 1e-4 then
		return CFrame.identity, 0
	end
	if angle > kMaxAlignmentAngle then
		return nil, angle
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-6 then
		return nil, angle
	end
	return CFrame.fromAxisAngle(axis.Unit, angle), angle
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
	maxSnapDistance: number,
	grabPosition: Vector3?
): SnapResult?
	local rotation = ghostCFrame.Rotation
	local bestDegreesOfFreedom = math.huge
	local bestDistance = math.huge
	local bestCFrame: CFrame? = nil

	for _, world in worldConnectors do
		for _, drag in dragConnectors do
			local rule = mateRule(drag.kind, world.kind)
			if rule == nil or not radiusCompatible(drag, world) then
				continue
			end
			local baseDirection = rotation:VectorToWorldSpace(drag.direction)
			local basePosition = ghostCFrame:PointToWorldSpace(drag.position)

			-- Desired world direction for the drag connector; alignment
			-- rotates the whole unit to it when within the cone.
			local desired: Vector3? = nil
			if rule == "point" then
				desired = -world.direction
			elseif rule == "ball" then
				desired = nil -- rotation-free
			elseif rule == "mouth" and drag.kind == "Stud" then
				local mouthA, mouthB = holeMouths(world.position, world.direction, world.length)
				local mouth = if (basePosition - mouthA).Magnitude <= (basePosition - mouthB).Magnitude
					then mouthA
					else mouthB
				local into = world.position - mouth
				desired = if into.Magnitude > 1e-4 then into.Unit else -world.direction
			else -- axial, or mouth with the hole dragged
				desired = if baseDirection:Dot(world.direction) >= 0
					then world.direction
					else -world.direction
			end

			local alignment: CFrame? = CFrame.identity
			local alignmentAngle = 0
			if desired ~= nil then
				alignment, alignmentAngle = shortestArc(baseDirection.Unit, desired)
				if alignment == nil then
					continue
				end
			end
			local candidateRotation = (alignment :: CFrame) * rotation
			local dragDirection = candidateRotation:VectorToWorldSpace(drag.direction)
			local dragPosition = ghostCFrame.Position + candidateRotation:VectorToWorldSpace(drag.position)

			local targetPosition: Vector3
			local degreesOfFreedom: number
			if rule == "point" then
				targetPosition = world.position
				degreesOfFreedom = 0
			elseif rule == "ball" then
				-- Rotation-free: translationally locked, but rank between
				-- point locks and axial slides.
				targetPosition = world.position
				degreesOfFreedom = 0.5
			elseif rule == "mouth" then
				if drag.kind == "Stud" then
					local mouthA, mouthB = holeMouths(world.position, world.direction, world.length)
					targetPosition = if (basePosition - mouthA).Magnitude <= (basePosition - mouthB).Magnitude
						then mouthA
						else mouthB
				else
					-- Dragging the hole onto a fixed stud: a mouth lands on
					-- the stud, hole center half a length along the stud.
					targetPosition = world.position + world.direction * ((drag.length or 0) / 2)
				end
				degreesOfFreedom = 0
			else -- axial
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

			-- Cursor-proximity metric: how far the connector sits from the
			-- target BEFORE any alignment rotation.
			local distance = (basePosition - targetPosition).Magnitude
			if distance > maxSnapDistance then
				continue
			end
			local score = distance + kRotationPenaltyWeight * alignmentAngle
			if grabPosition ~= nil then
				score += kGrabBiasWeight * (basePosition - grabPosition).Magnitude
			end
			if
				degreesOfFreedom < bestDegreesOfFreedom
				or (degreesOfFreedom == bestDegreesOfFreedom and score < bestDistance)
			then
				bestDegreesOfFreedom = degreesOfFreedom
				bestDistance = score
				bestCFrame = candidateRotation
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
			if rule ~= nil and not radiusCompatible(drag, world) then
				rule = nil
			end
			local mated = false
			if rule == "point" then
				mated = (dragPosition - world.position).Magnitude <= kMatedEpsilon
					and dragDirection:Dot(world.direction) <= kDirectionDotMax
			elseif rule == "ball" then
				mated = (dragPosition - world.position).Magnitude <= kMatedEpsilon
			elseif rule == "mouth" then
				if math.abs(dragDirection:Dot(world.direction)) >= kAxisDotMin then
					local studPosition = if drag.kind == "Stud" then dragPosition else world.position
					local holePosition = if drag.kind == "Stud" then world.position else dragPosition
					local holeDirection = if drag.kind == "Stud" then world.direction else dragDirection
					local holeLength = if drag.kind == "Stud" then world.length else drag.length
					local mouthA, mouthB = holeMouths(holePosition, holeDirection, holeLength)
					mated = (studPosition - mouthA).Magnitude <= kMatedEpsilon
						or (studPosition - mouthB).Magnitude <= kMatedEpsilon
				end
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
