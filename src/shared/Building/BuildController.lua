--!strict

-- The build test tool. Drag parts out of the palette into the world, or
-- pick up already-placed parts and move them; while dragging, all
-- connectors light up (studs green, sockets blue) and the mated pairs of
-- the current snap highlight yellow.
--
-- Controls:
--   Hold LMB on a palette entry OR on a placed part, drag, release to
--   place. R yaws the dragged part 90 degrees about world Y; T tips it
--   90 degrees toward the camera (nearest cardinal axis at press time).
--   Both are WORLD-space steps premultiplied onto the accumulated
--   orientation, so they compose intuitively in any order. Esc or RMB
--   cancels (a picked-up part returns to where it was).
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
local AssemblyGraph = require(script.Parent.AssemblyGraph)
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
-- Ball joints (towballs and their sockets).
local kBallColor = Color3.fromRGB(220, 90, 220)
local kMatchedColor = Color3.fromRGB(255, 220, 40)

local function baseMarkerColor(kind: string): Color3
	if kind == "Stud" then
		return kStudColor
	elseif kind == "Socket" then
		return kSocketColor
	elseif kind == "Towball" or kind == "TowballSocket" then
		return kBallColor
	else
		return kAxialColor
	end
end

type WorldConnector = findSnapPlacement.WorldConnector

type Marker = {
	adornment: SphereHandleAdornment,
	kind: string,
}

type HiddenProperties = {
	transparency: number,
	canQuery: boolean,
	canCollide: boolean,
	canTouch: boolean,
}

-- A draggable unit is a BasePart or a composite Model of rigid segments;
-- its connectors are expressed in the unit's PIVOT space so the solver
-- works identically for both.
type UnitConnector = {
	kind: string,
	position: Vector3, -- unit pivot space
	direction: Vector3, -- unit pivot space
	length: number?,
	oneSided: boolean?,
	secondary: Vector3?, -- unit pivot space (axle cross orientation)
	part: BasePart, -- owning segment (for markers)
	partLocalPosition: Vector3, -- in the segment's space (for markers)
}

