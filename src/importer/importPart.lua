--!strict

-- Imports one LDraw part as a MeshPart annotated with connection point
-- Attachments:
--   - "StudN" attachments (ConnectorType="Stud"): male studs
--   - "SocketN" attachments (ConnectorType="Socket"): derived anti-stud cells
-- Attachment UpVector points OUT of the part toward where the mating part
-- sits. Part attributes: PartNumber, Description, LDrawFile.

local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local LDrawFolder = script.Parent.Parent.shared.LDraw
local LDrawLibrary = require(LDrawFolder.LDrawLibrary)
local Types = require(LDrawFolder.Types)
local flattenMesh = require(LDrawFolder.flattenMesh)
local findConnections = require(LDrawFolder.findConnections)
local deriveSockets = require(LDrawFolder.deriveSockets)
local buildEditableMesh = require(LDrawFolder.buildEditableMesh)
local RobloxConvert = require(LDrawFolder.RobloxConvert)

-- Orthonormal frame with the given up vector (for Attachment CFrames).
local function frameWithUp(position: Vector3, up: Vector3): CFrame
	local reference = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up, right:Cross(up))
end

local function addConnectorAttachment(
	parent: MeshPart,
	name: string,
	connectorType: string,
	ldrawPosition: Vector3,
	ldrawDirection: Vector3,
	meshCenter: Vector3
)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	-- The MeshPart pivot is the geometry bbox center, not the LDraw origin.
	attachment.CFrame = frameWithUp(
		RobloxConvert.position(ldrawPosition) - meshCenter,
		RobloxConvert.direction(ldrawDirection)
	)
	attachment:SetAttribute("ConnectorType", connectorType)
	attachment.Parent = parent
end

-- Returns the imported MeshPart, or nil and an error message.
local function importPart(
	library: LDrawLibrary.LDrawLibrary,
	partRef: string,
	parent: Instance
): (MeshPart?, string?)
	local file = library:getFile(partRef)
	if file == nil then
		return nil, `Part file not found: {partRef}`
	end

	local mesh = flattenMesh(library, partRef) :: Types.FlatMesh
	if #mesh.triangles == 0 then
		return nil, `{partRef} contains no geometry`
	end
	local connections = findConnections(library, partRef) :: { Types.Connection }
	local sockets = deriveSockets(connections, mesh)

	local okBuild, editableMesh: any, buildStats: any = pcall(buildEditableMesh, mesh)
	if not okBuild then
		return nil, `Failed to build mesh: {editableMesh}`
	end
	local meshCenter = buildStats.meshCenter :: Vector3
	local okCreate, part: any = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh))
	end)
	if not okCreate then
		return nil, `CreateMeshPartAsync failed: {part}`
	end

	local recording = ChangeHistoryService:TryBeginRecording("Import LDraw part")

	part.Name = (partRef:gsub("%.dat$", ""))
	part.Anchored = true
	part:SetAttribute("LDrawFile", partRef)
	part:SetAttribute("PartNumber", (partRef:gsub("%.dat$", "")))
	if file.description ~= nil then
		part:SetAttribute("Description", file.description)
	end

	local studCount = 0
	for _, connection in connections do
		if connection.type == "Stud" then
			studCount += 1
			addConnectorAttachment(part, `Stud{studCount}`, "Stud", connection.position, connection.direction, meshCenter)
		end
	end
	for index, socket in sockets do
		addConnectorAttachment(part, `Socket{index}`, "Socket", socket.position, socket.direction, meshCenter)
	end

	part.Parent = parent

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("Import LDraw part")
	end

	return part, nil
end

return importPart
