--!strict

-- Per-player set persistence (ServerScriptService): the set editor
-- runs client-side, so saves are brokered to the server over a
-- RemoteFunction and stored in a DataStore, one key per player
-- holding all of that player's sets ({ name -> serialized SetData }).
--
-- Writes are cached and flushed on a short debounce (DataStores
-- throttle same-key writes), plus immediately on leave/shutdown. If
-- DataStores are unavailable (unpublished place / no API access) the
-- session cache still works and a warn explains that persistence is
-- off.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local kStoreName = "BuildItSets"
local kMaxNameLength = 100
local kMaxPayloadLength = 200_000
local kFlushDelay = 6 -- seconds (same-key write cooldown)

local remote = Instance.new("RemoteFunction")
remote.Name = "BuildItSetStore"
remote.Parent = ReplicatedStorage

local mStore: DataStore? = nil
do
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(kStoreName)
	end)
	if ok then
		mStore = store
	else
		warn(`[BuildIt] DataStore unavailable ({store}); sets will not persist across sessions`)
	end
end

local mSets: { [number]: { [string]: string } } = {}
local mDirty: { [number]: boolean } = {}
local mFlushScheduled: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return `player:{userId}`
end

local function loadPlayer(userId: number): { [string]: string }
	local cached = mSets[userId]
	if cached ~= nil then
		return cached
	end
	local sets: { [string]: string } = {}
	if mStore ~= nil then
		local ok, stored = pcall(function()
			return (mStore :: DataStore):GetAsync(keyFor(userId))
		end)
		if ok and type(stored) == "table" then
			for name, serialized in stored :: { [any]: any } do
				if type(name) == "string" and type(serialized) == "string" then
					sets[name] = serialized
				end
			end
		elseif not ok then
			warn(`[BuildIt] set load failed for {userId}: {stored}`)
		end
	end
	mSets[userId] = sets
	return sets
end

local function flush(userId: number)
	if not mDirty[userId] or mStore == nil then
		return
	end
	local sets = mSets[userId]
	if sets == nil then
		return
	end
	mDirty[userId] = nil
	local ok, problem = pcall(function()
		(mStore :: DataStore):SetAsync(keyFor(userId), sets)
	end)
	if not ok then
		mDirty[userId] = true
		warn(`[BuildIt] set save failed for {userId}: {problem}`)
	end
end

local function scheduleFlush(userId: number)
	mDirty[userId] = true
	if mFlushScheduled[userId] then
		return
	end
	mFlushScheduled[userId] = true
	task.delay(kFlushDelay, function()
		mFlushScheduled[userId] = nil
		flush(userId)
	end)
end

remote.OnServerInvoke = function(player: Player, action: unknown, name: unknown, payload: unknown): any
	local sets = loadPlayer(player.UserId)
	if action == "list" then
		local names = {}
		for setName in sets do
			table.insert(names, setName)
		end
		table.sort(names)
		return names
	elseif action == "load" and type(name) == "string" then
		return sets[name :: string]
	elseif action == "save" and type(name) == "string" and type(payload) == "string" then
		if #(name :: string) == 0 or #(name :: string) > kMaxNameLength then
			return false
		end
		if #(payload :: string) > kMaxPayloadLength then
			warn(`[BuildIt] set "{name}" too large to save ({#(payload :: string)} bytes)`)
			return false
		end
		sets[name :: string] = payload :: string
		scheduleFlush(player.UserId)
		return true
	elseif action == "delete" and type(name) == "string" then
		sets[name :: string] = nil
		scheduleFlush(player.UserId)
		return true
	end
	return nil
end

Players.PlayerRemoving:Connect(function(player)
	flush(player.UserId)
	mSets[player.UserId] = nil
end)

game:BindToClose(function()
	for userId in mDirty do
		flush(userId)
	end
end)
