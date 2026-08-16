--!strict

-- Reads the connector region Attachments (created by the importer) off a
-- part and expands them into individual cells for snapping and display.
--
-- Region attachments carry ConnectorType ("Stud"/"Socket") plus CountX,
-- CountZ, and Pitch attributes; the attachment CFrame is the region center
-- with UpVector pointing out of the part and XVector/ZVector as the grid
-- axes. Attachments without count attributes are treated as 1x1 regions
-- (which also covers legacy per-cell annotations).

export type ConnectorKind = "Stud" | "Socket"

export type Connector = {
	kind: ConnectorKind,
	position: Vector3, -- part-local (cell center on the mating plane)
	direction: Vector3, -- part-local unit, points toward the mating part
	attachment: Attachment, -- the region attachment (shared by its cells)
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
		local countX = child:GetAttribute("CountX") or 1
		local countZ = child:GetAttribute("CountZ") or 1
		local pitch = child:GetAttribute("Pitch") or 1
		if type(countX) ~= "number" or type(countZ) ~= "number" or type(pitch) ~= "number" then
			continue
		end

		local regionCFrame = child.CFrame
		local direction = regionCFrame.YVector
		for i = 1, countX do
			for j = 1, countZ do
				local offset = Vector3.new(
					(i - (countX + 1) / 2) * pitch,
					0,
					(j - (countZ + 1) / 2) * pitch
				)
				table.insert(connectors, {
					kind = kind :: ConnectorKind,
					position = regionCFrame:PointToWorldSpace(offset),
					direction = direction,
					attachment = child,
				})
			end
		end
	end
	return connectors
end

return getConnectors
