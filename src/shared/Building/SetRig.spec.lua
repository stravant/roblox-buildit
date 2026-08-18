--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local SetData = require(script.Parent.SetData)
local SetRig = require(script.Parent.SetRig)

-- Minimal stand-in part library: plain parts with PartNumber attributes.
local function makeTemplates(): Folder
	local folder = Instance.new("Folder")
	for _, partNumber in { "3001", "3020" } do
		local part = Instance.new("Part")
		part.Name = `Fake {partNumber}`
		part.Size = Vector3.new(2, 1, 4)
		part:SetAttribute("PartNumber", partNumber)
		part.Parent = folder
	end
	return folder
end

local function testSteps(): { SetData.Step }
	return {
		{ kind = "bag" },
		{
			kind = "place",
			target = "main",
			partNumber = "3001",
			color = { 196, 40, 28 },
			cframe = SetData.packCFrame(CFrame.new(0, 1, 0)),
		},
		{ kind = "subbuild", id = "sub1" },
		{
			kind = "place",
			target = "sub1",
			partNumber = "3020",
			cframe = SetData.packCFrame(CFrame.new(0, 1, 0)),
		},
		{ kind = "attach", id = "sub1", cframe = SetData.packCFrame(CFrame.new(0, 3, 0)) },
	}
end

return function(t: TestTypes.TestContext)
	t.test("buildTo materializes places, sub-builds, and attaches", function()
		local templates = makeTemplates()
		local container = Instance.new("Folder")
		local origin = CFrame.new(100, 5, 100)
		local rig = SetRig.create(origin, container)
		local steps = testSteps()

		-- Through step 4: main part placed, sub-build root + platform up
		-- with its plate on it.
		SetRig.buildTo(rig, steps, 4, templates)
		t.expect(rig.stepInstances[2]).toBeTruthy()
		local mainPart = rig.stepInstances[2] :: BasePart
		t.expect(mainPart.Parent).toBe(rig.mainRoot)
		t.expect(mainPart.Position).toBeCloseTo(origin:PointToWorldSpace(Vector3.new(0, 1, 0)))
		t.expect(mainPart.Color.R * 255).toBeCloseTo(196, 1)
		local subRoot = rig.subbuildRoots["sub1"]
		t.expect(subRoot).toBeTruthy()
		local subPart = rig.stepInstances[4] :: BasePart
		t.expect(subPart.Parent).toBe(subRoot)
		t.expect((subPart.Position - origin.Position).Magnitude > 5).toBe(true)

		-- Through step 5: attach folds the sub-build into main at the
		-- recorded pose.
		SetRig.buildTo(rig, steps, 5, templates)
		t.expect(rig.subbuildRoots["sub1"]).toBe(nil)
		local attached = rig.stepInstances[4] :: BasePart
		t.expect(attached.Parent).toBe(rig.mainRoot)
		-- Sub pivot in main space = (0,3,0); the plate sits at (0,1,0)
		-- within the sub-build -> (0,4,0) in main space.
		t.expect(attached.Position).toBeCloseTo(origin:PointToWorldSpace(Vector3.new(0, 4, 0)))

		-- Scrub back to nothing.
		SetRig.buildTo(rig, steps, 0, templates)
		t.expect(rig.stepInstances[2]).toBe(nil)
		t.expect(#rig.mainRoot:GetChildren()).toBe(0)

		SetRig.destroy(rig)
		container:Destroy()
		templates:Destroy()
	end)

	t.test("stepOfInstance maps placed parts back to steps", function()
		local templates = makeTemplates()
		local container = Instance.new("Folder")
		local rig = SetRig.create(CFrame.identity, container)
		local steps = testSteps()
		SetRig.buildTo(rig, steps, 2, templates)
		local placed = rig.stepInstances[2] :: BasePart
		t.expect(SetRig.stepOfInstance(rig, placed)).toBe(2)
		t.expect(SetRig.stepOfInstance(rig, rig.mainRoot)).toBe(nil)
		SetRig.destroy(rig)
		container:Destroy()
		templates:Destroy()
	end)
end
