--!strict

-- BuildIt bootstrap (StarterPlayerScripts): flat main menu selecting
-- between free build, the set editor, and following a set.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildIt = ReplicatedStorage:WaitForChild("BuildIt")
local Building = BuildIt:WaitForChild("Building")
local BuildController = require(Building:WaitForChild("BuildController"))
local FlatUI = require(Building:WaitForChild("FlatUI"))
local SetData = require(Building:WaitForChild("SetData"))
local SetEditorController = require(Building:WaitForChild("SetEditorController"))
local SetPlayerController = require(Building:WaitForChild("SetPlayerController"))
local SetStore = require(Building:WaitForChild("SetStore"))

-- Where set builds assemble: a part named BuildZone marks the spot
-- (its top face center), else a default clearing.
local function buildOrigin(): CFrame
	local zone = workspace:FindFirstChild("BuildZone")
	if zone ~= nil and zone:IsA("BasePart") then
		local part = zone :: BasePart
		return part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
	end
	return CFrame.new(0, 1, -40)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuildItMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local mActive: { stop: () -> () }? = nil
local mMenu: Frame? = nil

local showMenu: () -> ()

local function clearActive()
	if mActive ~= nil then
		(mActive :: { stop: () -> () }).stop()
		mActive = nil
	end
end

local function startFreeBuild()
	clearActive()
	mActive = BuildController.start()
end

local function startEditor(data: SetData.SetData)
	clearActive()
	mActive = SetEditorController.start({
		data = data,
		origin = buildOrigin(),
		onExit = function()
			clearActive()
			showMenu()
		end,
	})
end

local function startFollower(data: SetData.SetData)
	clearActive()
	mActive = SetPlayerController.start({
		data = data,
		origin = buildOrigin(),
		onExit = function()
			clearActive()
			showMenu()
		end,
	})
end

-- A vertical flat list of set names; onPick receives the loaded set.
local function setList(parent: Instance, y: number, onPick: (SetData.SetData) -> ()): number
	local names = SetStore.list()
	if #names == 0 then
		local empty = FlatUI.label(parent, "(no sets saved)", UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, y))
		empty.TextColor3 = FlatUI.kTextDim
		return y + 26
	end
	for _, name in names do
		FlatUI.button(parent, name, UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 0, y), function()
			local data = SetStore.load(name)
			if data ~= nil then
				onPick(data :: SetData.SetData)
			end
		end)
		y += 30
	end
	return y
end

showMenu = function()
	if mMenu ~= nil then
		(mMenu :: Frame):Destroy()
		mMenu = nil
	end
	local panel = FlatUI.frame(screenGui, UDim2.new(0, 280, 0, 0), UDim2.new(0.5, -140, 0.5, -160), FlatUI.kPanel)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Name = "MainMenu"
	mMenu = panel

	local title = FlatUI.label(panel, "BUILD IT", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 4))
	title.Font = FlatUI.kFontBold
	title.TextSize = 26

	local function closeMenu()
		if mMenu ~= nil then
			(mMenu :: Frame):Destroy()
			mMenu = nil
		end
	end

	local y = 52
	FlatUI.button(panel, "FREE BUILD", UDim2.new(1, -24, 0, 32), UDim2.new(0, 12, 0, y), function()
		closeMenu()
		startFreeBuild()
	end)
	y += 44

	local editorHeader = FlatUI.label(panel, "SET EDITOR", UDim2.new(1, -24, 0, 20), UDim2.new(0, 12, 0, y))
	editorHeader.TextColor3 = FlatUI.kTextDim
	editorHeader.TextXAlignment = Enum.TextXAlignment.Left
	y += 24
	local nameBox = FlatUI.textBox(panel, "new set name", UDim2.new(1, -100, 0, 26), UDim2.new(0, 12, 0, y))
	FlatUI.button(panel, "CREATE", UDim2.new(0, 68, 0, 26), UDim2.new(1, -80, 0, y), function()
		local name = nameBox.Text
		if name ~= "" then
			closeMenu()
			startEditor(SetData.new(name))
		end
	end)
	y += 34
	y = setList(panel, y, function(data)
		closeMenu()
		startEditor(data)
	end)
	y += 12

	local followHeader = FlatUI.label(panel, "FOLLOW SET", UDim2.new(1, -24, 0, 20), UDim2.new(0, 12, 0, y))
	followHeader.TextColor3 = FlatUI.kTextDim
	followHeader.TextXAlignment = Enum.TextXAlignment.Left
	y += 24
	y = setList(panel, y, function(data)
		closeMenu()
		startFollower(data)
	end)

	-- Bottom padding.
	FlatUI.label(panel, "", UDim2.new(1, 0, 0, 8), UDim2.new(0, 0, 0, y))
end

showMenu()
