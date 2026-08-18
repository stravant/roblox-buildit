--!strict

-- Flat UI kit for the in-game set tools: solid colors, square corners,
-- no gradients, no UICorner anywhere. One accent color for the active
-- element; everything else greys.

local FlatUI = {}

FlatUI.kBackground = Color3.fromRGB(24, 24, 26)
FlatUI.kPanel = Color3.fromRGB(38, 38, 42)
FlatUI.kCell = Color3.fromRGB(58, 58, 64)
FlatUI.kCellLight = Color3.fromRGB(120, 120, 128)
FlatUI.kAccent = Color3.fromRGB(247, 171, 0)
FlatUI.kText = Color3.fromRGB(235, 235, 235)
FlatUI.kTextDim = Color3.fromRGB(150, 150, 155)
FlatUI.kFont = Enum.Font.SourceSans
FlatUI.kFontBold = Enum.Font.SourceSansBold

function FlatUI.frame(parent: Instance, size: UDim2, position: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color or FlatUI.kPanel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function FlatUI.label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = FlatUI.kText
	label.Font = FlatUI.kFont
	label.TextSize = 16
	label.Parent = parent
	return label
end

function FlatUI.button(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	onClick: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = FlatUI.kCell
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = FlatUI.kText
	button.Font = FlatUI.kFontBold
	button.TextSize = 16
	button.MouseButton1Click:Connect(onClick)
	button.Parent = parent
	return button
end

function FlatUI.textBox(parent: Instance, placeholder: string, size: UDim2, position: UDim2): TextBox
	local box = Instance.new("TextBox")
	box.Size = size
	box.Position = position
	box.BackgroundColor3 = FlatUI.kBackground
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = FlatUI.kTextDim
	box.TextColor3 = FlatUI.kText
	box.Font = FlatUI.kFont
	box.TextSize = 16
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = parent
	return box
end

return FlatUI
