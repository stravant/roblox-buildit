--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local compositeParts = require(script.Parent.compositeParts)

return function(t: TestTypes.TestContext)
	t.test("hinge halves resolve to their assembly", function()
		t.expect(compositeParts.resolve("2429.dat")).toBe("73983.dat")
		t.expect(compositeParts.resolve("2430.dat")).toBe("73983.dat")
		t.expect(compositeParts.resolve("2429c01.dat")).toBe("73983.dat")
		t.expect(compositeParts.resolve("73983.dat")).toBe("73983.dat")
		t.expect(compositeParts.resolve("3001.dat")).toBe("3001.dat")
	end)

	t.test("assembly has a curated hinge joint", function()
		local composite = compositeParts.get("73983.dat")
		t.expect(composite).toBeTruthy()
		t.expect((composite :: any).joints[1].type).toBe("Hinge")
		t.expect(compositeParts.get("3001.dat")).toBeFalsy()
	end)

	t.test("minifig torso+arms+hands is a four-joint composite", function()
		t.expect(compositeParts.resolve("973.dat")).toBe("973c01.dat")
		t.expect(compositeParts.resolve("3818.dat")).toBe("973c01.dat")
		t.expect(compositeParts.resolve("982.dat")).toBe("973c01.dat")
		local composite = compositeParts.get("973c01.dat") :: any
		t.expect(composite).toBeTruthy()
		t.expect(#composite.joints).toBe(4)
		-- Hands stay standalone-importable (used alone as hooks/grips).
		t.expect(compositeParts.resolve("3820.dat")).toBe("3820.dat")
	end)

	t.test("2855 turntable is a virtual assembly", function()
		t.expect(compositeParts.resolve("2855.dat")).toBe("virtual:2855.dat")
		t.expect(compositeParts.resolve("2856.dat")).toBe("virtual:2855.dat")
		local composite = compositeParts.get("virtual:2855.dat") :: any
		t.expect(composite).toBeTruthy()
		t.expect(#composite.segments).toBe(2)
		t.expect(composite.partNumber).toBe("2855c")
	end)

	t.test("minifig legs are a two-joint composite", function()
		t.expect(compositeParts.resolve("970.dat")).toBe("3815c01.dat")
		t.expect(compositeParts.resolve("3816.dat")).toBe("3815c01.dat")
		local composite = compositeParts.get("3815c01.dat") :: any
		t.expect(composite).toBeTruthy()
		t.expect(#composite.joints).toBe(2)
		t.expect(composite.joints[1].segments).toEqual({ 1, 2 })
		t.expect(composite.joints[2].segments).toEqual({ 1, 3 })
	end)

	t.test("hinge and turntable families resolve to their assemblies", function()
		t.expect(compositeParts.resolve("3937.dat")).toBe("3937c01.dat")
		t.expect(compositeParts.resolve("3938.dat")).toBe("3937c01.dat")
		t.expect(compositeParts.resolve("652.dat")).toBe("652c01.dat")
		t.expect(compositeParts.resolve("654.dat")).toBe("652c01.dat")
		t.expect(compositeParts.resolve("3679.dat")).toBe("3680c01.dat")
		t.expect(compositeParts.resolve("3680c02.dat")).toBe("3680c01.dat")
		t.expect(compositeParts.resolve("3404.dat")).toBe("3403c01.dat")
		t.expect(compositeParts.get("652c01.dat")).toBeTruthy()
		t.expect(compositeParts.get("3680c01.dat")).toBeTruthy()
		t.expect(compositeParts.get("3403c01.dat")).toBeTruthy()
	end)
end
