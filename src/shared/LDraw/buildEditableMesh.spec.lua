--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local flattenMesh = require(script.Parent.flattenMesh)
local buildEditableMesh = require(script.Parent.buildEditableMesh)
local RobloxConvert = require(script.Parent.RobloxConvert)

local AssetService = game:GetService("AssetService")

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	t.test("converts LDraw space to Roblox space", function()
		-- LDraw: stud at (30, 0, 10) pointing -Y (up).
		t.expect(RobloxConvert.position(Vector3.new(30, 0, 10))).toBeCloseTo(Vector3.new(1.5, 0, -0.5))
		t.expect(RobloxConvert.direction(Vector3.new(0, -1, 0))).toBeCloseTo(Vector3.new(0, 1, 0))
		-- A brick bottom (y=24) maps below the top (y=0).
		t.expect(RobloxConvert.position(Vector3.new(0, 24, 0)).Y).toBeCloseTo(-1.2)
	end)

	t.test("builds a welded EditableMesh for the 2x4 brick", function()
		local mesh = flattenMesh(library, "3001.dat") :: any
		t.expect(mesh).toBeTruthy()
		local editableMesh, stats = buildEditableMesh(mesh)
		t.expect(editableMesh).toBeTruthy()
		t.log(`3001.dat mesh: {stats.vertexCount} vertices, {stats.triangleCount} triangles, {stats.normalCount} normals, {stats.sharpEdgeCount} sharp / {stats.smoothEdgeCount} smooth edges`)
		t.expect(stats.triangleCount > 200).toBe(true)
		-- Welding must actually share vertices across triangles.
		t.expect(stats.vertexCount < stats.triangleCount * 3 / 2).toBe(true)
		-- Converted geometry spans y in [-1.2, 0.2] around the LDraw origin,
		-- so the mesh got recentered by (0, -0.5, 0).
		t.expect(stats.meshCenter).toBeCloseTo(Vector3.new(0, -0.5, 0), 0.01)
		-- The brick has data-marked edges of both kinds (box outlines sharp,
		-- stud/tube cylinders smooth), and normal generation must share
		-- normals (smooth fans + the 6 box directions), not 3 per corner.
		t.expect(stats.sharpEdgeCount > 0).toBe(true)
		t.expect(stats.smoothEdgeCount > 0).toBe(true)
		t.expect(stats.normalCount > 6).toBe(true)
		t.expect(stats.normalCount < stats.triangleCount).toBe(true)
	end)

	t.test("cube primitive gets exactly 6 sharp face normals", function()
		local mesh = flattenMesh(library, "box.dat") :: any
		t.expect(mesh).toBeTruthy()
		local editableMesh, stats = buildEditableMesh(mesh)
		t.expect(stats.triangleCount).toBe(12)
		t.expect(stats.vertexCount).toBe(8)
		t.expect(stats.sharpEdgeCount).toBe(12)
		-- All 12 edges are marked sharp (type 2), so each face keeps its own
		-- geometric normal: exactly 6 distinct directions.
		t.expect(stats.normalCount).toBe(6)

		-- Read back: every corner normal must equal the face's geometric normal.
		for _, faceId in editableMesh:GetFaces() do
			local vertexIds = editableMesh:GetFaceVertices(faceId)
			local a = editableMesh:GetPosition(vertexIds[1])
			local b = editableMesh:GetPosition(vertexIds[2])
			local c = editableMesh:GetPosition(vertexIds[3])
			local geometric = (b - a):Cross(c - a).Unit
			for _, normalId in editableMesh:GetFaceNormals(faceId) do
				t.expect(editableMesh:GetNormal(normalId)).toBeCloseTo(geometric, 0.001)
			end
		end
	end)

	t.test("MeshPart from 2x4 brick renders", function()
		local mesh = flattenMesh(library, "3001.dat") :: any
		local editableMesh = buildEditableMesh(mesh)
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(editableMesh))
		part.Name = "Brick3001"
		part.Color = Color3.fromRGB(180, 0, 0)
		part.Anchored = true
		part.CFrame = CFrame.new(0, 10, 0)
		part.Parent = workspace

		-- 2x4 brick at scale 1/20: 4 x 1.4 x 2 studs (incl. stud height).
		t.expect(part.Size).toBeCloseTo(Vector3.new(4, 1.4, 2), 0.01)

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(Vector3.new(5, 14, 5), part.Position)
		task.wait(0.2)
		t.screenshot("buildit_3001_meshpart")

		part.Parent = nil
	end)
end
