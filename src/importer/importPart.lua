--!strict

-- Imports one LDraw part as a MeshPart annotated with connection
-- Attachments:
--   - Stud/socket grids: one REGION attachment per coalesced grid (name
--     "Studs4x2" / "Sockets4x2"; attributes ConnectorType, CountX, CountZ,
--     Pitch; CFrame at the region center, UpVector = mating direction,
--     XVector/ZVector = grid axes).
--   - Axial/point connectors (PegHole, AxleHole, Axle, TechnicPin, Bar,
--     Clip): one attachment each, named by type; attributes ConnectorType
--     and Length (Roblox studs, when the connector has an extent);
--     UpVector = connector axis.
-- The part is named from the LDraw description ("Brick 2 x 4");
-- attributes: PartNumber ("3001"), LDrawFile ("3001.dat").
--
-- No undo recording here: the caller owns the undo waypoint.

local AssetService = game:GetService("AssetService")

local LDrawFolder = require(script.Parent.ldrawFolder) :: any
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

-- Axial attachment orientation: YVector = the connector axis, XVector =
-- the SECONDARY axis (the axle cross flat orientation, taken from the
-- source primitive's transform). Keyed mates (axle in axle hole) use
-- the secondary to roll-align the cross on snap.
local function axialAttachmentCFrame(connection: Types.Connection, meshCenter: Vector3): CFrame
	local position = RobloxConvert.position(connection.position) - meshCenter
	local direction = RobloxConvert.direction(connection.direction)
	local transform = connection.transform
	local candidate = transform.XVector
	if candidate.Magnitude < 1e-6 or math.abs(candidate.Unit:Dot(connection.direction.Unit)) > 0.7 then
		candidate = transform.ZVector
	end
	if candidate.Magnitude < 1e-6 then
		return RobloxConvert.frameWithUp(position, direction)
	end
	local secondary = RobloxConvert.direction(candidate)
	secondary -= direction * secondary:Dot(direction)
	if secondary.Magnitude < 1e-3 then
		return RobloxConvert.frameWithUp(position, direction)
	end
	return CFrame.fromMatrix(position, secondary.Unit, direction)
end

local function addAxialAttachment(parent: MeshPart, connection: Types.Connection, meshCenter: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = connection.type
	attachment.CFrame = axialAttachmentCFrame(connection, meshCenter)
	attachment:SetAttribute("ConnectorType", connection.type)
	if connection.length ~= nil then
		attachment:SetAttribute("Length", connection.length * RobloxConvert.kDefaultScale)
	end
	if connection.oneSided then
		attachment:SetAttribute("OneSided", true)
	end
	if connection.radius ~= nil then
		attachment:SetAttribute("Radius", connection.radius * RobloxConvert.kDefaultScale)
	end
	attachment.Parent = parent
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
): (Instance?, string?)
	local file = library:getFile(partRef)
	if file == nil then
		return nil, `Part file not found: {partRef}`
	end

	local mesh = flattenMesh(library, partRef) :: Types.FlatMesh
	if #mesh.triangles == 0 then
		return nil, `{partRef} contains no geometry`
	end
	local connections = findConnections(library, partRef, mesh) :: { Types.Connection }
	local sockets = deriveSockets(connections, mesh)

	-- Build one MeshPart from a FlatMesh(-shaped) table. Split chunks
	-- reuse the parent mesh's bounds, so every chunk shares one
	-- coordinate space (meshCenter derives from the bounds).
	local function createMeshPart(flatMesh: Types.FlatMesh): (MeshPart?, Vector3?, string?)
		local okBuild, editableMesh: any, buildStats: any = pcall(buildEditableMesh, flatMesh)
		if not okBuild then
			return nil, nil, tostring(editableMesh)
		end
		local okCreate, meshPart: any = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh))
		end)
		if not okCreate then
			return nil, nil, tostring(meshPart)
		end
		meshPart.Anchored = true
		meshPart.Material = Enum.Material.SmoothPlastic
		return meshPart, buildStats.meshCenter :: Vector3, nil
	end

	local kSplitChunkTriangles = 15000

	local part: MeshPart?, meshCenterMaybe: Vector3?, buildError: string?
	part, meshCenterMaybe, buildError = createMeshPart(mesh)
	if part == nil and (buildError :: string):find("limit") ~= nil then
		-- Giant uncertified parts exceed the triangle limit when emitted
		-- double-sided; retry single-sided (possible backface holes beat
		-- not importing at all).
		mesh = flattenMesh(library, partRef, { forceSingleSided = true }) :: Types.FlatMesh
		part, meshCenterMaybe, buildError = createMeshPart(mesh)
	end

	-- The unit we annotate and return: the MeshPart itself, or a Model
	-- of chunk MeshParts when even single-sided exceeds the limit (9V
	-- switches). Chunks share the parent bounds, so they all sit at the
	-- same CFrame and attachments on the first chunk are in unit space.
	local unit: Instance
	local annotationTarget: Instance
	if part ~= nil then
		unit = part
		annotationTarget = part
	elseif (buildError :: string):find("limit") ~= nil then
		local model = Instance.new("Model")
		local firstChunk: MeshPart? = nil
		for start = 1, #mesh.triangles, kSplitChunkTriangles do
			local chunk = table.clone(mesh) :: any
			chunk.triangles = table.move(
				mesh.triangles,
				start,
				math.min(start + kSplitChunkTriangles - 1, #mesh.triangles),
				1,
				{}
			)
			local chunkPart, chunkCenter, chunkError = createMeshPart(chunk)
			if chunkPart == nil then
				model:Destroy()
				return nil, `Failed to build mesh chunk: {chunkError}`
			end
			meshCenterMaybe = chunkCenter
			chunkPart.Name = `Chunk{1 + (start - 1) / kSplitChunkTriangles}`
			chunkPart.CFrame = CFrame.identity
			chunkPart.Parent = model
			firstChunk = firstChunk or chunkPart
		end
		model.WorldPivot = CFrame.identity
		unit = model
		annotationTarget = firstChunk :: MeshPart
	else
		return nil, `Failed to build mesh: {buildError}`
	end
	local meshCenter = meshCenterMaybe :: Vector3

	local partNumber = (partRef:gsub("%.dat$", ""))
	unit.Name = cleanDescription(file.description) or partNumber
	unit:SetAttribute("LDrawFile", partRef)
	unit:SetAttribute("PartNumber", partNumber)
	-- Pivot offset from the LDraw origin (see buildEditableMesh): needed to
	-- place instances of this part at LDraw model transforms.
	unit:SetAttribute("MeshCenter", meshCenter)

	local regionCells: { Types.RegionCell } = {}
	for _, connection in connections do
		if connection.type == "Stud" then
			table.insert(regionCells, {
				kind = "Stud",
				position = connection.position,
				direction = connection.direction,
			})
		elseif connection.type ~= "Tube" and connection.type ~= "Pin" and connection.type ~= "Pocket" then
			-- Tubes/pins/pockets become Socket regions via deriveSockets;
			-- everything else is annotated individually.
			addAxialAttachment(annotationTarget :: MeshPart, connection, meshCenter)
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
		addRegionAttachment(annotationTarget :: MeshPart, region, meshCenter)
	end

	unit.Parent = parent

	return unit, nil
end

return importPart
