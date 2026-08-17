--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local Types = require(script.Parent.Types)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local flattenMesh = require(script.Parent.flattenMesh)
local findConnections = require(script.Parent.findConnections)
local deriveSockets = require(script.Parent.deriveSockets)

local function countByType(connections: { Types.Connection }): { [string]: number }
	local counts = {}
	for _, connection in connections do
		counts[connection.type] = (counts[connection.type] or 0) + 1
	end
	return counts
end

local function hasConnectionAt(
	connections: { Types.Connection },
	connectionType: string,
	position: Vector3,
	direction: Vector3
): boolean
	for _, connection in connections do
		if
			connection.type == connectionType
			and (connection.position - position).Magnitude < 0.1
			and (connection.direction - direction).Magnitude < 0.01
		then
			return true
		end
	end
	return false
end

local function hasSocketAt(sockets: { Types.Socket }, position: Vector3): boolean
	for _, socket in sockets do
		if (socket.position - position).Magnitude < 0.1 then
			return true
		end
	end
	return false
end

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	t.test("2x4 brick (3001): 8 studs up, 3 tubes down", function()
		local connections = findConnections(library, "3001.dat") :: any
		t.expect(connections).toBeTruthy()
		-- The interior shell also emits pocket cells (they dedup into the
		-- same derived sockets as the tube neighbors).
		t.expect(countByType(connections)).toEqual({ Stud = 8, Tube = 3, Pocket = 8 })

		local up = Vector3.new(0, -1, 0) -- LDraw up is -Y
		local down = Vector3.new(0, 1, 0)
		for _, x in { -30, -10, 10, 30 } do
			for _, z in { -10, 10 } do
				t.expect(hasConnectionAt(connections, "Stud", Vector3.new(x, 0, z), up)).toBe(true)
			end
		end
		for _, x in { -20, 0, 20 } do
			-- Tube free end on the bottom face (y=24).
			t.expect(hasConnectionAt(connections, "Tube", Vector3.new(x, 24, 0), down)).toBe(true)
		end
	end)

	t.test("2x4 plate (3020): tubes end on the plate bottom face", function()
		local connections = findConnections(library, "3020.dat") :: any
		t.expect(countByType(connections)).toEqual({ Stud = 8, Tube = 3, Pocket = 8 })
		t.expect(hasConnectionAt(connections, "Tube", Vector3.new(0, 8, 0), Vector3.new(0, 1, 0))).toBe(true)
	end)

	t.test("1x3 plate (3623): pins instead of tubes", function()
		local connections = findConnections(library, "3623.dat") :: any
		t.expect(countByType(connections)).toEqual({ Stud = 3, Pin = 2, Pocket = 3 })
		t.expect(hasConnectionAt(connections, "Pin", Vector3.new(-10, 8, 0), Vector3.new(0, 1, 0))).toBe(true)
		t.expect(hasConnectionAt(connections, "Pin", Vector3.new(10, 8, 0), Vector3.new(0, 1, 0))).toBe(true)
	end)

	t.test("1x1 brick (3005): stud plus cavity pocket", function()
		local connections = findConnections(library, "3005.dat") :: any
		t.expect(countByType(connections)).toEqual({ Stud = 1, Pocket = 1 })
		t.expect(hasConnectionAt(connections, "Stud", Vector3.new(0, 0, 0), Vector3.new(0, -1, 0))).toBe(true)
	end)

	t.test("1x1 brick (3005): pocket derives an underside socket", function()
		local mesh = flattenMesh(library, "3005.dat") :: any
		local connections = findConnections(library, "3005.dat") :: any
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(1)
		t.expect(sockets[1].position).toBeCloseTo(Vector3.new(0, 24, 0))
		t.expect(sockets[1].direction).toBeCloseTo(Vector3.new(0, 1, 0))
	end)

	t.test("derives 11 sockets for the 2x4 brick (8 cells + 3 tube centers)", function()
		local mesh = flattenMesh(library, "3001.dat") :: any
		local connections = findConnections(library, "3001.dat") :: any
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(11)
		for _, x in { -30, -10, 10, 30 } do
			for _, z in { -10, 10 } do
				t.expect(hasSocketAt(sockets, Vector3.new(x, 24, z))).toBe(true)
			end
		end
		-- Tube centers grip a single stud too (offset/jumper placements).
		for _, x in { -20, 0, 20 } do
			t.expect(hasSocketAt(sockets, Vector3.new(x, 24, 0))).toBe(true)
		end
		for _, socket in sockets do
			t.expect(socket.direction).toBeCloseTo(Vector3.new(0, 1, 0))
		end
	end)

	t.test("derives 3 sockets for the 1x3 plate (side candidates culled by bounds)", function()
		local mesh = flattenMesh(library, "3623.dat") :: any
		local connections = findConnections(library, "3623.dat") :: any
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(3)
		t.expect(hasSocketAt(sockets, Vector3.new(-20, 8, 0))).toBe(true)
		t.expect(hasSocketAt(sockets, Vector3.new(0, 8, 0))).toBe(true)
		t.expect(hasSocketAt(sockets, Vector3.new(20, 8, 0))).toBe(true)
	end)

	t.test("technic brick (3700): pegholes pair into a through-hole", function()
		local connections = findConnections(library, "3700.dat") :: any
		-- The hollow studs (stud2) also accept bars down their axis.
		t.expect(countByType(connections)).toEqual({ Stud = 2, HollowStud = 2, Pin = 1, PegHole = 1 })
		local hole = nil
		for _, connection in connections do
			if connection.type == "PegHole" then
				hole = connection
			end
		end
		t.expect(hole).toBeTruthy()
		t.expect(hole.position).toBeCloseTo(Vector3.new(0, 10, 0))
		t.expect(hole.length).toBeCloseTo(20)
		t.expect(math.abs(hole.direction.Z)).toBeCloseTo(1)
	end)

	t.test("technic brick 1x4 (3701): three through-holes", function()
		local connections = findConnections(library, "3701.dat") :: any
		t.expect(countByType(connections).PegHole).toBe(3)
	end)

	t.test("axle 2 (3704): one merged shaft at full length", function()
		local connections = findConnections(library, "3704.dat") :: any
		t.expect(countByType(connections)).toEqual({ Axle = 1 })
		local axle = connections[1]
		t.expect(axle.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
		t.expect(math.abs(axle.direction.X)).toBeCloseTo(1)
		-- End caps included: a 2M axle is exactly 40 (flush positioning
		-- in holes depends on this).
		t.expect(axle.length).toBeCloseTo(40, 0.5)
	end)

	t.test("notched axle (32062): segments merge across notches", function()
		local connections = findConnections(library, "32062.dat") :: any
		t.expect(countByType(connections)).toEqual({ Axle = 1 })
		t.expect(connections[1].length).toBeCloseTo(40, 0.5)
	end)

	t.test("friction pin (2780): two pin halves and a bar bore through", function()
		local connections = findConnections(library, "2780.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.TechnicPin).toBe(2)
		t.expect(counts.BarHole).toBe(1)
		for _, connection in connections do
			if connection.type == "TechnicPin" then
				t.expect(connection.length).toBeCloseTo(20)
				t.expect(math.abs(connection.direction.X)).toBeCloseTo(1)
				t.expect(math.abs(connection.position.X)).toBeCloseTo(10)
			else -- BarHole
				t.expect(math.abs(connection.direction.X)).toBeCloseTo(1)
				t.expect(connection.length >= 30).toBe(true)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 1)
			end
		end
	end)

	t.test("frictionless pin (3673): bar bore through", function()
		local connections = findConnections(library, "3673.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.TechnicPin).toBe(2)
		t.expect(counts.BarHole).toBe(1)
	end)

	t.test("gear 8 tooth (3647): axle hole with depth", function()
		local connections = findConnections(library, "3647.dat") :: any
		t.expect(countByType(connections).AxleHole).toBe(1)
		local hole = nil
		for _, connection in connections do
			if connection.type == "AxleHole" then
				hole = connection
			end
		end
		t.expect(hole.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
		t.expect(hole.length).toBeCloseTo(20)
		t.expect(math.abs(hole.direction.Z)).toBeCloseTo(1)
	end)

	t.test("bar 4L (30374): radius-4 cylinder detected as bar", function()
		local connections = findConnections(library, "30374.dat") :: any
		t.expect(countByType(connections)).toEqual({ Bar = 1 })
		local bar = connections[1]
		t.expect(bar.length).toBeCloseTo(80)
		t.expect(bar.position).toBeCloseTo(Vector3.new(0, 40, 0))
		t.expect(math.abs(bar.direction.Y)).toBeCloseTo(1)
	end)

	t.test("clip plate (4085c): clip at the grip center, plus a pocket socket", function()
		local connections = findConnections(library, "4085c.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.Clip).toBe(1)
		t.expect(counts.Stud).toBe(1)
		t.expect(counts.Pocket).toBe(1)
		local clip = nil
		for _, connection in connections do
			if connection.type == "Clip" then
				clip = connection
			end
		end
		-- Grip center = the neighboring stud cell center, half a module out
		-- from the plate edge: a clipped bar lines up with a bar mounted
		-- one stud in front of the clip.
		t.expect(clip.position).toBeCloseTo(Vector3.new(0, 4, -20))
		t.expect(math.abs(clip.direction.Y)).toBeCloseTo(1)

		local mesh = flattenMesh(library, "4085c.dat") :: any
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(1)
		t.expect(sockets[1].position).toBeCloseTo(Vector3.new(0, 8, 0))
	end)

	t.test("antenna (3957a): tube base derives a center socket", function()
		local mesh = flattenMesh(library, "3957a.dat") :: any
		local connections = findConnections(library, "3957a.dat") :: any
		t.expect(countByType(connections).Tube).toBe(1)
		t.expect(countByType(connections).Bar >= 1).toBe(true)
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(1)
		t.expect(sockets[1].position).toBeCloseTo(Vector3.new(0, 8, 0))
	end)

	t.test("towball plate (3184): radius-8 sphere detected as ball", function()
		local connections = findConnections(library, "3184.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.Towball).toBe(1)
		t.expect(counts.Stud).toBe(4)
		t.expect(hasConnectionAt(connections, "Towball", Vector3.new(0, 4, -28), Vector3.new(0, -1, 0))).toBe(true)
	end)

	t.test("axle towball (2736): axle plus ball", function()
		local connections = findConnections(library, "2736.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.Towball).toBe(1)
		t.expect(counts.Axle).toBe(1)
		t.expect(hasConnectionAt(connections, "Towball", Vector3.new(-12, 0, 0), Vector3.new(0, -1, 0))).toBe(true)
	end)

	t.test("socket plate (14418): joint8 socket cup", function()
		local connections = findConnections(library, "14418.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.TowballSocket).toBe(1)
		t.expect(counts.Stud).toBe(2)
		local socket = nil
		for _, connection in connections do
			if connection.type == "TowballSocket" then
				socket = connection
			end
		end
		t.expect(socket.position).toBeCloseTo(Vector3.new(30, 4, 0))
	end)

	t.test("axle connector hub (6553): through axle hole from the bush sleeve", function()
		local connections = findConnections(library, "6553.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		t.expect(counts.Axle).toBe(1)
		for _, connection in connections do
			if connection.type == "AxleHole" then
				-- bush0 rotated: sleeve perpendicular to the male axle.
				t.expect(math.abs(connection.direction.X)).toBeCloseTo(1)
				t.expect(connection.length).toBeCloseTo(12)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
				t.expect(connection.oneSided).toBeFalsy()
			elseif connection.type == "Axle" then
				t.expect(math.abs(connection.direction.Y)).toBeCloseTo(1)
				t.expect(connection.length).toBeCloseTo(30, 0.5)
			end
		end
	end)

	t.test("pin/bush connector (3651): blind axle hole via end cap merge", function()
		local connections = findConnections(library, "3651.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		t.expect(counts.PegHole).toBe(1)
		t.expect(counts.Stud).toBe(2)
		for _, connection in connections do
			if connection.type == "AxleHole" then
				-- axl5end cap at z=-10 + bush sleeve: one blind hole open
				-- toward +Z.
				t.expect(connection.oneSided).toBe(true)
				t.expect(connection.direction.Z > 0.9).toBe(true)
				t.expect(connection.length).toBeCloseTo(20)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
			elseif connection.type == "PegHole" then
				-- connhole: 20 LDU pin hole through the stud section.
				t.expect(connection.length).toBeCloseTo(20)
				t.expect(math.abs(connection.direction.X)).toBeCloseTo(1)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, -20), 0.1)
			end
		end
	end)

	t.test("technic bush (3713): axle hole detected via bush primitive", function()
		local connections = findConnections(library, "3713.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		t.expect((connections[1].length :: number) >= 12).toBe(true)
	end)

	t.test("rotor (2712): hub axle hole via axl5hol8", function()
		local connections = findConnections(library, "2712.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		t.expect(counts.Stud).toBe(3)
		for _, connection in connections do
			if connection.type == "AxleHole" then
				t.expect(connection.length).toBeCloseTo(8)
				t.expect(math.abs(connection.direction.Y)).toBeCloseTo(1)
			end
		end
	end)

	t.test("gear 16 tooth (4019): axle hole from tooth primitives, four bar holes", function()
		local connections = findConnections(library, "4019.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		-- The four real round holes around the hub are bar-sized.
		t.expect(counts.BarHole).toBe(4)
		for _, connection in connections do
			if connection.type == "AxleHole" then
				t.expect(connection.length).toBeCloseTo(20)
				t.expect(math.abs(connection.direction.Z)).toBeCloseTo(1)
			end
		end
	end)

	t.test("palm trunk (6135): axle hole from tooth primitives", function()
		local connections = findConnections(library, "6135.dat") :: any
		t.expect(countByType(connections).AxleHole).toBe(1)
	end)

	t.test("bevel gear (4143): axle hole (partial depth from axlehole ref)", function()
		local connections = findConnections(library, "4143.dat") :: any
		t.expect(countByType(connections)).toEqual({ AxleHole = 1 })
		t.expect(connections[1].length).toBeCloseTo(4)
	end)

	t.test("gear 24 tooth 3-axlehole (3648a): pin holes + center override", function()
		local connections = findConnections(library, "3648a.dat") :: any
		local counts = countByType(connections)
		-- Four hand-carved r6 pin-hole bores at the diagonals.
		t.expect(counts.PegHole).toBe(4)
		-- Center axle hole comes from the part override table.
		t.expect(counts.AxleHole).toBe(1)
		for _, x in { -10, 10 } do
			for _, y in { -10, 10 } do
				local found = false
				for _, connection in connections do
					if
						connection.type == "PegHole"
						and (connection.position - Vector3.new(x, y, 0)).Magnitude < 0.5
					then
						found = true
					end
				end
				t.expect(found).toBe(true)
			end
		end
		for _, connection in connections do
			if connection.type == "AxleHole" then
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
				t.expect(connection.length).toBeCloseTo(15.6)
			end
		end
	end)

	t.test("steering link (2739a): two towball socket cups plus the axle", function()
		local connections = findConnections(library, "2739a.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.TowballSocket).toBe(2)
		t.expect(counts.Axle).toBe(1)
		local found = 0
		for _, connection in connections do
			if connection.type == "TowballSocket" then
				found += 1
				t.expect(math.abs(connection.direction.Y)).toBeCloseTo(1)
				t.expect(
					(connection.position - Vector3.new(0, 0, 0)).Magnitude < 0.5
						or (connection.position - Vector3.new(0, 0, 100)).Magnitude < 0.5
				).toBe(true)
			end
		end
		t.expect(found).toBe(2)
	end)

	t.test("axle joiner (6538a): internal axle hole plus external slip surface", function()
		local connections = findConnections(library, "6538a.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.AxleHole).toBe(1)
		t.expect(counts.SlipAxle).toBe(1)
		for _, connection in connections do
			if connection.type == "SlipAxle" then
				t.expect(connection.length).toBeCloseTo(40)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
				t.expect(math.abs(connection.direction.Z)).toBeCloseTo(1)
			end
		end
	end)

	t.test("driving ring (6539): slip ring", function()
		local connections = findConnections(library, "6539.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.SlipRing).toBe(1)
		for _, connection in connections do
			if connection.type == "SlipRing" then
				t.expect(connection.length).toBeCloseTo(24)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 0, 0), 0.1)
			end
		end
	end)

	t.test("differential (6573): interior post is a bar, not sockets", function()
		local mesh = flattenMesh(library, "6573.dat") :: any
		local connections = findConnections(library, "6573.dat", mesh) :: any
		local counts = countByType(connections)
		-- The stud3-built planet gear post must not read as an anti-stud.
		t.expect(counts.Pin).toBe(nil)
		t.expect(counts.Tube).toBe(nil)
		t.expect(#deriveSockets(connections, mesh)).toBe(0)
		-- It reads as a short r4 bar inside the cage (8 LDU: stud3 * 2).
		local foundPost = false
		for _, connection in connections do
			if connection.type == "Bar" and math.abs((connection.length or 0) - 8) < 0.5 then
				foundPost = true
				t.expect(math.abs(connection.direction.Y)).toBeCloseTo(1)
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 16, 0), 0.1)
			end
		end
		t.expect(foundPost).toBe(true)
	end)

	t.test("boundary rule keeps legit anti-studs (mesh-aware 3001)", function()
		local mesh = flattenMesh(library, "3001.dat") :: any
		local connections = findConnections(library, "3001.dat", mesh) :: any
		t.expect(countByType(connections)).toEqual({ Stud = 8, Tube = 3, Pocket = 8 })
	end)

	t.test("tile (3069b): underside cavity derives per-cell sockets", function()
		local mesh = flattenMesh(library, "3069b.dat") :: any
		local connections = findConnections(library, "3069b.dat", mesh) :: any
		t.expect(countByType(connections).Pocket).toBe(2)
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets).toBe(2)
		t.expect(hasSocketAt(sockets, Vector3.new(-10, 8, 0))).toBe(true)
		t.expect(hasSocketAt(sockets, Vector3.new(10, 8, 0))).toBe(true)
	end)

	t.test("square 1x1s (3024/3005): box pocket derives the socket", function()
		local plateMesh = flattenMesh(library, "3024.dat") :: any
		local plate = findConnections(library, "3024.dat", plateMesh) :: any
		local plateSockets = deriveSockets(plate, plateMesh)
		t.expect(#plateSockets).toBe(1)
		t.expect(hasSocketAt(plateSockets, Vector3.new(0, 8, 0))).toBe(true)

		local brickMesh = flattenMesh(library, "3005.dat") :: any
		local brick = findConnections(library, "3005.dat", brickMesh) :: any
		local brickSockets = deriveSockets(brick, brickMesh)
		t.expect(#brickSockets).toBe(1)
		t.expect(hasSocketAt(brickSockets, Vector3.new(0, 24, 0))).toBe(true)
	end)

	t.test("round 1x1s (4073/3062b): center grip on a stud", function()
		local plateMesh = flattenMesh(library, "4073.dat") :: any
		local plate = findConnections(library, "4073.dat", plateMesh) :: any
		t.expect(countByType(plate).Tube).toBe(1)
		local plateSockets = deriveSockets(plate, plateMesh)
		t.expect(#plateSockets).toBe(1)
		t.expect(hasSocketAt(plateSockets, Vector3.new(0, 8, 0))).toBe(true)

		-- The brick's base grip is a stud4od open tube (rim at the bottom
		-- face); the tube-center socket grips a stud below.
		local brickMesh = flattenMesh(library, "3062b.dat") :: any
		local brick = findConnections(library, "3062b.dat", brickMesh) :: any
		local counts = countByType(brick)
		t.expect(counts.Stud).toBe(1)
		t.expect(counts.Tube).toBe(1)
		local brickSockets = deriveSockets(brick, brickMesh)
		t.expect(hasSocketAt(brickSockets, Vector3.new(0, 24, 0))).toBe(true)
	end)

	t.test("minifig headgear (3624/3833): brim-recessed grip tube kept", function()
		-- Hats grip the head stud with a stud4 tube recessed up to 4 LDU
		-- inside the brim; the boundary rule must not cull it.
		local capMesh = flattenMesh(library, "3624.dat") :: any
		local cap = findConnections(library, "3624.dat", capMesh) :: any
		t.expect(countByType(cap).Tube).toBe(1)
		local capSockets = deriveSockets(cap, capMesh)
		t.expect(hasSocketAt(capSockets, Vector3.new(0, 0, 0))).toBe(true)

		local helmetMesh = flattenMesh(library, "3833.dat") :: any
		local helmet = findConnections(library, "3833.dat", helmetMesh) :: any
		t.expect(countByType(helmet).Tube).toBe(1)
	end)

	t.test("fire ladder sections (850/851a/852): slide interfaces", function()
		local bottom = findConnections(library, "850.dat") :: any
		t.expect(countByType(bottom).SlideGroove).toBe(1)
		local top = findConnections(library, "852.dat") :: any
		t.expect(countByType(top).SlideRail).toBe(1)
		local middle = findConnections(library, "851a.dat") :: any
		local counts = countByType(middle)
		t.expect(counts.SlideRail).toBe(1)
		t.expect(counts.SlideGroove).toBe(1)
	end)

	t.test("train tracks (74746/53401/2865/74747/53400): two ends each", function()
		for _, ref in { "74746.dat", "53401.dat", "2865.dat", "74747.dat", "53400.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).TrackEnd).toBe(2)
		end
	end)

	t.test("monorail tracks: end and ramp joint counts", function()
		for _, ref in { "2670.dat", "2671.dat", "2672.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).MonoEnd).toBe(2)
		end
		for _, ref in { "2677.dat", "2678.dat" } do
			local connections = findConnections(library, ref) :: any
			local counts = countByType(connections)
			t.expect(counts.MonoEnd).toBe(1)
			t.expect(counts.MonoRampJoint).toBe(1)
		end
	end)

	t.test("9V switches (2861/2859): three track ends each", function()
		for _, ref in { "2861.dat", "2859.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).TrackEnd).toBe(3)
		end
	end)

	t.test("crossing and roller coaster tracks: end counts", function()
		local crossing = findConnections(library, "32087.dat") :: any
		t.expect(countByType(crossing).TrackEnd).toBe(4)
		for _, ref in { "25059.dat", "26022.dat", "25061.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).CoasterEnd).toBe(2)
		end
	end)

	t.test("vertex-analyzed batch: arms, pivot ladder, stove door", function()
		t.expect(countByType(findConnections(library, "795.dat") :: any).ArmFinger).toBe(1)
		t.expect(countByType(findConnections(library, "4221.dat") :: any).ArmFinger).toBe(1)
		t.expect(countByType(findConnections(library, "4000.dat") :: any).Bar).toBe(1)
		t.expect(countByType(findConnections(library, "843.dat") :: any).HingePin).toBe(1)
		t.expect(countByType(findConnections(library, "841.dat") :: any).HingeSocket).toBe(1)
	end)

	t.test("homemaker cupboard (837/838): rod and corner bores", function()
		local door = findConnections(library, "838.dat") :: any
		t.expect(countByType(door).HingePin).toBe(1)
		local cabinet = findConnections(library, "837.dat") :: any
		t.expect(countByType(cabinet).HingeSocket).toBe(2)
	end)

	t.test("modern ladder (15118): rungs read as bars", function()
		local connections = findConnections(library, "15118.dat") :: any
		t.expect(countByType(connections).Bar).toBe(8)
	end)

	t.test("classic 2x12 ladder (420/421): slide pair", function()
		local bottom = findConnections(library, "420.dat") :: any
		t.expect(countByType(bottom).SlideGroove).toBe(1)
		local top = findConnections(library, "421.dat") :: any
		t.expect(countByType(top).SlideRail).toBe(1)
	end)

	t.test("cupboard doors (4533/4535) and cabinets (4532/4534)", function()
		for _, case in { { "4533.dat", 37 }, { "4535.dat", 85 } } do
			local connections = findConnections(library, case[1] :: any) :: any
			local pins = {}
			for _, connection in connections do
				if connection.type == "HingePin" then
					table.insert(pins, connection)
				end
			end
			t.expect(#pins).toBe(1)
			t.expect(pins[1].length).toBeCloseTo(case[2] :: any)
		end
		local small = findConnections(library, "4532.dat") :: any
		t.expect(countByType(small).HingeSocket).toBe(2)
		local tall = findConnections(library, "4534.dat") :: any
		t.expect(countByType(tall).HingeSocket).toBe(2)
	end)

	t.test("cupboard drawer slide (4532/4536)", function()
		local cupboard = findConnections(library, "4532.dat") :: any
		t.expect(countByType(cupboard).SlideGroove).toBe(1)
		local drawer = findConnections(library, "4536.dat") :: any
		t.expect(countByType(drawer).SlideRail).toBe(1)
	end)

	t.test("wheel pins (4870) and notched rim (30027b)", function()
		local plate = findConnections(library, "4870.dat") :: any
		t.expect(countByType(plate).WheelPin).toBe(2)
		local rim = findConnections(library, "30027b.dat") :: any
		t.expect((countByType(rim).WheelHole or 0) >= 1).toBe(true)
	end)

	t.test("car sunroof (2348a/2349a): hinge line pair", function()
		local glass = findConnections(library, "2348a.dat") :: any
		t.expect(countByType(glass).HingeFinger).toBe(1)
		local roof = findConnections(library, "2349a.dat") :: any
		t.expect(countByType(roof).HingeFinger).toBe(1)
	end)

	t.test("hand-built finger rows (3937/2440/3314/3433/2347)", function()
		for _, ref in { "3937.dat", "2440.dat", "3314.dat", "3433.dat", "2347.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).HingeFinger).toBe(1)
		end
	end)

	t.test("friends minidoll (92198/1006030): bar-based joints", function()
		local head = findConnections(library, "92198.dat") :: any
		local headCounts = countByType(head)
		-- Neck bore reads as a bar hole; hair stud on top.
		t.expect(headCounts.BarHole).toBe(1)
		t.expect(headCounts.Stud).toBe(1)

		local torso = findConnections(library, "1006030.dat") :: any
		local torsoCounts = countByType(torso)
		-- r4 neck pin reads as a Bar; hip receiver shells as BarHoles.
		t.expect((torsoCounts.Bar or 0) >= 1).toBe(true)
		t.expect((torsoCounts.BarHole or 0) >= 1).toBe(true)

		local hips = findConnections(library, "1015152.dat") :: any
		local hipCounts = countByType(hips)
		t.expect((hipCounts.Bar or 0) >= 1).toBe(true)
		t.expect(hipCounts.MinidollHinge).toBe(1)

		local legsMesh = flattenMesh(library, "1023035.dat") :: any
		local legs = findConnections(library, "1023035.dat", legsMesh) :: any
		t.expect(countByType(legs).MinidollHinge).toBe(1)
		t.expect(countByType(legs).Pocket).toBe(2)
		local legsSockets = deriveSockets(legs, legsMesh)
		t.expect(hasSocketAt(legsSockets, Vector3.new(10, 0, 0))).toBe(true)
		t.expect(hasSocketAt(legsSockets, Vector3.new(-10, 0, 0))).toBe(true)

		-- Thick-hinge legs share a different foot subpart, same pitch.
		local thick = findConnections(library, "25727.dat") :: any
		t.expect(countByType(thick).Pocket).toBe(2)
	end)

	t.test("tile with clip (2555): clip override, no phantom bar hole", function()
		local connections = findConnections(library, "2555.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.Clip).toBe(1)
		-- The clip's own inner r4 arc must not double as a BarHole.
		t.expect(counts.BarHole).toBe(nil)
		t.expect(counts.Pocket).toBe(1)
	end)

	t.test("classic towball socket plate (3183a): curated socket", function()
		local connections = findConnections(library, "3183a.dat") :: any
		t.expect(countByType(connections).TowballSocket).toBe(1)
		for _, connection in connections do
			if connection.type == "TowballSocket" then
				t.expect(connection.position).toBeCloseTo(Vector3.new(0, 4, -18))
			end
		end
	end)

	t.test("minifig torso (973): neck stud at the torso top plane", function()
		local connections = findConnections(library, "973.dat") :: any
		t.expect(countByType(connections).Stud).toBe(1)
		-- At y=0 so a head's bottom pocket seats flush (official assembly
		-- convention: head origin at torso -24).
		t.expect(hasConnectionAt(connections, "Stud", Vector3.new(0, 0, 0), Vector3.new(0, -1, 0))).toBe(true)
	end)

	t.test("minifig legs: foot sockets", function()
		local right = findConnections(library, "3816.dat") :: any
		t.expect(hasConnectionAt(right, "Pocket", Vector3.new(-10, 28, 0), Vector3.new(0, 1, 0))).toBe(true)
		local left = findConnections(library, "3817.dat") :: any
		t.expect(hasConnectionAt(left, "Pocket", Vector3.new(10, 28, 0), Vector3.new(0, 1, 0))).toBe(true)
	end)

	t.test("minifig head (3626b): top stud and bottom neck pocket", function()
		local mesh = flattenMesh(library, "3626b.dat") :: any
		local connections = findConnections(library, "3626b.dat", mesh) :: any
		local counts = countByType(connections)
		t.expect(counts.Stud >= 1).toBe(true)
		t.expect(counts.Pocket >= 1).toBe(true)
		local sockets = deriveSockets(connections, mesh)
		t.expect(#sockets >= 1).toBe(true)
	end)

	t.test("minifig hand (3820): C-grip reads as a bar hole", function()
		local connections = findConnections(library, "3820.dat") :: any
		t.expect(countByType(connections).BarHole).toBe(1)
		for _, connection in connections do
			if connection.type == "BarHole" then
				t.expect(connection.length >= 8).toBe(true)
			end
		end
	end)

	t.test("classic towball socket family: curated sockets present", function()
		for _, ref in { "3730.dat", "3779.dat", "3491.dat", "3613.dat" } do
			local connections = findConnections(library, ref) :: any
			t.expect(countByType(connections).TowballSocket).toBe(1)
		end
	end)

	t.test("shutter (791): bump primitives are hinge pins", function()
		local connections = findConnections(library, "791.dat") :: any
		t.expect(countByType(connections).HingePin).toBe(2)
	end)

	t.test("door 1x6x10 (671): hinge edge rod", function()
		local connections = findConnections(library, "671.dat") :: any
		t.expect(countByType(connections).HingePin).toBe(1)
		for _, connection in connections do
			if connection.type == "HingePin" then
				t.expect(connection.length).toBeCloseTo(213)
				t.expect(math.abs(connection.direction.Y)).toBeCloseTo(1)
			end
		end
	end)

	t.test("window frame (3853): bump tabs are hinge pins", function()
		local connections = findConnections(library, "3853.dat") :: any
		t.expect(countByType(connections).HingePin).toBe(4)
		for _, connection in connections do
			if connection.type == "HingePin" then
				t.expect(connection.length).toBeCloseTo(1)
			end
		end
	end)

	t.test("door 1x3x5 (2657): bump pins at both ends", function()
		local connections = findConnections(library, "2657.dat") :: any
		t.expect(countByType(connections).HingePin).toBe(2)
		for _, connection in connections do
			if connection.type == "HingePin" then
				t.expect(connection.length).toBeCloseTo(1.25)
			end
		end
	end)

	t.test("cupboard (2656): four corner hinge holes", function()
		local connections = findConnections(library, "2656.dat") :: any
		t.expect(countByType(connections).HingeSocket).toBe(4)
	end)

	t.test("door frame 1x6x6 (42205): hinge holes both top corners", function()
		local connections = findConnections(library, "42205.dat") :: any
		local sockets = {}
		for _, connection in connections do
			if connection.type == "HingeSocket" then
				table.insert(sockets, connection)
			end
		end
		t.expect(#sockets).toBe(2)
		for _, socket in sockets do
			t.expect(socket.length).toBeCloseTo(4)
			t.expect(socket.oneSided).toBe(true)
		end
	end)

	t.test("shutter (3856): hook recesses are hinge sockets", function()
		local connections = findConnections(library, "3856.dat") :: any
		t.expect(countByType(connections).HingeSocket).toBe(2)
	end)

	t.test("door 1x4x6 (3644) + frame (30179): rod and corner bores", function()
		local door = findConnections(library, "3644.dat") :: any
		t.expect(countByType(door).HingePin).toBe(1)
		local frame = findConnections(library, "30179.dat") :: any
		t.expect(countByType(frame).HingeSocket).toBe(4)
		for _, connection in frame do
			if connection.type == "HingeSocket" then
				t.expect(connection.length).toBeCloseTo(136)
			end
		end
	end)

	t.test("cupboard 2x6x7 (2042/2043): hinge stacks and pin line", function()
		local cupboard = findConnections(library, "2042.dat") :: any
		t.expect(countByType(cupboard).HingeSocket).toBe(2)
		local door = findConnections(library, "2043.dat") :: any
		local foundPinLine = false
		for _, connection in door do
			if connection.type == "HingePin" and math.abs(connection.length - 52) < 0.01 then
				foundPinLine = true
			end
		end
		t.expect(foundPinLine).toBe(true)
	end)

	t.test("newer door 1x4x6 (60623) + frame (60596)", function()
		local door = findConnections(library, "60623.dat") :: any
		t.expect(countByType(door).HingePin).toBe(1)
		local frame = findConnections(library, "60596.dat") :: any
		t.expect(countByType(frame).HingeSocket).toBe(2)
	end)

	t.test("door 2x4x5 (4131) + frame (4130): rod and bores", function()
		local door = findConnections(library, "4131.dat") :: any
		t.expect(countByType(door).HingePin).toBe(1)
		local frame = findConnections(library, "4130.dat") :: any
		t.expect(countByType(frame).HingeSocket).toBe(2)
	end)

	t.test("door 2x6x7 (4072) + frame (4071): rod and corner rails", function()
		local door = findConnections(library, "4072.dat") :: any
		t.expect(countByType(door).HingePin).toBe(1)
		local frame = findConnections(library, "4071.dat") :: any
		t.expect(countByType(frame).HingeSocket).toBe(2)
	end)

	t.test("finger hinge plates (4275a/4276a): finger rows detected", function()
		local three = findConnections(library, "4275a.dat") :: any
		t.expect(countByType(three).HingeFinger).toBe(1)
		local two = findConnections(library, "4276a.dat") :: any
		t.expect(countByType(two).HingeFinger).toBe(1)
	end)

	t.test("click hinges (30364/30365/44301/44302): finger and fork", function()
		local singleBrick = findConnections(library, "30364.dat") :: any
		t.expect(countByType(singleBrick).ClickFinger).toBe(1)
		local dualBrick = findConnections(library, "30365.dat") :: any
		t.expect(countByType(dualBrick).ClickFork).toBe(1)
		local singlePlate = findConnections(library, "44301.dat") :: any
		t.expect(countByType(singlePlate).ClickFinger).toBe(1)
		local dualPlate = findConnections(library, "44302.dat") :: any
		t.expect(countByType(dualPlate).ClickFork).toBe(1)
	end)

	t.test("arm pieces (412/3612): arm finger rows detected", function()
		local rotated = findConnections(library, "412.dat") :: any
		t.expect(countByType(rotated).ArmFinger).toBe(2)
		local aligned = findConnections(library, "3612.dat") :: any
		t.expect(countByType(aligned).ArmFinger).toBe(2)
	end)

	t.test("tyre and rim (3641/4624): size-keyed seat pair", function()
		local tyre = findConnections(library, "3641.dat") :: any
		local tyreBores = {}
		for _, connection in tyre do
			if connection.type == "TyreBore" then
				table.insert(tyreBores, connection)
			end
		end
		t.expect(#tyreBores).toBe(1)
		t.expect(tyreBores[1].radius).toBeCloseTo(10)
		t.expect(math.abs(tyreBores[1].direction.Z)).toBeCloseTo(1)

		local rim = findConnections(library, "4624.dat") :: any
		local rimSeats = {}
		for _, connection in rim do
			if connection.type == "RimSeat" then
				table.insert(rimSeats, connection)
			end
		end
		t.expect(#rimSeats).toBe(1)
		t.expect(rimSeats[1].radius).toBeCloseTo(10)
	end)

	t.test("alias tyre (=Tyre 50945): description gate strips the prefix", function()
		local connections = findConnections(library, "50945.dat") :: any
		local bores = {}
		for _, connection in connections do
			if connection.type == "TyreBore" then
				table.insert(bores, connection)
			end
		end
		t.expect(#bores).toBe(1)
		t.expect(bores[1].radius).toBeCloseTo(11 * 2.5 / 2)
	end)

	t.test("rim+tyre combo part (11208c01): no seat connectors", function()
		local connections = findConnections(library, "11208c01.dat") :: any
		local counts = countByType(connections)
		t.expect(counts.RimSeat or 0).toBe(0)
		t.expect(counts.TyreBore or 0).toBe(0)
	end)

	t.test("magnets (2959bc01/2607bc01): pole faces on both ends", function()
		local casing = findConnections(library, "2959bc01.dat") :: any
		t.expect(countByType(casing).Magnet).toBe(2)
		local holder = findConnections(library, "2607bc01.dat") :: any
		t.expect(countByType(holder).Magnet).toBe(2)
	end)

	t.test("door frame (670): hinge sockets on both sides", function()
		local connections = findConnections(library, "670.dat") :: any
		t.expect(countByType(connections).HingeSocket).toBe(2)
		for _, connection in connections do
			if connection.type == "HingeSocket" then
				t.expect(connection.length).toBeCloseTo(213)
			end
		end
	end)

	t.test("stud groups (stug) resolve to individual studs", function()
		-- 3811.dat is a 32x32 baseplate variant... too heavy; use 3832
		-- (plate 2x10) which uses stud groups in newer library versions.
		-- If the part doesn't use stug this still validates counts.
		local connections = findConnections(library, "3832.dat") :: any
		t.expect(connections).toBeTruthy()
		t.expect(countByType(connections).Stud).toBe(20)
	end)
end
