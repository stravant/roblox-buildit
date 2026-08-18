--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local gearSatellites = require(script.Parent.gearSatellites)

local function part(name: string): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	return instance
end

return function(t: TestTypes.TestContext)
	t.test("carries off-axis neighbors, leaves coaxial bearings", function()
		-- Gear group spins about Z through the origin. The beam holds it
		-- via a coaxial hinge at the origin; a pin sits in an off-center
		-- hole 1 stud out; a clip hangs on that pin (transitive).
		local gear = part("gear")
		local beam = part("beam")
		local pin = part("pin")
		local clip = part("clip")
		local function rootOf(instance: BasePart): BasePart
			return instance
		end
		local axis = Vector3.new(0, 0, 1)
		local pairs = {
			{ part0 = gear, part1 = beam, position = Vector3.zero, axis = axis, kind = "Cylindrical" },
			{ part0 = pin, part1 = gear, position = Vector3.new(1, 0, 0), axis = axis, kind = "Hinge" },
			{ part0 = clip, part1 = pin, position = Vector3.new(1, 0, -0.5), axis = Vector3.new(1, 0, 0), kind = "Hinge" },
		}
		local carried = gearSatellites(pairs, rootOf, gear, Vector3.zero, axis, {})
		t.expect(carried[gear]).toBe(true)
		t.expect(carried[beam]).toBe(nil)
		t.expect(carried[pin]).toBe(true)
		t.expect(carried[clip]).toBe(true)

		-- Excluded roots never get carried, and don't propagate.
		local carriedExcluding = gearSatellites(pairs, rootOf, gear, Vector3.zero, axis, { [pin] = true })
		t.expect(carriedExcluding[pin]).toBe(nil)
		t.expect(carriedExcluding[clip]).toBe(nil)

		gear:Destroy()
		beam:Destroy()
		pin:Destroy()
		clip:Destroy()
	end)
end
