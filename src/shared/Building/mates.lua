--!strict

-- Shared mating logic: which connector kinds pair, and whether two
-- connectors at concrete world placements are ENGAGED (mated within
-- epsilon). Both the snap solver (for visualization of mated pairs)
-- and the assembly graph (for drag partitioning / physics planning)
-- use this module, so they can never disagree about what "connected"
-- means.
--
-- mates.check additionally classifies an engaged pair:
--   class:
--     "point" - stud in socket: fully located, separates only by
--               pulling the female off along the stud axis.
--     "mouth" - stud seated in a pin-hole mouth: rotates about the
--               hole axis, separates back out the mouth it entered.
--     "axial" - coaxial rod in bore/clip: rotates about the axis,
--               slides by `slide`, separates along the axis (one way
--               only for blind bores).
--     "ball"  - towball in cup: rotates freely, pops out in any
--               direction.
--     "face"  - magnets / rail-system track ends: face-to-face butt
--               joints, lift apart in any direction.
--   separationsA: unit directions the A-side part can be dragged to
--     separate the pair (nil = any direction separates). The B side
--     separates along the negations.

export type MateConnector = {
	kind: string,
	position: Vector3,
	direction: Vector3,
	length: number?,
	oneSided: boolean?,
	radius: number?,
}

export type MateClass = "point" | "mouth" | "axial" | "ball" | "face"

export type Mate = {
	class: MateClass,
	aKind: string, -- connector kinds on each side (a = the A-side unit)
	bKind: string,
	position: Vector3, -- representative point on the joint (world)
	axis: Vector3, -- joint axis (unit; separation/rotation axis)
	slide: number, -- residual slide freedom along axis (0 = locked)
	separationsA: { Vector3 }?,
}

export type MateRule = "point" | "axial" | "ball" | "mouth"

local mates = {}

-- Point mates: directions must be anti-parallel (a stud points up into a
-- socket that points down at it). Axial mates: |dot| must exceed the
-- threshold (sign-free).
mates.kDirectionDotMax = -0.99
mates.kAxisDotMin = 0.99
-- How close two mated connectors must be under the final placement.
mates.kMatedEpsilon = 0.05

