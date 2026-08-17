--!strict

-- Parses LDConfig.ldr !COLOUR definitions:
--   0 !COLOUR <name> CODE <c> VALUE #rrggbb EDGE #rrggbb [ALPHA <a>] [...]

local Types = require(script.Parent.Types)

local LDrawColors = {}

local function parseHexColor(token: string?): Color3?
	if token == nil or token:sub(1, 1) ~= "#" then
		return nil
	end
	local value = tonumber(token:sub(2), 16)
	if value == nil then
		return nil
	end
	return Color3.fromRGB(
		bit32.extract(value, 16, 8),
		bit32.extract(value, 8, 8),
		bit32.extract(value, 0, 8)
	)
end

function LDrawColors.parse(content: string): { [number]: Types.ColorDef }
	local result: { [number]: Types.ColorDef } = {}
	for line in content:gmatch("[^\r\n]+") do
		local tokens = {}
		for token in line:gmatch("%S+") do
			table.insert(tokens, token)
		end
		if tokens[1] ~= "0" or tokens[2] ~= "!COLOUR" or tokens[3] == nil then
			continue
		end

		local name = tokens[3]
		local code: number? = nil
		local color: Color3? = nil
		local edge: Color3? = nil
		local alpha: number? = nil
		local i = 4
		while i <= #tokens do
			local keyword = tokens[i]
			if keyword == "CODE" then
				code = tonumber(tokens[i + 1])
				i += 2
			elseif keyword == "VALUE" then
				color = parseHexColor(tokens[i + 1])
				i += 2
			elseif keyword == "EDGE" then
				-- EDGE may be a hex color or a reference to another code
				-- (older configs); only hex is supported.
				edge = parseHexColor(tokens[i + 1])
				i += 2
			elseif keyword == "ALPHA" or keyword == "LUMINANCE" then
				if keyword == "ALPHA" then
					alpha = tonumber(tokens[i + 1])
				end
				i += 2
			else
				-- Flag keywords: CHROME, PEARLESCENT, RUBBER, MATTE_METALLIC,
				-- METAL, MATERIAL <...> — MATERIAL consumes the rest.
				if keyword == "MATERIAL" then
					break
				end
				i += 1
			end
		end

		if code ~= nil and color ~= nil then
			result[code] = {
				code = code,
				name = name,
				color = color,
				edge = edge,
				alpha = alpha,
			}
		end
	end
	return result
end

return LDrawColors
