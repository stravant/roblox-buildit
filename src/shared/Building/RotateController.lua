--!strict

-- Edit-mode Rotate tool, physics-driven: click and hold any part of a
-- placed assembly and drag. The connected assembly gets real physics
-- joints (WeldConstraints inside rigid groups; Hinge/Cylindrical/
-- Prismatic/BallSocket constraints between them; composite JointPivot
-- pairs as hinges/prismatics), everything except the largest rigid
-- group is unanchored, and the grabbed part is moved toward the
-- cursor with workspace:IKMoveTo — the same constraint-respecting
-- inverse-kinematics solve Studio's own draggers use. Mechanisms
-- respond the way they're built: a hinge top swings, a 4-bar linkage
-- follows, a shock's piston slides, liftarms pinned twice stay rigid,
-- and anchored parts act as ground.
--
-- Release commits the pose (one undo recording); RMB/Esc cancels and
-- restores.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local getConnectors = require(script.Parent.getConnectors)
local AssemblyGraph = require(script.Parent.AssemblyGraph)
local applyPhysicsJoints = require(script.Parent.applyPhysicsJoints)

local kRaycastDistance = 500
-- IKMoveTo stiffnesses. The API defaults (0.5/0.5, what Studio's own
-- dragger uses) matter: stiffness 1 demands exact target satisfaction,
-- which explodes when an anchored part makes the cursor target
-- unreachable — the solver soft-blends toward the goal instead.
local kTranslateStiffness = 0.5
local kRotateStiffness = 0.5
-- Debug toggle: with the drive off, sessions only build joints for
-- inspection and nothing moves.
local kDriveEnabled = true

