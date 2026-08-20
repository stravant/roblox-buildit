--!strict

-- Locates the shared LDraw module folder from either tree shape this
-- importer code runs in:
--   - the importer plugin: src/shared mounts as a sibling "shared"
--     folder (Src.shared.LDraw)
--   - the game place: src/shared mounts as ReplicatedStorage.BuildIt
--     (the runtime PartLibrary bootstrap re-imports parts in-game)

local shared = script.Parent.Parent:FindFirstChild("shared")
if shared ~= nil then
	return (shared :: Instance):WaitForChild("LDraw")
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
return ReplicatedStorage:WaitForChild("BuildIt"):WaitForChild("LDraw")
