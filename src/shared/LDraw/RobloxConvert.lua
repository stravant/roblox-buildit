--!strict

-- Conversion from LDraw part space to Roblox space.
--
-- LDraw: right-handed, -Y up, +Z "into the screen", units are LDU
-- (1 stud-grid module = 20 LDU, brick height = 24 LDU).
-- Roblox: right-handed, +Y up.
--
-- We map (x, y, z) -> (x, -y, -z): a 180 degree rotation about X, which
-- preserves handedness (and therefore triangle winding). With the default
-- scale of 1/20, one stud-grid module = 1 Roblox stud, so a 1x1 brick is
-- 1 x 1.2 x 1 studs.

local RobloxConvert = {}

RobloxConvert.kDefaultScale = 1 / 20

-- 180 degree rotation about X (its own inverse).
local kRotation = CFrame.fromMatrix(
	Vector3.zero,
	Vector3.new(1, 0, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, -1)
)

function RobloxConvert.position(v: Vector3, scale: number?): Vector3
	local s = scale or RobloxConvert.kDefaultScale
	return Vector3.new(v.X * s, -v.Y * s, -v.Z * s)
end

function RobloxConvert.direction(v: Vector3): Vector3
	return Vector3.new(v.X, -v.Y, -v.Z).Unit
end

-- Converts an LDraw-space frame: each axis vector and the translation map
-- through the coordinate conversion (M * R, NOT the conjugation M * R * M —
-- the frame's axes are semantic directions like "mating direction", so the
-- axes themselves must be converted, e.g. local Y = LDraw up (0,-1,0)
-- becomes Roblox up (0,1,0)).
function RobloxConvert.cframe(transform: CFrame, scale: number?): CFrame
	local converted = kRotation * transform
	return converted.Rotation + RobloxConvert.position(transform.Position, scale)
end

-- Converts an LDraw placement transform for positioning imported part
-- GEOMETRY: the rotation is conjugated (M * R * M) so converted points
-- map correctly: placementCFrame(T) * converted(p) == converted(T * p).
-- Use this for placing part instances of a model; use cframe() for
-- attachment/axis frames.
function RobloxConvert.placementCFrame(transform: CFrame, scale: number?): CFrame
	local converted = kRotation * transform * kRotation
	return converted.Rotation + RobloxConvert.position(transform.Position, scale)
end

-- Orthonormal frame with the given (Roblox-space) up vector; used for
-- attachment CFrames.
function RobloxConvert.frameWithUp(position: Vector3, up: Vector3): CFrame
	local reference = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local right = reference:Cross(up).Unit
	return CFrame.fromMatrix(position, right, up, right:Cross(up))
end

return RobloxConvert
