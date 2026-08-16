--!strict

-- Reads the connector Attachments (created by the importer) off a part:
-- Attachments with a ConnectorType attribute of "Stud" or "Socket", whose
-- UpVector points out of the part toward where a mating part sits.

export type ConnectorKind = "Stud" | "Socket"

export type Connector = {
	kind: ConnectorKind,
	position: Vector3, -- part-local
	direction: Vector3, -- part-local unit, points toward the mating part
	attachment: Attachment,
}

local function getConnectors(part: BasePart): { Connector }
	local connectors: { Connector } = {}
	for _, child in part:GetChildren() do
		if not child:IsA("Attachment") then
			continue
		end
		local kind = child:GetAttribute("ConnectorType")
		if kind ~= "Stud" and kind ~= "Socket" then
			continue
		end
		table.insert(connectors, {
			kind = kind :: ConnectorKind,
			position = child.CFrame.Position,
			direction = child.CFrame.YVector,
			attachment = child,
		})
	end
	return connectors
end

return getConnectors
