--!strict
--!native

-- Builds an EditableMesh from a FlatMesh, converting LDraw space to Roblox
-- space (see RobloxConvert).
--
-- Vertices are welded by rounded position so shared edges share vertices,
-- and normals are generated explicitly. Edge sharpness comes from the
-- LDraw data itself, which marks authoring intent:
--   - type 2 edge lines        -> SHARP edge (no smoothing across it)
--   - type 5 conditional lines -> SMOOTH edge (curved surface: studs,
--     bars, cylinders)
--   - unmarked edges (e.g. across subfile seams) fall back to a crease
--     angle test
-- A face corner's normal is the area-weighted average of the fan of faces
-- reachable from it across smooth edges around that vertex. Without all
-- this, auto-computed normals average across 90-degree brick edges and
-- flat faces show shading gradients.
--
-- LEGO parts are single-colored in the game (Part.Color), so face color
-- codes are ignored here.
--
-- The mesh is recentered on its bounding box center (CreateMeshPartAsync
-- pivots the MeshPart there); stats.meshCenter reports where that center
-- was in converted-LDraw-origin space, so callers can convert LDraw-origin-
-- relative positions (e.g. connection points) to part-local space via
-- `RobloxConvert.position(p) - stats.meshCenter`.
--
-- Must run in a context allowed to call AssetService:CreateEditableMesh()
-- (Studio plugin / command bar).

local AssetService = game:GetService("AssetService")

local Types = require(script.Parent.Types)
local RobloxConvert = require(script.Parent.RobloxConvert)

local kWeldEpsilon = 1e-3
-- Fallback for edges with no type 2/5 marking.
local kCreaseAngleCos = math.cos(math.rad(40))
-- Never smooth together faces that are nearly back-to-back (protects
-- double-sided geometry from cancelling its own normals).
local kOpposedDotMin = -0.5

type BuildOptions = {
	scale: number?,
}

export type BuildStats = {
	vertexCount: number,
	triangleCount: number,
	normalCount: number,
	skippedDegenerate: number,
	sharpEdgeCount: number,
	smoothEdgeCount: number,
	-- Bounding box center in converted-LDraw-origin space (the mesh was
	-- shifted by -meshCenter so the part pivot lands on the bbox center).
	meshCenter: Vector3,
}

type FaceRecord = {
	faceId: number,
	vertexIds: { number },
	normal: Vector3, -- unit
	areaNormal: Vector3, -- cross product (2x area weighted)
}

