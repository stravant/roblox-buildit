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
-- Candidate choice: a single weighted score — translation distance,
-- distance from the grab point (both which drag connector engages and
-- where it lands, so the joint under the cursor wins), remaining
-- degrees of freedom (a locking mate is worth a modest distance
-- advantage, not an absolute one), a penalty for loose fallback fits
-- (an axle resting in a round pin hole never beats the axle hole
-- beside it), and the alignment rotation.
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
local mates = require(script.Parent.mates)

type Connector = getConnectors.Connector

export type WorldConnector = {
	kind: getConnectors.ConnectorKind,
	position: Vector3, -- world
	direction: Vector3, -- world unit, points toward the mating part
	length: number?, -- extent along direction (axial connectors)
	oneSided: boolean?, -- blind female bore, open only toward `direction`
	secondary: Vector3?, -- axle cross orientation (keyed roll alignment)
	part: BasePart?,
	attachment: Attachment?,
}

export type SnapResult = {
	cframe: CFrame,
	-- Connector pairs mated under `cframe`, as indices into the input lists.
	matchedPairs: { { dragIndex: number, worldIndex: number } },
}

-- Mating rules, partner table, and geometric helpers live in mates.lua
-- (shared with AssemblyGraph so "engaged" means the same thing there).
local kDirectionDotMax = mates.kDirectionDotMax
local kAxisDotMin = mates.kAxisDotMin
local kMatedEpsilon = mates.kMatedEpsilon
type MateRule = mates.MateRule
local mateRule = mates.rule
local radiusCompatible = mates.radiusCompatible
local holeMouths = mates.holeMouths
local slideRange = mates.slideRange

-- Scoring weight for distance from the grab point, applied to BOTH the
-- drag connector's current position and where it would land — so a part
-- held by one end snaps by that end, and among several world joints the
-- one under the cursor wins.
local kGrabBiasWeight = 0.5
-- Score penalty per remaining degree of freedom (studs): a locking mate
-- (stud, clicked pin) is preferred over a slide, but only as a modest
-- distance advantage — it must not hijack the joint under the cursor
-- (a stud mouthing into a gear's pin hole must not beat the axle mate
-- being aimed at the gear's bore).
local kDofPenaltyWeight = 0.75
-- Score penalty for loose fallback fits (mates.isLooseKindPair — axle
-- in a round pin hole, bar through a bore): valid mates, but never
-- preferred over a proper fit nearby.
local kLoosePairPenalty = 1.5

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
local oneSidedInterval = mates.oneSidedInterval

-- Keyed pairs roll-align on snap: the axle cross has 4-fold symmetry,
-- so the dragged unit additionally rotates about the mate axis to the
-- nearest 90-degree cross fit.
local kKeyedRollPairs: { [string]: { [string]: boolean } } = {
	Axle = { AxleHole = true },
	AxleHole = { Axle = true },
	SlipAxle = { SlipRing = true },
	SlipRing = { SlipAxle = true },
}

local function findSnapPlacement(
	ghostCFrame: CFrame,
	dragConnectors: { Connector },
	worldConnectors: { WorldConnector },
	maxSnapDistance: number,
	grabPosition: Vector3?
): SnapResult?
	local rotation = ghostCFrame.Rotation
	local bestScore = math.huge
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
			-- Keyed cross roll alignment (axle in axle hole).
			if
				rule == "axial"
				and kKeyedRollPairs[drag.kind] ~= nil
				and kKeyedRollPairs[drag.kind][world.kind]
				and drag.secondary ~= nil
				and world.secondary ~= nil
			then
				local axis = world.direction
				local from = candidateRotation:VectorToWorldSpace(drag.secondary :: Vector3)
				from -= axis * from:Dot(axis)
				local to = (world.secondary :: Vector3) - axis * (world.secondary :: Vector3):Dot(axis)
				if from.Magnitude > 1e-3 and to.Magnitude > 1e-3 then
					from = from.Unit
					to = to.Unit
					local angle = math.atan2(from:Cross(to):Dot(axis), from:Dot(to))
					local quarter = math.pi / 2
					-- Minimal roll to the nearest quarter-turn fit.
					local roll = angle - math.round(angle / quarter) * quarter
					candidateRotation = CFrame.fromAxisAngle(axis, roll) * candidateRotation
				end
			end
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
			local score = distance
				+ kRotationPenaltyWeight * alignmentAngle
				+ kDofPenaltyWeight * degreesOfFreedom
			if mates.isLooseKindPair(drag.kind, world.kind) then
				score += kLoosePairPenalty
			end
			if grabPosition ~= nil then
				local grab = grabPosition :: Vector3
				score += kGrabBiasWeight
					* ((basePosition - grab).Magnitude + (targetPosition - grab).Magnitude)
			end
			if score < bestScore then
				bestScore = score
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
			local mated = mates.check({
				kind = drag.kind,
				position = dragPosition,
				direction = dragDirection,
				length = drag.length,
				oneSided = drag.oneSided,
				radius = drag.radius,
			}, world :: any) ~= nil
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
