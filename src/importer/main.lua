--!strict

-- Importer UI: a part number box and an Import button. Talks to
-- ldrawserver.py (ws://localhost:38742) for LDraw file data. Imported
-- parts go into ReplicatedStorage.PartLibrary, the palette source for the
-- in-game build tool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local importPart = require(script.Parent.importPart)
local wsFileProvider = require(script.Parent.wsFileProvider)

local kServerUrl = "ws://localhost:38742"
local kBackgroundColor = Color3.fromRGB(46, 46, 46)
local kTextColor = Color3.fromRGB(220, 220, 220)

local function main(widget: DockWidgetPluginGui)
	local mProvider: wsFileProvider.WsFileProvider? = nil
	local mLibrary: LDrawLibrary.LDrawLibrary? = nil
	local mBusy = false

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = kBackgroundColor
	background.BorderSizePixel = 0
	background.Parent = widget

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = background

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = background

	local partNumberBox = Instance.new("TextBox")
	partNumberBox.LayoutOrder = 1
	partNumberBox.Size = UDim2.new(1, 0, 0, 28)
	partNumberBox.PlaceholderText = "Part number (e.g. 3001)"
	partNumberBox.Text = "3001"
	partNumberBox.ClearTextOnFocus = false
	partNumberBox.TextColor3 = kTextColor
	partNumberBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	partNumberBox.BorderSizePixel = 0
	partNumberBox.Font = Enum.Font.Code
	partNumberBox.TextSize = 16
	partNumberBox.Parent = background

	local importButton = Instance.new("TextButton")
	importButton.LayoutOrder = 2
	importButton.Size = UDim2.new(1, 0, 0, 28)
	importButton.Text = "Import"
	importButton.TextColor3 = kTextColor
	importButton.BackgroundColor3 = Color3.fromRGB(0, 90, 158)
	importButton.BorderSizePixel = 0
	importButton.Font = Enum.Font.SourceSansBold
	importButton.TextSize = 16
	importButton.Parent = background

	local statusLabel = Instance.new("TextLabel")
	statusLabel.LayoutOrder = 3
	statusLabel.Size = UDim2.new(1, 0, 0, 80)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = kTextColor
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.TextSize = 14
	statusLabel.Text = `Requires ldrawserver.py running ({kServerUrl})`
	statusLabel.Parent = background

	local function setStatus(text: string)
		statusLabel.Text = text
	end

	local function getPartLibraryFolder(): Folder
		local existing = ReplicatedStorage:FindFirstChild("PartLibrary")
		if existing ~= nil and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = "PartLibrary"
		folder.Parent = ReplicatedStorage
		return folder
	end

	local function getLibrary(): LDrawLibrary.LDrawLibrary
		if mLibrary == nil then
			local provider = wsFileProvider(kServerUrl)
			mProvider = provider
			mLibrary = LDrawLibrary.new(provider.readFile)
		end
		return mLibrary :: LDrawLibrary.LDrawLibrary
	end

	local function doImport()
		if mBusy then
			return
		end
		mBusy = true
		local partNumber = partNumberBox.Text:gsub("%s", "")
		if partNumber == "" then
			setStatus("Enter a part number first.")
			mBusy = false
			return
		end
		setStatus(`Importing {partNumber}...`)

		local ok, result, errorMessage = pcall(function()
			return importPart(getLibrary(), partNumber .. ".dat", getPartLibraryFolder())
		end)
		if not ok then
			-- Connection failure: force a fresh provider on the next try.
			if mProvider ~= nil then
				mProvider.close()
				mProvider = nil
				mLibrary = nil
			end
			setStatus(`Error: {result}`)
		elseif result == nil then
			setStatus(`Error: {errorMessage}`)
		else
			local part = result :: MeshPart
			Selection:Set({ part })
			local studs = 0
			local sockets = 0
			for _, child in part:GetChildren() do
				if child:IsA("Attachment") then
					local connectorType = child:GetAttribute("ConnectorType")
					if connectorType == "Stud" then
						studs += 1
					elseif connectorType == "Socket" then
						sockets += 1
					end
				end
			end
			setStatus(
				`Imported {part.Name} ({part:GetAttribute("Description")}) into ReplicatedStorage.PartLibrary: {studs} studs, {sockets} sockets`
			)
		end
		mBusy = false
	end

	local buttonConnection = importButton.Activated:Connect(function()
		task.spawn(doImport)
	end)

	widget.Destroying:Connect(function()
		buttonConnection:Disconnect()
		if mProvider ~= nil then
			mProvider.close()
			mProvider = nil
		end
	end)
end

return main
