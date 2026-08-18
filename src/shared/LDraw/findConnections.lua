--!strict

-- Discovers connector primitives in a part's composition tree.
--
-- LDraw parts are built compositionally, and the connectors are shared
-- primitives, which lets us identify connection points without geometry
-- analysis. The primitive table and geometry conventions live in
-- connectorPrimitives.lua; representative parts per category are indexed
-- in PARTS_INDEX.md.
--
-- Emitted connections (part space, LDU):
--   Stud       point, direction = out of the part (toward mate)
--   Tube/Pin   underside anti-stud primitives (see deriveSockets)
--   PegHole    through pin holes: two opposed face mouths paired into one
--              connector at the hole center, length = depth. Unpaired
--              mouths (blind holes) keep the face position, length nil.
--   AxleHole   axle-shaped hole: center + axis + length
--   Axle       axle shaft: center + axis + length (colinear segments
--              merged, so notched axles read as one shaft)
--   TechnicPin pin half: center + axis + length
--   Bar        radius-4 rod: center + axis + length (merged colinear)
--   BarHole    bar-sized bore: an INVERTED radius-4 cylinder (inside-out
--              rendering = female). Technic pins are hollow — their
--              classified primitives get an interior-only scan so the
--              bore through the pin is found.
--   Clip       vertical clip: position + grip axis + length
--   Towball    radius-8 sphere (ball center); TowballSocket: joint8socket
--              cup (grip center). Ball joints mate position-only —
--              direction is a fixed placeholder.
-- For axial types the direction sign is arbitrary (they mate either way).

local Types = require(script.Parent.Types)
local LDrawLibrary = require(script.Parent.LDrawLibrary)
local connectorPrimitives = require(script.Parent.connectorPrimitives)

local kMaxDepth = 64
local kRimOffset = Vector3.new(0, -4, 0)
-- Hollow studs (stud2*) have a bar-sized hole down their axis: the bore
-- spans the stud height (4 LDU) and its floor is flush with the part's
-- top face. The connector sits at the bore center with length = the true
-- bore depth, so the axial slide clamp seats an inserted bar's end
-- exactly flush with the part top.
local kHollowStudOffset = Vector3.new(0, -2, 0)
local kHollowStudGripLength = 4
-- Mirrored subparts can place the same connector twice.
local kPositionEpsilon = 0.5
-- Colinear segment merging: allow small gaps (axle notches interrupt the
-- shaft primitives by ~3 LDU; the slots of friction pins interrupt the
-- bore arcs by up to ~8 LDU).
local kMergeAxisDotMin = 0.99
local kMergePerpendicularMax = 1
local kMergeGapMax = 4
local kMergeGapMaxByType: { [string]: number } = {
	BarHole = 9,
}

local kMergedSegmentTypes: { [string]: boolean } = {
	Axle = true,
	AxleHole = true,
	Bar = true,
	BarHole = true,
	PegHole = true,
	HingePin = true,
	HingeSocket = true,
	ClickFork = true,
}

local function dedupKey(connectionType: string, position: Vector3, direction: Vector3): string
	local function q(value: number): number
		return math.round(value / kPositionEpsilon)
	end
	return string.format(
		"%s:%d,%d,%d:%d,%d,%d",
		connectionType,
		q(position.X), q(position.Y), q(position.Z),
		math.round(direction.X * 100), math.round(direction.Y * 100), math.round(direction.Z * 100)
	)
end

