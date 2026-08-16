--!strict

-- Reads the connector Attachments (created by the importer) off a part.
--
-- Stud/Socket region attachments (ConnectorType + CountX/CountZ/Pitch)
-- expand into individual cells; attachments without counts read as 1x1
-- regions (covers legacy per-cell annotations). Axial connectors
-- (PegHole, AxleHole, Axle, TechnicPin, Bar, Clip) pass through as single
-- connectors with their Length attribute (Roblox studs).

-- "Stud" | "Socket" | "PegHole" | "AxleHole" | "Axle" | "TechnicPin"
-- | "Bar" | "Clip"
export type ConnectorKind = string

export type Connector = {
	kind: ConnectorKind,
	position: Vector3, -- part-local (cell center / element center)
	-- Part-local unit: points toward the mating part for point connectors,
	-- element axis (sign arbitrary) for axial connectors.
	direction: Vector3,
	length: number?, -- extent along direction (axial connectors)
	attachment: Attachment, -- the source attachment (shared by grid cells)
}

local kGridKinds: { [string]: boolean } = {
	Stud = true,
	Socket = true,
}

local function getConnectors(part: BasePart): { Connector }
	local connectors: { Connector } = {}
	for _, child in part:GetChildren() do
		if not child:IsA("Attachment") then
			continue
		end
		local kind = child:GetAttribute("ConnectorType")
		if type(kind) ~= "string" then
			continue
		end

		if not kGridKinds[kind] then
			local length = child:GetAttribute("Length")
			table.insert(connectors, {
				kind = kind,
				position = child.CFrame.Position,
				direction = child.CFrame.YVector,
				length = if type(length) == "number" then length else nil,
				attachment = child,
			})
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
					kind = kind,
					position = regionCFrame:PointToWorldSpace(offset),
					direction = direction,
					length = nil,
					attachment = child,
				})
			end
		end
	end
	return connectors
end

return getConnectors
