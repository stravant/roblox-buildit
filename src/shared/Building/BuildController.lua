--!strict

-- The build test tool. Drag parts out of the palette into the world, or
-- pick up already-placed parts and move them; while dragging, all
-- connectors light up (studs green, sockets blue) and the mated pairs of
-- the current snap highlight yellow.
--
-- Controls:
--   Hold LMB on a palette entry OR on a placed part, drag, release to
--   place. R rotates the dragged part 90 degrees. Esc or RMB cancels
--   (a picked-up part returns to where it was).
--
-- ANY workspace part with connector attachments is a snap target and can
-- be picked up — including the copies the importer drops. New palette
-- placements go to workspace.Assembly in-game, or directly to workspace
-- in Edit mode; picked-up parts return to their original parent.
--
-- Runs in two contexts:
--   - In-game (StarterPlayerScripts): start() with no options builds its
--     own ScreenGui in PlayerGui.
--   - Studio Edit mode (importer plugin "Build" tool): start({guiParent =
--     dockWidget, plugin = plugin}) parents the palette to the widget,
--     skips character handling, and wraps placements in undo recordings.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local getConnectors = require(script.Parent.getConnectors)
local findSnapPlacement = require(script.Parent.findSnapPlacement)
local PartPalette = require(script.Parent.PartPalette)

local kMaxSnapDistance = 1.25
local kGridSize = 1
local kRaycastDistance = 500
local kGhostTransparency = 0.45
local kMarkerRadius = 0.13
local kMarkerRadiusMatched = 0.22
local kStudColor = Color3.fromRGB(90, 220, 90)
local kSocketColor = Color3.fromRGB(80, 170, 255)
-- Axial connectors (pegholes, axles, bars, clips...).
local kAxialColor = Color3.fromRGB(255, 140, 60)
local kMatchedColor = Color3.fromRGB(255, 220, 40)

local function baseMarkerColor(kind: string): Color3
	if kind == "Stud" then
		return kStudColor
	elseif kind == "Socket" then
		return kSocketColor
	else
		return kAxialColor
	end
end

type WorldConnector = findSnapPlacement.WorldConnector

type Marker = {
	adornment: SphereHandleAdornment,
	kind: string,
}

