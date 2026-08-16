--!strict

local TestTypes = require(script.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local importPart = require(script.Parent.importPart)

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	local function findRegion(part: Instance, connectorType: string): Attachment?
		for _, child in part:GetChildren() do
			if child:IsA("Attachment") and child:GetAttribute("ConnectorType") == connectorType then
				return child
			end
		end
		return nil
	end

	t.test("imports 3001 with one region attachment per connector field", function()
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

		-- Region attachments: one stud grid, the 4x2 socket cell grid, and
		-- the 3x1 tube-center socket row (offset placements).
		t.expect(#meshPart:GetChildren()).toBe(3)

		-- Part pivot is the bbox center: the geometry spans y in [-0.7, 0.7],
		-- studs base plane at +0.5, sockets on the bottom face at -0.7.
		local studs = findRegion(meshPart, "Stud") :: Attachment
		t.expect(studs).toBeTruthy()
		t.expect(studs.Name).toBe("Studs4x2")
		t.expect(studs:GetAttribute("CountX")).toBe(4)
		t.expect(studs:GetAttribute("CountZ")).toBe(2)
		t.expect(studs:GetAttribute("Pitch")).toBe(1)
		t.expect(studs.CFrame.Position).toBeCloseTo(Vector3.new(0, 0.5, 0))
		t.expect(studs.CFrame.YVector).toBeCloseTo(Vector3.new(0, 1, 0))

		local sockets = meshPart:FindFirstChild("Sockets4x2") :: Attachment
		t.expect(sockets).toBeTruthy()
		t.expect(sockets:GetAttribute("CountX")).toBe(4)
		t.expect(sockets:GetAttribute("CountZ")).toBe(2)
		t.expect(sockets.CFrame.Position).toBeCloseTo(Vector3.new(0, -0.7, 0))
		t.expect(sockets.CFrame.YVector).toBeCloseTo(Vector3.new(0, -1, 0))

		local tubeSockets = meshPart:FindFirstChild("Sockets3x1") :: Attachment
		t.expect(tubeSockets).toBeTruthy()
		t.expect(tubeSockets.CFrame.Position).toBeCloseTo(Vector3.new(0, -0.7, 0))

		folder:Destroy()
	end)

	t.test("imports 3700 with a PegHole attachment", function()
		local folder = Instance.new("Folder")
		local part = importPart(library, "3700.dat", folder) :: MeshPart
		t.expect(part).toBeTruthy()

		local pegHole: Attachment? = nil
		for _, child in part:GetChildren() do
			if child:IsA("Attachment") and child:GetAttribute("ConnectorType") == "PegHole" then
				pegHole = child
			end
		end
		t.expect(pegHole).toBeTruthy()
		local attachment = pegHole :: Attachment
		t.expect(attachment:GetAttribute("Length")).toBeCloseTo(1)
		-- Hole center: LDraw (0, 10, 0); part spans y -4..24 so the bbox
		-- center offset lands it at local origin, axis along Z.
		t.expect(attachment.CFrame.Position).toBeCloseTo(Vector3.new(0, 0, 0), 0.01)
		t.expect(math.abs(attachment.CFrame.YVector.Z)).toBeCloseTo(1)

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
