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
-- Everything created lives under one folder plus attachments on the
-- parts; destroy() removes all of it, leaving the assembly untouched.
-- Returns the weld PART pairs so callers can compute part-level rigid
-- groups (e.g. to decide what stays anchored while simulating).

local AssemblyGraph = require(script.Parent.AssemblyGraph)

export type ConstraintPair = {
	part0: BasePart,
	part1: BasePart,
	position: Vector3, -- joint position (world, at creation)
	axis: Vector3, -- joint axis (world, at creation)
	kind: string,
}

export type Applied = {
	folder: Folder,
	-- Part-level weld pairs (for rigid grouping).
	weldedPairs: { { BasePart } },
	-- Part-level articulated pairs with their joint geometry (for
	-- walking the joint graph and deciding what a code-driven spin
	-- carries along).
	constraintPairs: { ConstraintPair },
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
	constraintPairs: { ConstraintPair }
)
	table.insert(constraintPairs, {
		part0 = part0,
		part1 = part1,
		position = position,
		axis = axis,
		kind = kind,
	})
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
	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1
	constraint.Parent = folder
end

-- Composite internal joints: pair JointPivot attachments by JointIndex
-- (parent/child roles) and constrain per JointType.
local function applyCompositeJoints(
	unit: Instance,
	folder: Folder,
	created: { Instance },
	constraintPairs: { ConstraintPair }
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
	local constraintPairs: { ConstraintPair } = {}

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
		constraint.Part0 = part0
		constraint.Part1 = part1
		constraint.Parent = folder
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
			constraintPairs
		)
	end

	for id in graph.units do
		if included(id) and typeof(id) == "Instance" then
			applyCompositeJoints(id :: Instance, folder, created, constraintPairs)
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
		noCollision.Part0 = part0
		noCollision.Part1 = part1
		noCollision.Parent = folder
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
		destroy = destroy,
	}
end

return apply
