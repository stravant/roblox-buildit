--!strict

-- Imports a composite assembly (see compositeParts.lua): a Model with one
-- annotated MeshPart per rigid segment, posed per the LDraw Shortcut, plus
-- the curated articulation:
--   - Model attributes: PartNumber, LDrawFile, JointType
--   - each segment: its normal connector annotations, JointSegment index,
--     and a "JointPivot" Attachment at the joint (UpVector = articulation
--     axis)
-- Drag tooling treats the Model as a single unit; the future joint graph
-- rotates segments about their shared JointPivot.
--
-- No undo recording here: the caller owns the undo waypoint.

local LDrawFolder = script.Parent.Parent.shared.LDraw
local LDrawLibrary = require(LDrawFolder.LDrawLibrary)
local compositeParts = require(LDrawFolder.compositeParts)
local RobloxConvert = require(LDrawFolder.RobloxConvert)
local importPart = require(script.Parent.importPart)

local function cleanDescription(description: string?): string?
	if description == nil then
		return nil
	end
	local cleaned = (description:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
	return if #cleaned > 0 then cleaned else nil
end

local function importComposite(
	library: LDrawLibrary.LDrawLibrary,
	assemblyRef: string,
	parent: Instance
): (Model?, string?)
	local composite = compositeParts.get(assemblyRef)
	if composite == nil then
		return nil, `Not a known composite: {assemblyRef}`
	end
	local assembly = library:getFile(assemblyRef)
	if assembly == nil then
		return nil, `Assembly file not found: {assemblyRef}`
	end

	local jointCFrames: { CFrame } = {}
	for _, joint in composite.joints do
		table.insert(
			jointCFrames,
			RobloxConvert.frameWithUp(RobloxConvert.position(joint.position), RobloxConvert.direction(joint.axis))
		)
	end

	local model = Instance.new("Model")
	local segmentIndex = 0
	for _, ref in assembly.subfiles do
		local segment, errorMessage = importPart(library, ref.fileName, model)
		if segment == nil then
			model:Destroy()
			return nil, `Segment {ref.fileName}: {errorMessage}`
		end
		segmentIndex += 1
		local meshCenter = segment:GetAttribute("MeshCenter")
		if typeof(meshCenter) ~= "Vector3" then
			meshCenter = Vector3.zero
		end
		segment.CFrame = RobloxConvert.placementCFrame(ref.transform) * CFrame.new(meshCenter :: Vector3)
		segment:SetAttribute("JointSegment", segmentIndex)

		for jointIndex, joint in composite.joints do
			if joint.segments ~= nil and table.find(joint.segments :: { number }, segmentIndex) == nil then
				continue
			end
			local pivot = Instance.new("Attachment")
			pivot.Name = if #composite.joints == 1 then "JointPivot" else `JointPivot{jointIndex}`
			pivot.CFrame = segment.CFrame:ToObjectSpace(jointCFrames[jointIndex])
			pivot:SetAttribute("JointType", joint.type)
			pivot:SetAttribute("JointIndex", jointIndex)
			pivot.Parent = segment
		end
	end
	if segmentIndex == 0 then
		model:Destroy()
		return nil, `{assemblyRef} has no segments`
	end

	local partNumber = (assemblyRef:gsub("%.dat$", ""))
	model.Name = cleanDescription(assembly.description) or partNumber
	model:SetAttribute("LDrawFile", assemblyRef)
	model:SetAttribute("PartNumber", partNumber)
	model:SetAttribute("JointType", composite.joints[1].type)
	model:SetAttribute("JointCount", #composite.joints)
	-- No PrimaryPart: the model pivot stays the bounding box center, so
	-- PivotTo-based tooling treats composites like plain parts.
	model.Parent = parent

	return model, nil
end

return importComposite
