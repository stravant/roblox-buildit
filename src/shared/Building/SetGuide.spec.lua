--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local SetData = require(script.Parent.SetData)
local SetGuide = require(script.Parent.SetGuide)

local function place(partNumber: string, x: number, color: { number }?): SetData.Step
	return {
		kind = "place",
		target = "main",
		partNumber = partNumber,
		color = color,
		cframe = SetData.packCFrame(CFrame.new(x, 0, 0)),
	}
end

return function(t: TestTypes.TestContext)
	t.test("matchingSteps filters by part, color, doneness, range", function()
		local steps: { SetData.Step } = {
			{ kind = "bag" },
			place("3001", 0, { 196, 40, 28 }),
			place("3001", 2, { 13, 105, 172 }),
			place("3020", 4),
			place("3001", 6, { 196, 40, 28 }),
		}
		-- Red 2x4: steps 2 and 5 match; 3 is blue, 4 is another part.
		local matches = SetGuide.matchingSteps(steps, {}, 1, 5, "3001", { 196, 40, 28 })
		t.expect(#matches).toBe(2)
		t.expect(matches[1]).toBe(2)
		t.expect(matches[2]).toBe(5)
		-- Done steps drop out.
		matches = SetGuide.matchingSteps(steps, { [2] = true }, 1, 5, "3001", { 196, 40, 28 })
		t.expect(#matches).toBe(1)
		t.expect(matches[1]).toBe(5)
		-- Range clips.
		matches = SetGuide.matchingSteps(steps, {}, 1, 3, "3001", { 196, 40, 28 })
		t.expect(#matches).toBe(1)
		-- Nil color matches anything.
		matches = SetGuide.matchingSteps(steps, {}, 1, 5, "3001", nil)
		t.expect(#matches).toBe(3)
	end)

	t.test("pickTarget takes the nearest candidate within the radius", function()
		local positions: { [number]: Vector3 } = {
			[2] = Vector3.new(0, 0, 0),
			[5] = Vector3.new(6, 0, 0),
		}
		local function at(index: number): Vector3
			return positions[index]
		end
		t.expect(SetGuide.pickTarget({ 2, 5 }, at, Vector3.new(1, 0, 0), 4)).toBe(2)
		t.expect(SetGuide.pickTarget({ 2, 5 }, at, Vector3.new(5, 0, 0), 4)).toBe(5)
		t.expect(SetGuide.pickTarget({ 2, 5 }, at, Vector3.new(20, 0, 0), 4)).toBe(nil)
	end)

	t.test("nextStep defers attach until the rest of the range is done", function()
		local steps: { SetData.Step } = {
			{ kind = "bag" },
			{ kind = "subbuild", id = "sub1" },
			{
				kind = "place",
				target = "sub1",
				partNumber = "3001",
				cframe = SetData.packCFrame(CFrame.identity),
			},
			{ kind = "attach", id = "sub1", cframe = SetData.packCFrame(CFrame.identity) },
			place("3020", 0),
		}
		-- Place steps first, in order.
		t.expect(SetGuide.nextStep(steps, {}, 1, 5)).toBe(3)
		t.expect(SetGuide.nextStep(steps, { [3] = true }, 1, 5)).toBe(5)
		-- Attach only once every place is done.
		t.expect(SetGuide.nextStep(steps, { [3] = true, [5] = true }, 1, 5)).toBe(4)
		t.expect(SetGuide.nextStep(steps, { [3] = true, [4] = true, [5] = true }, 1, 5)).toBe(nil)
	end)

	t.test("step markers split a bag into instruction steps", function()
		local steps: { SetData.Step } = {
			{ kind = "bag" }, -- 1
			place("3001", 0), -- 2
			place("3020", 2), -- 3
			{ kind = "step" }, -- 4
			place("3001", 4), -- 5
		}
		local runs = SetGuide.stepRuns(steps, 1, 5)
		t.expect(#runs).toBe(2)
		t.expect(runs[1].first).toBe(1)
		t.expect(runs[1].last).toBe(3)
		t.expect(runs[2].first).toBe(4)
		t.expect(runs[2].last).toBe(5)

		-- Current run: first with pending work; advances when drained.
		local first, last, ordinal, count = SetGuide.currentRun(steps, {}, 1, 5)
		t.expect(first).toBe(1)
		t.expect(last).toBe(3)
		t.expect(ordinal).toBe(1)
		t.expect(count).toBe(2)
		first, last, ordinal = SetGuide.currentRun(steps, { [2] = true, [3] = true }, 1, 5)
		t.expect(first).toBe(4)
		t.expect(ordinal).toBe(2)
		t.expect(SetGuide.currentRun(steps, { [2] = true, [3] = true, [5] = true }, 1, 5)).toBe(nil)

		-- All pending places of the current step, for the hint ghosts.
		local pending = SetGuide.pendingPlaces(steps, { [2] = true }, 1, 3)
		t.expect(#pending).toBe(1)
		t.expect(pending[1]).toBe(3)

		-- No markers: the whole bag is one step.
		local flat: { SetData.Step } = { { kind = "bag" }, place("3001", 0) }
		local flatRuns = SetGuide.stepRuns(flat, 1, 2)
		t.expect(#flatRuns).toBe(1)
	end)

	t.test("rangeComplete requires every place and attach done", function()
		local steps: { SetData.Step } = {
			{ kind = "bag" },
			place("3001", 0),
			{ kind = "attach", id = "sub1", cframe = SetData.packCFrame(CFrame.identity) },
		}
		t.expect(SetGuide.rangeComplete(steps, {}, 1, 3)).toBe(false)
		t.expect(SetGuide.rangeComplete(steps, { [2] = true }, 1, 3)).toBe(false)
		t.expect(SetGuide.rangeComplete(steps, { [2] = true, [3] = true }, 1, 3)).toBe(true)
	end)
end
