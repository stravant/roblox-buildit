--!strict

-- What a code-driven gear spin carries along. The gear drive poses a
-- driven group by rotating it about its gear axis; constraint
-- NEIGHBORS of that group are not physically simulated during the
-- pose, so anything hanging off the group must be classified:
--
--   - COAXIAL joints (axis parallel to the spin axis AND positioned on
--     the spin line) are bearings: spinning does not move them. The
--     gear's own axle bearing in the beam stays put.
--   - Everything else is a SATELLITE: it rides the spinning group
--     rigidly (a pin stuck in an off-center gear hole orbits with the
--     gear), transitively (something clipped to that pin comes too).
--
-- Pure closure over the applied constraint pairs; the caller supplies
-- the part -> rigid-group-root mapping and any roots that must never
-- be carried (ground, the grabbed group).

local applyPhysicsJoints = require(script.Parent.applyPhysicsJoints)

local kAxisParallelDot = 0.99
local kOnAxisTolerance = 0.1 -- studs

-- Returns the set of rigid-group roots rigidly carried by spinning
-- `baseRoot` about the line (spinCenter, spinAxis). Always includes
-- baseRoot itself.
local function gearSatellites(
	constraintPairs: { applyPhysicsJoints.ConstraintPair },
	rootOf: (BasePart) -> BasePart,
	baseRoot: BasePart,
	spinCenter: Vector3,
	spinAxis: Vector3,
	excludedRoots: { [BasePart]: boolean }
): { [BasePart]: boolean }
	local included: { [BasePart]: boolean } = { [baseRoot] = true }
	local changed = true
	while changed do
		changed = false
		for _, entry in constraintPairs do
			local root0 = rootOf(entry.part0)
			local root1 = rootOf(entry.part1)
			local inside0 = included[root0] == true
			local inside1 = included[root1] == true
			if inside0 == inside1 then
				continue
			end
			local outside = if inside0 then root1 else root0
			if excludedRoots[outside] then
				continue
			end
			if math.abs(entry.axis:Dot(spinAxis)) > kAxisParallelDot then
				local offset = entry.position - spinCenter
				offset -= spinAxis * offset:Dot(spinAxis)
				if offset.Magnitude < kOnAxisTolerance then
					continue -- coaxial bearing: unaffected by the spin
				end
			end
			included[outside] = true
			changed = true
		end
	end
	return included
end

return gearSatellites
