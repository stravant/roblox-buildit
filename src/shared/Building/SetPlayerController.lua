--!strict

-- Set follower: guided building from an instruction set. The current
-- bag's parts spawn as a physical pile on a tray beside the build;
-- drag a part from the pile toward the build (or the sub-build's side
-- platform) and when it is near a pending step's pose that matches the
-- part, it snaps in exactly; release to commit. A translucent accent
-- hint shows the next step's placement. Bags advance when drained;
-- finished sub-builds drag onto the main build as a whole (the attach
-- step).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FlatUI = require(script.Parent.FlatUI)
local SetData = require(script.Parent.SetData)
local SetGuide = require(script.Parent.SetGuide)
local SetRig = require(script.Parent.SetRig)

local kTrayOffset = CFrame.new(0, 0, 16)
local kTrayColumns = 5
local kTraySpacing = 3
local kDragPlaneHeight = 3
local kHintTransparency = 0.6

export type StartOptions = {
	data: SetData.SetData,
	origin: CFrame,
	guiParent: Instance?,
	onExit: (() -> ())?,
}

export type Controller = {
	stop: () -> (),
}

type PileEntry = {
	unit: PVInstance,
	partNumber: string,
	color: { number }?,
	home: CFrame,
}

local SetPlayerController = {}

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

