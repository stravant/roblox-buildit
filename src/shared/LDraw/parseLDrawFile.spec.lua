--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local parseLDrawFile = require(script.Parent.parseLDrawFile)

return function(t: TestTypes.TestContext)
	t.test("parses header metadata", function()
		local parsed = parseLDrawFile([[
0 Brick  2 x  4
0 Name: 3001.dat
0 Author: James Jessiman
0 !LDRAW_ORG Part UPDATE 2004-03
0 BFC CERTIFY CCW
]])
		t.expect(parsed.description).toBe("Brick  2 x  4")
		t.expect(parsed.name).toBe("3001.dat")
		t.expect(parsed.fileType).toBe("Part")
		t.expect(parsed.certified).toBe(true)
		t.expect(parsed.parseErrorCount).toBe(0)
	end)

	t.test("parses subfile references with transform and normalized name", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CCW
1 16 20 4 0 1 0 0 0 -5 0 0 0 1 S\3001S01.DAT
]])
		t.expect(#parsed.subfiles).toBe(1)
		local ref = parsed.subfiles[1]
		t.expect(ref.colorCode).toBe(16)
		t.expect(ref.fileName).toBe("s/3001s01.dat")
		t.expect(ref.invert).toBe(false)
		t.expect(ref.transform.Position).toBeCloseTo(Vector3.new(20, 4, 0))
		t.expect(ref.transform.YVector).toBeCloseTo(Vector3.new(0, -5, 0))
		t.expect(ref.transform.XVector).toBeCloseTo(Vector3.new(1, 0, 0))
	end)

	t.test("records INVERTNEXT on the following reference only", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CCW
0 BFC INVERTNEXT
1 16 0 0 0 1 0 0 0 1 0 0 0 1 box5.dat
1 16 0 0 0 1 0 0 0 1 0 0 0 1 stud.dat
]])
		t.expect(#parsed.subfiles).toBe(2)
		t.expect(parsed.subfiles[1].invert).toBe(true)
		t.expect(parsed.subfiles[2].invert).toBe(false)
	end)

	t.test("parses triangles, quads, and lines", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CCW
3 16 0 0 0 1 0 0 0 0 1
4 4 -1 0 -1 1 0 -1 1 0 1 -1 0 1
2 24 0 0 0 1 1 1
]])
		t.expect(#parsed.triangles).toBe(1)
		t.expect(#parsed.quads).toBe(1)
		t.expect(#parsed.lines).toBe(1)
		t.expect(parsed.triangles[1].a).toBeCloseTo(Vector3.new(0, 0, 0))
		t.expect(parsed.triangles[1].b).toBeCloseTo(Vector3.new(1, 0, 0))
		t.expect(parsed.triangles[1].c).toBeCloseTo(Vector3.new(0, 0, 1))
		t.expect(parsed.quads[1].colorCode).toBe(4)
		t.expect(parsed.lines[1].colorCode).toBe(24)
	end)

	t.test("parses conditional lines keeping only the edge endpoints", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CCW
5 24 1 0 0 1 1 0 0.9 0 0.1 0.9 2 0.1
]])
		t.expect(#parsed.condLines).toBe(1)
		t.expect(#parsed.lines).toBe(0)
		t.expect(parsed.condLines[1].a).toBeCloseTo(Vector3.new(1, 0, 0))
		t.expect(parsed.condLines[1].b).toBeCloseTo(Vector3.new(1, 1, 0))
	end)

	t.test("normalizes CW-certified geometry to CCW at parse time", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CW
3 16 0 0 0 1 0 0 0 0 1
]])
		-- Vertex order b/c swapped relative to the source line.
		t.expect(parsed.triangles[1].a).toBeCloseTo(Vector3.new(0, 0, 0))
		t.expect(parsed.triangles[1].b).toBeCloseTo(Vector3.new(0, 0, 1))
		t.expect(parsed.triangles[1].c).toBeCloseTo(Vector3.new(1, 0, 0))
	end)

	t.test("respects mid-file winding statements", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC CERTIFY CCW
3 16 0 0 0 1 0 0 0 0 1
0 BFC CW
3 16 0 0 0 1 0 0 0 0 1
]])
		local first = parsed.triangles[1]
		local second = parsed.triangles[2]
		t.expect(first.b).toBeCloseTo(Vector3.new(1, 0, 0))
		t.expect(second.b).toBeCloseTo(Vector3.new(0, 0, 1))
	end)

	t.test("counts malformed lines without failing", function()
		local parsed = parseLDrawFile([[
0 Test
1 16 bogus 0 0 1 0 0 0 1 0 0 0 1 foo.dat
3 16 0 0 0 1 0 0
]])
		t.expect(parsed.parseErrorCount).toBe(2)
		t.expect(#parsed.subfiles).toBe(0)
		t.expect(#parsed.triangles).toBe(0)
	end)

	t.test("marks NOCERTIFY files", function()
		local parsed = parseLDrawFile([[
0 Test
0 BFC NOCERTIFY
]])
		t.expect(parsed.certified).toBe(false)
		local noStatement = parseLDrawFile("0 Test")
		t.expect(noStatement.certified).toBe(nil)
	end)
end
