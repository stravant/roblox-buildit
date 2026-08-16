--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local getConnectors = require(script.Parent.getConnectors)

return function(t: TestTypes.TestContext)
	t.test("expands region attachments into cells", function()
		local part = Instance.new("Part")

		local studs = Instance.new("Attachment")
		studs.Name = "Studs4x2"
		studs.CFrame = CFrame.new(0, 0.5, 0)
		studs:SetAttribute("ConnectorType", "Stud")
		studs:SetAttribute("CountX", 4)
		studs:SetAttribute("CountZ", 2)
		studs:SetAttribute("Pitch", 1)
		studs.Parent = part

		-- Distractors: attachment without the attribute, and a non-attachment.
		Instance.new("Attachment").Parent = part
		Instance.new("Weld").Parent = part

		local connectors = getConnectors(part)
		t.expect(#connectors).toBe(8)

		local found = {}
		for _, connector in connectors do
			t.expect(connector.kind).toBe("Stud")
			t.expect(connector.direction).toBeCloseTo(Vector3.new(0, 1, 0))
			t.expect(connector.attachment).toBe(studs)
			found[`{connector.position.X},{connector.position.Z}`] = true
		end
		for _, x in { -1.5, -0.5, 0.5, 1.5 } do
			for _, z in { -0.5, 0.5 } do
				t.expect(found[`{x},{z}`]).toBe(true)
			end
		end
		t.expect(connectors[1].position.Y).toBeCloseTo(0.5)

		part:Destroy()
	end)

	t.test("treats attachments without counts as 1x1 regions (legacy)", function()
		local part = Instance.new("Part")

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

		local connectors = getConnectors(part)
		t.expect(#connectors).toBe(1)
		t.expect(connectors[1].kind).toBe("Socket")
		t.expect(connectors[1].position).toBeCloseTo(Vector3.new(0.5, -0.7, 0.5))
		t.expect(connectors[1].direction).toBeCloseTo(Vector3.new(0, -1, 0))

		part:Destroy()
	end)

	t.test("returns empty for a part with no connectors", function()
		local part = Instance.new("Part")
		t.expect(getConnectors(part)).toEqual({})
		part:Destroy()
	end)
end
