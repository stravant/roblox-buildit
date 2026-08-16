--!strict

-- Only run tests in the runtests place to avoid disrupting other open places.
if workspace.Name ~= "runtests" then
	return
end

local CaptureService = game:GetService("CaptureService")
local HttpService = game:GetService("HttpService")

local WS_URL = "ws://localhost:38741"

--------------------------------------------------------------------------------
-- Minimal test framework
--------------------------------------------------------------------------------

type ExpectResult = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeCloseTo: (expected: any, epsilon: number?) -> (),
}

type TestContext = {
	test: (name: string, fn: () -> ()) -> (),
	expect: (value: any) -> ExpectResult,
	fail: (message: string) -> (),
	screenshot: (name: string?) -> (),
	log: (message: string) -> (),
	readFile: (path: string) -> string?,
	plugin: Plugin,
}

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k, _ in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function closeTo(value: any, expected: any, epsilon: number): boolean
	if type(value) == "number" and type(expected) == "number" then
		return math.abs(value - expected) <= epsilon
	elseif typeof(value) == "Vector3" and typeof(expected) == "Vector3" then
		return (value - expected).Magnitude <= epsilon
	end
	return false
end

local function createExpect(value: any): ExpectResult
	return {
		toBe = function(expected: any)
			if value ~= expected then
				error(`Expected {tostring(expected)}, got {tostring(value)}`, 2)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(value, expected) then
				error(`Expected values to be deeply equal`, 2)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`Expected truthy value, got {tostring(value)}`, 2)
			end
		end,
		toBeFalsy = function()
			if value then
				error(`Expected falsy value, got {tostring(value)}`, 2)
			end
		end,
		toBeCloseTo = function(expected: any, epsilon: number?)
			if not closeTo(value, expected, epsilon or 1e-4) then
				error(`Expected {tostring(expected)} (within {epsilon or 1e-4}), got {tostring(value)}`, 2)
			end
		end,
	}
end

--------------------------------------------------------------------------------
-- WebSocket connection, file requests, and test execution
--------------------------------------------------------------------------------

local function sendJson(ws: WebSocketClient, data: { [string]: any })
	ws:Send(HttpService:JSONEncode(data))
end

-- readFile requests: sent to runtests.py, which serves files out of the
-- ldraw/ directory. The requesting thread yields until the matching "file"
-- response arrives (responses are dispatched by the MessageReceived handler,
-- which runs in its own thread, so this cannot deadlock).
local mNextRequestId = 1
local mPendingRequests: { [number]: thread } = {}

local function requestReadFile(ws: WebSocketClient, path: string): string?
	local id = mNextRequestId
	mNextRequestId += 1
	mPendingRequests[id] = coroutine.running()
	sendJson(ws, { type = "readfile", id = id, path = path })
	local found, content = coroutine.yield()
	if found then
		return content
	end
	return nil
end

local function takeScreenshot(ws: WebSocketClient, name: string?)
	local done = false
	local success = false
	local captureOk, captureErr: any = pcall(function()
		CaptureService:TakeScreenshotCaptureAsync(function(result, _screenshotCapture)
			success = result == Enum.ScreenshotCaptureResult.Success
			done = true
		end, { UICaptureMode = Enum.UICaptureMode.All })
	end)
	if not captureOk then
		warn("[RunTests] Screenshot failed: " .. tostring(captureErr))
		sendJson(ws, { type = "screenshot", success = false, name = name })
		return
	end
	-- Wait for the callback (up to 5 seconds)
	local waited = 0
	while not done and waited < 5 do
		task.wait(0.1)
		waited += 0.1
	end
	sendJson(ws, { type = "screenshot", success = success, name = name })
end

