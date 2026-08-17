--!strict

-- Parses a model file (.mpd multi-part container or plain .ldr): splits
-- `0 FILE <name>` sections, resolves inter-section references, and
-- flattens the model into library part instances (part reference +
-- accumulated transform + resolved color). The first section is the main
-- model (OMR convention).

local Types = require(script.Parent.Types)
local parseLDrawFile = require(script.Parent.parseLDrawFile)

export type ModelInstance = {
	partRef: string, -- normalized library reference ("3666.dat")
	transform: CFrame, -- accumulated, LDraw space
	colorCode: number, -- resolved (16 only if never overridden)
}

export type LoadedModel = {
	name: string?,
	instances: { ModelInstance },
	sectionCount: number,
}

local kColorInherit = 16
local kMaxDepth = 64

local function normalizeName(name: string): string
	return (name:lower():gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function loadModel(content: string): LoadedModel
	-- Split into sections on "0 FILE <name>" lines (the FILE line itself
	-- is stripped so each section parses as a standalone file).
	local sections: { [string]: Types.ParsedFile } = {}
	local order: { string } = {}
	local currentName: string? = nil
	local currentLines: { string } = {}

	local function flush()
		if currentName ~= nil then
			sections[currentName :: string] = parseLDrawFile(table.concat(currentLines, "\n"))
			table.insert(order, currentName :: string)
		end
		currentLines = {}
	end

	for line in content:gmatch("[^\r\n]+") do
		local fileName = line:match("^%s*0%s+FILE%s+(.+)$")
		if fileName ~= nil then
			flush()
			currentName = normalizeName(fileName)
		elseif line:match("^%s*0%s+NOFILE%s*$") ~= nil then
			flush()
			currentName = nil
		else
			table.insert(currentLines, line)
		end
	end
	flush()

	-- A plain .ldr with no FILE sections is a single-section model.
	if #order == 0 then
		sections["main"] = parseLDrawFile(content)
		order = { "main" }
	end

	local instances: { ModelInstance } = {}

	local function recurse(section: Types.ParsedFile, transform: CFrame, colorCode: number, depth: number)
		if depth > kMaxDepth then
			error("loadModel: max section depth exceeded (reference cycle?)")
		end
		for _, ref in section.subfiles do
			local childColor = if ref.colorCode == kColorInherit then colorCode else ref.colorCode
			local childSection = sections[ref.fileName]
			if childSection ~= nil then
				recurse(childSection, transform * ref.transform, childColor, depth + 1)
			else
				table.insert(instances, {
					partRef = ref.fileName,
					transform = transform * ref.transform,
					colorCode = childColor,
				})
			end
		end
	end

	local mainSection = sections[order[1]]
	recurse(mainSection, CFrame.identity, kColorInherit, 1)

	return {
		name = mainSection.description,
		instances = instances,
		sectionCount = #order,
	}
end

return loadModel
