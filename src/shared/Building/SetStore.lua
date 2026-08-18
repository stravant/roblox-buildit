--!strict

-- Persistence for instruction sets: each set is one StringValue of
-- serialized SetData inside workspace.BuildItSets, so sets save with
-- the place and replicate to players.

local SetData = require(script.Parent.SetData)

local kFolderName = "BuildItSets"

local SetStore = {}

local function folder(create: boolean): Folder?
	local existing = workspace:FindFirstChild(kFolderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	if not create then
		return nil
	end
	local made = Instance.new("Folder")
	made.Name = kFolderName
	made.Parent = workspace
	return made
end

function SetStore.save(data: SetData.SetData)
	local container = folder(true) :: Folder
	local entry = container:FindFirstChild(data.name)
	if entry == nil or not entry:IsA("StringValue") then
		if entry ~= nil then
			entry:Destroy()
		end
		local value = Instance.new("StringValue")
		value.Name = data.name
		value.Parent = container
		entry = value
	end
	(entry :: StringValue).Value = SetData.serialize(data)
end

function SetStore.load(name: string): SetData.SetData?
	local container = folder(false)
	if container == nil then
		return nil
	end
	local entry = (container :: Folder):FindFirstChild(name)
	if entry == nil or not entry:IsA("StringValue") then
		return nil
	end
	return SetData.deserialize((entry :: StringValue).Value)
end

function SetStore.list(): { string }
	local names = {}
	local container = folder(false)
	if container ~= nil then
		for _, child in (container :: Folder):GetChildren() do
			if child:IsA("StringValue") then
				table.insert(names, child.Name)
			end
		end
	end
	table.sort(names)
	return names
end

return SetStore