-- `mesh` (optional): with bounds available, anti-stud primitives whose
-- free rim is INTERIOR rather than on the part surface are reclassified —
-- they aren't sockets (authors reuse stud3 as a round post: 6573's
-- differential cage gear post); solid stud3 posts become short Bars.
local function findConnections(
	library: LDrawLibrary.LDrawLibrary,
	rootRef: string,
	mesh: Types.FlatMesh?
): { Types.Connection }?
	local rootFile = library:getFile(rootRef)
	if rootFile == nil then
		return nil
	end

	local mConnections: { Types.Connection } = {}
	local mSeen: { [string]: boolean } = {}

	local function emit(
		connectionType: string,
		primitive: string,
		position: Vector3,
		direction: Vector3,
		transform: CFrame,
		length: number?,
		oneSided: boolean?,
		radius: number?
	)
		local key = dedupKey(connectionType, position, direction)
		if mSeen[key] then
			return
		end
		mSeen[key] = true
		table.insert(mConnections, {
			type = connectionType :: Types.ConnectionType,
			primitive = primitive,
			position = position,
			direction = direction,
			transform = transform,
			length = length,
			oneSided = oneSided,
			radius = radius,
		})
	end

	local function emitSpan(
		connectionType: string,
		primitive: string,
		transform: CFrame,
		localFrom: Vector3,
		localTo: Vector3,
		oneSided: boolean?
	)
		local p0 = transform:PointToWorldSpace(localFrom)
		local p1 = transform:PointToWorldSpace(localTo)
		local axis = p1 - p0
		if axis.Magnitude < 1e-6 then
			return
		end
		emit(connectionType, primitive, (p0 + p1) / 2, axis.Unit, transform, axis.Magnitude, oneSided)
	end

	local function emitSegment(connectionType: string, primitive: string, fullTransform: CFrame)
		emitSpan(connectionType, primitive, fullTransform, Vector3.zero, Vector3.new(0, 1, 0))
	end

	-- Curated per-part additions for hand-built connectors.
	local function applyOverrides(fileName: string, transform: CFrame)
		local overrides = connectorPrimitives.partOverrides[fileName]
		if overrides == nil then
			return
		end
		for _, override in overrides do
			local direction = transform:VectorToWorldSpace(override.direction)
			if direction.Magnitude < 1e-6 then
				continue
			end
			emit(
				override.type,
				fileName,
				transform:PointToWorldSpace(override.position),
				direction.Unit,
				transform,
				override.length,
				override.oneSided
			)
		end
	end

	-- boreOnly: scanning the interior of a classified connector primitive
	-- (Technic pins are hollow): only the inverted bar-bore rule applies.
	local function recurse(file: Types.ParsedFile, transform: CFrame, invert: boolean, depth: number, boreOnly: boolean)
		if depth > kMaxDepth then
			error("findConnections: max recursion depth exceeded (reference cycle?)")
		end
		for _, ref in file.subfiles do
			local fullTransform = transform * ref.transform
			applyOverrides(ref.fileName, fullTransform)
			local childInvert = invert ~= ref.invert
			local primitive = ref.fileName:match("([^/]+)$") or ref.fileName

			-- Inside-out = female geometry (see connectorPrimitives). Note:
			-- only the accumulated INVERTNEXT chain decides material side.
			-- Mirroring (negative determinant) flips WINDING, which BFC
			-- compensates for, but a reflected cylinder is geometrically
			-- still convex — the determinant must NOT participate here.
			local inverted = childInvert
			if inverted and connectorPrimitives.isBoreCylinder(ref.fileName, fullTransform) then
				emitSegment("BarHole", primitive, fullTransform)
				continue
			end
			if inverted and connectorPrimitives.isPinBoreCylinder(ref.fileName, fullTransform) then
				-- Hand-carved pin/axle hole bore (radius 6). Coaxial
				-- fragments merge; a bore coinciding with a paired-mouth
				-- peghole merges into it too.
				emitSegment("PegHole", primitive, fullTransform)
				continue
			end
			if inverted and connectorPrimitives.isTowballSocketCylinder(ref.fileName, fullTransform) then
				-- Cylindrical towball cup (candidates coaxial with a pin/
				-- axle hole get suppressed below: pin holes have r8
				-- channel sections too).
				emitSegment("TowballSocket", primitive, fullTransform)
				continue
			end

			if boreOnly then
				local subFile = library:getFile(ref.fileName)
				if subFile ~= nil then
					recurse(subFile, fullTransform, childInvert, depth + 1, true)
				end
				continue
			end

			local spec = connectorPrimitives.classify(ref.fileName)
			if spec == nil and not inverted and connectorPrimitives.isBarSegment(ref.fileName, fullTransform) then
				spec = { type = "Bar", geometry = "segmentY" }
			end
			if spec == nil and not inverted and connectorPrimitives.isTowballSphere(ref.fileName, fullTransform) then
				spec = { type = "Towball", geometry = "ballAt" }
			end

			if spec ~= nil then
				local geometry = (spec :: connectorPrimitives.Spec).geometry
				if geometry == "mouth" or geometry == "rim" then
					local minusY = -fullTransform.YVector
					if minusY.Magnitude < 1e-6 then
						continue
					end
					local position = if geometry == "mouth"
						then fullTransform.Position
						else fullTransform:PointToWorldSpace(kRimOffset)
					emit(spec.type, primitive, position, minusY.Unit, fullTransform, nil)
					-- Hollow studs additionally accept a bar down the axis
					-- (blind bore: open on the stud tip side only).
					if spec.type == "Stud" and primitive:sub(1, 5) == "stud2" then
						emit(
							"HollowStud",
							primitive,
							fullTransform:PointToWorldSpace(kHollowStudOffset),
							minusY.Unit,
							fullTransform,
							kHollowStudGripLength,
							true
						)
					end
				elseif geometry == "segmentY" or geometry == "segmentYFixed" then
					local localEnd = if geometry == "segmentYFixed"
						then Vector3.new(0, spec.length :: number, 0)
						else Vector3.new(0, 1, 0)
					emitSpan(spec.type, primitive, fullTransform, Vector3.zero, localEnd)
				elseif geometry == "span" then
					local axisName = spec.axis :: string
					local base = (spec.offset :: Vector3?) or Vector3.zero
					local localFrom: Vector3
					local localTo: Vector3
					if axisName == "Z" then
						localFrom = base + Vector3.new(0, 0, spec.spanMin :: number)
						localTo = base + Vector3.new(0, 0, spec.spanMax :: number)
					else
						localFrom = base + Vector3.new(0, spec.spanMin :: number, 0)
						localTo = base + Vector3.new(0, spec.spanMax :: number, 0)
					end
					emitSpan(spec.type, primitive, fullTransform, localFrom, localTo, spec.oneSided)
				elseif geometry == "capNegY" then
					-- Blind-end cap: short oneSided segment from the cap
					-- into the hole (local -Y); merging extends it with the
					-- adjacent hole segments, keeping the open direction.
					emitSpan(
						spec.type,
						primitive,
						fullTransform,
						Vector3.zero,
						Vector3.new(0, -(spec.length :: number), 0),
						true
					)
				elseif geometry == "shaftNegY" then
					local length = spec.length :: number
					local endPoint = fullTransform:PointToWorldSpace(Vector3.new(0, -length, 0))
					local axis = endPoint - fullTransform.Position
					if axis.Magnitude < 1e-6 then
						continue
					end
					local center = (fullTransform.Position + endPoint) / 2
					emit(spec.type, primitive, center, axis.Unit, fullTransform, axis.Magnitude)
				elseif geometry == "axisY" or geometry == "axisZ" or geometry == "axisX" then
					local axis = if geometry == "axisZ"
						then fullTransform.ZVector
						elseif geometry == "axisX" then fullTransform.XVector
						else fullTransform.YVector
					if axis.Magnitude < 1e-6 then
						continue
					end
					local position = if spec.offset ~= nil
						then fullTransform:PointToWorldSpace(spec.offset :: Vector3)
						else fullTransform.Position
					emit(spec.type, primitive, position, axis.Unit, fullTransform, spec.length)
				elseif geometry == "ballAt" then
					-- Direction is meaningless for ball joints; a fixed
					-- placeholder also lets partial sphere sections (which
					-- rotate per section) dedup to one ball.
					emit(spec.type, primitive, fullTransform.Position, Vector3.new(0, -1, 0), fullTransform, nil)
				elseif geometry == "cavity" then
					local cellsX, cellsZ = connectorPrimitives.cavityCells(fullTransform)
					if cellsX ~= nil and cellsZ ~= nil then
						local minusY = -fullTransform.YVector
						if minusY.Magnitude < 1e-6 then
							continue
						end
						local direction = minusY.Unit
						local rightAxis = fullTransform.XVector
						local forwardAxis = fullTransform.ZVector
						if rightAxis.Magnitude < 1e-6 or forwardAxis.Magnitude < 1e-6 then
							continue
						end
						rightAxis = rightAxis.Unit * 20
						forwardAxis = forwardAxis.Unit * 20
						for i = 1, cellsX :: number do
							for j = 1, cellsZ :: number do
								local position = fullTransform.Position
									+ rightAxis * (i - ((cellsX :: number) + 1) / 2)
									+ forwardAxis * (j - ((cellsZ :: number) + 1) / 2)
								emit(spec.type, primitive, position, direction, fullTransform, nil)
							end
						end
					end
					-- Off-size cavities are plain wall shells: nothing to emit,
					-- and box primitives are leaves so there is nothing to
					-- recurse into either.
				end
				-- Technic pins are hollow: scan their interior for the
				-- bar-sized bore running through them.
				if spec.type == "TechnicPin" then
					local subFile = library:getFile(ref.fileName)
					if subFile ~= nil then
						recurse(subFile, fullTransform, childInvert, depth + 1, true)
					end
				end
			else
				local subFile = library:getFile(ref.fileName)
				if subFile ~= nil then
					recurse(subFile, fullTransform, childInvert, depth + 1, false)
				end
			end
		end
	end

	applyOverrides((rootRef:lower():gsub("\\", "/")), CFrame.identity)
	recurse(rootFile, CFrame.identity, false, 1, false)

	-- Tyres and wheel rims: the mating size is encoded in the official
	-- descriptions — "Wheel Rim 6.4 x 8" seats "Tyre 6/ 50 x 8", the
	-- trailing number being the fit diameter in mm. Wheels are authored
	-- centered at the origin with the axle along Z. Combo parts ("...
	-- with Tyre ...") already include their tyre and get neither.
	do
		local kMmToLdu = 2.5
		-- "=" (alias) and "~" (internal) name prefixes still describe the
		-- same physical part; strip them so alias tyres/rims match.
		local description = (rootFile.description or ""):gsub("^[=~]%s*", "")
		if description:find("with Tyre") == nil then
			local rimFit = description:match("^Wheel Rim%s+[%d%.]+%s*x%s*([%d%.]+)")
			local tyreFit = description:match("^Tyre%s+[%d%.]+%s*/%s*[%d%.]+%s*x%s*([%d%.]+)")
			local fitRadius = tonumber(rimFit or tyreFit)
			if fitRadius ~= nil then
				fitRadius = fitRadius * kMmToLdu / 2
				emit(
					if rimFit ~= nil then "RimSeat" else "TyreBore",
					"description",
					Vector3.zero,
					Vector3.new(0, 0, 1),
					CFrame.identity,
					4,
					nil,
					fitRadius
				)
			end
		end
	end

	-- Pair opposed coaxial PegHole mouths into single through-hole
	-- connectors (position = hole center, length = depth).
	do
		local paired: { [number]: boolean } = {}
		for i, a in mConnections do
			-- Only bare mouths pair; segment-style pegholes (connhole)
			-- already carry their length.
			if a.type ~= "PegHole" or a.length ~= nil or paired[i] then
				continue
			end
			for j = i + 1, #mConnections do
				local b = mConnections[j]
				if b.type ~= "PegHole" or b.length ~= nil or paired[j] then
					continue
				end
				if a.direction:Dot(b.direction) > -0.99 then
					continue
				end
				-- b must sit behind a's face (mouths face away from each other).
				local delta = b.position - a.position
				if delta.Magnitude < 1e-3 then
					continue
				end
				if delta.Unit:Dot(a.direction) > -0.99 then
					continue
				end
				paired[j] = true
				a.position = (a.position + b.position) / 2
				a.length = delta.Magnitude
				break
			end
		end
		local filtered = {}
		for i, connection in mConnections do
			if not paired[i] then
				table.insert(filtered, connection)
			end
		end
		mConnections = filtered
	end

	-- Merge colinear touching segments (notched axles, bars built from
	-- multiple cylinders).
	do
		local merged = true
		while merged do
			merged = false
			for i, a in mConnections do
				if not kMergedSegmentTypes[a.type] or a.length == nil then
					continue
				end
				for j = i + 1, #mConnections do
					local b = mConnections[j]
					if b.type ~= a.type or b.length == nil then
						continue
					end
					local dot = a.direction:Dot(b.direction)
					if math.abs(dot) < kMergeAxisDotMin then
						continue
					end
					local delta = b.position - a.position
					local along = delta:Dot(a.direction)
					local perpendicular = (delta - a.direction * along).Magnitude
					if perpendicular > kMergePerpendicularMax then
						continue
					end
					local halfA = (a.length :: number) / 2
					local halfB = (b.length :: number) / 2
					local minB = along - halfB
					local maxB = along + halfB
					local gap = math.max(minB - halfA, -halfA - maxB)
					if gap > (kMergeGapMaxByType[a.type] or kMergeGapMax) then
						continue
					end
					local newMin = math.min(-halfA, minB)
					local newMax = math.max(halfA, maxB)
					a.position += a.direction * ((newMin + newMax) / 2)
					a.length = newMax - newMin
					-- A blind-end cap makes the whole merged hole oneSided,
					-- keeping the cap's open-side direction.
					if b.oneSided and not a.oneSided then
						a.direction = b.direction
						a.oneSided = true
					end
					table.remove(mConnections, j)
					merged = true
					break
				end
				if merged then
					break
				end
			end
		end
	end

	-- Suppress redundant/false inverted-cylinder candidates:
	--  - towball cups that are really the r8 channel sections inside
	--    pin/axle holes (coaxial with a detected hole)
	--  - bar holes that are really a Clip's inner gripping arc (coaxial
	--    with a Clip; the Clip is the semantic connector)
	do
		local kSuppressors: { [string]: { [string]: boolean } } = {
			TowballSocket = { PegHole = true, AxleHole = true },
			BarHole = { Clip = true },
		}
		local filtered = {}
		for _, connection in mConnections do
			local suppressed = false
			local suppressors = kSuppressors[connection.type]
			if suppressors ~= nil and connection.length ~= nil then
				for _, other in mConnections do
					if not suppressors[other.type] then
						continue
					end
					if math.abs(connection.direction:Dot(other.direction)) < 0.99 then
						continue
					end
					local delta = connection.position - other.position
					local along = delta:Dot(other.direction)
					local perpendicular = (delta - other.direction * along).Magnitude
					if
						perpendicular <= 2
						and math.abs(along) <= ((connection.length :: number) + (other.length or 0)) / 2 + 1
					then
						suppressed = true
						break
					end
				end
			end
			if not suppressed then
				table.insert(filtered, connection)
			end
		end
		mConnections = filtered
	end

	-- Bore fragments that never merged into a real bore (stray inverted
	-- fillets, countersink rings) are noise, not connectors.
	do
		local filtered = {}
		for _, connection in mConnections do
			local keep = true
			if connection.type == "BarHole" then
				keep = (connection.length or 0) >= connectorPrimitives.kBarMinLength
			elseif connection.type == "PegHole" and connection.length ~= nil then
				keep = (connection.length :: number) >= 6
			end
			if keep then
				table.insert(filtered, connection)
			end
		end
		mConnections = filtered
	end

	-- Anti-stud primitives must have their free rim ON the part surface
	-- (bottom or side face) to actually grip a stud; interior rims mean
	-- the primitive was reused as plain geometry. Minifig wearables are
	-- exempt: headgear grips the head stud with a tube recessed well
	-- inside the brim (police hat visors dip 8 LDU below the rim).
	-- Wearables: "Minifig ..." parts and any hair piece (minidoll hair
	-- is described "Figure Friends Hair ...").
	local kRootDescription = rootFile.description or ""
	local exemptRecessedRims = kRootDescription:match("^[=~]?%s*Minifig") ~= nil
		or kRootDescription:match("Hair") ~= nil
	if mesh ~= nil then
		local boundsMin = mesh.boundsMin
		local boundsMax = mesh.boundsMax
		local function boundarySupport(direction: Vector3): number
			return (if direction.X > 0 then boundsMax.X else boundsMin.X) * direction.X
				+ (if direction.Y > 0 then boundsMax.Y else boundsMin.Y) * direction.Y
				+ (if direction.Z > 0 then boundsMax.Z else boundsMin.Z) * direction.Z
		end
		local rebuilt: { Types.Connection } = {}
		for _, connection in mConnections do
			if connection.type == "Pin" or connection.type == "Tube" then
				local gap = boundarySupport(connection.direction)
					- connection.position:Dot(connection.direction)
				if gap > 1.5 and not exemptRecessedRims then
					-- Interior rim: a solid stud3 is geometrically a short
					-- r4 bar (the differential's planet gear post); hollow
					-- interior tubes are just geometry.
					if connection.type == "Pin" then
						local base = connection.transform.Position
						local axis = connection.position - base
						if axis.Magnitude > 1e-3 then
							table.insert(rebuilt, {
								type = "Bar" :: Types.ConnectionType,
								primitive = connection.primitive,
								position = (base + connection.position) / 2,
								direction = axis.Unit,
								transform = connection.transform,
								length = axis.Magnitude,
							})
						end
					end
					continue
				end
			end
			table.insert(rebuilt, connection)
		end
		mConnections = rebuilt
	end

	-- Sort for deterministic output.
	table.sort(mConnections, function(lhs, rhs)
		if lhs.position.Y ~= rhs.position.Y then
			return lhs.position.Y < rhs.position.Y
		elseif lhs.position.X ~= rhs.position.X then
			return lhs.position.X < rhs.position.X
		else
			return lhs.position.Z < rhs.position.Z
		end
	end)

	return mConnections
end

return findConnections
