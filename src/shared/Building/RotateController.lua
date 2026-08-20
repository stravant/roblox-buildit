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

-- In a RUNNING game there is no IKMoveTo (that is the Edit-time
-- dragger solve); physics is live instead, so the handle is pulled by
-- an AlignPosition and driven gears by AlignOrientations - the same
-- constraint network does the articulation either way.
local kIsRuntime = RunService:IsRunning()

local getConnectors = require(script.Parent.getConnectors)
local AssemblyGraph = require(script.Parent.AssemblyGraph)
local applyPhysicsJoints = require(script.Parent.applyPhysicsJoints)
local gearMeshPhase = require(script.Parent.gearMeshPhase)

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
	-- Gear bridges: propagation steps in BFS order from the grabbed
	-- group. Gears mesh with too many teeth to simulate, so meshing
	-- pairs get NoCollisionConstraints and each mesh becomes a RATIO
	-- BRIDGE between two constraint islands: per frame, a step reads
	-- the driver gear's accumulated rotation about its axis and gives
	-- the driven gear its ratio target via IKMoveTo - the constraint
	-- solver then moves everything attached to the driven gear (pins
	-- in its holes, cranks, prismatic followers) the same way it does
	-- for the grabbed part. One IKMoveTo per bridge per frame.
	gearSteps: {
		{
			fromReference: BasePart, -- driver gear part (measured)
			fromAxis: Vector3,
			toReference: BasePart, -- driven gear part (IK-driven)
			toAxis: Vector3,
			toCenter: Vector3,
			ratio: number, -- signed: driven = ratio * driver angle
			-- Tooth phase correction: added to the driven angle so the
			-- teeth interleave (computed at session start from tooth
			-- counts and the gears' cross reference directions).
			phase: number,
			lastAngle: number,
			accumulated: number,
			-- Per-frame alignment gate: gear centers/axes in their
			-- reference parts' LOCAL space, re-projected each frame. An
			-- axle sliding mid-drag can pull the gears out of mesh:
			-- while misaligned the bridge does not drive (the teeth slip
			-- past each other - driver rotation is NOT accumulated), and
			-- it naturally re-engages if the pair slides back into
			-- alignment. `engaged` is just the previous frame's state,
			-- for transition messages.
			engaged: boolean,
			-- The driven rigid group's union-find root: several bridges
			-- may target the same group (a sliding transmission axle
			-- carries two gear pairs between the same two axles); per
			-- frame at most ONE bridge drives a given root.
			toRoot: BasePart,
			fromTeeth: number,
			toTeeth: number,
			fromCenterLocal: Vector3,
			fromAxisLocal: Vector3,
			toCenterLocal: Vector3,
			toAxisLocal: Vector3,
			-- Tooth references in local space, for recomputing the phase
			-- from CURRENT geometry whenever the bridge (re-)engages.
			fromSecondaryLocal: Vector3?,
			toSecondaryLocal: Vector3?,
			orient: AlignOrientation?,
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

-- A part's rotation about `axis` relative to its original CFrame, in
-- (-pi, pi]: rotate a seed vector perpendicular to the axis by the
-- part's delta rotation and measure the swept angle.
local function spinAngle(part: BasePart, original: CFrame, axis: Vector3): number
	local deltaRotation = part.CFrame.Rotation * original.Rotation:Inverse()
	local seed = axis:Cross(Vector3.yAxis)
	if seed.Magnitude < 1e-3 then
		seed = axis:Cross(Vector3.xAxis)
	end
	seed = seed.Unit
	local rotated = deltaRotation * seed
	rotated -= axis * rotated:Dot(axis)
	if rotated.Magnitude < 1e-4 then
		return 0
	end
	return math.atan2(seed:Cross(rotated.Unit):Dot(axis), seed:Dot(rotated.Unit))
end

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
		if session.savedCanCollide ~= nil then
			for part, canCollide in session.savedCanCollide :: { [BasePart]: boolean } do
				part.CanCollide = canCollide
			end
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
			elseif descendant.Name:sub(1, 10) == "BuildItSim" and descendant.Parent ~= nil and descendant.Parent:IsA("BasePart") then
				-- Joint instances live under their Part0 (copyable repro).
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
		-- Structural = FRAME parts: studs AND sockets (the anti-stud
		-- underside cells), the brick/plate/technic-brick family. Pin or
		-- axle holes do NOT count as sockets - a stud-topped connector
		-- like 3651 (2 studs + pin hole + blind axle bore) is a machine
		-- element, not frame. Gears/bushes/wheels/links have no studs;
		-- pins and axles have neither. (Interim rule per user: studs +
		-- sockets is good enough until a more precise groundedness rule
		-- exists.)
		local function isStructuralUnit(id: any): boolean
			local unitInput = graph.units[id]
			if unitInput == nil then
				return false
			end
			local hasStud = false
			local hasSocket = false
			for _, connector in unitInput.connectors do
				if connector.kind == "Stud" then
					hasStud = true
				elseif connector.kind == "Socket" then
					hasSocket = true
				end
			end
			return hasStud and hasSocket
		end
		local structuralPart: { [BasePart]: boolean } = {}
		for id in assemblySet do
			local structural = isStructuralUnit(id)
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
					table.insert(tags, "non-structural")
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

		-- Gear drive chain: BFS through meshing pairs from the grabbed
		-- group establishes the drive TREE (one step per newly reached
		-- group); leftover meshes between two groups the tree already
		-- reaches become ALTERNATE bridges - a sliding transmission
		-- axle carries two gear pairs between the same two axles, and
		-- whichever pair is currently aligned drives (per frame at most
		-- one bridge drives a given group). The anchored group never
		-- gets driven (it is ground).
		local gearSteps = {}
		do
			local meshes = graph:gearMeshes()
			-- Discovery may include POTENTIAL meshes (within sliding
			-- range but not currently aligned): dormant steps start
			-- disengaged and the per-frame gate wakes them.
			local meshAligned: { [any]: boolean } = {}
			for _, mesh in meshes do
				meshAligned[mesh] = AssemblyGraph.gearsAligned(
					mesh.centerA,
					mesh.axisA,
					mesh.teethA,
					mesh.centerB,
					mesh.axisB,
					mesh.teethB
				)
			end
			if #meshes > 0 then
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

				local function resolveMesh(mesh): (BasePart?, BasePart?)
					local partA = unitMainPart(mesh.a)
					local partB = unitMainPart(mesh.b)
					if
						partA == nil
						or partB == nil
						or groupOf[partA :: BasePart] == nil
						or groupOf[partB :: BasePart] == nil
					then
						return nil, nil
					end
					return partA, partB
				end

				local function buildStep(mesh, forward: boolean, partA: BasePart, partB: BasePart, alternate: boolean)
					local fromAxis = if forward then mesh.axisA else mesh.axisB
					local toAxis = if forward then mesh.axisB else mesh.axisA
					-- Express both rotations about a COMMON axis direction;
					-- external gears counter-rotate.
					if toAxis:Dot(fromAxis) < 0 then
						toAxis = -toAxis
					end
					local fromTeeth = if forward then mesh.teethA else mesh.teethB
					local toTeeth = if forward then mesh.teethB else mesh.teethA
					local fromCenter = if forward then mesh.centerA else mesh.centerB
					local toCenter = if forward then mesh.centerB else mesh.centerA
					-- Tooth phase correction so the teeth interleave at the
					-- contact (see gearMeshPhase for the derivation and sign
					-- convention).
					local phase = gearMeshPhase(
						if forward then mesh.secondaryA else mesh.secondaryB,
						if forward then mesh.secondaryB else mesh.secondaryA,
						fromAxis,
						fromCenter,
						toCenter,
						fromTeeth,
						toTeeth
					)
					local fromPart = if forward then partA else partB
					local toPart = if forward then partB else partA
					table.insert(
						gearLines,
						`  {if alternate then "alt-drive" else "drive"}: {fromTeeth}t -> {toTeeth}t`
							.. ` ratio={-fromTeeth / toTeeth} phase={math.deg(phase)}deg`
							.. `{if meshAligned[mesh] == true then "" else " [dormant]"}`
					)
					table.insert(gearSteps, {
						fromReference = fromPart,
						fromAxis = fromAxis,
						toReference = toPart,
						toAxis = toAxis,
						toCenter = toCenter,
						ratio = -fromTeeth / toTeeth,
						phase = phase,
						lastAngle = 0,
						accumulated = 0,
						engaged = meshAligned[mesh] == true,
						toRoot = find(toPart),
						fromTeeth = fromTeeth,
						toTeeth = toTeeth,
						fromCenterLocal = fromPart.CFrame:PointToObjectSpace(fromCenter),
						fromAxisLocal = fromPart.CFrame:VectorToObjectSpace(fromAxis),
						toCenterLocal = toPart.CFrame:PointToObjectSpace(toCenter),
						toAxisLocal = toPart.CFrame:VectorToObjectSpace(toAxis),
					})
				end

				local driven: { [BasePart]: boolean } = { [grabbedRoot] = true }
				local depth: { [BasePart]: number } = { [grabbedRoot] = 0 }
				local usedMesh: { [any]: boolean } = {}

				-- Does this unused mesh cross from a reached group to an
				-- unreached one? Returns the orientation and parts if so.
				local function crossing(mesh): (boolean?, BasePart?, BasePart?)
					local partA, partB = resolveMesh(mesh)
					if partA == nil or partB == nil then
						return nil, nil, nil
					end
					local rootA = find(partA :: BasePart)
					local rootB = find(partB :: BasePart)
					if rootA == rootB then
						return nil, nil, nil -- welded together (same axle)
					end
					local forward = driven[rootA] == true and driven[rootB] ~= true
					local backward = driven[rootB] == true and driven[rootA] ~= true
					if not forward and not backward then
						return nil, nil, nil
					end
					local toRoot = if forward then rootB else rootA
					if toRoot == anchoredRoot then
						return nil, nil, nil -- never drive the ground
					end
					return forward, partA, partB
				end

				local function findCrossing(requireAligned: boolean): (any?, boolean?, BasePart?, BasePart?)
					for _, mesh in meshes do
						if usedMesh[mesh] then
							continue
						end
						if requireAligned and meshAligned[mesh] ~= true then
							continue
						end
						local forward, partA, partB = crossing(mesh)
						if forward ~= nil then
							return mesh, forward, partA, partB
						end
					end
					return nil, nil, nil, nil
				end

				-- Grow the drive tree one bridge at a time, ALWAYS taking
				-- an aligned crossing anywhere before falling back to a
				-- dormant one. A dormant mesh straight to a nearby group
				-- must not claim it at a shallow depth and shut out the
				-- multi-hop aligned path that actually drives it right now
				-- (two 40t gears a pitch-sum apart but axially offset
				-- would otherwise steal the root from the live 8t chain).
				while true do
					local mesh, forward, partA, partB = findCrossing(true)
					if mesh == nil then
						mesh, forward, partA, partB = findCrossing(false)
					end
					if mesh == nil then
						break
					end
					local fromRoot = find(if forward == true then partA :: BasePart else partB :: BasePart)
					local toRoot = find(if forward == true then partB :: BasePart else partA :: BasePart)
					driven[toRoot] = true
					depth[toRoot] = (depth[fromRoot] or 0) + 1
					usedMesh[mesh :: any] = true
					buildStep(mesh :: any, forward == true, partA :: BasePart, partB :: BasePart, false)
				end

				-- ALTERNATE bridges: unused meshes whose two groups the
				-- tree already reaches at different depths, oriented from
				-- the shallower (driver) side. Same-depth pairs are gear
				-- loops: skipped, the tree already drives both sides.
				for _, mesh in meshes do
					if usedMesh[mesh] then
						continue
					end
					local partA, partB = resolveMesh(mesh)
					if partA == nil or partB == nil then
						continue
					end
					local rootA = find(partA :: BasePart)
					local rootB = find(partB :: BasePart)
					if rootA == rootB then
						continue
					end
					local depthA = depth[rootA]
					local depthB = depth[rootB]
					if depthA == nil or depthB == nil or depthA == depthB then
						continue
					end
					buildStep(
						mesh,
						(depthA :: number) < (depthB :: number),
						partA :: BasePart,
						partB :: BasePart,
						true
					)
				end
				warn(`[BuildIt Rotate] gears:\n{table.concat(gearLines, "\n")}`)
			end
		end

		local recording: string? = nil
		if pluginRef ~= nil then
			recording = ChangeHistoryService:TryBeginRecording("BuildIt: Pose assembly")
		end

		local savedCanCollide: { [BasePart]: boolean }? = nil
		if kIsRuntime then
			local saved: { [BasePart]: boolean } = {}
			for _, part in simParts do
				saved[part] = part.CanCollide
				part.CanCollide = false
			end
			savedCanCollide = saved
		end
		if kIsRuntime then
			-- DEBUG (per user): every assembly part goes collision-free
			-- so only the constraints shape the motion. Not restored -
			-- observing the constraint network in isolation.
			for _, part in parts do
				part.CanCollide = false
			end
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

		-- Runtime drive: AlignPosition pulls the handle toward the
		-- cursor plane target; the constraint network articulates the
		-- rest, exactly like the Edit-time IK solve. The align must be
		-- FORCE-LIMITED: a rigid align applies whatever force reaches
		-- the target, and the cursor is almost always off the
		-- mechanism's reachable arc, so unlimited force visibly drags
		-- the joints out of alignment (the runtime analog of the Edit
		-- stiffness-1.0 explosion). Mass-scaled finite force lets the
		-- hard joints always win. Sim parts also get per-part gravity
		-- compensation: this is a POSING tool, and fighting droop with
		-- drive force is another alignment-error source.
		local driveAlign: AlignPosition? = nil
		if kIsRuntime then
			local totalMass = 0
			for _, part in simParts do
				totalMass += part.Mass
				if part.Mass > 0 then
					local liftAttachment = Instance.new("Attachment")
					liftAttachment.Name = "BuildItDrive"
					liftAttachment.Parent = part
					local lift = Instance.new("VectorForce")
					lift.Attachment0 = liftAttachment
					lift.RelativeTo = Enum.ActuatorRelativeTo.World
					lift.ApplyAtCenterOfMass = true
					lift.Force = Vector3.new(0, part.Mass * workspace.Gravity, 0)
					lift.Parent = joints.folder
				end
			end
			local driveAttachment = Instance.new("Attachment")
			driveAttachment.Name = "BuildItDrive"
			driveAttachment.Parent = handle
			local align = Instance.new("AlignPosition")
			align.Mode = Enum.PositionAlignmentMode.OneAttachment
			align.Attachment0 = driveAttachment
			align.RigidityEnabled = false
			-- Generous force + high responsiveness: snappy like the
			-- Edit-mode IK, but still finite so the joints win when the
			-- cursor leaves the reachable arc.
			align.MaxForce = math.max(totalMass, 1) * workspace.Gravity * 100
			align.MaxVelocity = 100
			align.Responsiveness = 80
			align.Position = grabWorldPosition
			align.Parent = joints.folder
			driveAlign = align
		end

		-- Jam state per driven root (for transition messages only).
		local mLastJammed: { [BasePart]: boolean } = {}

		local camera = workspace.CurrentCamera
		local session: Session = {
			grabbedPart = hitPart,
			handle = handle,
			driveAlign = driveAlign,
			savedCanCollide = savedCanCollide,
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
			local function ikMoveTo(movePart: BasePart, moveTarget: CFrame)
				local ok, problem = pcall(function()
					(workspace :: any):IKMoveTo(
						movePart,
						moveTarget,
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

			local part = session.handle
			local target = part.CFrame.Rotation + planeTarget
			if kDriveEnabled then
				if kIsRuntime then
					if session.driveAlign ~= nil then
						(session.driveAlign :: AlignPosition).Position = planeTarget
					end
				else
					ikMoveTo(part, target)
				end

				-- Propagate across the gear bridges off the solved pose:
				-- each driven gear gets its ratio target and IKMoveTo
				-- lets the constraint solver move its whole island.
				-- Angles are accumulated frame to frame (valid while no
				-- gear turns more than half a revolution per frame).
				-- Alignment pre-pass + jam detection: two aligned
				-- bridges with CONFLICTING ratios into the same group
				-- means the gear train is physically jammed - hold the
				-- group where it is instead of driving garbage.
				local stepAligned: { [any]: boolean } = {}
				local rootRatio: { [BasePart]: number } = {}
				local jammedRoots: { [BasePart]: boolean } = {}
				for _, step in session.gearSteps do
					-- Alignment gate from CURRENT poses: an axle sliding
					-- mid-drag can pull the pair out of mesh; sliding back
					-- re-engages it.
					local fromNow = step.fromReference.CFrame
					local toNow = step.toReference.CFrame
					local aligned = AssemblyGraph.gearsAligned(
						fromNow:PointToWorldSpace(step.fromCenterLocal),
						fromNow:VectorToWorldSpace(step.fromAxisLocal),
						step.fromTeeth,
						toNow:PointToWorldSpace(step.toCenterLocal),
						toNow:VectorToWorldSpace(step.toAxisLocal),
						step.toTeeth
					)
					stepAligned[step] = aligned
					if aligned ~= step.engaged then
						step.engaged = aligned
						if aligned then
							-- (Re-)engagement REBASE: while this bridge was
							-- dormant another bridge (or nothing) turned
							-- the driven group, so the frozen target is
							-- stale - driving it would snap the axle to a
							-- different orientation. Anchor the bridge to
							-- the group's ACTUAL spin, with the tooth
							-- interleave recomputed from current geometry.
							local toOriginal = session.originalCFrames[step.toReference]
							if toOriginal ~= nil then
								local actualSpin =
									spinAngle(step.toReference, toOriginal :: CFrame, step.toAxis)
								local fromAxisNow = fromNow:VectorToWorldSpace(step.fromAxisLocal)
								local meshPhaseNow = gearMeshPhase(
									if step.fromSecondaryLocal ~= nil
										then fromNow:VectorToWorldSpace(step.fromSecondaryLocal :: Vector3)
										else nil,
									if step.toSecondaryLocal ~= nil
										then toNow:VectorToWorldSpace(step.toSecondaryLocal :: Vector3)
										else nil,
									fromAxisNow,
									fromNow:PointToWorldSpace(step.fromCenterLocal),
									toNow:PointToWorldSpace(step.toCenterLocal),
									step.fromTeeth,
									step.toTeeth
								)
								step.phase = actualSpin + meshPhaseNow - step.accumulated * step.ratio
							end
						end
						warn(
							`[BuildIt Rotate] gear mesh {step.fromTeeth}t -> {step.toTeeth}t`
								.. ` {if aligned then "engaged" else "slid out of alignment: not driving"}`
						)
					end
					if aligned then
						local existing = rootRatio[step.toRoot]
						if existing == nil then
							rootRatio[step.toRoot] = step.ratio
						elseif math.abs((existing :: number) - step.ratio) > 1e-4 then
							jammedRoots[step.toRoot] = true
						end
					end
				end
				for root in jammedRoots do
					if not mLastJammed[root] then
						warn(
							"[BuildIt Rotate] conflicting gear ratios engaged into the same"
								.. " group: jammed (holding, not turning)"
						)
					end
				end
				mLastJammed = jammedRoots

				local claimedRoots: { [BasePart]: boolean } = {}
				for _, step in session.gearSteps do
					local aligned = stepAligned[step] == true
					local reference = step.fromReference
					local original = session.originalCFrames[reference]
					if original == nil then
						continue
					end
					local raw = spinAngle(reference, original :: CFrame, step.fromAxis)
					local wrap = raw - step.lastAngle
					if wrap > math.pi then
						wrap -= 2 * math.pi
					elseif wrap < -math.pi then
						wrap += 2 * math.pi
					end
					step.lastAngle = raw
					if not aligned or claimedRoots[step.toRoot] then
						-- Teeth slipping past each other (or another
						-- bridge already drives this group this frame):
						-- track the driver so wrap accounting stays
						-- valid, but do not accumulate - on
						-- (re-)engagement the driven gear resumes from
						-- where it is, no catch-up jump.
						continue
					end
					claimedRoots[step.toRoot] = true
					if not jammedRoots[step.toRoot] then
						step.accumulated += wrap
					end
					-- Jammed: accumulated stays frozen, so the IK target
					-- below HOLDS the group at its current angle instead
					-- of turning it.

					local drivenAngle = step.accumulated * step.ratio + step.phase
					local toOriginal = session.originalCFrames[step.toReference]
					if toOriginal ~= nil then
						local spin = CFrame.new(step.toCenter)
							* CFrame.fromAxisAngle(step.toAxis, drivenAngle)
							* CFrame.new(-step.toCenter)
						local driven = spin * (toOriginal :: CFrame)
						if kIsRuntime then
							-- Lazy per-bridge orientation driver.
							local orient = step.orient
							if orient == nil then
								local attachment = Instance.new("Attachment")
								attachment.Name = "BuildItDrive"
								attachment.Parent = step.toReference
								local align = Instance.new("AlignOrientation")
								align.Mode = Enum.OrientationAlignmentMode.OneAttachment
								align.Attachment0 = attachment
								align.RigidityEnabled = true
								align.Parent = session.joints.folder
								step.orient = align
								orient = align
							end
							(orient :: AlignOrientation).CFrame = driven.Rotation
						else
							ikMoveTo(step.toReference, driven)
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
