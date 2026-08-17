--!strict

-- Every part in the representative test set must yield at least one
-- connector (or resolve to a curated composite). Catches curation
-- regressions: a renamed override key or an over-eager suppression
-- pass silently turning a test-set part inert.

local TestTypes = require(script.Parent.Parent.TestTypes)
local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local findConnections = require(script.Parent.Parent.shared.LDraw.findConnections)
local deriveSockets = require(script.Parent.Parent.shared.LDraw.deriveSockets)
local compositeParts = require(script.Parent.Parent.shared.LDraw.compositeParts)
local kTestSet = require(script.Parent.testSet)

return function(t: TestTypes.TestContext)
	local library = LDrawLibrary.new(t.readFile)

	t.test("every test-set part yields connectors", function()
		local bare: { string } = {}
		for _, id in kTestSet do
			local ref = id .. ".dat"
			local resolved = compositeParts.resolve(ref)
			if compositeParts.get(resolved) ~= nil then
				continue -- composite: joints curated in compositeParts
			end
			-- No mesh: the boundary rule is skipped, which only ever
			-- KEEPS more connectors — fine for a non-empty check, and
			-- much faster than flattening 100+ parts.
			local connections = findConnections(library, ref)
			local sockets = deriveSockets(connections, nil)
			if #connections == 0 and #sockets == 0 then
				table.insert(bare, id)
			end
		end
		t.expect(table.concat(bare, ",")).toBe("")
	end)
end