type DragState = {
	template: BasePart,
	ghost: BasePart,
	rotationIndex: number,
	-- Rotation the R-key steps compose onto (identity for palette drags,
	-- the part's own rotation for picked-up parts).
	baseRotation: CFrame,
	-- Set when dragging an already-placed part: it is unparented for the
	-- duration of the drag and restored on place/cancel.
	existingPart: BasePart?,
	existingParent: Instance?,
	originalCFrame: CFrame?,
	ghostConnectors: { getConnectors.Connector },
	worldConnectors: { WorldConnector },
	ghostMarkers: { Marker },
	worldMarkers: { Marker },
	markerFolder: Folder,
	connections: { RBXScriptConnection },
}

export type StartOptions = {
	guiParent: Instance?,
	plugin: Plugin?,
}

export type Controller = {
	stop: () -> (),
}

local BuildController = {}

function BuildController.start(options: StartOptions?): Controller
	local opts: StartOptions = options or {}
	local pluginRef = opts.plugin

	local mOwnScreenGui: ScreenGui? = nil
	local guiParent: Instance
	if opts.guiParent ~= nil then
		guiParent = opts.guiParent :: Instance
	else
		local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "BuildItTool"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = playerGui
		mOwnScreenGui = screenGui
		guiParent = screenGui
	end

	local templatesFolder = ReplicatedStorage:FindFirstChild("PartLibrary")
	if templatesFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "PartLibrary"
		folder.Parent = ReplicatedStorage
		templatesFolder = folder
	end

	-- In-game, new parts collect in workspace.Assembly; in Edit mode they
	-- go directly into workspace alongside imported copies.
	local function getPlacementParent(): Instance
		if pluginRef ~= nil then
			return workspace
		end
		local existing = workspace:FindFirstChild("Assembly")
		if existing ~= nil then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = "Assembly"
		folder.Parent = workspace
		return folder
	end

	local mDragState: DragState? = nil
	local mPalette: PartPalette.PartPalette? = nil

	-- In Edit mode (plugin), placements should be undoable steps.
	local function recordChange(label: string, fn: () -> ())
		if pluginRef == nil then
			fn()
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording(label)
		fn()
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint(label)
		end
	end

	local function makeMarker(
		adornee: BasePart,
		localPosition: Vector3,
		kind: string,
		parent: Instance
	): Marker
		local adornment = Instance.new("SphereHandleAdornment")
		adornment.Adornee = adornee
		adornment.CFrame = CFrame.new(localPosition)
		adornment.Radius = kMarkerRadius
		adornment.Color3 = baseMarkerColor(kind)
		adornment.Transparency = 0.25
		adornment.Parent = parent
		return { adornment = adornment, kind = kind }
	end

	local function setMarkerMatched(marker: Marker, matched: boolean)
		if matched then
			marker.adornment.Color3 = kMatchedColor
			marker.adornment.Radius = kMarkerRadiusMatched
			marker.adornment.Transparency = 0
		else
			marker.adornment.Color3 = baseMarkerColor(marker.kind)
			marker.adornment.Radius = kMarkerRadius
			marker.adornment.Transparency = 0.25
		end
	end

	local function collectWorldConnectors(markerFolder: Folder, ghost: BasePart?): ({ WorldConnector }, { Marker })
		local worldConnectors: { WorldConnector } = {}
		local markers: { Marker } = {}
		for _, part in workspace:GetDescendants() do
			if not part:IsA("BasePart") or part == ghost then
				continue
			end
			for _, connector in getConnectors(part) do
				table.insert(worldConnectors, {
					kind = connector.kind,
					position = part.CFrame:PointToWorldSpace(connector.position),
					direction = part.CFrame:VectorToWorldSpace(connector.direction),
					length = connector.length,
					part = part,
					attachment = connector.attachment,
				})
				table.insert(markers, makeMarker(part, connector.position, connector.kind, markerFolder))
			end
		end
		return worldConnectors, markers
	end

	local function endDrag(canceled: boolean)
		local state = mDragState
		if state == nil then
			return
		end
		mDragState = nil
		for _, connection in state.connections do
			connection:Disconnect()
		end
		state.markerFolder:Destroy()
		state.ghost:Destroy()
		if canceled and state.existingPart ~= nil then
			-- Put a picked-up part back where it was.
			(state.existingPart :: BasePart).CFrame = state.originalCFrame :: CFrame;
			(state.existingPart :: BasePart).Parent = state.existingParent
		end
	end

	local function mouseRay(): Ray
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		return camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y)
	end

	local function updateGhost(state: DragState)
		local ray = mouseRay()

		local filterList: { Instance } = { state.ghost }
		if pluginRef == nil then
			local character = (Players.LocalPlayer :: Player).Character
			if character ~= nil then
				table.insert(filterList, character)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filterList

		local hitPoint: Vector3
		local result = workspace:Raycast(ray.Origin, ray.Direction * kRaycastDistance, params)
		if result ~= nil then
			hitPoint = result.Position
		elseif ray.Direction.Y < -1e-4 then
			hitPoint = ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)
		else
			hitPoint = ray.Origin + ray.Direction * 40
		end

		local rotation = CFrame.Angles(0, state.rotationIndex * math.pi / 2, 0) * state.baseRotation
		local baseCFrame = rotation + hitPoint + Vector3.new(0, state.ghost.Size.Y / 2, 0)

		local snap = findSnapPlacement(
			baseCFrame,
			state.ghostConnectors,
			state.worldConnectors,
			kMaxSnapDistance
		)

		if snap ~= nil then
			state.ghost.CFrame = snap.cframe
		else
			local position = baseCFrame.Position
			state.ghost.CFrame = rotation + Vector3.new(
				math.round(position.X / kGridSize) * kGridSize,
				position.Y,
				math.round(position.Z / kGridSize) * kGridSize
			)
		end

		for _, marker in state.ghostMarkers do
			setMarkerMatched(marker, false)
		end
		for _, marker in state.worldMarkers do
			setMarkerMatched(marker, false)
		end
		if snap ~= nil then
			for _, pair in snap.matchedPairs do
				setMarkerMatched(state.ghostMarkers[pair.dragIndex], true)
				setMarkerMatched(state.worldMarkers[pair.worldIndex], true)
			end
		end
	end

	local function placeGhost(state: DragState)
		recordChange("BuildIt: Place part", function()
			if state.existingPart ~= nil then
				local placed = state.existingPart :: BasePart
				placed.CFrame = state.ghost.CFrame
				placed.Parent = state.existingParent
			else
				local placed = state.template:Clone()
				placed.Anchored = true
				placed.CFrame = state.ghost.CFrame
				placed.Parent = getPlacementParent()
			end
		end)
		endDrag(false)
	end

	local function beginDrag(source: BasePart, isExisting: boolean)
		endDrag(true)

		local ghost = source:Clone()
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.Transparency = kGhostTransparency
		ghost.Parent = workspace

		local baseRotation = CFrame.identity
		local existingParent: Instance? = nil
		local originalCFrame: CFrame? = nil
		if isExisting then
			baseRotation = source.CFrame.Rotation
			existingParent = source.Parent
			originalCFrame = source.CFrame
			-- Out of the world while dragging: not a snap target, not a
			-- raycast obstacle.
			source.Parent = nil
		end

		-- Marker adornments live under the camera: always renderable, never
		-- replicated or saved.
		local markerFolder = Instance.new("Folder")
		markerFolder.Name = "BuildItMarkers"
		markerFolder.Parent = workspace.CurrentCamera

		local ghostConnectors = getConnectors(ghost)
		local ghostMarkers: { Marker } = {}
		for _, connector in ghostConnectors do
			table.insert(ghostMarkers, makeMarker(ghost, connector.position, connector.kind, markerFolder))
		end
		local worldConnectors, worldMarkers = collectWorldConnectors(markerFolder, ghost)

		local state: DragState = {
			template = source,
			ghost = ghost,
			rotationIndex = 0,
			baseRotation = baseRotation,
			existingPart = if isExisting then source else nil,
			existingParent = existingParent,
			originalCFrame = originalCFrame,
			ghostConnectors = ghostConnectors,
			worldConnectors = worldConnectors,
			ghostMarkers = ghostMarkers,
			worldMarkers = worldMarkers,
			markerFolder = markerFolder,
			connections = {},
		}
		mDragState = state

		table.insert(state.connections, RunService.RenderStepped:Connect(function()
			updateGhost(state)
		end))

		table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.KeyCode == Enum.KeyCode.R then
				state.rotationIndex = (state.rotationIndex + 1) % 4
			elseif
				input.KeyCode == Enum.KeyCode.Escape
				or input.UserInputType == Enum.UserInputType.MouseButton2
			then
				endDrag(true)
			end
		end))

		table.insert(state.connections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			-- Releasing back over the palette cancels instead of placing.
			local mouse = UserInputService:GetMouseLocation()
			local inset = GuiService:GetGuiInset()
			local screenPosition = Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y)
			if mPalette ~= nil and (mPalette :: PartPalette.PartPalette).containsPoint(screenPosition) then
				endDrag(true)
			else
				placeGhost(state)
			end
		end))

		updateGhost(state)
	end

	-- Picking up placed parts: LMB down over any connector-annotated part.
	local mPickupConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if mDragState ~= nil then
			return
		end
		local ray = mouseRay()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filterList: { Instance } = {}
		if pluginRef == nil then
			local character = (Players.LocalPlayer :: Player).Character
			if character ~= nil then
				table.insert(filterList, character)
			end
		end
		params.FilterDescendantsInstances = filterList
		local result = workspace:Raycast(ray.Origin, ray.Direction * kRaycastDistance, params)
		if result ~= nil and #getConnectors(result.Instance) > 0 then
			beginDrag(result.Instance, true)
		end
	end)

	mPalette = PartPalette.create(guiParent, templatesFolder :: Folder, function(template: BasePart)
		beginDrag(template, false)
	end)

	local function stop()
		endDrag(true)
		mPickupConnection:Disconnect()
		if mPalette ~= nil then
			(mPalette :: PartPalette.PartPalette).destroy()
			mPalette = nil
		end
		if mOwnScreenGui ~= nil then
			(mOwnScreenGui :: ScreenGui):Destroy()
			mOwnScreenGui = nil
		end
	end

	return {
		stop = stop,
	}
end

return BuildController
