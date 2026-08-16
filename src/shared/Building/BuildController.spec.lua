--!strict

-- BuildController is interactive (mouse-driven, per workspace policy no UI
-- testing beyond smoke) — this just catches syntax/require errors.

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local BuildController = require(script.Parent.BuildController)

return function(t: TestTypes.TestContext)
	t.test("module loads", function()
		t.expect(type(BuildController.start)).toBe("function")
	end)
end
