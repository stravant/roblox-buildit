--!strict

-- Instantiates real Roblox physics joints for an assembly:
--   - graph:physicsJoints() welds -> WeldConstraint between the nearest
--     segment parts of the two units.
--   - graph:physicsJoints() constraints -> HingeConstraint /
--     CylindricalConstraint / PrismaticConstraint / BallSocketConstraint,
--     with fresh attachments whose PRIMARY (X) axis is the joint axis.
--   - Composite Models' internal JointPivot pairs -> HingeConstraint
--     (JointType "Hinge") or PrismaticConstraint ("Slider"), likewise
--     axis-wrapped (JointPivot uses UpVector as the articulation axis).
--
-- Joint instances are parented UNDER their Part0 (named BuildItSim*),
-- so copying a set of parts into a test place brings their joints
-- along for repro; session-scoped extras (the drag handle, drive
-- aligns) live in the returned folder. destroy() removes all of it,
-- leaving the assembly untouched. Returns the weld PART pairs so
-- callers can compute part-level rigid groups (e.g. to decide what
-- stays anchored while simulating).

local AssemblyGraph = require(script.Parent.AssemblyGraph)

export type ConstraintInstance = {
	instance: Constraint,
	kind: string,
	part0: BasePart,
	part1: BasePart,
}

export type Applied = {
	folder: Folder,
	-- Part-level weld pairs (for rigid grouping).
	weldedPairs: { { BasePart } },
	-- Part-level articulated pairs (for walking the joint graph).
	constraintPairs: { { BasePart } },
	-- The articulated constraint INSTANCES with metadata: runtime
	-- drives motorize the grabbed group's bearing joint directly
	-- (empirically, non-rigid aligns cannot move a constrained
	-- assembly at all - motoring the joint is the reliable,
	-- IK-like, joint-space way to drive).
	constraintInstances: { ConstraintInstance },
	destroy: () -> (),
}

