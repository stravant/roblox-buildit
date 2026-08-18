--!strict

-- In-game set editor: the real build tool (palette, snapping, move
-- modes) recording every placement as an instruction step, with the
-- sequencer strip across the top to scrub/restructure the sequence.
--
-- Flow: placements insert a place step at the cursor (so you can scrub
-- back and insert mid-sequence). + BAG and + SUB-BUILD insert markers;
-- while a sub-build is open, placements record against its root on the
-- side platform. Picking the finished sub-build up (assembly move
-- mode) and dropping it on the main build records the attach step and
-- folds its parts into the main build. Moving an already-placed part
-- updates its step's pose; DELETE removes the step at the cursor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildController = require(script.Parent.BuildController)
local Sequencer = require(script.Parent.Sequencer)
local SetData = require(script.Parent.SetData)
local SetRig = require(script.Parent.SetRig)
local SetStore = require(script.Parent.SetStore)

export type StartOptions = {
	data: SetData.SetData,
	origin: CFrame,
	guiParent: Instance?,
	onExit: (() -> ())?,
}

export type Controller = {
	stop: () -> (),
}

local SetEditorController = {}

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

local function unitColor(unit: PVInstance): { number }?
	local color: { number }? = nil
	forEachPart(unit, function(part)
		if color == nil then
			color = SetData.packColor(part.Color)
		end
	end)
	return color
end

