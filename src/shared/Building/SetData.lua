--!strict

-- Instruction-set data model for in-game set building. A set is a name
-- plus a FLAT ORDERED list of steps:
--
--   bag      - start a new bag (a pile of parts drawn down to empty
--              before the next bag begins)
--   subbuild - open a sub-build: an isolated target assembled on its
--              own platform, later attached to the main build
--   place    - place one part (partNumber + color + pose relative to
--              its target root: "main" or a subbuild id)
--   attach   - attach a completed sub-build: the sub-build root's pose
--              in main-build space; its parts become main-build parts
--
-- Pure data + serialization; materialization lives in SetRig, editing
-- UI in SetEditorController, guided following in SetPlayerController.

local HttpService = game:GetService("HttpService")

export type StepKind = "bag" | "subbuild" | "place" | "attach"

export type Step = {
	kind: StepKind,
	-- place:
	target: string?, -- "main" or a subbuild id
	partNumber: string?,
	color: { number }?, -- {r, g, b} 0-255
	-- place (relative to target root) / attach (sub root in main space):
	cframe: { number }?, -- 12 components (position + rotation rows)
	-- subbuild / attach:
	id: string?,
}

export type SetData = {
	name: string,
	steps: { Step },
}

local SetData = {}

local kFormatVersion = 1

function SetData.new(name: string): SetData
	return { name = name, steps = {} }
end

function SetData.packCFrame(cframe: CFrame): { number }
	local components = { cframe:GetComponents() }
	for index, value in components do
		-- Trim float noise so serialized sets diff cleanly.
		components[index] = math.round(value * 10000) / 10000
	end
	return components
end

function SetData.unpackCFrame(packed: { number }): CFrame
	return CFrame.new(table.unpack(packed))
end

function SetData.packColor(color: Color3): { number }
	return {
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255),
	}
end

function SetData.unpackColor(packed: { number }): Color3
	return Color3.fromRGB(packed[1], packed[2], packed[3])
end

function SetData.serialize(data: SetData): string
	return HttpService:JSONEncode({
		version = kFormatVersion,
		name = data.name,
		steps = data.steps,
	})
end

function SetData.deserialize(text: string): SetData?
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	if type(decoded.name) ~= "string" or type(decoded.steps) ~= "table" then
		return nil
	end
	return { name = decoded.name, steps = decoded.steps }
end

-- The target new place steps record against after `cursor` steps: the
-- most recent subbuild that has not been attached yet, else "main".
function SetData.activeTarget(steps: { Step }, cursor: number): string
	local open: string? = nil
	for index = 1, math.min(cursor, #steps) do
		local step = steps[index]
		if step.kind == "subbuild" then
			open = step.id
		elseif step.kind == "attach" and step.id == open then
			open = nil
		end
	end
	return open or "main"
end

-- A fresh subbuild id not used by any existing step.
function SetData.nextSubbuildId(steps: { Step }): string
	local used: { [string]: boolean } = {}
	for _, step in steps do
		if step.id ~= nil then
			used[step.id :: string] = true
		end
	end
	local index = 1
	while used[`sub{index}`] do
		index += 1
	end
	return `sub{index}`
end

-- Bags partition the step list: a bag runs from its marker (or the
-- start of the list) up to just before the next marker. Returns
-- {first, last} step-index ranges, in order. A leading run of steps
-- before any bag marker forms an implicit first bag.
function SetData.bagRanges(steps: { Step }): { { first: number, last: number } }
	local ranges: { { first: number, last: number } } = {}
	local first: number? = if #steps > 0 and steps[1].kind ~= "bag" then 1 else nil
	for index, step in steps do
		if step.kind == "bag" then
			if first ~= nil then
				table.insert(ranges, { first = first :: number, last = index - 1 })
			end
			first = index
		end
	end
	if first ~= nil then
		table.insert(ranges, { first = first :: number, last = #steps })
	end
	return ranges
end

-- The bag (index into bagRanges) containing the given step, or nil.
function SetData.bagOfStep(steps: { Step }, stepIndex: number): number?
	for bagIndex, range in SetData.bagRanges(steps) do
		if stepIndex >= range.first and stepIndex <= range.last then
			return bagIndex
		end
	end
	return nil
end

-- Counts of parts needed by the place steps in a step range, keyed by
-- partNumber. Used for pile spawning and progress display.
function SetData.partCounts(steps: { Step }, first: number, last: number): { [string]: number }
	local counts: { [string]: number } = {}
	for index = first, last do
		local step = steps[index]
		if step ~= nil and step.kind == "place" then
			local key = step.partNumber :: string
			counts[key] = (counts[key] or 0) + 1
		end
	end
	return counts
end

return SetData
