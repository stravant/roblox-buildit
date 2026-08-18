--!strict

-- The build tool's part panel: a scrolling list of the templates in
-- ReplicatedStorage.PartLibrary with ViewportFrame thumbnails. Pressing
-- an entry starts a drag (reported via the onDragStart callback).

local kPanelWidth = 170
local kEntryHeight = 116
local kBackgroundColor = Color3.fromRGB(35, 35, 40)
local kEntryColor = Color3.fromRGB(52, 52, 60)
local kTextColor = Color3.fromRGB(225, 225, 225)

export type PartPalette = {
	frame: Frame,
	destroy: () -> (),
	-- True when the given screen position is over the panel (used to treat
	-- a release over the panel as a cancel).
	containsPoint: (position: Vector2) -> boolean,
}

local PartPalette = {}

local function templateSize(template: Instance): Vector3
	if template:IsA("Model") then
		return template:GetExtentsSize()
	end
	return (template :: BasePart).Size
end

local function makeThumbnail(template: PVInstance, parent: Instance)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -8, 0, 80)
	viewport.Position = UDim2.new(0, 4, 0, 4)
	viewport.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(140, 140, 140)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)

	local clone = template:Clone()
	clone:PivotTo(CFrame.identity)
	clone.Parent = viewport

	local camera = Instance.new("Camera")
	local size = templateSize(template)
	local extent = math.max(size.X, size.Y, size.Z)
	local eye = Vector3.new(1, 0.9, 1).Unit * extent * 1.6 + Vector3.new(0, 0.2, 0)
	camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
	camera.FieldOfView = 50
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	viewport.Parent = parent
end

function PartPalette.create(
	parentGui: Instance,
	templatesFolder: Instance,
	onDragStart: (template: PVInstance) -> ()
): PartPalette
	local mConnections: { RBXScriptConnection } = {}
	local mEntryConnections: { RBXScriptConnection } = {}

	local frame = Instance.new("Frame")
	frame.Name = "PartPalette"
	frame.Size = UDim2.new(0, kPanelWidth, 1, -80)
	frame.Position = UDim2.new(0, 10, 0, 40)
	frame.BackgroundColor3 = kBackgroundColor
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text = "Parts"
	title.TextColor3 = kTextColor
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 18
	title.Parent = frame

	-- Query box: filters entries by substring of name or part number.
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Size = UDim2.new(1, -8, 0, 24)
	search.Position = UDim2.new(0, 4, 0, 28)
	search.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.Text = ""
	search.PlaceholderText = "Search parts..."
	search.PlaceholderColor3 = Color3.fromRGB(140, 140, 145)
	search.TextColor3 = kTextColor
	search.Font = Enum.Font.SourceSans
	search.TextSize = 15
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Entries"
	scroll.Size = UDim2.new(1, 0, 1, -56)
	scroll.Position = UDim2.new(0, 0, 0, 56)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.Name
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll

	local function rebuild()
		for _, connection in mEntryConnections do
			connection:Disconnect()
		end
		table.clear(mEntryConnections)
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		local query = string.lower(search.Text)
		local templates: { PVInstance } = {}
		for _, child in templatesFolder:GetChildren() do
			if child:IsA("BasePart") or child:IsA("Model") then
				if query ~= "" then
					local haystack = string.lower(child.Name)
						.. " "
						.. string.lower(tostring(child:GetAttribute("PartNumber") or ""))
					if string.find(haystack, query, 1, true) == nil then
						continue
					end
				end
				table.insert(templates, child)
			end
		end

		if #templates == 0 then
			local empty = Instance.new("TextLabel")
			empty.Name = "EmptyLabel"
			empty.Size = UDim2.new(1, -12, 0, 80)
			empty.BackgroundTransparency = 1
			empty.TextColor3 = kTextColor
			empty.TextWrapped = true
			empty.Font = Enum.Font.SourceSans
			empty.TextSize = 15
			empty.Text = if query ~= ""
				then "No matches."
				else "No parts.\nImport parts into ReplicatedStorage.PartLibrary with the BuildIt Importer plugin (Edit mode)."
			empty.Parent = scroll
			return
		end

		for _, template in templates do
			local entry = Instance.new("TextButton")
			entry.Name = `Entry_{template.Name}`
			entry.Size = UDim2.new(1, -12, 0, kEntryHeight)
			entry.BackgroundColor3 = kEntryColor
			entry.BorderSizePixel = 0
			entry.Text = ""
			entry.AutoButtonColor = true

			makeThumbnail(template, entry)

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -8, 0, 26)
			label.Position = UDim2.new(0, 4, 0, 86)
			label.BackgroundTransparency = 1
			label.TextColor3 = kTextColor
			label.Font = Enum.Font.SourceSans
			label.TextSize = 15
			label.TextTruncate = Enum.TextTruncate.AtEnd
			local partNumber = template:GetAttribute("PartNumber")
			label.Text = if partNumber ~= nil then `{template.Name} ({partNumber})` else template.Name
			label.Parent = entry

			table.insert(mEntryConnections, entry.MouseButton1Down:Connect(function()
				onDragStart(template)
			end))

			entry.Parent = scroll
		end
	end

	rebuild()
	table.insert(mConnections, search:GetPropertyChangedSignal("Text"):Connect(rebuild))
	table.insert(mConnections, templatesFolder.ChildAdded:Connect(function()
		task.defer(rebuild)
	end))
	table.insert(mConnections, templatesFolder.ChildRemoved:Connect(function()
		task.defer(rebuild)
	end))

	frame.Parent = parentGui

	local function containsPoint(position: Vector2): boolean
		local topLeft = frame.AbsolutePosition
		local size = frame.AbsoluteSize
		return position.X >= topLeft.X
			and position.X <= topLeft.X + size.X
			and position.Y >= topLeft.Y
			and position.Y <= topLeft.Y + size.Y
	end

	local function destroy()
		for _, connection in mConnections do
			connection:Disconnect()
		end
		for _, connection in mEntryConnections do
			connection:Disconnect()
		end
		table.clear(mConnections)
		table.clear(mEntryConnections)
		frame:Destroy()
	end

	return {
		frame = frame,
		destroy = destroy,
		containsPoint = containsPoint,
	}
end

return PartPalette
