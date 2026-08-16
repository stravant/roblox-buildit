--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local getConnectors = require(script.Parent.getConnectors)

return function(t: TestTypes.TestContext)
	t.test("reads connector attachments off a part", function()
		local part = Instance.new("Part")

		local stud = Instance.new("Attachment")
		stud.Name = "Stud1"
		stud.CFrame = CFrame.new(1.5, 0.5, -0.5)
		stud:SetAttribute("ConnectorType", "Stud")
		stud.Parent = part

		local socket = Instance.new("Attachment")
		socket.Name = "Socket1"
		-- UpVector down: a socket on the part's bottom face.
		socket.CFrame = CFrame.fromMatrix(
			Vector3.new(0.5, -0.7, 0.5),
			Vector3.new(1, 0, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, -1)
		)
		socket:SetAttribute("ConnectorType", "Socket")
		socket.Parent = part

		-- Distractors: attachment without the attribute, and a non-attachment.
		Instance.new("Attachment").Parent = part
		Instance.new("Weld").Parent = part

		local connectors = getConnectors(part)
		t.expect(#connectors).toBe(2)

		local byKind = {}
		for _, connector in connectors do
			byKind[connector.kind] = connector
		end
		t.expect(byKind.Stud.position).toBeCloseTo(Vector3.new(1.5, 0.5, -0.5))
		t.expect(byKind.Stud.direction).toBeCloseTo(Vector3.new(0, 1, 0))
		t.expect(byKind.Socket.position).toBeCloseTo(Vector3.new(0.5, -0.7, 0.5))
		t.expect(byKind.Socket.direction).toBeCloseTo(Vector3.new(0, -1, 0))
		t.expect(byKind.Stud.attachment).toBe(stud)

		part:Destroy()
	end)

	t.test("returns empty for a part with no connectors", function()
		local part = Instance.new("Part")
		t.expect(getConnectors(part)).toEqual({})
		part:Destroy()
	end)
end
