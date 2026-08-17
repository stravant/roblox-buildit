--!strict

-- BuildController/RotateController are interactive (mouse-driven, per
-- workspace policy no UI testing beyond smoke) — this just catches
-- syntax/require errors.

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local BuildController = require(script.Parent.BuildController)
local RotateController = require(script.Parent.RotateController)

return function(t: TestTypes.TestContext)
	t.test("module loads", function()
		t.expect(type(BuildController.start)).toBe("function")
		t.expect(type(RotateController.start)).toBe("function")
	end)
end