function SetPlayerController.start(options: StartOptions): Controller
	local data = options.data
	local steps = data.steps
	local templatesFolder = ReplicatedStorage:WaitForChild("PartLibrary")

	local screenGui: ScreenGui? = nil
	local guiParent: Instance
	if options.guiParent ~= nil then
		guiParent = options.guiParent :: Instance
	else
		local gui = Instance.new("ScreenGui")
		gui.Name = "BuildItSetPlayer"
		gui.ResetOnSpawn = false
		gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
		screenGui = gui
		guiParent = gui
	end

	local rig = SetRig.create(options.origin)
	local trayOrigin = options.origin * kTrayOffset

	local panel = FlatUI.frame(guiParent, UDim2.new(0, 260, 0, 74), UDim2.new(0, 8, 0, 8), FlatUI.kPanel)
	local titleLabel = FlatUI.label(panel, data.name, UDim2.new(1, -12, 0, 22), UDim2.new(0, 8, 0, 2))
	titleLabel.Font = FlatUI.kFontBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	local progressLabel = FlatUI.label(panel, "", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 24))
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	local hintLabel = FlatUI.label(panel, "", UDim2.new(1, -12, 0, 20), UDim2.new(0, 8, 0, 44))
	hintLabel.TextColor3 = FlatUI.kTextDim
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	FlatUI.button(panel, "X", UDim2.new(0, 22, 0, 22), UDim2.new(1, -24, 0, 2), function()
		if options.onExit ~= nil then
			(options.onExit :: () -> ())()
		end
	end)

	local bags = SetData.bagRanges(steps)
	local mBagIndex = 0
	local mDone: { [number]: boolean } = {}
	local mPile: { PileEntry } = {}
	local mHints: { PVInstance } = {}
	local mComplete = false

	local mConnections: { RBXScriptConnection } = {}

	-- Dragging state.
	local mDragEntry: PileEntry? = nil
	local mDragAttach: string? = nil -- subbuild id being attached
	local mDragAttachOffset: CFrame? = nil
	local mDragTarget: number? = nil -- step index currently snapped to

	local function currentBagRange(): (number, number)
		local range = bags[mBagIndex]
		return range.first, range.last
	end

	-- The current INSTRUCTION STEP within the bag: multiple parts per
	-- step, guided together; the next step's hints appear only once
	-- this one is complete. (No step markers = the whole bag.)
	local function currentRunRange(): (number, number, number, number)
		local first, last = currentBagRange()
		local runFirst, runLast, ordinal, count = SetGuide.currentRun(steps, mDone, first, last)
		if runFirst == nil then
			return first, last, 1, 1
		end
		return runFirst :: number, runLast :: number, ordinal :: number, count :: number
	end

	local function targetWorldPose(index: number): CFrame
		local step = steps[index]
		if step.kind == "attach" then
			return rig.mainRoot:GetPivot() * SetData.unpackCFrame(step.cframe :: { number })
		end
		local root = SetRig.rootFor(rig, step.target :: string)
		return root:GetPivot() * SetData.unpackCFrame(step.cframe :: { number })
	end

	local function clearHint()
		for _, hint in mHints do
			hint:Destroy()
		end
		table.clear(mHints)
	end

	local function partName(partNumber: string): string
		local template = SetRig.findTemplate(templatesFolder, partNumber)
		return if template ~= nil then (template :: PVInstance).Name else partNumber
	end

	local function refreshHint()
		clearHint()
		if mComplete or mBagIndex == 0 then
			return
		end
		local runFirst, runLast = currentRunRange()
		local pending = SetGuide.pendingPlaces(steps, mDone, runFirst, runLast)
		if #pending == 0 then
			local nextIndex = SetGuide.nextStep(steps, mDone, runFirst, runLast)
			if nextIndex ~= nil and steps[nextIndex :: number].kind == "attach" then
				hintLabel.Text = "Attach the sub-build to the build"
			else
				hintLabel.Text = ""
			end
			return
		end
		-- Hint ghosts for EVERY pending part of the current step.
		local names: { [string]: boolean } = {}
		for _, index in pending do
			local step = steps[index]
			names[partName(step.partNumber :: string)] = true
			local template = SetRig.findTemplate(templatesFolder, step.partNumber :: string)
			if template == nil then
				continue
			end
			local hint = (template :: PVInstance):Clone()
			forEachPart(hint, function(part)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Color = FlatUI.kAccent
				part.Transparency = kHintTransparency
			end)
			hint:PivotTo(targetWorldPose(index))
			hint.Parent = rig.container
			table.insert(mHints, hint)
		end
		local nameList = {}
		for name in names do
			table.insert(nameList, name)
		end
		table.sort(nameList)
		hintLabel.Text = `Place: {table.concat(nameList, ", ")}`
	end

	local function refreshProgress()
		if mComplete then
			progressLabel.Text = "Set complete!"
			hintLabel.Text = ""
			return
		end
		local runFirst, runLast, ordinal, runCount = currentRunRange()
		local total = 0
		local doneCount = 0
		for index = runFirst, runLast do
			local step = steps[index]
			if step.kind == "place" or step.kind == "attach" then
				total += 1
				if mDone[index] then
					doneCount += 1
				end
			end
		end
		progressLabel.Text =
			`Bag {mBagIndex}/{#bags} · Step {ordinal}/{runCount} · {doneCount}/{total} parts`
	end

	local function spawnPile()
		for _, entry in mPile do
			entry.unit:Destroy()
		end
		table.clear(mPile)
		local first, last = currentBagRange()
		local slot = 0
		for index = first, last do
			local step = steps[index]
			if step.kind == "subbuild" then
				-- Sub-build platforms appear as soon as their bag opens.
				SetRig.ensureSubbuildRoot(rig, step.id :: string)
			end
			if step.kind ~= "place" or mDone[index] then
				continue
			end
			local template = SetRig.findTemplate(templatesFolder, step.partNumber :: string)
			if template == nil then
				warn(`[BuildIt Set] no template for part {step.partNumber}; skipping step {index}`)
				mDone[index] = true
				continue
			end
			local clone = (template :: PVInstance):Clone()
			forEachPart(clone, function(part)
				part.Anchored = true
				if step.color ~= nil then
					part.Color = SetData.unpackColor(step.color :: { number })
				end
			end)
			local column = slot % kTrayColumns
			local rowIndex = math.floor(slot / kTrayColumns)
			local home = trayOrigin
				* CFrame.new(
					(column - (kTrayColumns - 1) / 2) * kTraySpacing,
					1,
					rowIndex * kTraySpacing
				)
				* CFrame.Angles(0, math.random() * 2 * math.pi, 0)
			clone:PivotTo(home)
			clone.Parent = rig.container
			table.insert(mPile, {
				unit = clone,
				partNumber = step.partNumber :: string,
				color = step.color,
				home = home,
			})
			slot += 1
		end
	end

	local function advanceBag()
		mBagIndex += 1
		if mBagIndex > #bags then
			mComplete = true
			clearHint()
			refreshProgress()
			return
		end
		spawnPile()
		refreshHint()
		refreshProgress()
	end

	local function afterCommit()
		local first, last = currentBagRange()
		if SetGuide.rangeComplete(steps, mDone, first, last) then
			advanceBag()
		else
			refreshHint()
			refreshProgress()
		end
	end

	local function pileEntryOf(instance: Instance): PileEntry?
		for _, entry in mPile do
			if entry.unit == instance or instance:IsDescendantOf(entry.unit) then
				return entry
			end
		end
		return nil
	end

	-- The open subbuild whose attach step is the current next step, if
	-- the given instance belongs to it.
	local function attachableSubbuildOf(instance: Instance): (string?, number?)
		if mComplete or mBagIndex == 0 then
			return nil, nil
		end
		local runFirst, runLast = currentRunRange()
		local nextIndex = SetGuide.nextStep(steps, mDone, runFirst, runLast)
		if nextIndex == nil or steps[nextIndex :: number].kind ~= "attach" then
			return nil, nil
		end
		local id = steps[nextIndex :: number].id :: string
		local root = rig.subbuildRoots[id]
		if root ~= nil and instance:IsDescendantOf(root) then
			return id, nextIndex
		end
		return nil, nil
	end

	local function mouseRay(): Ray
		local camera = workspace.CurrentCamera
		local location = UserInputService:GetMouseLocation()
		return camera:ViewportPointToRay(location.X, location.Y)
	end

	local function planePoint(): Vector3?
		local ray = mouseRay()
		local planeY = options.origin.Position.Y + kDragPlaneHeight
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local t = (planeY - ray.Origin.Y) / ray.Direction.Y
		if t < 0 then
			return nil
		end
		return ray.Origin + ray.Direction * t
	end

	local function updateDrag()
		local point = planePoint()
		if point == nil then
			return
		end
		if mDragAttach ~= nil then
			local id = mDragAttach :: string
			local root = rig.subbuildRoots[id]
			local runFirst, runLast = currentRunRange()
			local attachIndex = SetGuide.nextStep(steps, mDone, runFirst, runLast)
			if root == nil or attachIndex == nil then
				return
			end
			local target = targetWorldPose(attachIndex :: number)
			local held = (point :: Vector3) + (mDragAttachOffset :: CFrame).Position
			if (target.Position - held).Magnitude <= SetGuide.kSnapRadius then
				mDragTarget = attachIndex
				root:PivotTo(target)
			else
				mDragTarget = nil
				root:PivotTo(CFrame.new(held) * root:GetPivot().Rotation)
			end
			return
		end
		local entry = mDragEntry
		if entry == nil then
			return
		end
		local runFirst, runLast = currentRunRange()
		local candidates = SetGuide.matchingSteps(
			steps,
			mDone,
			runFirst,
			runLast,
			(entry :: PileEntry).partNumber,
			(entry :: PileEntry).color
		)
		local picked = SetGuide.pickTarget(candidates, function(index)
			return targetWorldPose(index).Position
		end, point :: Vector3)
		mDragTarget = picked
		if picked ~= nil then
			(entry :: PileEntry).unit:PivotTo(targetWorldPose(picked :: number))
		else
			local rotation = (entry :: PileEntry).unit:GetPivot().Rotation
			;(entry :: PileEntry).unit:PivotTo(CFrame.new(point :: Vector3) * rotation)
		end
	end

	local function endDrag(commit: boolean)
		local entry = mDragEntry
		local attachId = mDragAttach
		local target = mDragTarget
		mDragEntry = nil
		mDragAttach = nil
		mDragAttachOffset = nil
		mDragTarget = nil

		if attachId ~= nil then
			local root = rig.subbuildRoots[attachId :: string]
			if root == nil then
				return
			end
			if commit and target ~= nil then
				mDone[target :: number] = true
				SetRig.applyAttach(rig, steps[target :: number])
				afterCommit()
			end
			-- Non-commit: the sub-build stays where it was dropped and
			-- can simply be picked up again.
			return
		end

		if entry == nil then
			return
		end
		if commit and target ~= nil then
			mDone[target :: number] = true
			local step = steps[target :: number]
			local root = SetRig.rootFor(rig, step.target :: string)
			;(entry :: PileEntry).unit:PivotTo(targetWorldPose(target :: number))
			;(entry :: PileEntry).unit.Parent = root
			rig.stepInstances[target :: number] = (entry :: PileEntry).unit
			for index, pileEntry in mPile do
				if pileEntry == entry then
					table.remove(mPile, index)
					break
				end
			end
			afterCommit()
		else
			(entry :: PileEntry).unit:PivotTo((entry :: PileEntry).home)
		end
	end

	table.insert(mConnections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if mComplete or mBagIndex == 0 then
			return
		end
		local ray = mouseRay()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { rig.container }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		if hit == nil then
			return
		end
		local entry = pileEntryOf(hit.Instance)
		if entry ~= nil then
			mDragEntry = entry
			return
		end
		local attachId = attachableSubbuildOf(hit.Instance)
		if attachId ~= nil then
			local root = rig.subbuildRoots[attachId :: string]
			local point = planePoint()
			if root ~= nil and point ~= nil then
				mDragAttach = attachId
				mDragAttachOffset = CFrame.new(root:GetPivot().Position - (point :: Vector3))
			end
		end
	end))

	table.insert(mConnections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			endDrag(true)
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.KeyCode == Enum.KeyCode.Escape
		then
			endDrag(false)
		end
	end))

	table.insert(mConnections, RunService.RenderStepped:Connect(function()
		if mDragEntry ~= nil or mDragAttach ~= nil then
			updateDrag()
		end
	end))

	advanceBag()

	local function stop()
		for _, connection in mConnections do
			connection:Disconnect()
		end
		table.clear(mConnections)
		clearHint()
		SetRig.destroy(rig)
		panel:Destroy()
		if screenGui ~= nil then
			(screenGui :: ScreenGui):Destroy()
		end
	end

	return { stop = stop }
end

return SetPlayerController
