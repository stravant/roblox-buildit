--!strict

-- Imports one LDraw part as a MeshPart annotated with connection REGION
-- Attachments (one per coalesced grid, not one per cell):
--   - Name "Studs4x2" / "Sockets4x2" (kind + dimensions, may repeat)
--   - Attributes: ConnectorType ("Stud"/"Socket"), CountX, CountZ, Pitch
--     (Roblox studs between cells)
--   - CFrame: region center; UpVector points OUT of the part toward the
--     mating part, XVector/ZVector are the grid axes.
-- The part is named from the LDraw description ("Brick 2 x 4");
-- attributes: PartNumber ("3001"), LDrawFile ("3001.dat").
--
-- No undo recording here: the caller owns the undo waypoint.

local AssetService = game:GetService("AssetService")

local LDrawFolder = script.Parent.Parent.shared.LDraw
local LDrawLibrary = require(LDrawFolder.LDrawLibrary)
local Types = require(LDrawFolder.Types)
local flattenMesh = require(LDrawFolder.flattenMesh)
local findConnections = require(LDrawFolder.findConnections)
local deriveSockets = require(LDrawFolder.deriveSockets)
local coalesceRegions = require(LDrawFolder.coalesceRegions)
local buildEditableMesh = require(LDrawFolder.buildEditableMesh)
local RobloxConvert = require(LDrawFolder.RobloxConvert)

-- LDraw descriptions pad with alignment spaces ("Brick  2 x  4").
local function cleanDescription(description: string?): string?
	if description == nil then
		return nil
	end
	local cleaned = (description:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
	return if #cleaned > 0 then cleaned else nil
end

local function addRegionAttachment(parent: MeshPart, region: Types.ConnectionRegion, meshCenter: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = `{region.kind}s{region.countX}x{region.countZ}`
	-- The MeshPart pivot is the geometry bbox center, not the LDraw origin.
	attachment.CFrame = RobloxConvert.cframe(region.frame).Rotation
		+ (RobloxConvert.position(region.frame.Position) - meshCenter)
	attachment:SetAttribute("ConnectorType", region.kind)
	attachment:SetAttribute("CountX", region.countX)
	attachment:SetAttribute("CountZ", region.countZ)
	attachment:SetAttribute("Pitch", region.pitch * RobloxConvert.kDefaultScale)
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

	local partNumber = (partRef:gsub("%.dat$", ""))
	part.Name = cleanDescription(file.description) or partNumber
	part.Anchored = true
	part:SetAttribute("LDrawFile", partRef)
	part:SetAttribute("PartNumber", partNumber)

	local regionCells: { Types.RegionCell } = {}
	for _, connection in connections do
		if connection.type == "Stud" then
			table.insert(regionCells, {
				kind = "Stud",
				position = connection.position,
				direction = connection.direction,
			})
		end
	end
	for _, socket in sockets do
		table.insert(regionCells, {
			kind = "Socket",
			position = socket.position,
			direction = socket.direction,
		})
	end
	for _, region in coalesceRegions(regionCells) do
		addRegionAttachment(part, region, meshCenter)
	end

	part.Parent = parent

	return part, nil
end

return importPart
