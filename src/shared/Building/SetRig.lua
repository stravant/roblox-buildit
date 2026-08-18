--!strict

-- Materializes SetData steps into the world: a container folder holding
-- the main build root Model, one root Model per open sub-build (each on
-- its own platform slab beside the main build), and the placed part
-- clones. The editor scrubs by rebuilding to a cursor; the follower
-- applies steps one at a time as the player completes them.

local SetData = require(script.Parent.SetData)

local kContainerName = "BuildItSetRig"
-- Sub-build platforms line up beside the main build.
local kSubbuildOffset = CFrame.new(14, 0, 0)
local kSubbuildSpacing = CFrame.new(0, 0, 10)
local kPlatformSize = Vector3.new(8, 1, 8)
local kPlatformColor = Color3.fromRGB(70, 70, 74)

export type Rig = {
	container: Folder,
	origin: CFrame,
	mainRoot: Model,
	subbuildRoots: { [string]: Model },
	-- place/attach step index -> the instance it produced (for place,
	-- the part; for attach, the sub-build's former root parts stay
	-- tracked by their own place steps).
	stepInstances: { [number]: PVInstance },
}

local SetRig = {}

local function forEachPart(unit: Instance, fn: (BasePart) -> ())
	if unit:IsA("BasePart") then
		fn(unit)
	end
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("BasePart") then
			fn(descendant)
		end
	end
end

local function makeRoot(name: string, pivot: CFrame, parent: Instance): Model
	local root = Instance.new("Model")
	root.Name = name
	root.WorldPivot = pivot
	root.Parent = parent
	return root
end

local function makePlatform(name: string, cframe: CFrame, parent: Instance)
	local platform = Instance.new("Part")
	platform.Name = name
	platform.Size = kPlatformSize
	platform.Color = kPlatformColor
	platform.Material = Enum.Material.SmoothPlastic
	platform.Anchored = true
	platform.CFrame = cframe
	platform.Parent = parent
end

function SetRig.create(origin: CFrame, parent: Instance?): Rig
	local container = Instance.new("Folder")
	container.Name = kContainerName
	container.Parent = parent or workspace
	return {
		container = container,
		origin = origin,
		mainRoot = makeRoot("Main", origin, container),
		subbuildRoots = {},
		stepInstances = {},
	}
end

-- The world pivot a sub-build root spawns at: beside the main build,
-- successive platforms stepping away.
local function subbuildPivot(rig: Rig, ordinal: number): CFrame
	return rig.origin * kSubbuildOffset * CFrame.new(0, 0, (ordinal - 1) * kSubbuildSpacing.Z)
end

function SetRig.ensureSubbuildRoot(rig: Rig, id: string): Model
	local existing = rig.subbuildRoots[id]
	if existing ~= nil then
		return existing
	end
	local count = 0
	for _ in rig.subbuildRoots do
		count += 1
	end
	local pivot = subbuildPivot(rig, count + 1)
	local root = makeRoot(`Subbuild_{id}`, pivot, rig.container)
	makePlatform(`SubbuildPlatform_{id}`, pivot * CFrame.new(0, -kPlatformSize.Y / 2, 0), rig.container)
	rig.subbuildRoots[id] = root
	return root
end

function SetRig.rootFor(rig: Rig, target: string): Model
	if target == "main" then
		return rig.mainRoot
	end
	return SetRig.ensureSubbuildRoot(rig, target)
end

function SetRig.findTemplate(templatesFolder: Instance, partNumber: string): PVInstance?
	for _, child in templatesFolder:GetChildren() do
		if
			(child:IsA("BasePart") or child:IsA("Model"))
			and child:GetAttribute("PartNumber") == partNumber
		then
			return child
		end
	end
	return nil
end

-- Instantiate one place step's part (shared by editor scrub and the
-- follower's commit): clone the template, tint, pose, parent.
function SetRig.instantiatePlace(
	rig: Rig,
	step: SetData.Step,
	stepIndex: number,
	templatesFolder: Instance
): PVInstance?
	local template = SetRig.findTemplate(templatesFolder, step.partNumber :: string)
	if template == nil then
		warn(`[BuildIt Set] no PartLibrary template for part {step.partNumber}`)
		return nil
	end
	local root = SetRig.rootFor(rig, step.target :: string)
	local clone = (template :: PVInstance):Clone()
	forEachPart(clone, function(part)
		part.Anchored = true
		if step.color ~= nil then
			part.Color = SetData.unpackColor(step.color :: { number })
		end
	end)
	clone:PivotTo(root:GetPivot() * SetData.unpackCFrame(step.cframe :: { number }))
	clone.Parent = root
	rig.stepInstances[stepIndex] = clone
	return clone
end

-- Apply an attach step: move the whole sub-build rigidly to its
-- recorded pose on the main build and fold its parts into the main
-- root. The sub-build root and platform disappear.
function SetRig.applyAttach(rig: Rig, step: SetData.Step)
	local id = step.id :: string
	local root = rig.subbuildRoots[id]
	if root == nil then
		return
	end
	root:PivotTo(rig.mainRoot:GetPivot() * SetData.unpackCFrame(step.cframe :: { number }))
	for _, child in root:GetChildren() do
		child.Parent = rig.mainRoot
	end
	root:Destroy()
	rig.subbuildRoots[id] = nil
	local platform = rig.container:FindFirstChild(`SubbuildPlatform_{id}`)
	if platform ~= nil then
		platform:Destroy()
	end
end

function SetRig.applyStep(rig: Rig, steps: { SetData.Step }, index: number, templatesFolder: Instance)
	local step = steps[index]
	if step.kind == "place" then
		SetRig.instantiatePlace(rig, step, index, templatesFolder)
	elseif step.kind == "subbuild" then
		SetRig.ensureSubbuildRoot(rig, step.id :: string)
	elseif step.kind == "attach" then
		SetRig.applyAttach(rig, step)
	end
	-- bag: no world effect
end

-- Rebuild the whole rig state to steps[1..cursor] from scratch (editor
-- scrubbing: sets are small, correctness over cleverness).
function SetRig.buildTo(rig: Rig, steps: { SetData.Step }, cursor: number, templatesFolder: Instance)
	for _, child in rig.container:GetChildren() do
		child:Destroy()
	end
	table.clear(rig.subbuildRoots)
	table.clear(rig.stepInstances)
	rig.mainRoot = makeRoot("Main", rig.origin, rig.container)
	for index = 1, math.min(cursor, #steps) do
		SetRig.applyStep(rig, steps, index, templatesFolder)
	end
end

-- The step index that produced a given instance (or an ancestor of
-- it), for editor pickups of placed parts.
function SetRig.stepOfInstance(rig: Rig, instance: Instance): number?
	for index, placed in rig.stepInstances do
		if placed == instance or instance:IsDescendantOf(placed) then
			return index
		end
	end
	return nil
end

function SetRig.destroy(rig: Rig)
	rig.container:Destroy()
	table.clear(rig.subbuildRoots)
	table.clear(rig.stepInstances)
end

return SetRig
