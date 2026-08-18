--!strict

-- Tooth-phase correction for a gear mesh: the signed rotation (about
-- the common axis) to apply to the DRIVEN gear so its teeth interleave
-- with the driver's at the contact line.
--
-- Derivation (axis A, contact direction c from driver center to driven
-- center, all angles CCW about A): each gear's tooth reference is its
-- mounting bore's secondary axis (cardinal-toothed gears carry a tooth
-- along it), and fractional phase f = (angle from reference to the
-- contact direction) * teeth / 2pi mod 1. Projected onto the shared
-- tangent line at the contact, the driver's nearest tooth center sits
-- at fraction -fFrom of a pitch and the driven gear's at +fTo, so
-- interleaving (teeth into gaps, half a pitch apart) requires
--     fTo == (0.5 - fFrom) mod 1.
-- Rotating the driven gear CCW by beta DECREASES fTo by
-- beta * teeth / 2pi, so the correction is the NEGATED delta (getting
-- this sign wrong doubles the mesh error on every grab instead of
-- fixing it - the gears twitch on every click).
--
-- Returns 0 when either tooth reference is missing (legacy imports) or
-- degenerate (reference parallel to the axis).

-- Fractional tooth phase [0, 1) of a gear at the contact direction:
-- 0 = tooth centered on the contact line, 0.5 = gap centered.
local function toothPhase(reference: Vector3?, axis: Vector3, contact: Vector3, teeth: number): number?
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

local function gearMeshPhase(
	fromSecondary: Vector3?,
	toSecondary: Vector3?,
	axis: Vector3, -- common axis, both rotations expressed about it
	fromCenter: Vector3,
	toCenter: Vector3,
	fromTeeth: number,
	toTeeth: number
): number
	local contact = toCenter - fromCenter
	contact -= axis * contact:Dot(axis)
	if contact.Magnitude < 1e-3 then
		return 0
	end
	contact = contact.Unit
	local fromPhase = toothPhase(fromSecondary, axis, contact, fromTeeth)
	local toPhase = toothPhase(toSecondary, axis, -contact, toTeeth)
	if fromPhase == nil or toPhase == nil then
		return 0
	end
	local targetFraction = (0.5 - (fromPhase :: number)) % 1
	local deltaFraction = (targetFraction - (toPhase :: number) + 0.5) % 1 - 0.5
	return -deltaFraction * 2 * math.pi / toTeeth
end

return gearMeshPhase
