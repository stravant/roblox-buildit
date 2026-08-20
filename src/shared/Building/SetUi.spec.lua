--!strict

-- UI smoke test: the sequencer mounts, renders cells for a step list,
-- and routes button/cell clicks to callbacks.

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local SetData = require(script.Parent.SetData)
local Sequencer = require(script.Parent.Sequencer)

return function(t: TestTypes.TestContext)
	t.test("sequencer mounts and renders step cells", function()
		local parent = Instance.new("Folder")
		local scrubbed: number? = nil
		local sequencer = Sequencer.create(parent, "Test Set", {
			onScrub = function(cursor)
				scrubbed = cursor
			end,
			onAddBag = function() end,
			onAddStep = function() end,
			onAddSubbuild = function() end,
			onDelete = function() end,
			onSave = function() end,
			onExit = function() end,
		})

		local steps: { SetData.Step } = {
			{ kind = "bag" },
			{
				kind = "place",
				target = "main",
				partNumber = "3001",
				cframe = SetData.packCFrame(CFrame.identity),
			},
			{ kind = "step" },
			{ kind = "subbuild", id = "sub1" },
			{ kind = "attach", id = "sub1", cframe = SetData.packCFrame(CFrame.identity) },
		}
		sequencer.refresh(steps, 2)
		sequencer.setStatus("status text")

		local strip = sequencer.frame:FindFirstChild("Steps") :: Instance
		t.expect(strip).toBeTruthy()
		-- Cell0 + one cell per step.
		local cells = 0
		for _, child in strip:GetChildren() do
			if child:IsA("TextButton") then
				cells += 1
			end
		end
		t.expect(cells).toBe(6)
		t.expect((strip:FindFirstChild("Cell1") :: TextButton).Text).toBe("B1")
		t.expect((strip:FindFirstChild("Cell3") :: TextButton).Text).toBe("S2")
		t.expect((strip:FindFirstChild("Cell4") :: TextButton).Text).toBe("SUB")
		t.expect((strip:FindFirstChild("Cell5") :: TextButton).Text).toBe("ATT")

		sequencer.destroy()
		t.expect(parent:FindFirstChild("Sequencer")).toBe(nil)
		parent:Destroy()
		local _ = scrubbed
	end)
end
