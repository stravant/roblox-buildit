--!strict

-- Importer UI: a part number box and an Import button. Talks to
-- ldrawserver.py (ws://localhost:38742) for LDraw file data. Imported
-- parts go into ReplicatedStorage.PartLibrary, the palette source for the
-- in-game build tool.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local LDrawLibrary = require(script.Parent.Parent.shared.LDraw.LDrawLibrary)
local compositeParts = require(script.Parent.Parent.shared.LDraw.compositeParts)
local importPart = require(script.Parent.importPart)
local importComposite = require(script.Parent.importComposite)
local importModel = require(script.Parent.importModel)
local wsFileProvider = require(script.Parent.wsFileProvider)

local kServerUrl = "ws://localhost:38742"

-- The representative set from PARTS_INDEX.md: one part per handled
-- connection category, for playing with every connector type.
local kTestSet = {
	"3001", -- Brick 2x4: stud + socket grids
	"3003", -- Brick 2x2
	"3005", -- Brick 1x1 (known gap: no underside sockets)
	"3020", -- Plate 2x4
	"3623", -- Plate 1x3: pin-derived sockets
	"3700", -- Technic Brick 1x2: peghole
	"3701", -- Technic Brick 1x4: 3 pegholes
	"3704", -- Technic Axle 2
	"32062", -- Technic Axle 2 Notched
	"2780", -- Technic Friction Pin
	"3647", -- Technic Gear 8 Tooth: axle hole
	"30374", -- Bar 4L
	"4085c", -- Plate 1x1 with Clip Vertical
	"3957a", -- Antenna 4H: bar + tube base
	"3184", -- Plate 1x4 with Towball
	"2736", -- Technic Axle Towball
	"3170", -- Plate 1x2 with Ball Joint-8 on Both Ends
	"14418", -- Plate 1x2 with Socket Joint-8
	"6553", -- Axle hub: through axle hole perpendicular to a 1.5 axle
	"3651", -- Pin/bush connector: blind axle hole + pin hole + 2 studs
	"3713", -- Technic Bush
	"2429", -- Hinge Plate 1x4 (imports the full 73983 composite assembly)
	"2712", -- Technic Rotor 3 Blade
	"4019", -- Technic Gear 16 Tooth
	"6135", -- Palm trunk with axle hole
	"4143", -- Technic Gear 14 Tooth Bevel
	"3648a", -- Gear 24 Tooth with 3 axleholes + 4 pin holes
	"2739a", -- Technic Steering Link 6L: two towball sockets
	"6538a", -- Technic Axle Joiner: axle hole + slip surface
	"6539", -- Technic Transmission Driving Ring: slips onto 6538a
	"6573", -- Technic Differential: gear post bar in the cage
}
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
	partNumberBox.PlaceholderText = "Part (3001), range (3001,3010), or set (8880)"
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

	local testSetButton = Instance.new("TextButton")
	testSetButton.LayoutOrder = 3
	testSetButton.Size = UDim2.new(1, 0, 0, 28)
	testSetButton.Text = `Import Test Set ({#kTestSet} parts)`
	testSetButton.TextColor3 = kTextColor
	testSetButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	testSetButton.BorderSizePixel = 0
	testSetButton.Font = Enum.Font.SourceSansBold
	testSetButton.TextSize = 16
	testSetButton.Parent = background

	local reimportButton = Instance.new("TextButton")
	reimportButton.LayoutOrder = 4
	reimportButton.Size = UDim2.new(1, 0, 0, 28)
	reimportButton.Text = "Re-import Selected"
	reimportButton.TextColor3 = kTextColor
	reimportButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	reimportButton.BorderSizePixel = 0
	reimportButton.Font = Enum.Font.SourceSansBold
	reimportButton.TextSize = 16
	reimportButton.Parent = background

	local statusLabel = Instance.new("TextLabel")
	statusLabel.LayoutOrder = 5
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

	local function countCells(unit: Instance, connectorType: string): number
		local count = 0
		for _, child in unit:GetDescendants() do
			if child:IsA("Attachment") and child:GetAttribute("ConnectorType") == connectorType then
				local countX = child:GetAttribute("CountX") or 1
				local countZ = child:GetAttribute("CountZ") or 1
				count += (countX :: number) * (countZ :: number)
			end
		end
		return count
	end

	local function unitSize(unit: Instance): Vector3
		if unit:IsA("Model") then
			return unit:GetExtentsSize()
		end
		return (unit :: BasePart).Size
	end

	-- Routes a ref through composite resolution: hinge halves import as
	-- their full articulated assembly (a Model of jointed segments).
	local function importUnit(ref: string, parentInstance: Instance): (Instance?, string?)
		local resolved = compositeParts.resolve(ref)
		if compositeParts.get(resolved) ~= nil then
			return importComposite(getLibrary(), resolved, parentInstance)
		end
		return importPart(getLibrary(), ref, parentInstance)
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

	local function runImport(numbers: { string })
		mBusy = true
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
		local lastPart: Instance? = nil
		local aborted = false

		for index, partNumber in numbers do
			if isRange then
				setStatus(`Importing {partNumber} ({index}/{#numbers}), {imported} imported so far...`)
			else
				setStatus(`Importing {partNumber}...`)
			end

			local ok, result, errorMessage = pcall(function(): (Instance?, string?)
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
				return importUnit(partNumber .. ".dat", folder)
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

			local part = result :: Instance
			lastPart = part
			imported += 1

			-- Re-import: replace any previous template for this part (use
			-- the template's own PartNumber: composites resolve, so typing
			-- "2429" produces the "73983" assembly template).
			local newPartNumber = part:GetAttribute("PartNumber")
			for _, child in folder:GetChildren() do
				if child ~= part and child:GetAttribute("PartNumber") == newPartNumber then
					child.Parent = nil
				end
			end

			-- Drop a visible copy resting on y=0, flowing left-to-right in rows.
			local copy = part:Clone()
			local size = unitSize(copy)
			if cursorX > 0 and cursorX + size.X > kRowWidth then
				cursorX = 0
				cursorZ += rowDepth + 1
				rowDepth = 0
			end
			copy:PivotTo(CFrame.new(
				baseX + cursorX + size.X / 2,
				size.Y / 2,
				baseZ + cursorZ + size.Z / 2
			))
			cursorX += size.X + 1
			rowDepth = math.max(rowDepth, size.Z)
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
			local part = lastPart :: Instance
			setStatus(
				`Imported {part.Name} ({part:GetAttribute("PartNumber")}) into PartLibrary + workspace copy: `
					.. `{countCells(part, "Stud")} studs, {countCells(part, "Socket")} sockets`
			)
		else
			setStatus(`Error: {lastError}`)
		end
		mBusy = false
	end

	-- Model/set files live in sets/ (e.g. "8880" -> "sets/8880-1.mpd").
	local function findModelPath(text: string): string?
		local candidates = {
			`sets/{text}`,
			`sets/{text}.mpd`,
			`sets/{text}.ldr`,
			`sets/{text}-1.mpd`,
		}
		if text:match("^sets/") ~= nil then
			table.insert(candidates, 1, text)
		end
		local provider = mProvider
		if provider == nil then
			return nil
		end
		for _, candidate in candidates do
			if candidate:match("%.mpd$") ~= nil or candidate:match("%.ldr$") ~= nil then
				if provider.readFile(candidate) ~= nil then
					return candidate
				end
			end
		end
		return nil
	end

	local function runModelImport(modelPath: string)
		mBusy = true
		setStatus(`Loading {modelPath}...`)
		local recording = ChangeHistoryService:TryBeginRecording("Import LDraw model")
		local ok, result, errorMessage = pcall(function()
			return importModel(
				getLibrary(),
				(mProvider :: wsFileProvider.WsFileProvider).readFile,
				modelPath,
				getPartLibraryFolder(),
				setStatus
			)
		end)
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint("Import LDraw model")
		end
		if not ok then
			if mProvider ~= nil then
				mProvider.close()
				mProvider = nil
				mLibrary = nil
			end
			setStatus(`Error: {result}`)
		elseif result == nil then
			setStatus(`Error: {errorMessage}`)
		else
			local summary = result :: importModel.ImportModelResult
			Selection:Set({ summary.folder })
			local skippedText = if #summary.skippedRefs > 0
				then ` Skipped: {table.concat(summary.skippedRefs, ", ")}`
				else ""
			setStatus(
				`Assembled {summary.folder.Name}: {summary.placedCount}/{summary.instanceCount} parts placed, `
					.. `{summary.uniquePartCount} unique ({summary.importedTemplateCount} new templates).{skippedText}`
			)
		end
		mBusy = false
	end

	local function doImport()
		if mBusy then
			return
		end
		local partNumbers, parseError = parsePartNumbers(partNumberBox.Text)
		if partNumbers == nil then
			setStatus(parseError :: string)
			return
		end
		local numbers = partNumbers :: { string }

		-- A single token that matches a file in sets/ imports as a model.
		if #numbers == 1 then
			local probeOk, modelPath = pcall(function()
				getLibrary() -- ensure the provider is connected
				return findModelPath(numbers[1])
			end)
			if probeOk and modelPath ~= nil then
				runModelImport(modelPath :: string)
				return
			end
		end

		runImport(numbers)
	end

	local function doImportTestSet()
		if mBusy then
			return
		end
		runImport(kTestSet)
	end

	-- Re-import the selection with the current importer code: refreshes
	-- the PartLibrary templates AND swaps the selected instances in place
	-- (folders/models are searched, so selecting an assembled set works).
	type SelectedUnit = { instance: Instance, ref: string }

	local function collectSelectedImports(): ({ SelectedUnit }, { string })
		local units: { SelectedUnit } = {}
		local unitsSeen: { [Instance]: boolean } = {}
		local refs: { string } = {}
		local refsSeen: { [string]: boolean } = {}
		local function addUnit(instance: Instance, ref: string)
			if unitsSeen[instance] then
				return
			end
			unitsSeen[instance] = true
			table.insert(units, { instance = instance, ref = ref })
			if not refsSeen[ref] then
				refsSeen[ref] = true
				table.insert(refs, ref)
			end
		end
		local function visit(instance: Instance)
			-- Composite Models are one unit; don't descend into their
			-- segments.
			if instance:IsA("Model") then
				local ref = instance:GetAttribute("LDrawFile")
				if type(ref) == "string" then
					addUnit(instance, ref)
					return
				end
			elseif instance:IsA("BasePart") then
				local ref = instance:GetAttribute("LDrawFile")
				if type(ref) == "string" then
					-- A selected composite segment re-imports its whole
					-- assembly.
					local model = instance:FindFirstAncestorOfClass("Model")
					if model ~= nil and type(model:GetAttribute("LDrawFile")) == "string" then
						addUnit(model, model:GetAttribute("LDrawFile") :: string)
					else
						addUnit(instance, ref)
					end
				end
			end
			for _, child in instance:GetChildren() do
				visit(child)
			end
		end
		for _, instance in Selection:Get() do
			visit(instance)
		end
		return units, refs
	end

	local function doReimport()
		if mBusy then
			return
		end
		mBusy = true
		local selectedUnits, refs = collectSelectedImports()
		if #refs == 0 then
			setStatus("Select imported parts (or folders of them) first.")
			mBusy = false
			return
		end

		local recording = ChangeHistoryService:TryBeginRecording("Re-import LDraw parts")
		local folder = getPartLibraryFolder()
		local imported: { [string]: Instance } = {}
		local failed = 0
		local aborted = false
		for index, ref in refs do
			setStatus(`Re-importing {ref} ({index}/{#refs})...`)
			local ok, result = pcall(function(): Instance?
				return (importUnit(ref, folder))
			end)
			if not ok then
				if mProvider ~= nil then
					mProvider.close()
					mProvider = nil
					mLibrary = nil
				end
				setStatus(`Error: {result}`)
				aborted = true
				break
			elseif result == nil then
				failed += 1
			else
				local template = result :: Instance
				imported[ref] = template
				local newPartNumber = template:GetAttribute("PartNumber")
				for _, child in folder:GetChildren() do
					if child ~= template and child:GetAttribute("PartNumber") == newPartNumber then
						child.Parent = nil
					end
				end
			end
		end

		local replaced = 0
		if not aborted then
			local newSelection: { Instance } = {}
			for _, unit in selectedUnits do
				local old = unit.instance
				local template = imported[unit.ref]
				-- Templates themselves were already replaced above.
				if template == nil or old == template or old.Parent == nil or old.Parent == folder then
					continue
				end
				local clone = template:Clone()
				clone:PivotTo(old:GetPivot())
				if clone:IsA("BasePart") and old:IsA("BasePart") then
					clone.Color = old.Color
					clone.Transparency = old.Transparency
					clone.Anchored = old.Anchored
				end
				clone.Parent = old.Parent
				old.Parent = nil
				table.insert(newSelection, clone)
				replaced += 1
			end
			if #newSelection > 0 then
				Selection:Set(newSelection)
			end
			setStatus(
				`Re-imported {#refs - failed} of {#refs} parts, replaced {replaced} placed instances.`
					.. (if failed > 0 then ` {failed} failed.` else "")
			)
		end

		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint("Re-import LDraw parts")
		end
		mBusy = false
	end

	local buttonConnection = importButton.Activated:Connect(function()
		task.spawn(doImport)
	end)
	local testSetConnection = testSetButton.Activated:Connect(function()
		task.spawn(doImportTestSet)
	end)
	local reimportConnection = reimportButton.Activated:Connect(function()
		task.spawn(doReimport)
	end)

	widget.Destroying:Connect(function()
		buttonConnection:Disconnect()
		testSetConnection:Disconnect()
		reimportConnection:Disconnect()
		if mProvider ~= nil then
			mProvider.close()
			mProvider = nil
		end
	end)
end

return main
