--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local gearMeshPhase = require(script.Parent.gearMeshPhase)

-- Two 8-tooth gears on axis Z, centers 1 stud apart (pitch radii 0.5 +
-- 0.5). Driver at origin with a tooth pointing at the contact (+X);
-- a properly meshed partner carries its nearest tooth half a pitch off
-- the contact line.
local kAxis = Vector3.new(0, 0, 1)
local kFromCenter = Vector3.zero
local kToCenter = Vector3.new(1, 0, 0)
local kHalfPitch = math.pi / 8 -- half of 2pi/8

local function rotated(direction: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(kAxis, angle) * direction
end

return function(t: TestTypes.TestContext)
	t.test("a properly meshed pair needs zero correction", function()
		-- Driven reference: tooth toward the driver (-X), offset half a
		-- pitch = meshed.
		local toReference = rotated(Vector3.new(-1, 0, 0), kHalfPitch)
		local phase =
			gearMeshPhase(Vector3.new(1, 0, 0), toReference, kAxis, kFromCenter, kToCenter, 8, 8)
		t.expect(phase).toBeCloseTo(0, 0.0001)
	end)

	t.test("a perturbed driven gear gets exactly the undo rotation", function()
		-- Perturb the meshed pose by rotating the driven gear CCW by a
		-- quarter pitch: the correction must be exactly that rotation
		-- backwards. (The sign matters: flipped, the correction DOUBLES
		-- the error and the gears twitch on every grab.)
		local perturbation = (math.pi / 4) / 8 -- quarter pitch of an 8t
		local toReference = rotated(Vector3.new(-1, 0, 0), kHalfPitch + perturbation)
		local phase =
			gearMeshPhase(Vector3.new(1, 0, 0), toReference, kAxis, kFromCenter, kToCenter, 8, 8)
		t.expect(phase).toBeCloseTo(-perturbation, 0.0001)
	end)

	t.test("correction is idempotent: applying it yields zero next time", function()
		local perturbation = 0.11
		local toReference = rotated(Vector3.new(-1, 0, 0), kHalfPitch + perturbation)
		local phase =
			gearMeshPhase(Vector3.new(1, 0, 0), toReference, kAxis, kFromCenter, kToCenter, 8, 8)
		local corrected = rotated(toReference, phase)
		local phaseAfter =
			gearMeshPhase(Vector3.new(1, 0, 0), corrected, kAxis, kFromCenter, kToCenter, 8, 8)
		t.expect(phaseAfter).toBeCloseTo(0, 0.0001)
	end)

	t.test("mixed tooth counts mesh at the contact, not by angle", function()
		-- 8t driving 24t, centers 2 apart (0.5 + 1.5). Driver tooth at
		-- the contact; driven meshed = tooth half of ITS pitch off.
		local toCenter = Vector3.new(2, 0, 0)
		local halfPitch24 = math.pi / 24
		local toReference = rotated(Vector3.new(-1, 0, 0), halfPitch24)
		local phase =
			gearMeshPhase(Vector3.new(1, 0, 0), toReference, kAxis, kFromCenter, toCenter, 8, 24)
		t.expect(phase).toBeCloseTo(0, 0.0001)
		-- Perturbed by a third of the 24t pitch.
		local perturbation = (2 * math.pi / 24) / 3
		local perturbed = rotated(toReference, perturbation)
		local perturbedPhase =
			gearMeshPhase(Vector3.new(1, 0, 0), perturbed, kAxis, kFromCenter, toCenter, 8, 24)
		t.expect(perturbedPhase).toBeCloseTo(-perturbation, 0.0001)
	end)

	t.test("missing references mean no correction", function()
		t.expect(gearMeshPhase(nil, Vector3.new(-1, 0, 0), kAxis, kFromCenter, kToCenter, 8, 8)).toBe(0)
		t.expect(gearMeshPhase(Vector3.new(1, 0, 0), nil, kAxis, kFromCenter, kToCenter, 8, 8)).toBe(0)
		-- Reference parallel to the axis is degenerate.
		t.expect(gearMeshPhase(kAxis, Vector3.new(-1, 0, 0), kAxis, kFromCenter, kToCenter, 8, 8)).toBe(0)
	end)
end
