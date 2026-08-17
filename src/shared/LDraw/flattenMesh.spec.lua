--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local flattenMesh = require(script.Parent.flattenMesh)

-- A unit square in the XZ plane, wound CCW viewed from -Y (LDraw "above"):
-- normal of (b-a) x (c-a) points -Y.
local kSquare = [[
0 Square
0 BFC CERTIFY CCW
4 16 0 0 0 1 0 0 1 0 1 0 0 1
]]

local function triangleNormal(tri: { a: Vector3, b: Vector3, c: Vector3 }): Vector3
	return (tri.b - tri.a):Cross(tri.c - tri.a).Unit
end

return function(t: TestTypes.TestContext)
	local function makeLibrary(files: { [string]: string })
		return LDrawLibrary.new(function(path: string): string?
			return files[path]
		end)
	end

	t.test("flattens quads into two triangles", function()
		local library = makeLibrary({ ["p/square.dat"] = kSquare })
		local mesh = flattenMesh(library, "square.dat") :: any
		t.expect(#mesh.triangles).toBe(2)
		t.expect(mesh.hasUncertified).toBe(false)
		t.expect(triangleNormal(mesh.triangles[1])).toBeCloseTo(Vector3.new(0, -1, 0))
		t.expect(triangleNormal(mesh.triangles[2])).toBeCloseTo(Vector3.new(0, -1, 0))
	end)

	t.test("applies subfile transforms", function()
		local library = makeLibrary({
			["p/square.dat"] = kSquare,
			["parts/moved.dat"] = [[
0 Moved
0 BFC CERTIFY CCW
1 16 10 20 30 1 0 0 0 1 0 0 0 1 square.dat
]],
		})
		local mesh = flattenMesh(library, "moved.dat") :: any
		t.expect(mesh.triangles[1].a).toBeCloseTo(Vector3.new(10, 20, 30))
		t.expect(mesh.boundsMin).toBeCloseTo(Vector3.new(10, 20, 30))
		t.expect(mesh.boundsMax).toBeCloseTo(Vector3.new(11, 20, 31))
	end)

	t.test("corrects winding under mirroring transforms", function()
		local library = makeLibrary({
			["p/square.dat"] = kSquare,
			["parts/mirrored.dat"] = [[
0 Mirrored
0 BFC CERTIFY CCW
1 16 0 0 0 1 0 0 0 1 0 0 0 1 square.dat
1 16 10 0 0 -1 0 0 0 1 0 0 0 1 square.dat
]],
		})
		local mesh = flattenMesh(library, "mirrored.dat") :: any
		t.expect(#mesh.triangles).toBe(4)
		for _, tri in mesh.triangles do
			t.expect(triangleNormal(tri)).toBeCloseTo(Vector3.new(0, -1, 0))
		end
	end)

	t.test("applies INVERTNEXT", function()
		local library = makeLibrary({
			["p/square.dat"] = kSquare,
			["parts/inverted.dat"] = [[
0 Inverted
0 BFC CERTIFY CCW
0 BFC INVERTNEXT
1 16 0 0 0 1 0 0 0 1 0 0 0 1 square.dat
]],
		})
		local mesh = flattenMesh(library, "inverted.dat") :: any
		t.expect(#mesh.triangles).toBe(2)
		t.expect(triangleNormal(mesh.triangles[1])).toBeCloseTo(Vector3.new(0, 1, 0))
	end)

	t.test("resolves color inheritance", function()
		local library = makeLibrary({
			["p/square.dat"] = kSquare,
			["parts/colored.dat"] = [[
0 Colored
0 BFC CERTIFY CCW
1 16 0 0 0 1 0 0 0 1 0 0 0 1 square.dat
1 4 10 0 0 1 0 0 0 1 0 0 0 1 square.dat
]],
		})
		local defaultMesh = flattenMesh(library, "colored.dat") :: any
		t.expect(defaultMesh.triangles[1].colorCode).toBe(16)
		t.expect(defaultMesh.triangles[3].colorCode).toBe(4)

		local coloredMesh = flattenMesh(library, "colored.dat", { colorCode = 7 }) :: any
		t.expect(coloredMesh.triangles[1].colorCode).toBe(7)
		t.expect(coloredMesh.triangles[3].colorCode).toBe(4)
	end)

	t.test("emits uncertified geometry double-sided", function()
		local library = makeLibrary({
			["p/nobfc.dat"] = [[
0 No BFC statement
4 16 0 0 0 1 0 0 1 0 1 0 0 1
]],
		})
		local mesh = flattenMesh(library, "nobfc.dat") :: any
		t.expect(#mesh.triangles).toBe(4)
		t.expect(mesh.hasUncertified).toBe(true)
	end)

	t.test("collects transformed sharp and smooth edge markings", function()
		local library = makeLibrary({
			["p/edged.dat"] = [[
0 Edged
0 BFC CERTIFY CCW
4 16 0 0 0 1 0 0 1 0 1 0 0 1
2 24 0 0 0 1 0 0
5 24 1 0 0 1 0 1 2 0 0 0 0 2
]],
			["parts/edgemoved.dat"] = [[
0 Moved edges
0 BFC CERTIFY CCW
1 16 10 0 0 1 0 0 0 1 0 0 0 1 edged.dat
]],
		})
		local mesh = flattenMesh(library, "edgemoved.dat") :: any
		t.expect(#mesh.sharpEdges).toBe(1)
		t.expect(#mesh.smoothEdges).toBe(1)
		t.expect(mesh.sharpEdges[1].a).toBeCloseTo(Vector3.new(10, 0, 0))
		t.expect(mesh.sharpEdges[1].b).toBeCloseTo(Vector3.new(11, 0, 0))
		t.expect(mesh.smoothEdges[1].a).toBeCloseTo(Vector3.new(11, 0, 0))
		t.expect(mesh.smoothEdges[1].b).toBeCloseTo(Vector3.new(11, 0, 1))
	end)

	t.test("reports missing referenced files", function()
		local library = makeLibrary({
			["parts/broken.dat"] = [[
0 Broken
0 BFC CERTIFY CCW
1 16 0 0 0 1 0 0 0 1 0 0 0 1 nosuchfile.dat
]],
		})
		local mesh = flattenMesh(library, "broken.dat") :: any
		t.expect(mesh.missingFiles).toEqual({ "nosuchfile.dat" })
	end)

	t.test("returns nil for a missing root file", function()
		local library = makeLibrary({})
		t.expect(flattenMesh(library, "nope.dat")).toBeFalsy()
	end)

	t.test("flattens real 3001 brick with correct bounds", function()
		local library = LDrawLibrary.new(t.readFile)
		local mesh = flattenMesh(library, "3001.dat") :: any
		t.expect(mesh).toBeTruthy()
		t.log(`3001.dat: {#mesh.triangles} triangles`)
		t.expect(#mesh.triangles > 200).toBe(true)
		t.expect(mesh.missingFiles).toEqual({})
		t.expect(mesh.hasUncertified).toBe(false)
		-- 2x4 brick: 80x40 LDU footprint, 24 LDU body + 4 LDU studs up (-Y).
		t.expect(mesh.boundsMin).toBeCloseTo(Vector3.new(-40, -4, -20), 0.01)
		t.expect(mesh.boundsMax).toBeCloseTo(Vector3.new(40, 24, 20), 0.01)
	end)
end
