--!strict
--!native

-- Parses the text of a single LDraw file (.dat/.ldr) into a ParsedFile.
--
-- Handled line types:
--   0 - comments and metas (description, Name:, !LDRAW_ORG, BFC statements)
--   1 - subfile reference with affine transform
--   2 - edge line (marks a SHARP edge)
--   3 - triangle
--   4 - quad
--   5 - conditional line (marks a SMOOTH edge; control points dropped)
--
-- BFC handling: CERTIFY/NOCERTIFY set `certified`. Winding statements
-- (CCW/CW, including in the CERTIFY line) are consumed at parse time by
-- normalizing all stored triangles/quads to CCW order, so downstream code
-- never needs to track winding. INVERTNEXT is recorded on the following
-- subfile reference.

local Types = require(script.Parent.Types)

local function normalizeFileName(name: string): string
	return (name:lower():gsub("\\", "/"))
end

local function parseLDrawFile(content: string): Types.ParsedFile
	local result: Types.ParsedFile = {
		description = nil,
		name = nil,
		fileType = nil,
		certified = nil,
		subfiles = {},
		triangles = {},
		quads = {},
		lines = {},
		condLines = {},
		parseErrorCount = 0,
	}

	-- Winding of subsequently parsed faces. Only meaningful while certified;
	-- files without BFC info get emitted as-is and flattened double-sided.
	local mWindingCCW = true
	local mPendingInvert = false
	local mSawFirstComment = false

	for line in content:gmatch("[^\r\n]+") do
		local tokens = {}
		for token in line:gmatch("%S+") do
			table.insert(tokens, token)
		end
		local lineType = tokens[1]
		if lineType == nil then
			continue
		end

		if lineType == "0" then
			local keyword = tokens[2]
			if keyword == "BFC" then
				for i = 3, #tokens do
					local word = tokens[i]
					if word == "CERTIFY" then
						result.certified = true
					elseif word == "NOCERTIFY" then
						result.certified = false
					elseif word == "CCW" then
						mWindingCCW = true
					elseif word == "CW" then
						mWindingCCW = false
					elseif word == "INVERTNEXT" then
						mPendingInvert = true
					end
				end
			elseif keyword == "Name:" then
				result.name = normalizeFileName(line:match("^%s*0%s+Name:%s*(.-)%s*$") or "")
			elseif keyword == "!LDRAW_ORG" or keyword == "LDRAW_ORG" then
				result.fileType = tokens[3]
			elseif not mSawFirstComment and keyword ~= nil and keyword:sub(1, 1) ~= "!" then
				result.description = line:match("^%s*0%s+(.-)%s*$")
			end
			if keyword ~= nil then
				mSawFirstComment = true
			end
		elseif lineType == "1" then
			-- 1 <color> x y z a b c d e f g h i <file>
			local numbers = table.create(13)
			local ok = true
			for i = 2, 14 do
				local value = tonumber(tokens[i])
				if value == nil then
					ok = false
					break
				end
				numbers[i - 1] = value
			end
			local fileName = tokens[15]
			if ok and fileName ~= nil then
				-- Filenames may contain spaces: join remaining tokens.
				for i = 16, #tokens do
					fileName ..= " " .. tokens[i]
				end
				table.insert(result.subfiles, {
					colorCode = numbers[1],
					transform = CFrame.new(
						numbers[2], numbers[3], numbers[4], -- x y z
						numbers[5], numbers[6], numbers[7], -- a b c
						numbers[8], numbers[9], numbers[10], -- d e f
						numbers[11], numbers[12], numbers[13] -- g h i
					),
					fileName = normalizeFileName(fileName),
					invert = mPendingInvert,
				})
			else
				result.parseErrorCount += 1
			end
			mPendingInvert = false
		elseif lineType == "2" or lineType == "3" or lineType == "4" or lineType == "5" then
			local vertexCount = if lineType == "5" then 4 else tonumber(lineType) :: number
			local numbers = table.create(1 + vertexCount * 3)
			local ok = true
			for i = 2, 2 + vertexCount * 3 do
				local value = tonumber(tokens[i])
				if value == nil then
					ok = false
					break
				end
				numbers[i - 1] = value
			end
			if not ok then
				result.parseErrorCount += 1
				continue
			end
			local colorCode = numbers[1]
			local a = Vector3.new(numbers[2], numbers[3], numbers[4])
			local b = Vector3.new(numbers[5], numbers[6], numbers[7])
			if lineType == "2" then
				table.insert(result.lines, { colorCode = colorCode, a = a, b = b })
			elseif lineType == "5" then
				-- Only the edge endpoints matter; the two control points
				-- (used for view-dependent rendering) are dropped.
				table.insert(result.condLines, { colorCode = colorCode, a = a, b = b })
			else
				local c = Vector3.new(numbers[8], numbers[9], numbers[10])
				if lineType == "3" then
					if mWindingCCW then
						table.insert(result.triangles, { colorCode = colorCode, a = a, b = b, c = c })
					else
						table.insert(result.triangles, { colorCode = colorCode, a = a, b = c, c = b })
					end
				else
					local d = Vector3.new(numbers[11], numbers[12], numbers[13])
					if mWindingCCW then
						table.insert(result.quads, { colorCode = colorCode, a = a, b = b, c = c, d = d })
					else
						table.insert(result.quads, { colorCode = colorCode, a = a, b = d, c = c, d = b })
					end
				end
			end
		end
		-- Line type 5 (optional lines) and anything unknown: ignored.
	end

	return result
end

return parseLDrawFile
