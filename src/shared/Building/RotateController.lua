--!strict

-- Edit-mode Rotate tool, physics-driven: click and hold any part of a
-- placed assembly and drag. The connected assembly gets real physics
-- joints (WeldConstraints inside rigid groups; Hinge/Cylindrical/
-- Prismatic/BallSocket constraints between them; composite JointPivot
-- pairs as hinges/prismatics), everything except the largest rigid
-- group is unanchored, and the grabbed point is pulled toward the
-- cursor by an AlignPosition while the simulation is stepped manually
-- with workspace:StepPhysics. Mechanisms respond the way they're
-- built: a hinge top swings, a 4-bar linkage follows, a shock's piston
-- slides, liftarms pinned twice stay rigid.
--
-- Gravity is zeroed and velocities damped each step, so this is
-- posing, not free simulation: the assembly only moves where the drag
-- pulls it, and it stops when the mouse stops. Release commits the
-- pose (one undo recording); RMB/Esc cancels and restores.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local getConnectors = require(script.Parent.getConnectors)
local AssemblyGraph = require(script.Parent.AssemblyGraph)
local applyPhysicsJoints = require(script.Parent.applyPhysicsJoints)

local kRaycastDistance = 500
-- Drive strength: strong enough to pose crisply, bounded so an
-- impossible target (dragging against a locked joint) strains instead
-- of exploding.
local kDriveMaxForce = 1e6
local kDriveResponsiveness = 60
-- Per-step velocity damping: kills oscillation and stops the assembly
-- when the mouse stops.
local kVelocityDamping = 0.5
local kMaxStepDelta = 1 / 45
local kSubsteps = 3

type Session = {
	grabbedPart: BasePart,
	simParts: { BasePart },
	anchoredParts: { BasePart },
	originalCFrames: { [BasePart]: CFrame },
	joints: applyPhysicsJoints.Applied,
	driveAttachment: Attachment,
	drive: AlignPosition,
	planeOrigin: Vector3,
	planeNormal: Vector3,
	originalGravity: number,
	recording: string?,
	connections: { RBXScriptConnection },
}

export type StartOptions = {
	plugin: Plugin?,
}

export type Controller = {
	stop: () -> (),
}

local RotateController = {}

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

-- All placed units eligible for the assembly graph (same criteria as
-- the build tool): composite Models and connector-annotated parts.
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
	scan(workspace)
	return units
end

-- The graph unit a clicked part belongs to.
local function unitForPart(part: BasePart): Instance?
	local model = part:FindFirstAncestorOfClass("Model")
	if model ~= nil and model:GetAttribute("LDrawFile") ~= nil then
		return model
	end
	if #getConnectors(part) > 0 then
		return part
	end
	return nil
end

