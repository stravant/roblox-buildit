--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local SetData = require(script.Parent.SetData)

return function(t: TestTypes.TestContext)
	t.test("serializes and deserializes a set", function()
		local data = SetData.new("Test Car")
		table.insert(data.steps, { kind = "bag" })
		table.insert(data.steps, {
			kind = "place",
			target = "main",
			partNumber = "3001",
			color = { 196, 40, 28 },
			cframe = SetData.packCFrame(CFrame.new(1, 2, 3) * CFrame.Angles(0, math.pi / 2, 0)),
		})
		table.insert(data.steps, { kind = "subbuild", id = "sub1" })
		table.insert(data.steps, {
			kind = "place",
			target = "sub1",
			partNumber = "3020",
			cframe = SetData.packCFrame(CFrame.identity),
		})
		table.insert(data.steps, {
			kind = "attach",
			id = "sub1",
			cframe = SetData.packCFrame(CFrame.new(0, 1, 0)),
		})

		local restored = SetData.deserialize(SetData.serialize(data))
		t.expect(restored).toBeTruthy()
		local roundTripped = restored :: SetData.SetData
		t.expect(roundTripped.name).toBe("Test Car")
		t.expect(#roundTripped.steps).toBe(5)
		t.expect(roundTripped.steps[2].partNumber).toBe("3001")
		t.expect(roundTripped.steps[2].color[1]).toBe(196)
		local cframe = SetData.unpackCFrame(roundTripped.steps[2].cframe :: { number })
		t.expect(cframe.Position).toBeCloseTo(Vector3.new(1, 2, 3))
		t.expect(cframe.XVector).toBeCloseTo(Vector3.new(0, 0, -1), 0.001)
	end)

	t.test("rejects garbage input", function()
		t.expect(SetData.deserialize("not json")).toBeFalsy()
		t.expect(SetData.deserialize('{"nope": true}')).toBeFalsy()
	end)

	t.test("activeTarget tracks open sub-builds", function()
		local steps: { SetData.Step } = {
			{ kind = "bag" },
			{ kind = "place", target = "main", partNumber = "3001", cframe = SetData.packCFrame(CFrame.identity) },
			{ kind = "subbuild", id = "sub1" },
			{ kind = "place", target = "sub1", partNumber = "3020", cframe = SetData.packCFrame(CFrame.identity) },
			{ kind = "attach", id = "sub1", cframe = SetData.packCFrame(CFrame.identity) },
			{ kind = "place", target = "main", partNumber = "3001", cframe = SetData.packCFrame(CFrame.identity) },
		}
		t.expect(SetData.activeTarget(steps, 0)).toBe("main")
		t.expect(SetData.activeTarget(steps, 2)).toBe("main")
		t.expect(SetData.activeTarget(steps, 3)).toBe("sub1")
		t.expect(SetData.activeTarget(steps, 4)).toBe("sub1")
		t.expect(SetData.activeTarget(steps, 5)).toBe("main")
		t.expect(SetData.activeTarget(steps, 6)).toBe("main")
	end)

	t.test("nextSubbuildId avoids used ids", function()
		local steps: { SetData.Step } = {
			{ kind = "subbuild", id = "sub1" },
			{ kind = "subbuild", id = "sub2" },
		}
		t.expect(SetData.nextSubbuildId(steps)).toBe("sub3")
		t.expect(SetData.nextSubbuildId({})).toBe("sub1")
	end)

	t.test("bagRanges partitions steps, with an implicit first bag", function()
		local place: SetData.Step = {
			kind = "place",
			target = "main",
			partNumber = "3001",
			cframe = SetData.packCFrame(CFrame.identity),
		}
		local steps: { SetData.Step } = {
			place,
			place,
			{ kind = "bag" },
			place,
			{ kind = "bag" },
			place,
			place,
		}
		local ranges = SetData.bagRanges(steps)
		t.expect(#ranges).toBe(3)
		t.expect(ranges[1].first).toBe(1)
		t.expect(ranges[1].last).toBe(2)
		t.expect(ranges[2].first).toBe(3)
		t.expect(ranges[2].last).toBe(4)
		t.expect(ranges[3].first).toBe(5)
		t.expect(ranges[3].last).toBe(7)
		t.expect(SetData.bagOfStep(steps, 4)).toBe(2)
		t.expect(SetData.bagOfStep(steps, 7)).toBe(3)

		-- Explicit bag first: no implicit range.
		local explicit: { SetData.Step } = { { kind = "bag" }, place }
		local explicitRanges = SetData.bagRanges(explicit)
		t.expect(#explicitRanges).toBe(1)
		t.expect(explicitRanges[1].first).toBe(1)
		t.expect(explicitRanges[1].last).toBe(2)
	end)

	t.test("partCounts tallies place steps in a range", function()
		local function place(partNumber: string): SetData.Step
			return {
				kind = "place",
				target = "main",
				partNumber = partNumber,
				cframe = SetData.packCFrame(CFrame.identity),
			}
		end
		local steps: { SetData.Step } = { { kind = "bag" }, place("3001"), place("3001"), place("3020") }
		local counts = SetData.partCounts(steps, 1, 4)
		t.expect(counts["3001"]).toBe(2)
		t.expect(counts["3020"]).toBe(1)
	end)
end
