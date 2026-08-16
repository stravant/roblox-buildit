--!strict

-- Build test tool bootstrap (StarterPlayerScripts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildIt = ReplicatedStorage:WaitForChild("BuildIt")
local BuildController = require(BuildIt:WaitForChild("Building"):WaitForChild("BuildController"))

BuildController.start()
