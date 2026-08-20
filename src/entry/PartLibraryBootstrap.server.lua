--!strict

-- PartLibrary bootstrap (ServerScriptService): imported meshes are
-- DataModel content - session-fixed, replicating to clients, but NOT
-- saved with the place - so the part library is rebuilt from LDraw
-- data IN THE BACKGROUND on game startup. Requires ldrawserver.py
-- (ws://localhost:38742); if it is unreachable the bootstrap warns
-- once and leaves whatever library exists.
--
-- Templates replace their predecessors one by one as they finish, so
-- the palette fills in progressively; the folder itself is created
-- immediately so tools waiting on it can start. Import work is
-- time-budgeted through the pipeline's cooperative yield so the
-- rebuild does not stutter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local importerFolder = ReplicatedStorage:WaitForChild("BuildItImporter")
local sharedFolder = ReplicatedStorage:WaitForChild("BuildIt")
local LDrawFolder = sharedFolder:WaitForChild("LDraw")

local importPart = require(importerFolder:WaitForChild("importPart")) :: any
local importComposite = require(importerFolder:WaitForChild("importComposite")) :: any
local wsFileProvider = require(importerFolder:WaitForChild("wsFileProvider")) :: any
local kTestSet = require(importerFolder:WaitForChild("testSet")) :: { string }
local kTestSetColors = require(importerFolder:WaitForChild("testSetColors")) :: { [string]: Color3 }
local LDrawLibrary = require(LDrawFolder:WaitForChild("LDrawLibrary")) :: any
local compositeParts = require(LDrawFolder:WaitForChild("compositeParts")) :: any

local kServerUrl = "ws://localhost:38742"

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

local function tint(unit: Instance, partNumber: string)
	local color = kTestSetColors[partNumber]
	if color == nil then
		return
	end
	if unit:IsA("BasePart") then
		unit.Color = color
	end
	for _, descendant in unit:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

task.spawn(function()
	local folder = getPartLibraryFolder()

	-- Purge templates whose mesh content died with a previous session:
	-- object/DataModel content does not save, so templates from older
	-- imports reopen as geometry-less grey boxes (SourceType None).
	-- Test-set parts get rebuilt below; stale extras (old model
	-- imports) just go away.
	local purged = 0
	for _, child in folder:GetChildren() do
		local dead = false
		local function check(instance: Instance)
			if
				instance:IsA("MeshPart")
				and instance.MeshContent.SourceType == Enum.ContentSourceType.None
			then
				dead = true
			end
		end
		check(child)
		for _, descendant in child:GetDescendants() do
			check(descendant)
		end
		if dead then
			child:Destroy()
			purged += 1
		end
	end
	if purged > 0 then
		print(`[BuildIt] purged {purged} stale geometry-less templates`)
	end

	local okProvider, provider = pcall(wsFileProvider, kServerUrl)
	if not okProvider then
		warn(`[BuildIt] part library rebuild skipped: LDraw server unreachable ({provider})`)
		return
	end
	local library = LDrawLibrary.new((provider :: any).readFile)

	-- Probe the connection with a file every part needs; bail cleanly
	-- if the server is not actually there.
	if (provider :: any).readFile("LDConfig.ldr") == nil then
		warn(`[BuildIt] part library rebuild skipped: ldrawserver.py not responding on {kServerUrl}`)
		pcall((provider :: any).close)
		return
	end

	print(`[BuildIt] rebuilding part library ({#kTestSet} parts) in the background...`)

	-- Time-budgeted cooperative yield: the import pipeline calls this
	-- inside its heavy loops; past the per-frame budget it waits a
	-- frame, so the rebuild never stutters gameplay.
	local kFrameBudgetSeconds = 0.006
	local budgetStart = os.clock()
	local function backgroundYield()
		if os.clock() - budgetStart > kFrameBudgetSeconds then
			task.wait()
			budgetStart = os.clock()
		end
	end
	local importOptions = { yield = backgroundYield }

	local rebuilt = 0
	local failed = 0
	for index, partNumber in kTestSet do
		local ref = `{partNumber}.dat`
		local resolved = compositeParts.resolve(ref)
		local ok, unit, errorMessage = pcall(function()
			if compositeParts.get(resolved) ~= nil then
				return importComposite(library, resolved, folder, importOptions)
			end
			return importPart(library, ref, folder, importOptions)
		end)
		if ok and unit ~= nil then
			local importedNumber = tostring((unit :: Instance):GetAttribute("PartNumber") or partNumber)
			tint(unit :: Instance, importedNumber)
			-- Replace any previous template for the same part.
			for _, child in folder:GetChildren() do
				if child ~= unit and child:GetAttribute("PartNumber") == importedNumber then
					child:Destroy()
				end
			end
			rebuilt += 1
		else
			failed += 1
			warn(`[BuildIt] import failed for {partNumber}: {if ok then errorMessage else unit}`)
		end
		if index % 10 == 0 then
			print(`[BuildIt] part library rebuild: {index}/{#kTestSet}`)
		end
		task.wait()
	end
	print(
		`[BuildIt] part library rebuilt: {rebuilt}/{#kTestSet} parts`
			.. `{if failed > 0 then ` ({failed} failed)` else ""}`
	)
	pcall((provider :: any).close)
end)
