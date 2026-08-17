--!strict

local TestTypes = require(script.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local importComposite = require(script.Parent.importComposite)

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	t.test("imports the 1x4 hinge plate as a jointed two-segment model", function()
		local folder = Instance.new("Folder")
		local model, errorMessage = importComposite(library, "73983.dat", folder)
		t.expect(errorMessage).toBeFalsy()
		t.expect(model).toBeTruthy()
		local hinge = model :: Model

		t.expect(hinge:GetAttribute("PartNumber")).toBe("73983")
		t.expect(hinge:GetAttribute("JointType")).toBe("Hinge")

		local segments = {}
		for _, child in hinge:GetChildren() do
			if child:IsA("MeshPart") then
				table.insert(segments, child)
			end
		end
		t.expect(#segments).toBe(2)

		for _, segment in segments do
			-- Segments keep their own connector annotations.
			local hasConnector = false
			local pivot: Attachment? = nil
			for _, child in segment:GetChildren() do
				if child:IsA("Attachment") then
					if child.Name == "JointPivot" then
						pivot = child
					elseif child:GetAttribute("ConnectorType") ~= nil then
						hasConnector = true
					end
				end
			end
			t.expect(hasConnector).toBe(true)
			t.expect(pivot).toBeTruthy()
			local pivotAttachment = pivot :: Attachment
			t.expect(pivotAttachment:GetAttribute("JointType")).toBe("Hinge")
			-- Both segments' pivots coincide at the assembly origin with a
			-- vertical (Roblox +Y) articulation axis.
			local worldCFrame = segment.CFrame * pivotAttachment.CFrame
			t.expect(worldCFrame.Position).toBeCloseTo(Vector3.new(0, 0, 0), 0.01)
			t.expect(worldCFrame.YVector).toBeCloseTo(Vector3.new(0, 1, 0))
			t.expect(segment:GetAttribute("JointSegment")).toBeTruthy()
		end

		folder:Destroy()
	end)

	t.test("imports the minifig torso assembly with four joints", function()
		local folder = Instance.new("Folder")
		local model, errorMessage = importComposite(library, "973c01.dat", folder)
		t.expect(errorMessage).toBeFalsy()
		local torso = model :: Model
		t.expect(torso:GetAttribute("JointCount")).toBe(4)

		local segments = 0
		local pivotCounts: { [string]: number } = {}
		for _, child in torso:GetChildren() do
			if child:IsA("MeshPart") then
				segments += 1
				for _, attachment in child:GetChildren() do
					if attachment:IsA("Attachment") and attachment.Name:match("^JointPivot") then
						pivotCounts[attachment.Name] = (pivotCounts[attachment.Name] or 0) + 1
					end
				end
			end
		end
		t.expect(segments).toBe(5)
		-- Each joint's pivot appears on exactly its two segments.
		for jointIndex = 1, 4 do
			t.expect(pivotCounts[`JointPivot{jointIndex}`]).toBe(2)
		end
		-- Each joint has exactly one parent-role and one child-role pivot.
		local roles: { [string]: number } = {}
		for _, child in torso:GetDescendants() do
			if child:IsA("Attachment") and child.Name:match("^JointPivot") then
				local key = `{child.Name}:{child:GetAttribute("JointRole")}`
				roles[key] = (roles[key] or 0) + 1
			end
		end
		for jointIndex = 1, 4 do
			t.expect(roles[`JointPivot{jointIndex}:parent`]).toBe(1)
			t.expect(roles[`JointPivot{jointIndex}:child`]).toBe(1)
		end

		folder:Destroy()
	end)
end
