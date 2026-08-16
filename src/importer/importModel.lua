--!strict

-- Imports a whole model/set file (.mpd/.ldr, e.g. from the LDraw OMR):
-- ensures a PartLibrary template exists for every unique referenced part
-- (reusing already-imported templates by their LDrawFile attribute), then
-- assembles colored clones under a single workspace folder using the
-- model's transforms.
--
-- No undo recording here: the caller owns the undo waypoint.

local LDrawFolder = script.Parent.Parent.shared.LDraw
local LDrawLibrary = require(LDrawFolder.LDrawLibrary)
local LDrawColors = require(LDrawFolder.LDrawColors)
local loadModel = require(LDrawFolder.loadModel)
local RobloxConvert = require(LDrawFolder.RobloxConvert)
local importPart = require(script.Parent.importPart)

export type ImportModelResult = {
	folder: Folder,
	placedCount: number,
	instanceCount: number,
	uniquePartCount: number,
	importedTemplateCount: number,
	skippedRefs: { string },
}

local function importModel(
	library: LDrawLibrary.LDrawLibrary,
	readFile: (path: string) -> string?,
	modelPath: string,
	templatesFolder: Instance,
	setStatus: (text: string) -> ()
): (ImportModelResult?, string?)
	local content = readFile(modelPath)
	if content == nil then
		return nil, `Model file not found: {modelPath}`
	end
	local model = loadModel(content)
	if #model.instances == 0 then
		return nil, `{modelPath} contains no part references`
	end

	local colors: { [number]: any } = {}
	local ldconfig = readFile("LDConfig.ldr")
	if ldconfig ~= nil then
		colors = LDrawColors.parse(ldconfig)
	end

	local uniqueRefs: { [string]: boolean } = {}
	local uniqueList: { string } = {}
	for _, instance in model.instances do
		if not uniqueRefs[instance.partRef] then
			uniqueRefs[instance.partRef] = true
			table.insert(uniqueList, instance.partRef)
		end
	end
	table.sort(uniqueList)

	-- Reuse templates already in the PartLibrary.
	local templates: { [string]: MeshPart } = {}
	for _, child in templatesFolder:GetChildren() do
		local ref = child:GetAttribute("LDrawFile")
		if type(ref) == "string" and child:IsA("MeshPart") then
			templates[ref] = child
		end
	end

	local importedTemplateCount = 0
	local skippedRefs: { string } = {}
	for index, ref in uniqueList do
		if templates[ref] ~= nil then
			continue
		end
		setStatus(`Importing {ref} ({index}/{#uniqueList} unique parts)...`)
		local ok, part = pcall(importPart, library, ref, templatesFolder)
		if ok and part ~= nil then
			templates[ref] = part :: MeshPart
			importedTemplateCount += 1
		else
			table.insert(skippedRefs, ref)
		end
	end

	setStatus(`Assembling {#model.instances} parts...`)
	local folder = Instance.new("Folder")
	folder.Name = modelPath:match("([^/]+)%.[^.]+$") or modelPath
	local placedCount = 0
	for _, instance in model.instances do
		local template = templates[instance.partRef]
		if template == nil then
			continue
		end
		local clone = template:Clone()
		local meshCenter = clone:GetAttribute("MeshCenter")
		if typeof(meshCenter) ~= "Vector3" then
			meshCenter = Vector3.zero
		end
		clone.CFrame = RobloxConvert.placementCFrame(instance.transform)
			* CFrame.new(meshCenter :: Vector3)
		local colorDef = colors[instance.colorCode]
		if colorDef ~= nil then
			clone.Color = colorDef.color
			if colorDef.alpha ~= nil then
				clone.Transparency = 1 - colorDef.alpha / 255
			end
		end
		clone.Anchored = true
		clone.Parent = folder
		placedCount += 1
		if placedCount % 200 == 0 then
			setStatus(`Assembling... ({placedCount}/{#model.instances})`)
			task.wait()
		end
	end
	folder.Parent = workspace

	return {
		folder = folder,
		placedCount = placedCount,
		instanceCount = #model.instances,
		uniquePartCount = #uniqueList,
		importedTemplateCount = importedTemplateCount,
		skippedRefs = skippedRefs,
	}, nil
end

return importModel
