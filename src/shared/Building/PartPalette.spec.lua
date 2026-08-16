--!strict

local CoreGui = game:GetService("CoreGui")

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local PartPalette = require(script.Parent.PartPalette)

return function(t: TestTypes.TestContext)
	t.test("builds entries for template parts and cleans up", function()
		local screen = Instance.new("ScreenGui")
		screen.Parent = CoreGui
		local folder = Instance.new("Folder")

		local template = Instance.new("Part")
		template.Name = "3001"
		template.Size = Vector3.new(4, 1.4, 2)
		template:SetAttribute("Description", "Brick  2 x  4")
		template.Parent = folder

		local palette = PartPalette.create(screen, folder, function() end)
		local entry = palette.frame:FindFirstChild("Entry_3001", true)
		t.expect(entry).toBeTruthy()
		t.expect((entry :: Instance):FindFirstChildOfClass("ViewportFrame")).toBeTruthy()

		-- Adding a template refreshes the list.
		local second = Instance.new("Part")
		second.Name = "3020"
		second.Size = Vector3.new(4, 0.6, 2)
		second.Parent = folder
		task.wait()
		t.expect(palette.frame:FindFirstChild("Entry_3020", true)).toBeTruthy()

		palette.destroy()
		t.expect(screen:FindFirstChild("PartPalette")).toBeFalsy()

		folder:Destroy()
		screen:Destroy()
	end)

	t.test("shows an empty-state message with no templates", function()
		local screen = Instance.new("ScreenGui")
		screen.Parent = CoreGui
		local folder = Instance.new("Folder")

		local palette = PartPalette.create(screen, folder, function() end)
		t.expect(palette.frame:FindFirstChild("EmptyLabel", true)).toBeTruthy()

		palette.destroy()
		folder:Destroy()
		screen:Destroy()
	end)
end
