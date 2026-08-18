--!strict

-- Hardcoded gear data, keyed by part number. LEGO spur gears share a
-- module where the PITCH RADIUS in studs = teeth / 16 (8t = 0.5, 24t =
-- 1.5, 40t = 2.5), which is what makes mixed gear trains mesh on the
-- stud/half-stud grid. Gears can't be simulated physically (far too
-- many tooth contacts) — instead meshing pairs get a
-- NoCollisionConstraint and the pose code drives driven gears from the
-- driver by tooth ratio (see AssemblyGraph.gearMeshes and
-- RotateController).
--
-- v1 covers parallel-axis meshing (spur and double-bevel); plain bevel
-- and crown gears mesh on perpendicular axes and are listed for tooth
-- data but not yet mesh-detected.

export type GearInfo = {
	teeth: number,
}

return {
	-- Spur gears
	["3647"] = { teeth = 8 },
	["4019"] = { teeth = 16 },
	["94925"] = { teeth = 16 },
	["3648"] = { teeth = 24 },
	["3648a"] = { teeth = 24 },
	["3648b"] = { teeth = 24 },
	["24505"] = { teeth = 24 },
	["3649"] = { teeth = 40 },
	["10928"] = { teeth = 8 },
	["6542"] = { teeth = 16 }, -- clutch gear (freewheel not modeled)
	["6542a"] = { teeth = 16 },
	["6542b"] = { teeth = 16 },
	["18946"] = { teeth = 20 }, -- bike gear ring? verify when used
	-- Double bevel (mesh parallel like spurs)
	["32270"] = { teeth = 12 },
	["32269"] = { teeth = 20 },
	["32498"] = { teeth = 36 },
	["65413"] = { teeth = 28 },
	-- Plain bevel / crown (perpendicular mesh - listed, not detected yet)
	["6589"] = { teeth = 12 },
	["32198"] = { teeth = 20 },
	["4143"] = { teeth = 14 },
	["3650"] = { teeth = 24 },
	["3650a"] = { teeth = 24 },
	["3650b"] = { teeth = 24 },
} :: { [string]: GearInfo }
