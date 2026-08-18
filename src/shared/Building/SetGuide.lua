--!strict

-- Pure guidance logic for following a set: which pending steps a
-- dragged pile part could satisfy, and which one (if any) it should
-- snap to given where the player is holding it.

local SetData = require(script.Parent.SetData)

local SetGuide = {}

-- How close (studs) the held part must be to a target pose before it
-- snaps in.
SetGuide.kSnapRadius = 4

local function colorsMatch(a: { number }?, b: { number }?): boolean
	if a == nil or b == nil then
		return true -- untinted sets/parts match anything
	end
	local ca = a :: { number }
	local cb = b :: { number }
	return math.abs(ca[1] - cb[1]) <= 2 and math.abs(ca[2] - cb[2]) <= 2 and math.abs(ca[3] - cb[3]) <= 2
end

-- Pending place steps in [first, last] that the given part identity
-- can satisfy.
function SetGuide.matchingSteps(
	steps: { SetData.Step },
	done: { [number]: boolean },
	first: number,
	last: number,
	partNumber: string,
	color: { number }?
): { number }
	local matches = {}
	for index = first, last do
		local step = steps[index]
		if
			step ~= nil
			and step.kind == "place"
			and not done[index]
			and step.partNumber == partNumber
			and colorsMatch(step.color, color)
		then
			table.insert(matches, index)
		end
	end
	return matches
end

-- The step whose target position is nearest the held point, within the
-- snap radius. `targetPosition` maps a step index to the world position
-- its part would land at (root pivot * step cframe).
function SetGuide.pickTarget(
	candidates: { number },
	targetPosition: (index: number) -> Vector3,
	heldPoint: Vector3,
	radius: number?
): number?
	local snapRadius = radius or SetGuide.kSnapRadius
	local best: number? = nil
	local bestDistance = math.huge
	for _, index in candidates do
		local distance = (targetPosition(index) - heldPoint).Magnitude
		if distance <= snapRadius and distance < bestDistance then
			best = index
			bestDistance = distance
		end
	end
	return best
end

-- The next not-done step index in [first, last], for the hint ghost
-- and progress display. Attach steps only become "next" once every
-- other step in the range is done (you finish the sub-build first).
function SetGuide.nextStep(
	steps: { SetData.Step },
	done: { [number]: boolean },
	first: number,
	last: number
): number?
	local pendingAttach: number? = nil
	for index = first, last do
		local step = steps[index]
		if step == nil or done[index] then
			continue
		end
		if step.kind == "place" then
			return index
		elseif step.kind == "attach" and pendingAttach == nil then
			pendingAttach = index
		end
	end
	return pendingAttach
end

-- True when every place/attach step in the range is done (bag drained).
function SetGuide.rangeComplete(
	steps: { SetData.Step },
	done: { [number]: boolean },
	first: number,
	last: number
): boolean
	for index = first, last do
		local step = steps[index]
		if step ~= nil and (step.kind == "place" or step.kind == "attach") and not done[index] then
			return false
		end
	end
	return true
end

return SetGuide