local function runTests(ws: WebSocketClient, filter: string)
	local testsFolder = script.Parent.Src
	local testModules = testsFolder:QueryDescendants("ModuleScript")

	local totalPassed = 0
	local totalFailed = 0
	local totalCount = 0

	for _, testModule in testModules do
		local moduleName = testModule.Name
		if moduleName:sub(-5) == ".spec" then
			moduleName = moduleName:sub(1, -6)
		else
			-- Skip modules that don't end with .spec
			continue
		end

		-- Load the test module
		local ok, testFn = pcall(require, testModule)
		if not ok then
			sendJson(ws, {
				type = "result",
				name = moduleName .. " (load)",
				status = "fail",
				error = tostring(testFn),
				duration = 0,
			})
			totalFailed += 1
			totalCount += 1
			continue
		end

		if type(testFn) ~= "function" then
			sendJson(ws, {
				type = "result",
				name = moduleName .. " (load)",
				status = "fail",
				error = "Test module did not return a function",
				duration = 0,
			})
			totalFailed += 1
			totalCount += 1
			continue
		end

		-- Create the test context
		local t: TestContext = {
			test = function() end,
			expect = createExpect,
			fail = function(message: string)
				error(message, 2)
			end,
			screenshot = function(name: string?)
				takeScreenshot(ws, name)
			end,
			-- Forward a line to the test runner's terminal output (print() only reaches
			-- the Studio console, which the runner doesn't read).
			log = function(message: string)
				sendJson(ws, { type = "output", message = message })
			end,
			readFile = function(path: string): string?
				return requestReadFile(ws, path)
			end,
			plugin = plugin,
		}

		-- Collect and run individual tests
		local tests: { { name: string, fn: () -> () } } = {}
		t.test = function(name: string, fn: () -> ())
			table.insert(tests, { name = name, fn = fn })
		end

		-- Call the module function to register tests
		local registerOk, registerErr = pcall(testFn, t)
		if not registerOk then
			sendJson(ws, {
				type = "result",
				name = moduleName .. " (register)",
				status = "fail",
				error = tostring(registerErr),
				duration = 0,
			})
			totalFailed += 1
			totalCount += 1
			continue
		end

		-- Run each registered test
		for _, testEntry in tests do
			local fullName = moduleName .. " > " .. testEntry.name

			-- Apply filter
			if filter ~= "all" and not string.find(fullName, filter, 1, true) then
				continue
			end

			totalCount += 1

			local startTime = os.clock()
			local runOk, runErr: any = pcall(testEntry.fn)
			local duration = math.round((os.clock() - startTime) * 1000)

			if runOk then
				totalPassed += 1
				sendJson(ws, {
					type = "result",
					name = fullName,
					status = "pass",
					duration = duration,
				})
			else
				totalFailed += 1
				sendJson(ws, {
					type = "result",
					name = fullName,
					status = "fail",
					error = tostring(runErr),
					duration = duration,
				})
			end
		end
	end

	sendJson(ws, {
		type = "done",
		passed = totalPassed,
		failed = totalFailed,
		total = totalCount,
	})
end

--------------------------------------------------------------------------------
-- Main: connect to WebSocket server
--------------------------------------------------------------------------------

local ws: WebSocketClient = HttpService:CreateWebStreamClient(
	Enum.WebStreamClientType.WebSocket,
	{ Url = WS_URL }
)

ws.Opened:Connect(function()
	sendJson(ws, { type = "ready" })
end)

ws.MessageReceived:Connect(function(message: string)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, message)
	if not ok then
		warn("[RunTests] Failed to decode message: " .. message)
		return
	end

	if data.type == "run" then
		local filter = data.filter or "all"

		sendJson(ws, { type = "output", message = "Running tests with filter: " .. filter })

		local runOk, runErr: any = pcall(runTests, ws, filter)
		if not runOk then
			sendJson(ws, {
				type = "output",
				message = "Fatal error running tests: " .. tostring(runErr),
			})
			sendJson(ws, {
				type = "done",
				passed = 0,
				failed = 1,
				total = 1,
			})
		end
	elseif data.type == "file" then
		local thread = mPendingRequests[data.id]
		if thread ~= nil then
			mPendingRequests[data.id] = nil
			task.spawn(thread, data.found == true, data.content)
		end
	end
end)

ws.Closed:Connect(function()
	-- Server disconnected, nothing to do
end)
