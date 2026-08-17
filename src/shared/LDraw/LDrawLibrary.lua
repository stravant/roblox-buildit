--!strict

-- Resolution + caching layer over a FileProvider.
--
-- LDraw files reference each other by bare name ("4-4cyli.dat",
-- "s\3001s01.dat"). Per the LDraw spec the reference is resolved against the
-- P directory (primitives), then PARTS, then MODELS. The FileProvider is
-- handed library-relative paths like "p/4-4cyli.dat".

local Types = require(script.Parent.Types)
local parseLDrawFile = require(script.Parent.parseLDrawFile)

local kSearchPrefixes = { "p/", "parts/", "models/", "" }

local LDrawLibrary = {}
LDrawLibrary.__index = LDrawLibrary

export type LDrawLibrary = typeof(setmetatable(
	{} :: {
		mFileProvider: Types.FileProvider,
		mCache: { [string]: Types.ParsedFile | false },
	},
	LDrawLibrary
))

function LDrawLibrary.new(fileProvider: Types.FileProvider): LDrawLibrary
	return setmetatable({
		mFileProvider = fileProvider,
		mCache = {} :: { [string]: Types.ParsedFile | false },
	}, LDrawLibrary)
end

local function normalizeRef(ref: string): string
	return (ref:lower():gsub("\\", "/"))
end

-- Resolve a reference as it appears in a type-1 line (e.g. "3001.dat",
-- "s\3001s01.dat", "48\4-4cyli.dat"). Returns nil if not found.
function LDrawLibrary.getFile(self: LDrawLibrary, ref: string): Types.ParsedFile?
	local normalized = normalizeRef(ref)
	local cached = self.mCache[normalized]
	if cached ~= nil then
		return cached or nil
	end

	local content: string? = nil
	for _, prefix in kSearchPrefixes do
		content = self.mFileProvider(prefix .. normalized)
		if content ~= nil then
			break
		end
	end

	if content == nil then
		self.mCache[normalized] = false
		return nil
	end
	local parsed = parseLDrawFile(content)
	self.mCache[normalized] = parsed
	return parsed
end

-- Convenience: fetch a part by its part number ("3001" -> "3001.dat").
function LDrawLibrary.getPart(self: LDrawLibrary, partNumber: string): Types.ParsedFile?
	return self:getFile(partNumber .. ".dat")
end

return LDrawLibrary