function SetEditorController.start(options: StartOptions): Controller
	local data = options.data
	local mCursor = #data.steps

	local screenGui: ScreenGui? = nil
	local guiParent: Instance
	if options.guiParent ~= nil then
		guiParent = options.guiParent :: Instance
	else
		local gui = Instance.new("ScreenGui")
		gui.Name = "BuildItSetEditor"
		gui.ResetOnSpawn = false
		gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
		screenGui = gui
		guiParent = gui
	end

	local templatesFolder = ReplicatedStorage:WaitForChild("PartLibrary")
	local rig = SetRig.create(options.origin)
	SetRig.buildTo(rig, data.steps, mCursor, templatesFolder)

	-- Sub-build pickup snapshot: primary unit's pose in sub-root space
	-- at pickup, so the attach pose can be derived from wherever the
	-- group lands (the root Model's own pivot does not follow member
	-- PivotTo moves).
	local mPickupStep: number? = nil
	local mPickupSubbuild: string? = nil
	local mPickupPoseInSub: CFrame? = nil

	local sequencer: Sequencer.Sequencer? = nil

	local function refreshUi()
		if sequencer ~= nil then
			local target = SetData.activeTarget(data.steps, mCursor)
			local bags = SetData.bagRanges(data.steps)
			;(sequencer :: Sequencer.Sequencer).refresh(data.steps, mCursor)
			;(sequencer :: Sequencer.Sequencer).setStatus(
				`step {mCursor}/{#data.steps} · bag {SetData.bagOfStep(data.steps, math.max(mCursor, 1)) or #bags} · target {target}`
			)
		end
	end

	local function rebuild()
		SetRig.buildTo(rig, data.steps, mCursor, templatesFolder)
		refreshUi()
	end

	local function insertStep(step: SetData.Step)
		table.insert(data.steps, mCursor + 1, step)
		mCursor += 1
	end

	-- The root that owns an instance, as a target string, or nil.
	local function targetOfInstance(instance: Instance): string?
		if instance:IsDescendantOf(rig.mainRoot) then
			return "main"
		end
		for id, root in rig.subbuildRoots do
			if instance:IsDescendantOf(root) then
				return id
			end
		end
		return nil
	end

	local controller = BuildController.start({
		guiParent = guiParent,
		placeParent = function()
			return SetRig.rootFor(rig, SetData.activeTarget(data.steps, mCursor))
		end,
		scanRoot = function()
			return rig.container
		end,
		onPicked = function(unit)
			mPickupStep = SetRig.stepOfInstance(rig, unit)
			mPickupSubbuild = targetOfInstance(unit)
			local sub = mPickupSubbuild
			if sub ~= nil and sub ~= "main" then
				local root = rig.subbuildRoots[sub :: string]
				if root ~= nil then
					mPickupPoseInSub = root:GetPivot():ToObjectSpace(unit:GetPivot())
					return
				end
			end
			mPickupPoseInSub = nil
		end,
		onPlaced = function(primary, group, isExisting)
			if not isExisting then
				-- New part from the palette: record a place step at the
				-- cursor against the active target.
				local target = SetData.activeTarget(data.steps, mCursor)
				local root = SetRig.rootFor(rig, target)
				local partNumber = primary:GetAttribute("PartNumber")
				if partNumber == nil then
					warn("[BuildIt SetEditor] placed unit has no PartNumber; not recorded")
					return
				end
				insertStep({
					kind = "place",
					target = target,
					partNumber = tostring(partNumber),
					color = unitColor(primary),
					cframe = SetData.packCFrame(root:GetPivot():ToObjectSpace(primary:GetPivot())),
				})
				rig.stepInstances[mCursor] = primary
				refreshUi()
				return
			end

			-- Existing unit(s) moved. Whole-open-sub-build move = attach.
			local openSub = SetData.activeTarget(data.steps, mCursor)
			if
				openSub ~= "main"
				and mPickupSubbuild == openSub
				and mPickupPoseInSub ~= nil
			then
				local root = rig.subbuildRoots[openSub]
				if root ~= nil then
					local moved: { [Instance]: boolean } = { [primary] = true }
					for _, unit in group do
						moved[unit] = true
					end
					local allMoved = true
					for _, child in root:GetChildren() do
						if (child:IsA("BasePart") or child:IsA("Model")) and not moved[child] then
							allMoved = false
							break
						end
					end
					if allMoved then
						local subPivot = primary:GetPivot() * (mPickupPoseInSub :: CFrame):Inverse()
						insertStep({
							kind = "attach",
							id = openSub,
							cframe = SetData.packCFrame(rig.mainRoot:GetPivot():ToObjectSpace(subPivot)),
						})
						-- Fold the sub-build into the main root physically.
						root:PivotTo(subPivot)
						for _, child in root:GetChildren() do
							child.Parent = rig.mainRoot
						end
						root:Destroy()
						rig.subbuildRoots[openSub] = nil
						local platform = rig.container:FindFirstChild(`SubbuildPlatform_{openSub}`)
						if platform ~= nil then
							platform:Destroy()
						end
						refreshUi()
						return
					end
				end
			end

			-- Plain move of placed part(s): update each unit's step pose.
			local units: { PVInstance } = { primary }
			for _, unit in group do
				table.insert(units, unit)
			end
			for _, unit in units do
				local stepIndex = SetRig.stepOfInstance(rig, unit)
				local target = targetOfInstance(unit)
				if stepIndex ~= nil and target ~= nil then
					local step = data.steps[stepIndex :: number]
					local root = SetRig.rootFor(rig, target :: string)
					step.cframe = SetData.packCFrame(root:GetPivot():ToObjectSpace(unit:GetPivot()))
					step.target = target
				end
			end
			refreshUi()
		end,
	})

	sequencer = Sequencer.create(guiParent, data.name, {
		onScrub = function(cursor)
			mCursor = math.clamp(cursor, 0, #data.steps)
			rebuild()
		end,
		onAddBag = function()
			insertStep({ kind = "bag" })
			refreshUi()
		end,
		onAddSubbuild = function()
			local id = SetData.nextSubbuildId(data.steps)
			insertStep({ kind = "subbuild", id = id })
			SetRig.ensureSubbuildRoot(rig, id)
			refreshUi()
		end,
		onDelete = function()
			if mCursor >= 1 then
				table.remove(data.steps, mCursor)
				mCursor -= 1
				rebuild()
			end
		end,
		onSave = function()
			SetStore.save(data)
			;(sequencer :: Sequencer.Sequencer).setStatus(`saved "{data.name}"`)
		end,
		onExit = function()
			SetStore.save(data)
			if options.onExit ~= nil then
				(options.onExit :: () -> ())()
			end
		end,
	})
	refreshUi()

	local function stop()
		controller.stop()
		if sequencer ~= nil then
			(sequencer :: Sequencer.Sequencer).destroy()
		end
		SetRig.destroy(rig)
		if screenGui ~= nil then
			(screenGui :: ScreenGui):Destroy()
		end
	end

	return { stop = stop }
end

return SetEditorController
