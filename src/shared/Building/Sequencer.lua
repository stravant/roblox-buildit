--!strict

-- The set editor's sequencer: a flat strip across the top of the
-- screen. One square cell per step (bags render as labeled dividers,
-- sub-build/attach cells in accent tones, place steps as plain cells),
-- a cursor showing how much of the set is materialized, transport
-- buttons, and the step-structure buttons (+Bag, +Sub-build, Delete).
-- Clicking a cell scrubs the cursor to just after that step.

local FlatUI = require(script.Parent.FlatUI)
local SetData = require(script.Parent.SetData)

local kBarHeight = 64
local kCellSize = 18
local kCellGap = 2
local kBagCellWidth = 34

export type Callbacks = {
	onScrub: (cursor: number) -> (),
	onAddBag: () -> (),
	onAddStep: () -> (),
	onAddSubbuild: () -> (),
	onDelete: () -> (),
	onSave: () -> (),
	onExit: () -> (),
}

export type Sequencer = {
	frame: Frame,
	-- Re-render cells from the current step list + cursor.
	refresh: (steps: { SetData.Step }, cursor: number) -> (),
	setStatus: (text: string) -> (),
	destroy: () -> (),
}

local Sequencer = {}

function Sequencer.create(parent: Instance, setName: string, callbacks: Callbacks): Sequencer
	local mCellConnections: { RBXScriptConnection } = {}

	local frame = FlatUI.frame(
		parent,
		UDim2.new(1, 0, 0, kBarHeight),
		UDim2.new(0, 0, 0, 0),
		FlatUI.kBackground
	)
	frame.Name = "Sequencer"

	-- Row 1: transport + structure buttons + name + status.
	local row = FlatUI.frame(frame, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0), FlatUI.kBackground)
	row.Name = "Controls"
	local x = 4
	local function addButton(text: string, width: number, onClick: () -> ()): TextButton
		local button = FlatUI.button(row, text, UDim2.new(0, width, 0, 24), UDim2.new(0, x, 0, 3), onClick)
		x += width + 4
		return button
	end
	addButton("|<", 28, function()
		callbacks.onScrub(0)
	end)
	local backButton = addButton("<", 28, function() end)
	local forwardButton = addButton(">", 28, function() end)
	local endButton = addButton(">|", 28, function() end)
	x += 8
	addButton("+ BAG", 56, callbacks.onAddBag)
	addButton("NEXT STEP", 84, callbacks.onAddStep)
	addButton("+ SUB-BUILD", 96, callbacks.onAddSubbuild)
	addButton("DELETE", 64, callbacks.onDelete)
	x += 8
	addButton("SAVE", 52, callbacks.onSave)
	addButton("EXIT", 52, callbacks.onExit)

	local nameLabel = FlatUI.label(row, setName, UDim2.new(0, 200, 0, 24), UDim2.new(0, x + 8, 0, 3))
	nameLabel.Font = FlatUI.kFontBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local status = FlatUI.label(row, "", UDim2.new(0, 400, 0, 24), UDim2.new(1, -404, 0, 3))
	status.TextColor3 = FlatUI.kTextDim
	status.TextXAlignment = Enum.TextXAlignment.Right

	-- Row 2: the step cells.
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Steps"
	strip.Size = UDim2.new(1, -8, 0, kCellSize + 10)
	strip.Position = UDim2.new(0, 4, 0, 32)
	strip.BackgroundColor3 = FlatUI.kPanel
	strip.BorderSizePixel = 0
	strip.ScrollBarThickness = 4
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new(0, 0, 0, 0)
	strip.Parent = frame

	local mSteps: { SetData.Step } = {}
	local mCursor = 0

	local function cellColor(step: SetData.Step): Color3
		if step.kind == "bag" then
			return FlatUI.kBackground
		elseif step.kind == "step" then
			return FlatUI.kCell
		elseif step.kind == "subbuild" or step.kind == "attach" then
			return FlatUI.kAccent
		end
		return FlatUI.kCellLight
	end

	local function render()
		for _, connection in mCellConnections do
			connection:Disconnect()
		end
		table.clear(mCellConnections)
		for _, child in strip:GetChildren() do
			child:Destroy()
		end

		local cellX = 4
		-- Position 0 cell: scrub to "before everything".
		local zero = Instance.new("TextButton")
		zero.Name = "Cell0"
		zero.Size = UDim2.new(0, 8, 0, kCellSize)
		zero.Position = UDim2.new(0, cellX, 0, 5)
		zero.BackgroundColor3 = if mCursor == 0 then FlatUI.kAccent else FlatUI.kPanel
		zero.BorderSizePixel = 0
		zero.Text = ""
		table.insert(mCellConnections, zero.MouseButton1Click:Connect(function()
			callbacks.onScrub(0)
		end))
		zero.Parent = strip
		cellX += 8 + kCellGap

		local bagNumber = 0
		local stepNumber = 0
		for index, step in mSteps do
			local width = kCellSize
			local text = ""
			if step.kind == "bag" then
				bagNumber += 1
				stepNumber = 0
				width = kBagCellWidth
				text = `B{bagNumber}`
			elseif step.kind == "step" then
				stepNumber += 1
				width = kBagCellWidth
				text = `S{stepNumber + 1}`
			elseif step.kind == "subbuild" then
				width = kBagCellWidth
				text = "SUB"
			elseif step.kind == "attach" then
				width = kBagCellWidth
				text = "ATT"
			end
			local cell = Instance.new("TextButton")
			cell.Name = `Cell{index}`
			cell.Size = UDim2.new(0, width, 0, kCellSize)
			cell.Position = UDim2.new(0, cellX, 0, 5)
			cell.BackgroundColor3 = cellColor(step)
			cell.BackgroundTransparency = if index <= mCursor then 0 else 0.6
			cell.BorderSizePixel = if index == mCursor then 2 else 0
			cell.BorderColor3 = FlatUI.kText
			cell.Text = text
			cell.TextColor3 = if step.kind == "bag" or step.kind == "step"
				then FlatUI.kText
				else FlatUI.kBackground
			cell.Font = FlatUI.kFontBold
			cell.TextSize = 12
			local stepIndex = index
			table.insert(mCellConnections, cell.MouseButton1Click:Connect(function()
				callbacks.onScrub(stepIndex)
			end))
			cell.Parent = strip
			cellX += width + kCellGap
		end
	end

	backButton.MouseButton1Click:Connect(function()
		callbacks.onScrub(math.max(0, mCursor - 1))
	end)
	forwardButton.MouseButton1Click:Connect(function()
		callbacks.onScrub(math.min(#mSteps, mCursor + 1))
	end)
	endButton.MouseButton1Click:Connect(function()
		callbacks.onScrub(#mSteps)
	end)

	local function refresh(steps: { SetData.Step }, cursor: number)
		mSteps = steps
		mCursor = cursor
		render()
	end

	local function setStatus(text: string)
		status.Text = text
	end

	local function destroy()
		for _, connection in mCellConnections do
			connection:Disconnect()
		end
		table.clear(mCellConnections)
		frame:Destroy()
	end

	render()

	return {
		frame = frame,
		refresh = refresh,
		setStatus = setStatus,
		destroy = destroy,
	}
end

return Sequencer
