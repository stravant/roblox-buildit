--!strict

-- The in-game build test tool. Drag parts out of the palette into the
-- world; while dragging, all connectors light up (studs green, sockets
-- blue) and the mated pairs of the current snap highlight yellow.
--
-- Controls:
--   Hold LMB on a palette entry, drag into the world, release to place.
--   R rotates the dragged part 90 degrees. Esc or RMB cancels the drag.
--
-- Placed parts go in workspace.Assembly and keep their connector
-- attachments, so they become snap targets for the next part.

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
local kMatchedColor = Color3.fromRGB(255, 220, 40)

type WorldConnector = findSnapPlacement.WorldConnector

type Marker = {
	adornment: SphereHandleAdornment,
	kind: string,
}

type DragState = {
	template: BasePart,
	ghost: BasePart,
	rotationIndex: number,
	ghostConnectors: { getConnectors.Connector },
	worldConnectors: { WorldConnector },
	ghostMarkers: { Marker },
	worldMarkers: { Marker },
	markerFolder: Folder,
	connections: { RBXScriptConnection },
}

local BuildController = {}

function BuildController.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildItTool"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local templatesFolder = ReplicatedStorage:FindFirstChild("PartLibrary")
	if templatesFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "PartLibrary"
		folder.Parent = ReplicatedStorage
		templatesFolder = folder
	end

	local assemblyFolder = workspace:FindFirstChild("Assembly")
	if assemblyFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "Assembly"
		folder.Parent = workspace
		assemblyFolder = folder
	end

	local mDragState: DragState? = nil
	local mPalette: PartPalette.PartPalette? = nil

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
		adornment.Color3 = if kind == "Stud" then kStudColor else kSocketColor
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
			marker.adornment.Color3 = if marker.kind == "Stud" then kStudColor else kSocketColor
			marker.adornment.Radius = kMarkerRadius
			marker.adornment.Transparency = 0.25
		end
	end

	local function collectWorldConnectors(markerFolder: Folder): ({ WorldConnector }, { Marker })
		local worldConnectors: { WorldConnector } = {}
		local markers: { Marker } = {}
		for _, part in (assemblyFolder :: Folder):GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			for _, connector in getConnectors(part) do
				table.insert(worldConnectors, {
					kind = connector.kind,
					position = part.CFrame:PointToWorldSpace(connector.position),
					direction = part.CFrame:VectorToWorldSpace(connector.direction),
					part = part,
					attachment = connector.attachment,
				})
				table.insert(markers, makeMarker(part, connector.position, connector.kind, markerFolder))
			end
		end
		return worldConnectors, markers
	end

	local function endDrag()
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
	end

	local function updateGhost(state: DragState)
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local ray = camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y)

		local filterList: { Instance } = { state.ghost }
		local character = player.Character
		if character ~= nil then
			table.insert(filterList, character)
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
		local placed = state.template:Clone()
		placed.CFrame = state.ghost.CFrame
		placed.Anchored = true
		placed.Parent = assemblyFolder
		endDrag()
	end

	local function beginDrag(template: BasePart)
		endDrag()

		local ghost = template:Clone()
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.Transparency = kGhostTransparency
		ghost.Parent = workspace

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
		local worldConnectors, worldMarkers = collectWorldConnectors(markerFolder)

		local state: DragState = {
			template = template,
			ghost = ghost,
			rotationIndex = 0,
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

		table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if input.KeyCode == Enum.KeyCode.R then
				state.rotationIndex = (state.rotationIndex + 1) % 4
			elseif
				input.KeyCode == Enum.KeyCode.Escape
				or input.UserInputType == Enum.UserInputType.MouseButton2
			then
				endDrag()
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
				endDrag()
			else
				placeGhost(state)
			end
		end))

		updateGhost(state)
	end

	mPalette = PartPalette.create(screenGui, templatesFolder :: Folder, beginDrag)
end

return BuildController