function RotateController.start(options: StartOptions?): Controller
	local opts: StartOptions = options or {}
	local pluginRef = opts.plugin

	local mSession: Session? = nil

	local function mouseRay(): Ray
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		return camera:ViewportPointToRay(mouse.X - inset.X, mouse.Y - inset.Y)
	end

	local function finishRecording(session: Session, commit: boolean)
		if pluginRef == nil then
			return
		end
		if session.recording ~= nil then
			ChangeHistoryService:FinishRecording(
				session.recording :: string,
				if commit
					then Enum.FinishRecordingOperation.Commit
					else Enum.FinishRecordingOperation.Cancel
			)
			session.recording = nil
		end
	end

	local function endSession(commit: boolean)
		local session = mSession
		if session == nil then
			return
		end
		mSession = nil
		for _, connection in session.connections do
			connection:Disconnect()
		end
		session.drive:Destroy()
		session.driveAttachment:Destroy()
		session.joints.destroy()
		workspace.Gravity = session.originalGravity
		for _, part in session.simParts do
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.Anchored = true
		end
		if not commit then
			for part, cframe in session.originalCFrames do
				part.CFrame = cframe
			end
		end
		finishRecording(session, commit)
	end

	local function beginSession(hitPart: BasePart, grabWorldPosition: Vector3)
		endSession(false)

		local unit = unitForPart(hitPart)
		if unit == nil then
			return
		end

		-- Rebuild the graph from scratch (Edit mode: undo and external
		-- edits make the workspace the only source of truth).
		local graph = AssemblyGraph.build(AssemblyGraph.collectUnits(collectGraphUnits()))
		if graph.units[unit] == nil then
			return
		end
		local assemblySet: { [any]: boolean } = {}
		for _, id in graph:partitionAssembly(unit) do
			assemblySet[id] = true
		end

		local joints = applyPhysicsJoints(graph, assemblySet)

		-- Part-level rigid groups: parts welded (directly or transitively)
		-- move as one body; constraints articulate between groups.
		local parts: { BasePart } = {}
		local groupOf: { [BasePart]: BasePart } = {}
		local function find(part: BasePart): BasePart
			while groupOf[part] ~= part do
				groupOf[part] = groupOf[groupOf[part]]
				part = groupOf[part]
			end
			return part
		end
		for id in assemblySet do
			forEachUnitPart(id :: Instance, function(part)
				table.insert(parts, part)
				groupOf[part] = part
			end)
		end
		for _, pair in joints.weldedPairs do
			local rootA, rootB = find(pair[1]), find(pair[2])
			if rootA ~= rootB then
				groupOf[rootA] = rootB
			end
		end
		local groupVolume: { [BasePart]: number } = {}
		local groupCount = 0
		for _, part in parts do
			local root = find(part)
			if groupVolume[root] == nil then
				groupVolume[root] = 0
				groupCount += 1
			end
			local size = part.Size
			groupVolume[root] += size.X * size.Y * size.Z
		end
		if groupCount < 2 then
			-- Fully rigid (or a lone part): nothing to articulate.
			joints.destroy()
			return
		end

		-- The largest rigid group that ISN'T the grabbed one stays
		-- anchored as ground; everything else simulates.
		local grabbedRoot = find(hitPart)
		local anchoredRoot: BasePart? = nil
		for root, volume in groupVolume do
			if root == grabbedRoot then
				continue
			end
			if anchoredRoot == nil or volume > groupVolume[anchoredRoot :: BasePart] then
				anchoredRoot = root
			end
		end

		local simParts: { BasePart } = {}
		local anchoredParts: { BasePart } = {}
		local originalCFrames: { [BasePart]: CFrame } = {}
		for _, part in parts do
			originalCFrames[part] = part.CFrame
			if find(part) == anchoredRoot then
				table.insert(anchoredParts, part)
			else
				table.insert(simParts, part)
			end
		end

		local recording: string? = nil
		if pluginRef ~= nil then
			recording = ChangeHistoryService:TryBeginRecording("BuildIt: Pose assembly")
		end

		for _, part in simParts do
			part.Anchored = false
		end

		local driveAttachment = Instance.new("Attachment")
		driveAttachment.Name = "BuildItDrive"
		driveAttachment.WorldPosition = grabWorldPosition
		driveAttachment.Parent = hitPart
		local drive = Instance.new("AlignPosition")
		drive.Mode = Enum.PositionAlignmentMode.OneAttachment
		drive.Attachment0 = driveAttachment
		drive.MaxForce = kDriveMaxForce
		drive.MaxVelocity = math.huge
		drive.Responsiveness = kDriveResponsiveness
		drive.Position = grabWorldPosition
		drive.Parent = joints.folder

		local camera = workspace.CurrentCamera
		local session: Session = {
			grabbedPart = hitPart,
			simParts = simParts,
			anchoredParts = anchoredParts,
			originalCFrames = originalCFrames,
			joints = joints,
			driveAttachment = driveAttachment,
			drive = drive,
			planeOrigin = grabWorldPosition,
			planeNormal = -camera.CFrame.LookVector,
			originalGravity = workspace.Gravity,
			recording = recording,
			connections = {},
		}
		workspace.Gravity = 0
		mSession = session

		table.insert(session.connections, RunService.RenderStepped:Connect(function(deltaTime: number)
			-- Cursor target on the camera-facing plane through the grab
			-- point (the classic 3D drag plane).
			local ray = mouseRay()
			local denominator = ray.Direction:Dot(session.planeNormal)
			if math.abs(denominator) > 1e-4 then
				local t = (session.planeOrigin - ray.Origin):Dot(session.planeNormal) / denominator
				if t > 0 then
					session.drive.Position = ray.Origin + ray.Direction * t
				end
			end

			-- Step the simulation manually: only the assembly's sim parts
			-- integrate; the rest of the place is untouched.
			local step = math.min(deltaTime, kMaxStepDelta) / kSubsteps
			for _ = 1, kSubsteps do
				local ok = pcall(function()
					(workspace :: any):StepPhysics(step, session.simParts)
				end)
				if not ok then
					break
				end
				for _, part in session.simParts do
					part.AssemblyLinearVelocity *= kVelocityDamping
					part.AssemblyAngularVelocity *= kVelocityDamping
				end
			end
		end))

		table.insert(session.connections, UserInputService.InputEnded:Connect(function(input, _gameProcessed)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				endSession(true)
			end
		end))

		table.insert(session.connections, UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if
				input.UserInputType == Enum.UserInputType.MouseButton2
				or input.KeyCode == Enum.KeyCode.Escape
			then
				endSession(false)
			elseif
				input.KeyCode == Enum.KeyCode.Z
				and (
					UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				)
			then
				endSession(false)
			end
		end))
	end

	local mPickupConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if mSession ~= nil then
			return
		end
		local ray = mouseRay()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		local result = workspace:Raycast(ray.Origin, ray.Direction * kRaycastDistance, params)
		if result == nil then
			return
		end
		local hit = result.Instance
		if hit:IsA("BasePart") then
			beginSession(hit, result.Position)
		end
	end)

	local function stop()
		endSession(false)
		mPickupConnection:Disconnect()
	end

	return {
		stop = stop,
	}
end

return RotateController
