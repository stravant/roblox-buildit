--!strict

-- The build test tool. Drag parts out of the palette into the world, or
-- pick up already-placed parts and move them; while dragging, all
-- connectors light up (studs green, sockets blue) and the mated pairs of
-- the current snap highlight yellow.
--
-- Controls:
--   Hold LMB on a palette entry OR on a placed part, drag, release to
--   place. R yaws the dragged part 90 degrees; T tilts it 90 degrees
--   toward the camera (about the nearest cardinal axis at press time,
--   accumulating per press). Esc or RMB cancels (a picked-up part
--   returns to where it was).
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
-- Spatial query bounds: only connectors near the ghost are tested and
-- shown (a large imported set makes global scans O(n) per frame).
local kSnapQueryPadding = 6
local kMaxNearbyParts = 256
local kMaxNearbyConnectors = 400
-- RMB cancels only on a CLICK: an RMB drag is a camera orbit and must
-- not cancel the part drag.
local kRightClickCancelMaxMovement = 5
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
	-- Accumulated T-key tilts (each press adds a 90-degree tip toward the
	-- camera about the cardinal axis captured at press time).
	tiltRotation: CFrame,
	-- Rotation the R/T-key steps compose onto (identity for palette drags,
	-- the part's own rotation for picked-up parts).
	baseRotation: CFrame,
	-- Set when dragging an already-placed part: it is unparented for the
	-- duration of the drag and restored on place/cancel.
	existingPart: BasePart?,
	existingParent: Instance?,
	originalCFrame: CFrame?,
	ghostConnectors: { getConnectors.Connector },
	ghostMarkers: { Marker },
	-- Pooled adornments reassigned each frame to the nearby connectors.
	markerPool: { Marker },
	markerFolder: Folder,
	overlapParams: OverlapParams,
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
	-- RMB press position while dragging (click-vs-orbit discrimination).
	local mRightMouseDownAt: Vector2? = nil

	-- In Edit mode (plugin), each drag is one undo recording spanning from
	-- pickup to place: committing on place makes the whole move/placement
	-- a single Ctrl+Z step, and canceling rolls back so aborted drags
	-- leave no trace in the undo stack.
	local mRecording: string? = nil
	local mRecordingLabel = "BuildIt"

	local function beginRecording(label: string)
		if pluginRef == nil then
			return
		end
		mRecordingLabel = label
		mRecording = ChangeHistoryService:TryBeginRecording(label)
	end

	local function finishRecording(commit: boolean)
		if pluginRef == nil then
			return
		end
		if mRecording ~= nil then
			ChangeHistoryService:FinishRecording(
				mRecording,
				if commit
					then Enum.FinishRecordingOperation.Commit
					else Enum.FinishRecordingOperation.Cancel
			)
			mRecording = nil
		elseif commit then
			-- Recording failed to start (e.g. another recording active):
			-- still mark an undo waypoint for the committed change.
			ChangeHistoryService:SetWaypoint(mRecordingLabel)
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

	-- Part-local connectors don't change while dragging: cache per part,
	-- built lazily for parts that come near the ghost. Cleared per drag so
	-- edits between drags are picked up and parts can be garbage collected.
	local mConnectorCache: { [BasePart]: { getConnectors.Connector } } = {}

	local function getCachedConnectors(part: BasePart): { getConnectors.Connector }
		local cached = mConnectorCache[part]
		if cached == nil then
			cached = getConnectors(part)
			mConnectorCache[part] = cached
		end
		return cached
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
		table.clear(mConnectorCache)
		state.markerFolder:Destroy()
		state.ghost:Destroy()
		if canceled then
			if state.existingPart ~= nil then
				-- Put a picked-up part back where it was.
				(state.existingPart :: BasePart).CFrame = state.originalCFrame :: CFrame;
				(state.existingPart :: BasePart).Parent = state.existingParent
			end
			finishRecording(false)
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

		local rotation = CFrame.Angles(0, state.rotationIndex * math.pi / 2, 0)
			* state.tiltRotation
			* state.baseRotation
		-- Rest the rotated bounding box on the hit point.
		local size = state.ghost.Size
		local halfHeight = 0.5 * (
			math.abs(rotation.XVector.Y) * size.X
			+ math.abs(rotation.YVector.Y) * size.Y
			+ math.abs(rotation.ZVector.Y) * size.Z
		)
		local baseCFrame = rotation + hitPoint + Vector3.new(0, halfHeight, 0)

		-- Spatial query: only connectors near the ghost participate in
		-- snapping and get markers.
		state.overlapParams.FilterDescendantsInstances = filterList
		local queryRadius = state.ghost.Size.Magnitude / 2 + kSnapQueryPadding
		local nearbyParts = workspace:GetPartBoundsInRadius(baseCFrame.Position, queryRadius, state.overlapParams)

		local worldConnectors: { WorldConnector } = {}
		local localPositions: { Vector3 } = {}
		for _, part in nearbyParts do
			if #worldConnectors >= kMaxNearbyConnectors then
				break
			end
			for _, connector in getCachedConnectors(part) do
				if #worldConnectors >= kMaxNearbyConnectors then
					break
				end
				table.insert(worldConnectors, {
					kind = connector.kind,
					position = part.CFrame:PointToWorldSpace(connector.position),
					direction = part.CFrame:VectorToWorldSpace(connector.direction),
					length = connector.length,
					oneSided = connector.oneSided,
					part = part,
					attachment = connector.attachment,
				})
				table.insert(localPositions, connector.position)
			end
		end

		local snap = findSnapPlacement(
			baseCFrame,
			state.ghostConnectors,
			worldConnectors,
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

		-- Assign the marker pool to this frame's nearby connectors; hide
		-- any leftover pooled adornments.
		for index, connector in worldConnectors do
			local marker = state.markerPool[index]
			if marker == nil then
				marker = makeMarker(connector.part :: BasePart, localPositions[index], connector.kind, state.markerFolder)
				state.markerPool[index] = marker
			else
				marker.kind = connector.kind
				marker.adornment.Adornee = connector.part
				marker.adornment.CFrame = CFrame.new(localPositions[index])
			end
			setMarkerMatched(marker, false)
		end
		for index = #worldConnectors + 1, #state.markerPool do
			state.markerPool[index].adornment.Adornee = nil
		end

		for _, marker in state.ghostMarkers do
			setMarkerMatched(marker, false)
		end
		if snap ~= nil then
			for _, pair in snap.matchedPairs do
				setMarkerMatched(state.ghostMarkers[pair.dragIndex], true)
				local worldMarker = state.markerPool[pair.worldIndex]
				if worldMarker ~= nil then
					setMarkerMatched(worldMarker, true)
				end
			end
		end
	end

	local function placeGhost(state: DragState)
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
		endDrag(false)
		finishRecording(true)
	end

	local function beginDrag(source: BasePart, isExisting: boolean)
		endDrag(true)
		beginRecording(if isExisting then "BuildIt: Move part" else "BuildIt: Place part")

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

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.MaxParts = kMaxNearbyParts

		local state: DragState = {
			template = source,
			ghost = ghost,
			rotationIndex = 0,
			tiltRotation = CFrame.identity,
			baseRotation = baseRotation,
			existingPart = if isExisting then source else nil,
			existingParent = existingParent,
			originalCFrame = originalCFrame,
			ghostConnectors = ghostConnectors,
			ghostMarkers = ghostMarkers,
			markerPool = {},
			markerFolder = markerFolder,
			overlapParams = overlapParams,
			connections = {},
		}
		mDragState = state

		table.insert(state.connections, RunService.RenderStepped:Connect(function()
			updateGhost(state)
		end))

		table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.KeyCode == Enum.KeyCode.R then
				state.rotationIndex = (state.rotationIndex + 1) % 4
			elseif input.KeyCode == Enum.KeyCode.T then
				-- Tip the part toward the camera: rotate 90 degrees about
				-- the horizontal axis perpendicular to the camera's look
				-- direction snapped to the nearest cardinal.
				local look = workspace.CurrentCamera.CFrame.LookVector
				local cardinal: Vector3
				if math.abs(look.X) > math.abs(look.Z) then
					cardinal = Vector3.new(math.sign(look.X), 0, 0)
				else
					cardinal = Vector3.new(0, 0, math.sign(look.Z))
				end
				if cardinal.Magnitude < 0.5 then
					cardinal = Vector3.zAxis -- camera looking straight up/down
				end
				local axis = cardinal:Cross(Vector3.yAxis)
				state.tiltRotation = CFrame.fromAxisAngle(axis, math.pi / 2) * state.tiltRotation
			elseif
				input.KeyCode == Enum.KeyCode.Z
				and (
					UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				)
			then
				-- Ctrl+Z mid-drag: cancel the drag so Studio's undo applies
				-- to a clean state.
				endDrag(true)
			elseif input.KeyCode == Enum.KeyCode.Escape then
				endDrag(true)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Defer to release: an RMB DRAG is a camera orbit, only an
				-- RMB CLICK cancels.
				mRightMouseDownAt = UserInputService:GetMouseLocation()
			end
		end))

		table.insert(state.connections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				local downAt = mRightMouseDownAt
				mRightMouseDownAt = nil
				if
					downAt ~= nil
					and (UserInputService:GetMouseLocation() - downAt).Magnitude <= kRightClickCancelMaxMovement
				then
					endDrag(true)
				end
				return
			end
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
