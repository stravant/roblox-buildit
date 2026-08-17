--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local loadModel = require(script.Parent.loadModel)

return function(t: TestTypes.TestContext)
	t.test("flattens mpd sections into part instances", function()
		local model = loadModel([[
0 FILE main.ldr
0 Test Model
1 1 0 0 40 1 0 0 0 1 0 0 0 1 sub.ldr
1 4 100 0 0 1 0 0 0 1 0 0 0 1 3001.dat
0 FILE sub.ldr
0 Submodel
1 16 20 0 0 1 0 0 0 1 0 0 0 1 3005.dat
1 2 0 8 0 1 0 0 0 1 0 0 0 1 3005.dat
]])
		t.expect(model.name).toBe("Test Model")
		t.expect(model.sectionCount).toBe(2)
		t.expect(#model.instances).toBe(3)

		-- Section refs compose transforms; color 16 inherits the ref color.
		local bySpot = {}
		for _, instance in model.instances do
			bySpot[`{instance.partRef}:{instance.transform.Position.X},{instance.transform.Position.Y},{instance.transform.Position.Z}`] =
				instance.colorCode
		end
		t.expect(bySpot["3005.dat:20,0,40"]).toBe(1)
		t.expect(bySpot["3005.dat:0,8,40"]).toBe(2)
		t.expect(bySpot["3001.dat:100,0,0"]).toBe(4)
	end)

	t.test("treats a plain ldr without FILE sections as one model", function()
		local model = loadModel([[
0 Plain Model
1 4 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat
]])
		t.expect(model.sectionCount).toBe(1)
		t.expect(#model.instances).toBe(1)
		t.expect(model.instances[1].partRef).toBe("3001.dat")
	end)

	t.test("loads the 8880 Super Car set", function()
		local content = t.readFile("sets/8880-1.mpd")
		t.expect(content).toBeTruthy()
		local model = loadModel(content :: string)
		t.expect(model.sectionCount).toBe(71)

		local unique = {}
		local uniqueCount = 0
		for _, instance in model.instances do
			if not unique[instance.partRef] then
				unique[instance.partRef] = true
				uniqueCount += 1
			end
		end
		t.log(`8880: {#model.instances} part instances, {uniqueCount} unique parts, {model.sectionCount} sections`)
		t.expect(#model.instances > 800).toBe(true)
		t.expect(uniqueCount > 50).toBe(true)
	end)
end