local function buildEditableMesh(flatMesh: Types.FlatMesh, options: BuildOptions?): (EditableMesh, BuildStats)
	local scale = if options ~= nil and options.scale ~= nil then options.scale else RobloxConvert.kDefaultScale

	-- Converted-space bounds: the Y/Z negation swaps mins and maxes.
	local convertedMin = Vector3.new(flatMesh.boundsMin.X, -flatMesh.boundsMax.Y, -flatMesh.boundsMax.Z) * scale
	local convertedMax = Vector3.new(flatMesh.boundsMax.X, -flatMesh.boundsMin.Y, -flatMesh.boundsMin.Z) * scale
	local meshCenter = (convertedMin + convertedMax) / 2

	local mesh = AssetService:CreateEditableMesh()
	local mVertexIds: { [string]: number } = {}
	local mVertexPositions: { [number]: Vector3 } = {}
	local mStats: BuildStats = {
		vertexCount = 0,
		triangleCount = 0,
		normalCount = 0,
		skippedDegenerate = 0,
		sharpEdgeCount = 0,
		smoothEdgeCount = 0,
		meshCenter = meshCenter,
	}

	local function positionKey(position: Vector3): string
		return string.format(
			"%d,%d,%d",
			math.round(position.X / kWeldEpsilon),
			math.round(position.Y / kWeldEpsilon),
			math.round(position.Z / kWeldEpsilon)
		)
	end

	local function getVertex(ldrawPosition: Vector3): number
		local position = RobloxConvert.position(ldrawPosition, scale) - meshCenter
		local key = positionKey(position)
		local existing = mVertexIds[key]
		if existing ~= nil then
			return existing
		end
		local id = mesh:AddVertex(position)
		mVertexIds[key] = id
		mVertexPositions[id] = position
		mStats.vertexCount += 1
		return id
	end

	-- Pass 1: add welded vertices and faces, recording adjacency.
	local mFaces: { FaceRecord } = {}
	local mVertexFaces: { [number]: { number } } = {}
	local mEdgeFaces: { [string]: { number } } = {}

	local function edgeKey(vertexA: number, vertexB: number): string
		if vertexA < vertexB then
			return vertexA .. ":" .. vertexB
		else
			return vertexB .. ":" .. vertexA
		end
	end

	for _, triangle in flatMesh.triangles do
		local ia = getVertex(triangle.a)
		local ib = getVertex(triangle.b)
		local ic = getVertex(triangle.c)
		if ia == ib or ib == ic or ia == ic then
			mStats.skippedDegenerate += 1
			continue
		end
		local pa = mVertexPositions[ia]
		local areaNormal = (mVertexPositions[ib] - pa):Cross(mVertexPositions[ic] - pa)
		if areaNormal.Magnitude < 1e-12 then
			mStats.skippedDegenerate += 1
			continue
		end

		local faceId = mesh:AddTriangle(ia, ib, ic)
		mStats.triangleCount += 1

		local faceIndex = #mFaces + 1
		local face: FaceRecord = {
			faceId = faceId,
			vertexIds = { ia, ib, ic },
			normal = areaNormal.Unit,
			areaNormal = areaNormal,
		}
		mFaces[faceIndex] = face
		for corner, vertexId in face.vertexIds do
			local faceList = mVertexFaces[vertexId]
			if faceList == nil then
				faceList = {}
				mVertexFaces[vertexId] = faceList
			end
			table.insert(faceList, faceIndex)

			local otherVertexId = face.vertexIds[corner % 3 + 1]
			local key = edgeKey(vertexId, otherVertexId)
			local edgeList = mEdgeFaces[key]
			if edgeList == nil then
				edgeList = {}
				mEdgeFaces[key] = edgeList
			end
			table.insert(edgeList, faceIndex)
		end
	end

	-- Classify edges from the LDraw line markings.
	local mSharpEdgeSet: { [string]: boolean } = {}
	local mSmoothEdgeSet: { [string]: boolean } = {}
	local function classifyEdges(edges: { Types.FlatEdge }, target: { [string]: boolean }): number
		local count = 0
		for _, edge in edges do
			local ia = mVertexIds[positionKey(RobloxConvert.position(edge.a, scale) - meshCenter)]
			local ib = mVertexIds[positionKey(RobloxConvert.position(edge.b, scale) - meshCenter)]
			if ia ~= nil and ib ~= nil and ia ~= ib then
				target[edgeKey(ia, ib)] = true
				count += 1
			end
		end
		return count
	end
	mStats.sharpEdgeCount = classifyEdges(flatMesh.sharpEdges, mSharpEdgeSet)
	mStats.smoothEdgeCount = classifyEdges(flatMesh.smoothEdges, mSmoothEdgeSet)

	local function isSmoothEdge(key: string, faceA: FaceRecord, faceB: FaceRecord): boolean
		if mSharpEdgeSet[key] then
			return false
		elseif mSmoothEdgeSet[key] then
			return true
		else
			return faceA.normal:Dot(faceB.normal) > kCreaseAngleCos
		end
	end

	-- Pass 2: crease-aware corner normals. For each face corner, flood the
	-- fan of faces around that vertex crossing only smooth edges.
	local mNormalIds: { [string]: number } = {}
	local function getNormalId(normal: Vector3): number
		local key = string.format(
			"%d,%d,%d",
			math.round(normal.X * 1000),
			math.round(normal.Y * 1000),
			math.round(normal.Z * 1000)
		)
		local existing = mNormalIds[key]
		if existing ~= nil then
			return existing
		end
		local id = mesh:AddNormal(normal)
		mNormalIds[key] = id
		mStats.normalCount += 1
		return id
	end

	local function cornerNormal(startIndex: number, vertexId: number): Vector3
		local startFace = mFaces[startIndex]
		local visited: { [number]: boolean } = { [startIndex] = true }
		local queue: { number } = { startIndex }
		local sum = Vector3.zero
		while #queue > 0 do
			local faceIndex = table.remove(queue) :: number
			local face = mFaces[faceIndex]
			sum += face.areaNormal
			for _, otherVertexId in face.vertexIds do
				if otherVertexId == vertexId then
					continue
				end
				local key = edgeKey(vertexId, otherVertexId)
				local neighbors = mEdgeFaces[key]
				if neighbors == nil then
					continue
				end
				for _, neighborIndex in neighbors do
					if visited[neighborIndex] then
						continue
					end
					local neighbor = mFaces[neighborIndex]
					if
						neighbor.normal:Dot(startFace.normal) > kOpposedDotMin
						and isSmoothEdge(key, face, neighbor)
					then
						visited[neighborIndex] = true
						table.insert(queue, neighborIndex)
					end
				end
			end
		end
		if sum.Magnitude < 1e-9 then
			return startFace.normal
		end
		return sum.Unit
	end

	for faceIndex, face in mFaces do
		local cornerNormalIds = table.create(3)
		for corner, vertexId in face.vertexIds do
			cornerNormalIds[corner] = getNormalId(cornerNormal(faceIndex, vertexId))
		end
		mesh:SetFaceNormals(face.faceId, cornerNormalIds)
	end

	return mesh, mStats
end

return buildEditableMesh
