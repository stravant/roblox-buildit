--!strict

-- Visual audit contact sheet: imports the parts listed in
-- sets/audit_sheet.txt, renders every connector as a colored marker
-- (studs green, sockets blue, ball joints purple, axial orange), and
-- takes a screenshot. Gated on sets/audit_enable.txt like zzAudit.

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local compositeParts = require(script.Parent.compositeParts)
local getConnectors = require(script.Parent.Parent.Building.getConnectors)

return function(t: TestTypes.TestContext)
	t.test("audit contact sheet", function()
		if t.readFile("sets/audit_enable.txt") == nil then
			t.log("sheet skipped (no sets/audit_enable.txt)")
			return
		end
		local listing = t.readFile("sets/audit_sheet.txt")
		if listing == nil then
			t.log("sheet skipped (no sets/audit_sheet.txt)")
			return
		end

		local importPart = require(script.Parent.Parent.Parent.importer.importPart) :: any
		local importComposite = require(script.Parent.Parent.Parent.importer.importComposite) :: any
		local library = LDrawLibrary.new(t.readFile)

		local folder = Instance.new("Folder")
		folder.Name = "AuditSheet"
		folder.Parent = workspace
		local markerFolder = Instance.new("Folder")
		markerFolder.Parent = workspace.CurrentCamera

		local function markerColor(kind: string): Color3
			if kind == "Stud" then
				return Color3.fromRGB(90, 220, 90)
			elseif kind == "Socket" then
				return Color3.fromRGB(80, 170, 255)
			elseif kind == "Towball" or kind == "TowballSocket" then
				return Color3.fromRGB(220, 90, 220)
			else
				return Color3.fromRGB(255, 140, 60)
			end
		end

		local cursorX = 0
		for line in (listing :: string):gmatch("[^\r\n]+") do
			local id = line:match("^%s*(%S+)")
			if id == nil then
				continue
			end
			local ref = compositeParts.resolve(id .. ".dat")
			local ok, unit = pcall(function(): Instance?
				if compositeParts.get(ref) ~= nil then
					return (importComposite(library, ref, folder))
				end
				return (importPart(library, ref, folder))
			end)
			if not ok or unit == nil then
				t.log(`sheet: {id} FAILED: {tostring(unit)}`)
				continue
			end
			local instance = unit :: Instance
			local size: Vector3
			if instance:IsA("Model") then
				size = instance:GetExtentsSize()
			else
				size = (instance :: BasePart).Size
			end
			(instance :: PVInstance):PivotTo(CFrame.new(cursorX + size.X / 2, size.Y / 2 + 0.05, 0))
			cursorX += size.X + 1.5

			local parts: { BasePart } = {}
			if instance:IsA("BasePart") then
				table.insert(parts, instance)
			end
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
			for _, part in parts do
				for _, connector in getConnectors(part) do
					local adornment = Instance.new("SphereHandleAdornment")
					adornment.Adornee = part
					adornment.CFrame = CFrame.new(connector.position)
					adornment.Radius = 0.14
					adornment.Color3 = markerColor(connector.kind)
					adornment.Transparency = 0.1
					adornment.Parent = markerFolder
				end
			end
		end

		local center = Vector3.new(cursorX / 2, 0.5, 0)
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, cursorX * 0.45, cursorX * 0.5), center)
		task.wait(0.3)
		t.screenshot("audit_sheet")
		-- Scene intentionally left in place so an OS-level screenshot can
		-- capture it if CaptureService fails; the next sheet run replaces it.
	end)
end
