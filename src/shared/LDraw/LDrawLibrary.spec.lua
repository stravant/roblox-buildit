--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.LDrawLibrary)

return function(t: TestTypes.TestContext)
	local function makeFakeProvider(files: { [string]: string }): ((path: string) -> string?, { count: number })
		local stats = { count = 0 }
		return function(path: string): string?
			stats.count += 1
			return files[path]
		end, stats
	end

	t.test("resolves references against p/ then parts/", function()
		local provider = makeFakeProvider({
			["p/stud.dat"] = "0 Stud Primitive",
			["parts/3001.dat"] = "0 Brick  2 x  4",
			-- Same name in both: p/ must win (LDraw search order).
			["p/clash.dat"] = "0 From P",
			["parts/clash.dat"] = "0 From Parts",
		})
		local library = LDrawLibrary.new(provider)

		local stud = library:getFile("stud.dat")
		t.expect(stud).toBeTruthy()
		t.expect((stud :: any).description).toBe("Stud Primitive")

		local brick = library:getFile("3001.dat")
		t.expect((brick :: any).description).toBe("Brick  2 x  4")

		local clash = library:getFile("clash.dat")
		t.expect((clash :: any).description).toBe("From P")
	end)

	t.test("normalizes case and backslashes in references", function()
		local provider = makeFakeProvider({
			["parts/s/3001s01.dat"] = "0 Subpart",
		})
		local library = LDrawLibrary.new(provider)
		local file = library:getFile("S\\3001S01.DAT")
		t.expect(file).toBeTruthy()
		t.expect((file :: any).description).toBe("Subpart")
	end)

	t.test("caches parsed files and misses", function()
		local provider, stats = makeFakeProvider({
			["p/stud.dat"] = "0 Stud",
		})
		local library = LDrawLibrary.new(provider)

		local first = library:getFile("stud.dat")
		local countAfterFirst = stats.count
		local second = library:getFile("stud.dat")
		t.expect(second).toBe(first)
		t.expect(stats.count).toBe(countAfterFirst)

		-- Misses are cached too (no repeated provider probing).
		t.expect(library:getFile("nope.dat")).toBeFalsy()
		local countAfterMiss = stats.count
		t.expect(library:getFile("nope.dat")).toBeFalsy()
		t.expect(stats.count).toBe(countAfterMiss)
	end)

	t.test("getPart appends .dat", function()
		local provider = makeFakeProvider({
			["parts/3001.dat"] = "0 Brick  2 x  4",
		})
		local library = LDrawLibrary.new(provider)
		t.expect((library:getPart("3001") :: any).description).toBe("Brick  2 x  4")
	end)

	t.test("loads real library files through the test file server", function()
		local library = LDrawLibrary.new(t.readFile)
		local brick = library:getFile("3001.dat")
		t.expect(brick).toBeTruthy()
		t.expect((brick :: any).description).toBe("Brick  2 x  4")
		t.expect((brick :: any).fileType).toBe("Part")
		t.expect(#(brick :: any).subfiles).toBe(1)

		-- Subpart reference resolves through parts/s/.
		local subpart = library:getFile((brick :: any).subfiles[1].fileName)
		t.expect(subpart).toBeTruthy()
		t.expect((subpart :: any).fileType).toBe("Subpart")
	end)
end
