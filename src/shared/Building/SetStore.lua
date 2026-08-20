--!strict

-- Client-side set persistence API. The set editor runs on the client,
-- so save/load/list broker through the server's DataStore-backed
-- remote (SetStoreServer: one DataStore key per player holding all of
-- their sets). When the remote is unavailable (offline module tests),
-- an in-memory table stands in so the tools still function - with no
-- persistence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SetData = require(script.Parent.SetData)

local kRemoteName = "BuildItSetStore"
local kRemoteTimeout = 5

local SetStore = {}

local mRemote: RemoteFunction? = nil
local mRemoteResolved = false
local mLocalFallback: { [string]: string } = {}

local function getRemote(): RemoteFunction?
	if not mRemoteResolved then
		mRemoteResolved = true
		local found = ReplicatedStorage:WaitForChild(kRemoteName, kRemoteTimeout)
		if found ~= nil and found:IsA("RemoteFunction") then
			mRemote = found
		else
			warn("[BuildIt] set store remote missing; sets will NOT persist")
		end
	end
	return mRemote
end

local function invoke(action: string, name: string?, payload: string?): any
	local remote = getRemote()
	if remote == nil then
		return nil
	end
	local ok, result = pcall(function()
		return (remote :: RemoteFunction):InvokeServer(action, name, payload)
	end)
	if not ok then
		warn(`[BuildIt] set store {action} failed: {result}`)
		return nil
	end
	return result
end

function SetStore.save(data: SetData.SetData)
	local serialized = SetData.serialize(data)
	if invoke("save", data.name, serialized) == true then
		return
	end
	mLocalFallback[data.name] = serialized
end

function SetStore.load(name: string): SetData.SetData?
	local serialized = invoke("load", name)
	if type(serialized) ~= "string" then
		serialized = mLocalFallback[name]
	end
	if type(serialized) ~= "string" then
		return nil
	end
	return SetData.deserialize(serialized :: string)
end

function SetStore.list(): { string }
	local names = invoke("list")
	if type(names) == "table" then
		return names :: { string }
	end
	local fallbackNames = {}
	for name in mLocalFallback do
		table.insert(fallbackNames, name)
	end
	table.sort(fallbackNames)
	return fallbackNames
end

return SetStore