-- Axles fit through pin holes too (loose/rotating, but a valid build
-- connection), bars insert into hollow studs, and bars pass through
-- axle holes (a bevel gear sits on the differential cage's post).
mates.kAxialPartners = {
	TechnicPin = { PegHole = true },
	PegHole = { TechnicPin = true, Axle = true },
	Axle = { AxleHole = true, PegHole = true },
	AxleHole = { Axle = true, Bar = true },
	Bar = { Clip = true, HollowStud = true, BarHole = true, AxleHole = true },
	Clip = { Bar = true },
	HollowStud = { Bar = true },
	BarHole = { Bar = true, WheelPin = true },
	WheelPin = { WheelHole = true, BarHole = true },
	WheelHole = { WheelPin = true },
	SlideRail = { SlideGroove = true },
	SlideGroove = { SlideRail = true },
	MinidollHinge = { MinidollHinge = true },
	SlipAxle = { SlipRing = true },
	SlipRing = { SlipAxle = true },
	HingePin = { HingeSocket = true },
	HingeSocket = { HingePin = true },
	HingeFinger = { HingeFinger = true },
	ClickFinger = { ClickFork = true },
	ClickFork = { ClickFinger = true },
	ArmFinger = { ArmFinger = true },
	TyreBore = { RimSeat = true },
	RimSeat = { TyreBore = true },
} :: { [string]: { [string]: boolean } }

-- Self-mating face-to-face butt joints (weakest links: they lift apart
-- in any direction; physics treats them as rigid while engaged).
local kFaceKinds: { [string]: boolean } = {
	Magnet = true,
	TrackEnd = true,
	CoasterEnd = true,
	MonoEnd = true,
	MonoRampJoint = true,
}

function mates.rule(a: string, b: string): MateRule?
	if (a == "Stud" and b == "Socket") or (a == "Socket" and b == "Stud") then
		return "point"
	elseif kFaceKinds[a] and a == b then
		-- Pole faces / track ends couple coincident and anti-parallel,
		-- same shape as studs.
		return "point"
	elseif (a == "Towball" and b == "TowballSocket") or (a == "TowballSocket" and b == "Towball") then
		return "ball"
	elseif (a == "Stud" and b == "PegHole") or (a == "PegHole" and b == "Stud") then
		return "mouth"
	end
	local partners = mates.kAxialPartners[a]
	if partners ~= nil and partners[b] then
		return "axial"
	end
	return nil
end

-- Size-keyed interfaces (TyreBore/RimSeat) carry a mating radius; a
-- candidate pair only mates when both radii agree within tolerance
-- (0.15 studs = 3 LDU covers the mm rounding in official part names).
local kRadiusTolerance = 0.15

function mates.radiusCompatible(a: { radius: number? }, b: { radius: number? }): boolean
	if a.radius == nil and b.radius == nil then
		return true
	end
	if a.radius == nil or b.radius == nil then
		return false
	end
	return math.abs((a.radius :: number) - (b.radius :: number)) <= kRadiusTolerance
end

-- Both mouths of a hole connector (its segment ends; a bare mouth with
-- no length is its own single mouth).
function mates.holeMouths(position: Vector3, direction: Vector3, length: number?): (Vector3, Vector3)
	local halfSpan = direction * ((length or 0) / 2)
	return position - halfSpan, position + halfSpan
end

-- The dragged element may slide along the axis by half the length
-- difference before it would poke out of / lose its partner.
function mates.slideRange(lengthA: number?, lengthB: number?): number
	return math.abs((lengthA or 0) - (lengthB or 0)) / 2
end

-- Blind female bore: the male seats anywhere from bottomed-out to
-- half-engaged, measured along the female's (mouth-facing) direction.
function mates.oneSidedInterval(maleLength: number, femaleLength: number): (number, number)
	local sMin = (maleLength - femaleLength) / 2
	return sMin, math.max(sMin, maleLength / 2)
end

local kEpsilon = mates.kMatedEpsilon

-- Is the pair (a, b) engaged at their current world placements? Returns
-- the classified Mate, or nil.
function mates.check(a: MateConnector, b: MateConnector): Mate?
	local rule = mates.rule(a.kind, b.kind)
	if rule == nil or not mates.radiusCompatible(a, b) then
		return nil
	end

	if rule == "point" then
		if (a.position - b.position).Magnitude > kEpsilon then
			return nil
		end
		if a.direction:Dot(b.direction) > mates.kDirectionDotMax then
			return nil
		end
		if kFaceKinds[a.kind] then
			return {
				class = "face" :: MateClass,
				aKind = a.kind,
				bKind = b.kind,
				position = a.position,
				axis = a.direction,
				slide = 0,
				separationsA = nil, -- butt joints lift apart any way
			}
		end
		-- The female pulls off along the male's stud direction.
		local maleDirection = if a.kind == "Stud" then a.direction else b.direction
		local aSeparation = if a.kind == "Stud" then -maleDirection else maleDirection
		return {
			class = "point" :: MateClass,
			aKind = a.kind,
			bKind = b.kind,
			position = a.position,
			axis = maleDirection,
			slide = 0,
			separationsA = { aSeparation },
		}
	elseif rule == "ball" then
		if (a.position - b.position).Magnitude > kEpsilon then
			return nil
		end
		return {
			class = "ball" :: MateClass,
			aKind = a.kind,
			bKind = b.kind,
			position = a.position,
			axis = a.direction,
			slide = 0,
			separationsA = nil, -- balls pop out in any pull direction
		}
	elseif rule == "mouth" then
		if math.abs(a.direction:Dot(b.direction)) < mates.kAxisDotMin then
			return nil
		end
		local stud = if a.kind == "Stud" then a else b
		local hole = if a.kind == "Stud" then b else a
		local mouthA, mouthB = mates.holeMouths(hole.position, hole.direction, hole.length)
		if (stud.position - mouthA).Magnitude > kEpsilon and (stud.position - mouthB).Magnitude > kEpsilon then
			return nil
		end
		-- The stud escapes back out the mouth it entered: opposite its
		-- own (inward-pointing) direction.
		local aSeparation = if a.kind == "Stud" then -a.direction else b.direction
		return {
			class = "mouth" :: MateClass,
			aKind = a.kind,
			bKind = b.kind,
			position = stud.position,
			axis = hole.direction,
			slide = 0,
			separationsA = { aSeparation },
		}
	elseif rule == "axial" then
		if math.abs(a.direction:Dot(b.direction)) < mates.kAxisDotMin then
			return nil
		end
		if a.oneSided or b.oneSided then
			local female = if a.oneSided then a else b
			local male = if a.oneSided then b else a
			local femaleLength = female.length or 0
			local maleLength = male.length or 0
			local sMin, sMax = mates.oneSidedInterval(maleLength, femaleLength)
			local delta = male.position - female.position
			local s = delta:Dot(female.direction)
			local perpendicular = (delta - female.direction * s).Magnitude
			if perpendicular > kEpsilon or s < sMin - kEpsilon or s > sMax + kEpsilon then
				return nil
			end
			-- The male escapes out the mouth: along the female's
			-- (mouth-facing) direction.
			local aSeparation = if a.oneSided then -female.direction else female.direction
			return {
				class = "axial" :: MateClass,
				aKind = a.kind,
				bKind = b.kind,
				position = female.position,
				axis = female.direction,
				slide = (sMax - sMin) / 2,
				separationsA = { aSeparation },
			}
		end
		local delta = a.position - b.position
		local along = delta:Dot(b.direction)
		local perpendicular = (delta - b.direction * along).Magnitude
		local slide = mates.slideRange(a.length, b.length)
		if perpendicular > kEpsilon or math.abs(along) > slide + kEpsilon then
			return nil
		end
		return {
			class = "axial" :: MateClass,
			aKind = a.kind,
			bKind = b.kind,
			position = (a.position + b.position) / 2,
			axis = b.direction,
			slide = slide,
			separationsA = { b.direction, -b.direction },
		}
	end
	return nil
end

return mates