-- The unit's segment part nearest a world position (a BasePart unit is
-- its own segment).
local function nearestPart(unit: Instance, position: Vector3): BasePart?
	if unit:IsA("BasePart") then
		return unit
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("BasePart") then
			local distance = (descendant.Position - position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = descendant
			end
		end
	end
	return best
end

-- An attachment at `position` whose primary (X) axis is `axis` (Roblox
-- constraints articulate about/along the attachment primary axis).
local function axisAttachment(part: BasePart, position: Vector3, axis: Vector3): Attachment
	local perpendicular = axis:Cross(Vector3.yAxis)
	if perpendicular.Magnitude < 1e-3 then
		perpendicular = axis:Cross(Vector3.xAxis)
	end
	perpendicular = perpendicular.Unit
	local attachment = Instance.new("Attachment")
	attachment.Name = "BuildItJoint"
	-- Parent FIRST: WorldCFrame on an unparented attachment writes the
	-- local CFrame (there is no part frame yet), which would land the
	-- attachment at part.CFrame * worldPose once parented.
	attachment.Parent = part
	attachment.WorldCFrame = CFrame.fromMatrix(position, axis, perpendicular)
	return attachment
end

local function createConstraint(
	kind: string,
	part0: BasePart,
	part1: BasePart,
	position: Vector3,
	axis: Vector3,
	folder: Folder,
	created: { Instance },
	constraintPairs: { { BasePart } },
	constraintInstances: { ConstraintInstance },
	slideLower: number?,
	slideUpper: number?
)
	table.insert(constraintPairs, { part0, part1 })
	local attachment0 = axisAttachment(part0, position, axis)
	local attachment1 = axisAttachment(part1, position, axis)
	table.insert(created, attachment0)
	table.insert(created, attachment1)
	local constraint: Constraint
	if kind == "Hinge" then
		constraint = Instance.new("HingeConstraint")
	elseif kind == "Cylindrical" then
		constraint = Instance.new("CylindricalConstraint")
	elseif kind == "Prismatic" then
		constraint = Instance.new("PrismaticConstraint")
	else
		constraint = Instance.new("BallSocketConstraint")
	end
	constraint.Name = `BuildItSim{kind}`
	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1
	-- Sliding limits (Attachment1's travel along Attachment0's axis;
	-- the attachments start coincident, so limits are relative to the
	-- current pose): an axle through a hole slides only as far as its
	-- poke-out range / keyed stops allow.
	if
		(kind == "Cylindrical" or kind == "Prismatic")
		and slideLower ~= nil
		and slideUpper ~= nil
	then
		local sliding = constraint :: CylindricalConstraint | PrismaticConstraint
		sliding.LimitsEnabled = true
		sliding.LowerLimit = slideLower :: number
		sliding.UpperLimit = slideUpper :: number
	end
	constraint.Parent = part0
	table.insert(created, constraint)
	table.insert(constraintInstances, {
		instance = constraint,
		kind = kind,
		part0 = part0,
		part1 = part1,
	})
end

-- Composite internal joints: pair JointPivot attachments by JointIndex
-- (parent/child roles) and constrain per JointType.
local function applyCompositeJoints(
	unit: Instance,
	folder: Folder,
	created: { Instance },
	constraintPairs: { { BasePart } },
	constraintInstances: { ConstraintInstance }
)
	if not unit:IsA("Model") then
		return
	end
	local parents: { [number]: Attachment } = {}
	local children: { [number]: Attachment } = {}
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name:match("^JointPivot") ~= nil then
			local index = (descendant:GetAttribute("JointIndex") :: number?) or 1
			if descendant:GetAttribute("JointRole") == "child" then
				children[index] = descendant
			else
				parents[index] = descendant
			end
		end
	end
	for index, parentPivot in parents do
		local childPivot = children[index]
		if childPivot == nil then
			continue
		end
		local parentPart = parentPivot.Parent :: BasePart
		local childPart = childPivot.Parent :: BasePart
		local jointType = (parentPivot:GetAttribute("JointType") :: string?) or "Hinge"
		local kind = if jointType == "Slider" then "Prismatic" else "Hinge"
		-- JointPivot uses UpVector (Y) as the articulation axis.
		local pivotWorld = parentPart.CFrame * parentPivot.CFrame
		createConstraint(
			kind,
			parentPart,
			childPart,
			pivotWorld.Position,
			pivotWorld.YVector,
			folder,
			created,
			constraintPairs
		)
	end
end

local function apply(graph: AssemblyGraph.AssemblyGraph, unitFilter: { [any]: boolean }?): Applied
	local folder = Instance.new("Folder")
	folder.Name = "BuildItSimJoints"
	folder.Parent = workspace

	local created: { Instance } = {}
	local weldedPairs: { { BasePart } } = {}
	local constraintPairs: { { BasePart } } = {}
	local constraintInstances: { ConstraintInstance } = {}

	local function included(id: any): boolean
		return unitFilter == nil or unitFilter[id] == true
	end

	local joints = graph:physicsJoints()
	for _, weld in joints.welds do
		if not included(weld.a) or not included(weld.b) then
			continue
		end
		local part0 = nearestPart(weld.a :: Instance, weld.position)
		local part1 = nearestPart(weld.b :: Instance, weld.position)
		if part0 == nil or part1 == nil then
			continue
		end
		local constraint = Instance.new("WeldConstraint")
		constraint.Name = "BuildItSimWeld"
		constraint.Part0 = part0
		constraint.Part1 = part1
		constraint.Parent = part0
		table.insert(created, constraint)
		table.insert(weldedPairs, { part0 :: BasePart, part1 :: BasePart })
	end
	for _, entry in joints.constraints do
		if not included(entry.a) or not included(entry.b) then
			continue
		end
		local part0 = nearestPart(entry.a :: Instance, entry.position)
		local part1 = nearestPart(entry.b :: Instance, entry.position)
		if part0 == nil or part1 == nil then
			continue
		end
		createConstraint(
			entry.kind,
			part0 :: BasePart,
			part1 :: BasePart,
			entry.position,
			entry.axis,
			folder,
			created,
			constraintPairs,
			constraintInstances,
			entry.slideLower,
			entry.slideUpper
		)
	end

	for id in graph.units do
		if included(id) and typeof(id) == "Instance" then
			applyCompositeJoints(id :: Instance, folder, created, constraintPairs, constraintInstances)
		end
	end

	-- Meshing gears can't collide physically (far too many tooth
	-- contacts): free each meshing pair; the pose code drives driven
	-- gears by tooth ratio instead.
	for _, mesh in graph:gearMeshes() do
		if not included(mesh.a) or not included(mesh.b) then
			continue
		end
		local part0 = nearestPart(mesh.a :: Instance, mesh.centerA)
		local part1 = nearestPart(mesh.b :: Instance, mesh.centerB)
		if part0 == nil or part1 == nil then
			continue
		end
		local noCollision = Instance.new("NoCollisionConstraint")
		noCollision.Name = "BuildItSimNoCollide"
		noCollision.Part0 = part0
		noCollision.Part1 = part1
		noCollision.Parent = part0 :: BasePart
		table.insert(created, noCollision)
	end

	local function destroy()
		folder:Destroy()
		for _, instance in created do
			instance:Destroy()
		end
	end

	return {
		folder = folder,
		weldedPairs = weldedPairs,
		constraintPairs = constraintPairs,
		constraintInstances = constraintInstances,
		destroy = destroy,
	}
end

return apply
