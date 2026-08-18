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
local gearSatellites = require(script.Parent.gearSatellites)

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
	-- Invisible massless handle welded to the grabbed part at the click
	-- point. IKMoveTo drives a part's ORIGIN toward the target - for a
	-- part whose origin sits on the joint axis (a beam centered on its
	-- pin) no translation is reachable and nothing moves. The handle's
	-- origin IS the grab point, always off-axis, so its position error
	-- is reducible by articulating the mechanism.
	handle: BasePart,
	simParts: { BasePart },
	anchoredParts: { BasePart },
	originalCFrames: { [BasePart]: CFrame },
	-- Gear drive: propagation steps in BFS order from the grabbed
	-- group. Each step reads the FROM group's accumulated rotation
	-- about its gear axis and poses the TO group about its own axis by
	-- the tooth ratio (external mesh reverses direction). Gears mesh
	-- with too many teeth to simulate; the meshing pairs get
	-- NoCollisionConstraints and this code supplies the gearing.
	gearSteps: {
		{
			fromParts: { BasePart },
			toParts: { BasePart },
			fromAxis: Vector3,
			fromCenter: Vector3,
			toAxis: Vector3,
			toCenter: Vector3,
			ratio: number, -- signed: driven = ratio * driver angle
			-- Tooth phase correction: added to the driven angle so the
			-- teeth interleave (computed at session start from tooth
			-- counts and the gears' cross reference directions).
			phase: number,
			fromReference: BasePart,
			lastAngle: number,
			accumulated: number,
		}
	},
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

	-- Sweep ALL leftover sim joints from the place, not just the ones
	-- this session object remembers: previous sessions survive plugin
	-- reloads, undo can resurrect committed joint folders, and the
	-- debug keep-on-mouse-up behavior leaves them around by design.
	local function destroyLeftoverJoints()
		if mLeftoverJoints ~= nil then
			pcall((mLeftoverJoints :: applyPhysicsJoints.Applied).destroy)
			mLeftoverJoints = nil
		end
		for _, child in workspace:GetChildren() do
			if child:IsA("Folder") and child.Name == "BuildItSimJoints" then
				child:Destroy()
			end
		end
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("Attachment") and (descendant.Name == "BuildItJoint" or descendant.Name == "BuildItDrive") then
				descendant:Destroy()
			end
		end
	end

	local function beginSession(hitPart: BasePart, grabWorldPosition: Vector3)
		endSession(false)
		destroyLeftoverJoints()

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
		local structuralPart: { [BasePart]: boolean } = {}
		for id in assemblySet do
			-- Structural = frame parts. Fasteners (pins/axles) and GEARS
			-- are machine elements: anchoring a gear defeats the drive.
			local structural = not graph:isFastenerUnit(id) and not graph:isGearUnit(id)
			forEachUnitPart(id :: Instance, function(part)
				table.insert(parts, part)
				groupOf[part] = part
				if structural then
					structuralPart[part] = true
				end
			end)
		end
		for _, pair in joints.weldedPairs do
			local rootA, rootB = find(pair[1]), find(pair[2])
			if rootA ~= rootB then
				groupOf[rootA] = rootB
			end
		end
		local groupVolume: { [BasePart]: number } = {}
		local groupStructural: { [BasePart]: boolean } = {}
		local groupCount = 0
		for _, part in parts do
			local root = find(part)
			if groupVolume[root] == nil then
				groupVolume[root] = 0
				groupCount += 1
			end
			local size = part.Size
			groupVolume[root] += size.X * size.Y * size.Z
			if structuralPart[part] then
				groupStructural[root] = true
			end
		end
		if groupCount < 2 then
			-- Fully rigid (or a lone part): nothing to articulate.
			-- DEBUG: say so — a silently dead grab usually means the
			-- grabbed unit's subassembly is DISCONNECTED from the rest in
			-- the graph (a mate expected to hold isn't engaged).
			local names = {}
			for _, part in parts do
				table.insert(names, part.Name)
			end
			warn(
				`[BuildIt Rotate] fully rigid: {#parts} part(s) in 1 group, nothing to articulate.`
					.. ` Connected component: {table.concat(names, ", ")}`
			)
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
			local rootA, rootB = find(pair.part0), find(pair.part1)
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
		-- Prefer STRUCTURAL groups (containing a part with studs and
		-- inlets, not just fastener rods) over leaves like a lone pin:
		-- a pin sticking out may be hop-farthest, but pinning it as
		-- ground is useless. Structural beats distance beats volume.
		-- (Interim heuristic per user: "studs + inlets" is good enough
		-- for now; a more precise groundedness rule can come later.)
		local anchoredRoot: BasePart? = nil
		local anchoredDistance = -1
		local anchoredStructural = false
		for root, volume in groupVolume do
			if root == grabbedRoot then
				continue
			end
			local rootDistance = distance[root] or -1
			if rootDistance < 0 then
				continue -- not joint-connected to the grabbed group
			end
			local rootStructural = groupStructural[root] == true
			local better: boolean
			if anchoredRoot == nil then
				better = true
			elseif rootStructural ~= anchoredStructural then
				better = rootStructural
			elseif rootDistance ~= anchoredDistance then
				better = rootDistance > anchoredDistance
			else
				better = volume > groupVolume[anchoredRoot :: BasePart]
			end
			if better then
				anchoredRoot = root
				anchoredDistance = rootDistance
				anchoredStructural = rootStructural
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
				if not groupStructural[root] then
					table.insert(tags, "fastener")
				end
				local suffix = if #tags > 0 then ` [{table.concat(tags, ", ")}]` else ""
				table.insert(lines, `  group (d={distance[root] or "-"}){suffix}: {table.concat(members, ", ")}`)
			end
			for _, pair in joints.weldedPairs do
				table.insert(lines, `  weld: {pair[1].Name} <-> {pair[2].Name}`)
			end
			for _, pair in joints.constraintPairs do
				table.insert(lines, `  constraint ({pair.kind}): {pair.part0.Name} <-> {pair.part1.Name}`)
			end
			warn(table.concat(lines, "\n"))
		end

		-- Gear drive chain: BFS through meshing pairs starting from the
		-- grabbed group. Each mesh whose far side isn't yet driven
		-- becomes a propagation step; the anchored group never gets
		-- driven (it is ground).
		local gearSteps = {}
		do
			local meshes = graph:gearMeshes()
			if #meshes > 0 then
				local partsOfGroup: { [BasePart]: { BasePart } } = {}
				for _, part in parts do
					local root = find(part)
					partsOfGroup[root] = partsOfGroup[root] or {}
					table.insert(partsOfGroup[root] :: { BasePart }, part)
				end
				-- Fractional tooth phase of a gear at the contact
				-- direction: 0 = tooth centered on the contact line, 0.5
				-- = gap centered. The tooth reference is the mounting
				-- bore's secondary axis (cardinal-toothed gears carry a
				-- tooth along it); teeth are evenly spaced, so only the
				-- tooth count matters beyond that.
				local function toothPhase(
					reference: Vector3?,
					axis: Vector3,
					contact: Vector3,
					teeth: number
				): number?
					if reference == nil then
						return nil
					end
					local projected = (reference :: Vector3) - axis * (reference :: Vector3):Dot(axis)
					if projected.Magnitude < 1e-3 then
						return nil
					end
					projected = projected.Unit
					local angle = math.atan2(projected:Cross(contact):Dot(axis), projected:Dot(contact))
					return (angle * teeth / (2 * math.pi)) % 1
				end

				local function unitMainPart(id: any): BasePart?
					local instance = id :: Instance
					if instance:IsA("BasePart") then
						return instance
					end
					return instance:FindFirstChildWhichIsA("BasePart", true)
				end
				-- DEBUG: report the gear drive plan alongside the session
				-- diagnostics above.
				local gearLines = {}
				for _, mesh in meshes do
					local partA = unitMainPart(mesh.a)
					local partB = unitMainPart(mesh.b)
					local inSimA = partA ~= nil and groupOf[partA :: BasePart] ~= nil
					local inSimB = partB ~= nil and groupOf[partB :: BasePart] ~= nil
					table.insert(
						gearLines,
						`  mesh: {if partA then (partA :: BasePart).Name else "?"}({mesh.teethA})`
							.. `{if inSimA then "" else " [NOT IN SIM]"}`
							.. ` <-> {if partB then (partB :: BasePart).Name else "?"}({mesh.teethB})`
							.. `{if inSimB then "" else " [NOT IN SIM]"}`
					)
				end
				local driven: { [BasePart]: boolean } = { [grabbedRoot] = true }
				local frontier = { grabbedRoot }
				while #frontier > 0 do
					local nextFrontier = {}
					for _, mesh in meshes do
						local partA = unitMainPart(mesh.a)
						local partB = unitMainPart(mesh.b)
						if partA == nil or partB == nil or groupOf[partA :: BasePart] == nil or groupOf[partB :: BasePart] == nil then
							continue
						end
						local rootA = find(partA :: BasePart)
						local rootB = find(partB :: BasePart)
						if rootA == rootB then
							continue -- welded together (same axle): no gearing
						end
						for _, current in frontier do
							local forward = rootA == current and not driven[rootB]
							local backward = rootB == current and not driven[rootA]
							if not forward and not backward then
								continue
							end
							local fromRoot = if forward then rootA else rootB
							local toRoot = if forward then rootB else rootA
							if toRoot == anchoredRoot then
								continue -- never drive the ground
							end
							local fromAxis = if forward then mesh.axisA else mesh.axisB
							local toAxis = if forward then mesh.axisB else mesh.axisA
							-- Express both rotations about a COMMON axis
							-- direction; external gears counter-rotate.
							if toAxis:Dot(fromAxis) < 0 then
								toAxis = -toAxis
							end
							local fromTeeth = if forward then mesh.teethA else mesh.teethB
							local toTeeth = if forward then mesh.teethB else mesh.teethA
							local fromCenter = if forward then mesh.centerA else mesh.centerB
							local toCenter = if forward then mesh.centerB else mesh.centerA
							-- Tooth phase correction: a proper mesh puts a
							-- tooth of one gear in the gap of the other at
							-- the contact line, i.e. the fractional phases
							-- complement to 0.5.
							local phase = 0
							local contact = toCenter - fromCenter
							contact -= fromAxis * contact:Dot(fromAxis)
							if contact.Magnitude > 1e-3 then
								contact = contact.Unit
								local fromPhase = toothPhase(
									if forward then mesh.secondaryA else mesh.secondaryB,
									fromAxis,
									contact,
									fromTeeth
								)
								local toPhase = toothPhase(
									if forward then mesh.secondaryB else mesh.secondaryA,
									fromAxis,
									-contact,
									toTeeth
								)
								if fromPhase ~= nil and toPhase ~= nil then
									local targetFraction = (0.5 - (fromPhase :: number)) % 1
									local deltaFraction = (targetFraction - (toPhase :: number) + 0.5) % 1 - 0.5
									phase = deltaFraction * 2 * math.pi / toTeeth
								end
							end
							-- The spin carries satellites: constraint
							-- neighbors joined off the spin axis (a pin in
							-- an off-center gear hole) ride along rigidly;
							-- coaxial bearings (the axle in the beam) and
							-- groups with their own motion (ground, the
							-- grabbed group, already-driven gears) do not.
							local excluded: { [BasePart]: boolean } = { [grabbedRoot] = true }
							if anchoredRoot ~= nil then
								excluded[anchoredRoot :: BasePart] = true
							end
							for drivenRoot in driven do
								excluded[drivenRoot] = true
							end
							excluded[toRoot] = nil
							local carriedRoots = gearSatellites(
								joints.constraintPairs,
								find,
								toRoot,
								toCenter,
								toAxis,
								excluded
							)
							local toParts: { BasePart } = {}
							local satelliteCount = 0
							for root in carriedRoots do
								if root ~= toRoot then
									satelliteCount += 1
								end
								for _, part in partsOfGroup[root] or {} do
									table.insert(toParts, part)
								end
							end
							driven[toRoot] = true
							table.insert(nextFrontier, toRoot)
							table.insert(
								gearLines,
								`  drive: {fromTeeth}t -> {toTeeth}t ratio={-fromTeeth / toTeeth}`
									.. ` phase={math.deg(phase)}deg satellites={satelliteCount}`
							)
							table.insert(gearSteps, {
								fromParts = partsOfGroup[fromRoot] or {},
								toParts = toParts,
								fromAxis = fromAxis,
								fromCenter = fromCenter,
								toAxis = toAxis,
								toCenter = toCenter,
								ratio = -fromTeeth / toTeeth,
								phase = phase,
								fromReference = if forward then partA :: BasePart else partB :: BasePart,
								lastAngle = 0,
								accumulated = 0,
							})
						end
					end
					frontier = nextFrontier
				end
				warn(`[BuildIt Rotate] gears:\n{table.concat(gearLines, "\n")}`)
			end
		end

		local recording: string? = nil
		if pluginRef ~= nil then
			recording = ChangeHistoryService:TryBeginRecording("BuildIt: Pose assembly")
		end

		for _, part in simParts do
			part.Anchored = false
		end

		-- The manipulation handle (see Session.handle).
		local handle = Instance.new("Part")
		handle.Name = "BuildItHandle"
		handle.Size = Vector3.new(0.2, 0.2, 0.2)
		handle.CFrame = CFrame.new(grabWorldPosition)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.Massless = true
		handle.Anchored = false
		handle.Parent = joints.folder
		local handleWeld = Instance.new("WeldConstraint")
		handleWeld.Part0 = handle
		handleWeld.Part1 = hitPart
		handleWeld.Parent = joints.folder

		local camera = workspace.CurrentCamera
		local session: Session = {
			grabbedPart = hitPart,
			handle = handle,
			simParts = simParts,
			anchoredParts = anchoredParts,
			originalCFrames = originalCFrames,
			gearSteps = gearSteps,
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

			-- Drive the HANDLE: its origin is the grab point, so the
			-- target is simply the cursor point on the drag plane (with
			-- the handle's current rotation - orientation follows the
			-- mechanism).
			local part = session.handle
			local target = part.CFrame.Rotation + planeTarget
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

				-- Gear the driven groups off the solved pose. Angles are
				-- accumulated frame to frame (valid while no gear turns
				-- more than half a revolution per frame).
				for _, step in session.gearSteps do
					local reference = step.fromReference
					local original = session.originalCFrames[reference]
					if original == nil then
						continue
					end
					local deltaRotation = reference.CFrame.Rotation * original.Rotation:Inverse()
					local seed = step.fromAxis:Cross(Vector3.yAxis)
					if seed.Magnitude < 1e-3 then
						seed = step.fromAxis:Cross(Vector3.xAxis)
					end
					seed = seed.Unit
					local rotated = deltaRotation * seed
					rotated -= step.fromAxis * rotated:Dot(step.fromAxis)
					local raw = 0
					if rotated.Magnitude > 1e-4 then
						raw = math.atan2(seed:Cross(rotated.Unit):Dot(step.fromAxis), seed:Dot(rotated.Unit))
					end
					local wrap = raw - step.lastAngle
					if wrap > math.pi then
						wrap -= 2 * math.pi
					elseif wrap < -math.pi then
						wrap += 2 * math.pi
					end
					step.lastAngle = raw
					step.accumulated += wrap

					local drivenAngle = step.accumulated * step.ratio + step.phase
					local spin = CFrame.new(step.toCenter)
						* CFrame.fromAxisAngle(step.toAxis, drivenAngle)
						* CFrame.new(-step.toCenter)
					for _, toPart in step.toParts do
						local toOriginal = session.originalCFrames[toPart]
						if toOriginal ~= nil then
							toPart.CFrame = spin * toOriginal
						end
					end
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
