--!strict

local TestTypes = require(script.Parent.Parent.Parent.TestTypes)
local LDrawColors = require(script.Parent.LDrawColors)

return function(t: TestTypes.TestContext)
	t.test("parses !COLOUR definitions", function()
		local colors = LDrawColors.parse([[
0 LDraw.org Configuration File
0 !COLOUR Black CODE 0 VALUE #1B2A34 EDGE #808080
0 !COLOUR Trans_Clear CODE 47 VALUE #FCFCFC EDGE #C3C3C3 ALPHA 128
0 !COLOUR Chrome_Gold CODE 334 VALUE #DFC176 EDGE #B4A143 CHROME
]])
		local black = colors[0]
		t.expect(black).toBeTruthy()
		t.expect(black.name).toBe("Black")
		t.expect(black.color.R * 255).toBeCloseTo(0x1B, 0.5)
		t.expect(black.color.G * 255).toBeCloseTo(0x2A, 0.5)
		t.expect(black.color.B * 255).toBeCloseTo(0x34, 0.5)
		t.expect(black.alpha).toBe(nil)

		t.expect(colors[47].alpha).toBe(128)
		t.expect(colors[334].name).toBe("Chrome_Gold")
	end)

	t.test("parses the real LDConfig.ldr", function()
		local content = t.readFile("LDConfig.ldr")
		t.expect(content).toBeTruthy()
		local colors = LDrawColors.parse(content :: string)

		local count = 0
		for _ in colors do
			count += 1
		end
		t.log(`LDConfig.ldr: {count} colors`)
		t.expect(count > 100).toBe(true)

		local red = colors[4]
		t.expect(red).toBeTruthy()
		t.expect(red.name).toBe("Red")
		t.expect(red.color.R * 255).toBeCloseTo(0xB4, 0.5)
		t.expect(red.color.G * 255).toBeCloseTo(0x00, 0.5)
		t.expect(red.color.B * 255).toBeCloseTo(0x00, 0.5)
	end)
end
