--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local Types = require(script.Parent.Types)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local flattenMesh = require(script.Parent.flattenMesh)
local findConnections = require(script.Parent.findConnections)
local deriveSockets = require(script.Parent.deriveSockets)
local coalesceRegions = require(script.Parent.coalesceRegions)

local kUp = Vector3.new(0, -1, 0) -- LDraw up

local function studCell(x: number, y: number, z: number, direction: Vector3?): Types.RegionCell
	return { kind = "Stud", position = Vector3.new(x, y, z), direction = direction or kUp }
end

local function gridCells(xs: { number }, zs: { number }): { Types.RegionCell }
	local cells = {}
	for _, x in xs do
		for _, z in zs do
			table.insert(cells, studCell(x, 0, z))
		end
	end
	return cells
end

return function(t: TestTypes.TestContext)
	t.test("coalesces a full grid into one region", function()
		local regions = coalesceRegions(gridCells({ -30, -10, 10, 30 }, { -10, 10 }))
		t.expect(#regions).toBe(1)
		local region = regions[1]
		t.expect(region.kind).toBe("Stud")
		t.expect(region.countX).toBe(4)
		t.expect(region.countZ).toBe(2)
		t.expect(region.pitch).toBe(20)
		t.expect(region.frame.Position).toBeCloseTo(Vector3.new(0, 0, 0))
		t.expect(region.frame.YVector).toBeCloseTo(kUp)
	end)

	t.test("splits an L-shaped field into two rectangles", function()
		local cells = gridCells({ 0, 20, 40 }, { 0 })
		table.insert(cells, studCell(0, 0, 20))
		local regions = coalesceRegions(cells)
		t.expect(#regions).toBe(2)
		local total = 0
		for _, region in regions do
			total += region.countX * region.countZ
		end
		t.expect(total).toBe(4)
	end)

	t.test("separates cells by direction", function()
		local cells = {
			studCell(0, 0, 0),
			studCell(20, 0, 0),
			studCell(40, 0, 0, Vector3.new(-1, 0, 0)), -- side stud
		}
		local regions = coalesceRegions(cells)
		t.expect(#regions).toBe(2)
	end)

	t.test("separates off-lattice cells (jumper offset)", function()
		local regions = coalesceRegions({
			studCell(0, 0, 0),
			studCell(20, 0, 0),
			-- Half-module offset: must not merge into the same lattice.
			studCell(50, 0, 0),
		})
		t.expect(#regions).toBe(2)
	end)

	t.test("separates cells on different planes", function()
		local regions = coalesceRegions({
			studCell(0, 0, 0),
			studCell(20, 8, 0),
		})
		t.expect(#regions).toBe(2)
	end)

	t.test("keeps stud and socket regions apart", function()
		local regions = coalesceRegions({
			{ kind = "Stud", position = Vector3.new(0, 0, 0), direction = kUp },
			{ kind = "Socket", position = Vector3.new(0, 24, 0), direction = -kUp },
		})
		t.expect(#regions).toBe(2)
	end)

	t.test("non-axis-aligned directions fall back to 1x1 regions", function()
		local diagonal = Vector3.new(1, -1, 0).Unit
		local regions = coalesceRegions({
			studCell(0, 0, 0, diagonal),
			studCell(20, 0, 0, diagonal),
		})
		t.expect(#regions).toBe(2)
		t.expect(regions[1].countX).toBe(1)
		t.expect(regions[1].frame.YVector).toBeCloseTo(diagonal)
	end)

	t.test("2x4 brick (3001) reduces to stud, socket, and tube-center regions", function()
		local library = LDrawLibrary.new(t.readFile)
		local mesh = flattenMesh(library, "3001.dat") :: any
		local connections = findConnections(library, "3001.dat") :: any
		local sockets = deriveSockets(connections, mesh)

		local cells: { Types.RegionCell } = {}
		for _, connection in connections do
			if connection.type == "Stud" then
				table.insert(cells, { kind = "Stud", position = connection.position, direction = connection.direction })
			end
		end
		for _, socket in sockets do
			table.insert(cells, { kind = "Socket", position = socket.position, direction = socket.direction })
		end

		local regions = coalesceRegions(cells)
		-- Studs 4x2, socket cells 4x2, and the 3x1 tube-center socket row
		-- (which sits on a half-module-offset lattice, so it stays its own
		-- region).
		t.expect(#regions).toBe(3)
		local studRegion: Types.ConnectionRegion? = nil
		local socketCellRegion: Types.ConnectionRegion? = nil
		local tubeCenterRegion: Types.ConnectionRegion? = nil
		for _, region in regions do
			if region.kind == "Stud" then
				studRegion = region
			elseif region.countX * region.countZ == 8 then
				socketCellRegion = region
			else
				tubeCenterRegion = region
			end
		end
		t.expect((studRegion :: any).countX).toBe(4)
		t.expect((studRegion :: any).countZ).toBe(2)
		t.expect((studRegion :: any).frame.Position).toBeCloseTo(Vector3.new(0, 0, 0))
		t.expect((socketCellRegion :: any).countX).toBe(4)
		t.expect((socketCellRegion :: any).countZ).toBe(2)
		t.expect((socketCellRegion :: any).frame.Position).toBeCloseTo(Vector3.new(0, 24, 0))
		t.expect((socketCellRegion :: any).frame.YVector).toBeCloseTo(Vector3.new(0, 1, 0))
		t.expect((tubeCenterRegion :: any).countX * (tubeCenterRegion :: any).countZ).toBe(3)
		t.expect((tubeCenterRegion :: any).frame.Position).toBeCloseTo(Vector3.new(0, 24, 0))
	end)
end
