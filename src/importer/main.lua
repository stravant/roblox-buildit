--!strict

-- Importer UI: a part number box and an Import button. Talks to
-- ldrawserver.py (ws://localhost:38742) for LDraw file data. Imported
-- parts go into ReplicatedStorage.PartLibrary, the palette source for the
-- in-game build tool.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
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
	partNumberBox.PlaceholderText = "Part number (3001) or range (3001,3010)"
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

	local kMaxRangeCount = 200
	local kRowWidth = 40 -- studs per row of workspace copies

	local function countCells(part: MeshPart, connectorType: string): number
		local count = 0
		for _, child in part:GetChildren() do
			if child:IsA("Attachment") and child:GetAttribute("ConnectorType") == connectorType then
				local countX = child:GetAttribute("CountX") or 1
				local countZ = child:GetAttribute("CountZ") or 1
				count += (countX :: number) * (countZ :: number)
			end
		end
		return count
	end

	-- "3001" imports one part; "3001,3010" imports every existing part in
	-- the numeric range (skipping gaps and ~moved/=alias/_shortcut stubs).
	local function parsePartNumbers(text: string): ({ string }?, string?)
		local minText, maxText = text:match("^%s*(%d+)%s*,%s*(%d+)%s*$")
		if minText ~= nil then
			local rangeMin = tonumber(minText) :: number
			local rangeMax = tonumber(maxText) :: number
			if rangeMax < rangeMin then
				rangeMin, rangeMax = rangeMax, rangeMin
			end
			if rangeMax - rangeMin + 1 > kMaxRangeCount then
				return nil, `Range too large (max {kMaxRangeCount} parts).`
			end
			local numbers = {}
			for n = rangeMin, rangeMax do
				table.insert(numbers, tostring(n))
			end
			return numbers, nil
		end
		local single = text:gsub("%s", "")
		if single == "" then
			return nil, "Enter a part number first."
		end
		return { single }, nil
	end

	local function doImport()
		if mBusy then
			return
		end
		mBusy = true
		local partNumbers, parseError = parsePartNumbers(partNumberBox.Text)
		if partNumbers == nil then
			setStatus(parseError :: string)
			mBusy = false
			return
		end
		local numbers = partNumbers :: { string }
		local isRange = #numbers > 1

		local recording = ChangeHistoryService:TryBeginRecording("Import LDraw parts")
		local folder = getPartLibraryFolder()

		-- Workspace copies lay out in rows on the ground in front of the camera.
		local camera = workspace.CurrentCamera
		local ahead = camera.CFrame.Position + camera.CFrame.LookVector * 20
		local baseX = math.round(ahead.X)
		local baseZ = math.round(ahead.Z)
		local cursorX = 0
		local cursorZ = 0
		local rowDepth = 0

		local imported = 0
		local skipped = 0
		local copies: { Instance } = {}
		local lastError: string? = nil
		local lastPart: MeshPart? = nil
		local aborted = false

		for index, partNumber in numbers do
			if isRange then
				setStatus(`Importing {partNumber} ({index}/{#numbers}), {imported} imported so far...`)
			else
				setStatus(`Importing {partNumber}...`)
			end

			local ok, result, errorMessage = pcall(function(): (MeshPart?, string?)
				if isRange then
					-- Skip alias/moved/shortcut stubs; only import real parts.
					local file = getLibrary():getFile(partNumber .. ".dat")
					if file == nil then
						return nil, "no such part"
					end
					local description = file.description
					if description ~= nil then
						local prefix = description:sub(1, 1)
						if prefix == "~" or prefix == "=" or prefix == "_" then
							return nil, "alias/stub"
						end
					end
				end
				return importPart(getLibrary(), partNumber .. ".dat", folder)
			end)
			if not ok then
				-- Hard failure (e.g. lost server connection): abort the batch
				-- and force a fresh provider on the next try.
				if mProvider ~= nil then
					mProvider.close()
					mProvider = nil
					mLibrary = nil
				end
				lastError = tostring(result)
				aborted = true
				break
			elseif result == nil then
				skipped += 1
				lastError = errorMessage
				continue
			end

			local part = result :: MeshPart
			lastPart = part
			imported += 1

			-- Re-import: replace any previous template for this part.
			for _, child in folder:GetChildren() do
				if child ~= part and child:GetAttribute("PartNumber") == partNumber then
					child.Parent = nil
				end
			end

			-- Drop a visible copy resting on y=0, flowing left-to-right in rows.
			local copy = part:Clone()
			if cursorX > 0 and cursorX + copy.Size.X > kRowWidth then
				cursorX = 0
				cursorZ += rowDepth + 1
				rowDepth = 0
			end
			copy.CFrame = CFrame.new(
				baseX + cursorX + copy.Size.X / 2,
				copy.Size.Y / 2,
				baseZ + cursorZ + copy.Size.Z / 2
			)
			cursorX += copy.Size.X + 1
			rowDepth = math.max(rowDepth, copy.Size.Z)
			copy.Parent = workspace
			table.insert(copies, copy)
		end

		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint("Import LDraw parts")
		end
		if #copies > 0 then
			Selection:Set(copies)
		end

		if aborted then
			setStatus(`Error: {lastError}`)
		elseif isRange then
			setStatus(`Imported {imported} of {#numbers} parts ({skipped} skipped).`)
		elseif lastPart ~= nil then
			local part = lastPart :: MeshPart
			setStatus(
				`Imported {part.Name} ({part:GetAttribute("PartNumber")}) into PartLibrary + workspace copy: `
					.. `{countCells(part, "Stud")} studs, {countCells(part, "Socket")} sockets`
			)
		else
			setStatus(`Error: {lastError}`)
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
