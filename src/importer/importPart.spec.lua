--!strict

local TestTypes = require(script.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local importPart = require(script.Parent.importPart)

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	local function findAttachmentNear(part: Instance, connectorType: string, position: Vector3): Attachment?
		for _, child in part:GetChildren() do
			if
				child:IsA("Attachment")
				and child:GetAttribute("ConnectorType") == connectorType
				and (child.CFrame.Position - position).Magnitude < 0.01
			then
				return child
			end
		end
		return nil
	end

	t.test("imports 3001 with bbox-centered connector attachments", function()
		local folder = Instance.new("Folder")
		local part, errorMessage = importPart(library, "3001.dat", folder)
		t.expect(errorMessage).toBeFalsy()
		t.expect(part).toBeTruthy()
		local meshPart = part :: MeshPart

		t.expect(meshPart.Size).toBeCloseTo(Vector3.new(4, 1.4, 2), 0.01)
		-- Named from the description (whitespace collapsed); id in attributes.
		t.expect(meshPart.Name).toBe("Brick 2 x 4")
		t.expect(meshPart:GetAttribute("PartNumber")).toBe("3001")
		t.expect(meshPart:GetAttribute("LDrawFile")).toBe("3001.dat")
		t.expect(meshPart:GetAttribute("Description")).toBe(nil)

		local studs = 0
		local sockets = 0
		for _, child in meshPart:GetChildren() do
			if child:IsA("Attachment") then
				local connectorType = child:GetAttribute("ConnectorType")
				if connectorType == "Stud" then
					studs += 1
				elseif connectorType == "Socket" then
					sockets += 1
				end
			end
		end
		t.expect(studs).toBe(8)
		t.expect(sockets).toBe(8)

		-- Part pivot is the bbox center: the geometry spans y in [-0.7, 0.7],
		-- studs base plane at +0.5, sockets on the bottom face at -0.7.
		-- LDraw stud (30, 0, 10) converts to (1.5, 0, -0.5) then shifts up 0.5.
		local stud = findAttachmentNear(meshPart, "Stud", Vector3.new(1.5, 0.5, -0.5))
		t.expect(stud).toBeTruthy()
		t.expect((stud :: Attachment).CFrame.YVector).toBeCloseTo(Vector3.new(0, 1, 0))

		local socket = findAttachmentNear(meshPart, "Socket", Vector3.new(0.5, -0.7, -0.5))
		t.expect(socket).toBeTruthy()
		t.expect((socket :: Attachment).CFrame.YVector).toBeCloseTo(Vector3.new(0, -1, 0))

		folder:Destroy()
	end)

	t.test("reports missing parts", function()
		local folder = Instance.new("Folder")
		local part, errorMessage = importPart(library, "notarealpart.dat", folder)
		t.expect(part).toBeFalsy()
		t.expect(errorMessage).toBeTruthy()
		folder:Destroy()
	end)
end