type DragState = {
	template: PVInstance,
	ghost: PVInstance,
	-- Accumulated R/T rotations. Every keypress PREMULTIPLIES a world-space
	-- 90-degree step (yaw for R, tip-toward-camera for T), so both keys act
	-- in world space regardless of the order they were pressed in.
	orientation: CFrame,
	-- Rotation the steps compose onto (identity for palette drags, the
	-- unit's own rotation for picked-up parts).
	baseRotation: CFrame,
	-- Where the unit was grabbed, in pivot space: the drag handle. Zero
	-- (center) for palette drags.
	grabLocal: Vector3,
	-- Set when dragging an already-placed unit: it stays PARENTED but is
	-- hidden in place (see beginDrag — unparenting breaks undo recordings
	-- and loses the part entirely if the plugin reloads mid-drag), and is
	-- restored on place/cancel.
	existingPart: PVInstance?,
	hiddenProperties: { [BasePart]: HiddenProperties }?,
	originalCFrame: CFrame?,
	ghostConnectors: { UnitConnector },
	ghostMarkers: { Marker },
	-- Group dragging (existing picks only): units traveling with the
	-- primary per the current move mode, hidden in place like the
	-- primary and ghosted at fixed offsets from the primary ghost.
	groupGhosts: { { ghost: PVInstance, offset: CFrame, original: PVInstance } },
	-- Pooled adornments reassigned each frame to the nearby connectors.
	markerPool: { Marker },
	markerFolder: Folder,
	overlapParams: OverlapParams,
	connections: { RBXScriptConnection },
}

export type StartOptions = {
	guiParent: Instance?,
	plugin: Plugin?,
	-- Externally owned palette (e.g. the plugin's persistent Build widget):
	-- the controller uses it for release-over-panel detection but does not
	-- create or destroy it; the owner wires entry clicks to dragTemplate.
	palette: PartPalette.PartPalette?,
	-- Set-editor hooks. placeParent: where newly placed units parent
	-- (default workspace.Assembly in-game / workspace in Edit mode).
	-- scanRoot: the container scanned for snapping/graph units (default
	-- = the placement parent). onPicked fires when an existing unit is
	-- picked up; onPlaced after any placement commits, with the primary
	-- unit and any group members that moved with it.
	placeParent: (() -> Instance)?,
	scanRoot: (() -> Instance)?,
	onPicked: ((unit: PVInstance) -> ())?,
	onPlaced: ((primary: PVInstance, group: { PVInstance }, isExisting: boolean) -> ())?,
}

export type Controller = {
	stop: () -> (),
	dragTemplate: (template: PVInstance) -> (),
}

local function forEachUnitPart(unit: Instance, fn: (BasePart) -> ())
	if unit:IsA("BasePart") then
		fn(unit)
	end
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("BasePart") then
			fn(descendant)
		end
	end
end

local function unitExtents(unit: PVInstance): Vector3
	if unit:IsA("Model") then
		return unit:GetExtentsSize()
	end
	return (unit :: BasePart).Size
end

-- All connectors of a unit, expressed in its pivot space.
local function unitConnectors(unit: PVInstance): { UnitConnector }
	local pivot = unit:GetPivot()
	local connectors: { UnitConnector } = {}
	forEachUnitPart(unit, function(part)
		for _, connector in getConnectors(part) do
			local worldPosition = part.CFrame:PointToWorldSpace(connector.position)
			local worldDirection = part.CFrame:VectorToWorldSpace(connector.direction)
			table.insert(connectors, {
				kind = connector.kind,
				position = pivot:PointToObjectSpace(worldPosition),
				direction = pivot:VectorToObjectSpace(worldDirection),
				length = connector.length,
				oneSided = connector.oneSided,
				radius = connector.radius,
				secondary = if connector.secondary ~= nil
					then pivot:VectorToObjectSpace(part.CFrame:VectorToWorldSpace(connector.secondary :: Vector3))
					else nil,
				part = part,
				partLocalPosition = connector.position,
			})
		end
	end)
	return connectors
end

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
	-- go directly into workspace alongside imported copies. The set
	-- editor overrides via placeParent (active build root).
	local function getPlacementParent(): Instance
		if opts.placeParent ~= nil then
			return (opts.placeParent :: () -> Instance)()
		end
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

	local function getScanRoot(): Instance
		if opts.scanRoot ~= nil then
			return (opts.scanRoot :: () -> Instance)()
		end
		return getPlacementParent()
	end

	-- All placed units eligible for the assembly graph: composite Models
	-- (LDrawFile attribute) and connector-annotated loose parts, found
	-- under the placement container (recursing through folders/models
	-- that are not themselves units).
	local function collectGraphUnits(): { Instance }
		local units: { Instance } = {}
		local function scan(container: Instance)
			for _, child in container:GetChildren() do
				if child:IsA("Model") and child:GetAttribute("LDrawFile") ~= nil then
					table.insert(units, child)
				elseif child:IsA("BasePart") then
					if #getConnectors(child) > 0 then
						table.insert(units, child)
					end
				elseif child:IsA("Folder") or child:IsA("Model") then
					scan(child)
				end
			end
		end
		scan(getScanRoot())
		return units
	end

	-- Move mode: what comes along when picking up a placed unit.
	--   "part"     - just the picked unit.
	--   "chunk"    - units held by clutched joints: what sits on the
	--                picked unit's studs, plus pins/clips/hinges/etc.
	--                Its sockets always break from what's underneath.
	--   "assembly" - the whole connected component, including loose
	--                fits (axles spinning in holes, frictionless pins).
	local mMoveMode: "part" | "chunk" | "assembly" = "chunk"
	-- Axial grid snap: when ON, axle holes land on one-stud increments
	-- along axles (and axles in pin holes) instead of sliding freely.
	local mGridSnap = false
	local mModeBar: Frame? = nil

	do
		local kModes: { { mode: "part" | "chunk" | "assembly", label: string } } = {
			{ mode = "part", label = "Part" },
			{ mode = "chunk", label = "Chunk" },
			{ mode = "assembly", label = "Assembly" },
		}
		local bar = Instance.new("Frame")
		bar.Name = "MoveModeBar"
		bar.Position = UDim2.new(0, 10, 0, 8)
		bar.Size = UDim2.new(0, 320, 0, 26)
		bar.BackgroundTransparency = 1
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 4)
		layout.Parent = bar
		local buttons: { [string]: TextButton } = {}
		local function restyle()
			for mode, button in buttons do
				local active = mode == mMoveMode
				button.BackgroundColor3 = if active
					then Color3.fromRGB(0, 90, 158)
					else Color3.fromRGB(58, 58, 58)
				button.TextColor3 = if active
					then Color3.fromRGB(255, 255, 255)
					else Color3.fromRGB(190, 190, 190)
			end
		end
		for _, entry in kModes do
			local button = Instance.new("TextButton")
			button.Name = entry.label
			button.Size = UDim2.new(0, 76, 1, 0)
			button.Text = entry.label
			button.Font = Enum.Font.SourceSansBold
			button.TextSize = 14
			button.BorderSizePixel = 0
			button.AutoButtonColor = true
			button.Parent = bar
			buttons[entry.mode] = button
			button.Activated:Connect(function()
				mMoveMode = entry.mode
				restyle()
			end)
		end
		-- Grid snap toggle (independent of the move mode).
		local gridButton = Instance.new("TextButton")
		gridButton.Name = "GridSnap"
		gridButton.Size = UDim2.new(0, 76, 1, 0)
		gridButton.Font = Enum.Font.SourceSansBold
		gridButton.TextSize = 14
		gridButton.BorderSizePixel = 0
		gridButton.AutoButtonColor = true
		gridButton.Parent = bar
		local function restyleGrid()
			gridButton.Text = if mGridSnap then "Grid: ON" else "Grid: OFF"
			gridButton.BackgroundColor3 = if mGridSnap
				then Color3.fromRGB(0, 90, 158)
				else Color3.fromRGB(58, 58, 58)
			gridButton.TextColor3 = if mGridSnap
				then Color3.fromRGB(255, 255, 255)
				else Color3.fromRGB(190, 190, 190)
		end
		gridButton.Activated:Connect(function()
			mGridSnap = not mGridSnap
			restyleGrid()
		end)
		restyleGrid()
		restyle()
		bar.Parent = guiParent
		mModeBar = bar
	end

	local mDragState: DragState? = nil
	local mPalette: PartPalette.PartPalette? = nil
	-- RMB press state while dragging (click-vs-orbit discrimination). The
	-- camera CFrame matters: orbiting locks the cursor and RESTORES its
	-- position on release, so mouse movement alone reads as zero.
	local mRightMouseDown: { position: Vector2, cameraCFrame: CFrame }? = nil

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

	-- Un-hide a picked-up unit (restore the properties saved at pickup).
	local function restoreHidden(state: DragState)
		local saved = state.hiddenProperties
		if saved == nil then
			return
		end
		for part, properties in saved do
			part.Transparency = properties.transparency
			part.CanQuery = properties.canQuery
			part.CanCollide = properties.canCollide
			part.CanTouch = properties.canTouch
		end
		state.hiddenProperties = nil
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
		for _, entry in state.groupGhosts do
			entry.ghost:Destroy()
		end
		if canceled then
			if state.existingPart ~= nil then
				-- Put a picked-up unit back where it was. Group members
				-- were never moved; restoring their hidden properties is
				-- all a cancel needs.
				restoreHidden(state);
				(state.existingPart :: PVInstance):PivotTo(state.originalCFrame :: CFrame)
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

	-- Lift the move group into the drag: every unit in `moving` (except
	-- the primary) is hidden in place, ghosted at a fixed offset, and
	-- contributes its connectors to snapping/markers.
	local function liftGroup(state: DragState, moving: { any })
		if state.existingPart == nil then
			return
		end
		local sourcePivot = state.originalCFrame :: CFrame
		local saved = state.hiddenProperties :: { [BasePart]: HiddenProperties }
		for _, movingUnit in moving do
			if movingUnit == state.existingPart then
				continue
			end
			local original = movingUnit :: PVInstance
			local offset = sourcePivot:ToObjectSpace(original:GetPivot())

			-- Clone the ghost BEFORE hiding the original.
			local ghost = original:Clone()
			forEachUnitPart(ghost, function(part)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Transparency = kGhostTransparency
			end)
			ghost.Parent = workspace

			forEachUnitPart(original, function(part)
				saved[part] = {
					transparency = part.Transparency,
					canQuery = part.CanQuery,
					canCollide = part.CanCollide,
					canTouch = part.CanTouch,
				}
				part.Transparency = 1
				part.CanQuery = false
				part.CanCollide = false
				part.CanTouch = false
			end)

			table.insert(state.groupGhosts, { ghost = ghost, offset = offset, original = original })

			-- The group member's connectors join the drag set, expressed
			-- in the PRIMARY unit's pivot space (offset is rigid).
			for _, connector in unitConnectors(ghost) do
				table.insert(state.ghostConnectors, {
					kind = connector.kind,
					position = offset:PointToWorldSpace(connector.position),
					direction = offset:VectorToWorldSpace(connector.direction),
					length = connector.length,
					oneSided = connector.oneSided,
					radius = connector.radius,
					secondary = if connector.secondary ~= nil
						then offset:VectorToWorldSpace(connector.secondary :: Vector3)
						else nil,
					part = connector.part,
					partLocalPosition = connector.partLocalPosition,
				})
				table.insert(
					state.ghostMarkers,
					makeMarker(connector.part, connector.partLocalPosition, connector.kind, state.markerFolder)
				)
			end
		end
	end

	local function updateGhost(state: DragState)
		local ray = mouseRay()

		local filterList: { Instance } = { state.ghost }
		for _, entry in state.groupGhosts do
			table.insert(filterList, entry.ghost)
		end
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

		local rotation = state.orientation * state.baseRotation
		local size = unitExtents(state.ghost)
		local rotatedGrab = rotation:VectorToWorldSpace(state.grabLocal)
		-- SNAP pose: the grabbed point follows the cursor in ALL THREE
		-- axes - the cursor expresses where the user wants the grabbed
		-- spot to go, so mate candidates are measured from there. (The
		-- rested pose below would float a large unit's connectors half
		-- its bounding box above the surface under the cursor - a 24t
		-- gear's bore ends up ~1.8 studs off an axle the cursor is
		-- pointing straight at, outside the snap radius.)
		local snapBaseCFrame = rotation + (hitPoint - rotatedGrab)
		local grabWorldPosition = hitPoint

		-- DISPLAY pose when nothing snaps: rest the rotated bounding box
		-- on the hit point, keeping the grabbed point under the cursor
		-- horizontally (natural for dropping bricks onto surfaces).
		local halfHeight = 0.5 * (
			math.abs(rotation.XVector.Y) * size.X
			+ math.abs(rotation.YVector.Y) * size.Y
			+ math.abs(rotation.ZVector.Y) * size.Z
		)
		local restedCFrame = rotation + Vector3.new(
			hitPoint.X - rotatedGrab.X,
			hitPoint.Y + halfHeight,
			hitPoint.Z - rotatedGrab.Z
		)

		-- Spatial query: only connectors near the ghost participate in
		-- snapping and get markers.
		state.overlapParams.FilterDescendantsInstances = filterList
		local queryRadius = size.Magnitude / 2 + kSnapQueryPadding
		local nearbyParts = workspace:GetPartBoundsInRadius(snapBaseCFrame.Position, queryRadius, state.overlapParams)

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
					radius = connector.radius,
					secondary = if connector.secondary ~= nil
						then part.CFrame:VectorToWorldSpace(connector.secondary :: Vector3)
						else nil,
					part = part,
					attachment = connector.attachment,
				})
				table.insert(localPositions, connector.position)
			end
		end

		local snap = findSnapPlacement(
			snapBaseCFrame,
			state.ghostConnectors :: any,
			worldConnectors,
			kMaxSnapDistance,
			grabWorldPosition,
			mGridSnap
		)

		local targetPivot: CFrame
		if snap ~= nil then
			targetPivot = snap.cframe
		else
			local position = restedCFrame.Position
			targetPivot = rotation + Vector3.new(
				math.round(position.X / kGridSize) * kGridSize,
				position.Y,
				math.round(position.Z / kGridSize) * kGridSize
			)
		end
		state.ghost:PivotTo(targetPivot)
		for _, entry in state.groupGhosts do
			entry.ghost:PivotTo(targetPivot * entry.offset)
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
		local ghostPivot = state.ghost:GetPivot()
		local primary: PVInstance
		local group: { PVInstance } = {}
		local isExisting = state.existingPart ~= nil
		if state.existingPart ~= nil then
			local placed = state.existingPart :: PVInstance
			restoreHidden(state)
			placed:PivotTo(ghostPivot)
			for _, entry in state.groupGhosts do
				entry.original:PivotTo(ghostPivot * entry.offset)
				table.insert(group, entry.original)
			end
			primary = placed
		else
			local placed = state.template:Clone()
			forEachUnitPart(placed, function(part)
				part.Anchored = true
			end)
			placed:PivotTo(ghostPivot)
			placed.Parent = getPlacementParent()
			primary = placed
		end
		endDrag(false)
		finishRecording(true)
		if opts.onPlaced ~= nil then
			(opts.onPlaced :: (PVInstance, { PVInstance }, boolean) -> ())(primary, group, isExisting)
		end
	end

	local function beginDrag(source: PVInstance, isExisting: boolean, grabWorldPosition: Vector3?)
		endDrag(true)
		beginRecording(if isExisting then "BuildIt: Move part" else "BuildIt: Place part")
		if isExisting and opts.onPicked ~= nil then
			(opts.onPicked :: (PVInstance) -> ())(source)
		end

		local grabLocal = Vector3.zero
		if grabWorldPosition ~= nil then
			grabLocal = source:GetPivot():PointToObjectSpace(grabWorldPosition)
		end

		-- Rebuild the assembly graph from scratch every pickup: undo and
		-- external edits can change anything between drags, so the
		-- workspace is the only source of truth in Edit mode. Built
		-- BEFORE the ghost clone enters the workspace so the ghost's
		-- connectors never pollute the graph.
		local partitionGraph: AssemblyGraph.AssemblyGraph? = nil
		if isExisting and mMoveMode ~= "part" then
			partitionGraph = AssemblyGraph.build(AssemblyGraph.collectUnits(collectGraphUnits()))
		end

		local ghost = source:Clone()
		forEachUnitPart(ghost, function(part)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = kGhostTransparency
		end)
		ghost.Parent = workspace

		local baseRotation = CFrame.identity
		local originalCFrame: CFrame? = nil
		local hiddenProperties: { [BasePart]: HiddenProperties }? = nil
		if isExisting then
			baseRotation = source:GetPivot().Rotation
			originalCFrame = source:GetPivot()
			-- Hide in place while dragging: CanQuery=false removes it from
			-- snapping/raycasts. NEVER unparent — undo recordings lose
			-- instances that leave the DataModel mid-recording, and a
			-- plugin reload mid-drag would orphan the part entirely.
			local saved: { [BasePart]: HiddenProperties } = {}
			forEachUnitPart(source, function(part)
				saved[part] = {
					transparency = part.Transparency,
					canQuery = part.CanQuery,
					canCollide = part.CanCollide,
					canTouch = part.CanTouch,
				}
				part.Transparency = 1
				part.CanQuery = false
				part.CanCollide = false
				part.CanTouch = false
			end)
			hiddenProperties = saved
		end

		-- Marker adornments live under the camera: always renderable, never
		-- replicated or saved.
		local markerFolder = Instance.new("Folder")
		markerFolder.Name = "BuildItMarkers"
		markerFolder.Parent = workspace.CurrentCamera

		local ghostConnectors = unitConnectors(ghost)
		local ghostMarkers: { Marker } = {}
		for _, connector in ghostConnectors do
			table.insert(
				ghostMarkers,
				makeMarker(connector.part, connector.partLocalPosition, connector.kind, markerFolder)
			)
		end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.MaxParts = kMaxNearbyParts

		local state: DragState = {
			template = source,
			ghost = ghost,
			orientation = CFrame.identity,
			baseRotation = baseRotation,
			grabLocal = grabLocal,
			existingPart = if isExisting then source else nil,
			hiddenProperties = hiddenProperties,
			originalCFrame = originalCFrame,
			ghostConnectors = ghostConnectors,
			ghostMarkers = ghostMarkers,
			groupGhosts = {},
			markerPool = {},
			markerFolder = markerFolder,
			overlapParams = overlapParams,
			connections = {},
		}
		mDragState = state

		-- The move mode decides the group up front (no drag direction
		-- needed): the picked unit's studs carry what's stacked on them
		-- and its sockets break away ("chunk"), or the whole connected
		-- component comes along ("assembly").
		if partitionGraph ~= nil then
			local moving = if mMoveMode == "assembly"
				then partitionGraph:partitionAssembly(source)
				else partitionGraph:partitionChunk(source)
			liftGroup(state, moving)
		end

		table.insert(state.connections, RunService.RenderStepped:Connect(function()
			updateGhost(state)
		end))

		table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.KeyCode == Enum.KeyCode.R then
				state.orientation = CFrame.Angles(0, math.pi / 2, 0) * state.orientation
			elseif input.KeyCode == Enum.KeyCode.T then
				-- Tip the part toward the camera: a WORLD-space 90-degree
				-- rotation about the horizontal axis perpendicular to the
				-- camera's look direction snapped to the nearest cardinal.
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
				state.orientation = CFrame.fromAxisAngle(axis, math.pi / 2) * state.orientation
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
				mRightMouseDown = {
					position = UserInputService:GetMouseLocation(),
					cameraCFrame = workspace.CurrentCamera.CFrame,
				}
			end
		end))

		table.insert(state.connections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				local down = mRightMouseDown
				mRightMouseDown = nil
				if down == nil then
					return
				end
				local moved = (UserInputService:GetMouseLocation() - down.position).Magnitude
					> kRightClickCancelMaxMovement
				-- Any camera rotation means this was an orbit, even though
				-- the restored cursor position reads as unmoved.
				local camera = workspace.CurrentCamera
				local rotated = camera.CFrame.LookVector:Dot(down.cameraCFrame.LookVector) < 0.99995
					or (camera.CFrame.Position - down.cameraCFrame.Position).Magnitude > 0.01
				if not moved and not rotated then
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
		if result == nil then
			return
		end
		-- A hit on a composite segment picks up the whole assembly Model.
		local hit = result.Instance
		local model = hit:FindFirstAncestorOfClass("Model")
		if model ~= nil and model:GetAttribute("LDrawFile") ~= nil then
			beginDrag(model, true, result.Position)
		elseif #getConnectors(hit) > 0 then
			beginDrag(hit, true, result.Position)
		end
	end)

	local mOwnsPalette = opts.palette == nil
	if opts.palette ~= nil then
		mPalette = opts.palette
	else
		mPalette = PartPalette.create(guiParent, templatesFolder :: Folder, function(template: PVInstance)
			beginDrag(template, false)
		end)
	end

	local function stop()
		endDrag(true)
		mPickupConnection:Disconnect()
		if mModeBar ~= nil then
			(mModeBar :: Frame):Destroy()
			mModeBar = nil
		end
		if mOwnsPalette and mPalette ~= nil then
			(mPalette :: PartPalette.PartPalette).destroy()
		end
		mPalette = nil
		if mOwnScreenGui ~= nil then
			(mOwnScreenGui :: ScreenGui):Destroy()
			mOwnScreenGui = nil
		end
	end

	return {
		stop = stop,
		dragTemplate = function(template: PVInstance)
			beginDrag(template, false)
		end,
	}
end

return BuildController
