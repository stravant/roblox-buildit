--!strict

-- Types for the RunTests harness (see runtests.server.lua). Spec modules
-- return a function receiving a TestContext.

export type ExpectResult = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	-- Numbers and Vector3s, with optional epsilon (default 1e-4).
	toBeCloseTo: (expected: any, epsilon: number?) -> (),
}

export type TestContext = {
	test: (name: string, fn: () -> ()) -> (),
	expect: (value: any) -> ExpectResult,
	fail: (message: string) -> (),
	screenshot: (name: string?) -> (),
	log: (message: string) -> (),
	-- Reads a file from the LDraw library directory on disk (path relative
	-- to ldraw/, e.g. "parts/3001.dat"). Served by runtests.py over the
	-- test WebSocket. Returns nil if the file doesn't exist.
	readFile: (path: string) -> string?,
	plugin: Plugin,
}

return {}
