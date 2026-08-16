--!strict

-- A FileProvider backed by a WebSocket connection to ldrawserver.py, which
-- serves files out of the ldraw/ directory on disk.
--
-- Protocol: request {type="readfile", id, path} -> response
-- {type="file", id, found, content}.

local HttpService = game:GetService("HttpService")

local kOpenTimeout = 5
local kRequestTimeout = 10

export type WsFileProvider = {
	readFile: (path: string) -> string?,
	close: () -> (),
}

local function wsFileProvider(url: string): WsFileProvider
	local mOpen = false
	local mClosed = false
	local mNextRequestId = 1
	local mPendingRequests: { [number]: thread } = {}
	local mOpenWaiters: { thread } = {}

	local ws: WebSocketClient = HttpService:CreateWebStreamClient(
		Enum.WebStreamClientType.WebSocket,
		{ Url = url }
	)

	local openedConnection = ws.Opened:Connect(function()
		mOpen = true
		for _, thread in mOpenWaiters do
			task.spawn(thread)
		end
		table.clear(mOpenWaiters)
	end)

	local messageConnection = ws.MessageReceived:Connect(function(message: string)
		local ok, data = pcall(HttpService.JSONDecode, HttpService, message)
		if not ok or data.type ~= "file" then
			return
		end
		local thread = mPendingRequests[data.id]
		if thread ~= nil then
			mPendingRequests[data.id] = nil
			task.spawn(thread, data.found == true, data.content)
		end
	end)

	local closedConnection: RBXScriptConnection
	closedConnection = ws.Closed:Connect(function()
		mClosed = true
		mOpen = false
		-- Fail out anything still waiting.
		for id, thread in mPendingRequests do
			mPendingRequests[id] = nil
			task.spawn(thread, false, nil)
		end
		for _, thread in mOpenWaiters do
			task.spawn(thread)
		end
		table.clear(mOpenWaiters)
	end)

	local function waitForOpen(): boolean
		if mOpen then
			return true
		elseif mClosed then
			return false
		end
		local thread = coroutine.running()
		table.insert(mOpenWaiters, thread)
		local timeoutThread = task.delay(kOpenTimeout, function()
			local index = table.find(mOpenWaiters, thread)
			if index ~= nil then
				table.remove(mOpenWaiters, index)
				task.spawn(thread)
			end
		end)
		coroutine.yield()
		task.cancel(timeoutThread)
		return mOpen
	end

	local function readFile(path: string): string?
		if not waitForOpen() then
			error("wsFileProvider: could not connect to " .. url .. " (is ldrawserver.py running?)")
		end
		local id = mNextRequestId
		mNextRequestId += 1
		mPendingRequests[id] = coroutine.running()
		ws:Send(HttpService:JSONEncode({ type = "readfile", id = id, path = path }))
		local timeoutThread = task.delay(kRequestTimeout, function()
			local thread = mPendingRequests[id]
			if thread ~= nil then
				mPendingRequests[id] = nil
				task.spawn(thread, false, nil)
			end
		end)
		local found, content = coroutine.yield()
		task.cancel(timeoutThread)
		if found then
			return content
		end
		return nil
	end

	local function close()
		openedConnection:Disconnect()
		messageConnection:Disconnect()
		closedConnection:Disconnect()
		mClosed = true
		pcall(function()
			ws:Close()
		end)
	end

	return {
		readFile = readFile,
		close = close,
	}
end

return wsFileProvider