type Session = {
	grabbedPart: BasePart,
	grabLocal: Vector3, -- grab point in the grabbed part's space
	simParts: { BasePart },
	anchoredParts: { BasePart },
	originalCFrames: { [BasePart]: CFrame },
	reportedDriveError: boolean?,
	joints: applyPhysicsJoints.Applied,
	planeOrigin: Vector3,
	planeNormal: Vector3,
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
	-- DEBUG AID: joints from the previous session are left in the place
	-- on mouse up (inspect them with constraint visualization); they are
	-- only cleaned up when the next session begins.
	local mLeftoverJoints: applyPhysicsJoints.Applied? = nil

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
		-- Keep the joints around for inspection (destroyed at the start
		-- of the next session).
		mLeftoverJoints = session.joints
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
		if mLeftoverJoints ~= nil then
			pcall((mLeftoverJoints :: applyPhysicsJoints.Applied).destroy)
			mLeftoverJoints = nil
		end

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

		-- Pin the OTHER EXTREMITY of the assembly: the rigid group
		-- FARTHEST from the grabbed one (by joint-graph hops) stays
		-- anchored as ground, so the whole chain between grip and
		-- ground has something to articulate against. (Anchoring a
		-- group adjacent to the grip would leave the far end of the
		-- chain undriven and free to wander.) Volume breaks ties.
		local grabbedRoot = find(hitPart)
		local groupAdjacency: { [BasePart]: { [BasePart]: boolean } } = {}
		for _, pair in joints.constraintPairs do
			local rootA, rootB = find(pair[1]), find(pair[2])
			if rootA ~= rootB then
				groupAdjacency[rootA] = groupAdjacency[rootA] or {}
				groupAdjacency[rootA][rootB] = true
				groupAdjacency[rootB] = groupAdjacency[rootB] or {}
				groupAdjacency[rootB][rootA] = true
			end
		end
		local distance: { [BasePart]: number } = { [grabbedRoot] = 0 }
		local queue = { grabbedRoot }
		local head = 1
		while head <= #queue do
			local current = queue[head]
			head += 1
			for neighbor in groupAdjacency[current] or {} do
				if distance[neighbor] == nil then
					distance[neighbor] = distance[current] + 1
					table.insert(queue, neighbor)
				end
			end
		end
		local anchoredRoot: BasePart? = nil
		local anchoredDistance = -1
		for root, volume in groupVolume do
			if root == grabbedRoot then
				continue
			end
			local rootDistance = distance[root] or -1
			if rootDistance < 0 then
				continue -- not joint-connected to the grabbed group
			end
			if
				anchoredRoot == nil
				or rootDistance > anchoredDistance
				or (rootDistance == anchoredDistance and volume > groupVolume[anchoredRoot :: BasePart])
			then
				anchoredRoot = root
				anchoredDistance = rootDistance
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

		-- DEBUG: report what the session built so anchoring/joint issues
		-- are visible at a glance.
		do
			local lines = { `[BuildIt Rotate] {groupCount} rigid groups, grabbed = {hitPart:GetFullName()}` }
			local membersByRoot: { [BasePart]: { string } } = {}
			for _, part in parts do
				local root = find(part)
				membersByRoot[root] = membersByRoot[root] or {}
				table.insert(membersByRoot[root], part.Name)
			end
			for root, members in membersByRoot do
				local tags = {}
				if root == grabbedRoot then
					table.insert(tags, "GRABBED")
				end
				if root == anchoredRoot then
					table.insert(tags, "ANCHORED")
				end
				local suffix = if #tags > 0 then ` [{table.concat(tags, ", ")}]` else ""
				table.insert(lines, `  group (d={distance[root] or "-"}){suffix}: {table.concat(members, ", ")}`)
			end
			for _, pair in joints.weldedPairs do
				table.insert(lines, `  weld: {pair[1].Name} <-> {pair[2].Name}`)
			end
			for _, pair in joints.constraintPairs do
				table.insert(lines, `  constraint: {pair[1].Name} <-> {pair[2].Name}`)
			end
			warn(table.concat(lines, "\n"))
		end

		local recording: string? = nil
		if pluginRef ~= nil then
			recording = ChangeHistoryService:TryBeginRecording("BuildIt: Pose assembly")
		end

		for _, part in simParts do
			part.Anchored = false
		end

		local camera = workspace.CurrentCamera
		local session: Session = {
			grabbedPart = hitPart,
			grabLocal = hitPart.CFrame:PointToObjectSpace(grabWorldPosition),
			simParts = simParts,
			anchoredParts = anchoredParts,
			originalCFrames = originalCFrames,
			joints = joints,
			planeOrigin = grabWorldPosition,
			planeNormal = -camera.CFrame.LookVector,
			recording = recording,
			connections = {},
		}
		mSession = session

		table.insert(session.connections, RunService.RenderStepped:Connect(function(_deltaTime: number)
			-- Cursor target on the camera-facing plane through the grab
			-- point (the classic 3D drag plane).
			local ray = mouseRay()
			local denominator = ray.Direction:Dot(session.planeNormal)
			if math.abs(denominator) < 1e-4 then
				return
			end
			local t = (session.planeOrigin - ray.Origin):Dot(session.planeNormal) / denominator
			if t <= 0 then
				return
			end
			local planeTarget = ray.Origin + ray.Direction * t

			-- Target CFrame: keep the part's current rotation, translate
			-- so the grabbed point lands on the cursor; rotate stiffness
			-- 0 leaves orientation to the mechanism's joints.
			local part = session.grabbedPart
			local rotatedGrab = part.CFrame:VectorToWorldSpace(session.grabLocal)
			local target = part.CFrame.Rotation + (planeTarget - rotatedGrab)
			if kDriveEnabled then
				local ok, problem = pcall(function()
					(workspace :: any):IKMoveTo(
						part,
						target,
						kTranslateStiffness,
						kRotateStiffness,
						Enum.IKCollisionsMode.NoCollisions
					)
				end)
				if not ok and not session.reportedDriveError then
					session.reportedDriveError = true
					warn(`[BuildIt Rotate] IKMoveTo failed: {problem}`)
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
