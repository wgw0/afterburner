--!strict
-- Loads service/controller modules from a folder and runs them in two passes (DEVELOPMENT.md §1.2):
--   Init:  set up state, declare things. Must not yield or call other modules.
--   Start: connect events, start loops. Each Start runs in its own thread so one can't block the rest.
-- Modules may set `Priority` (lower runs first, default 100); ties break on name.
-- Start failures are counted in `Boot.startFailures` so the startup smoke test can see them.

export type Module = {
	Priority: number?,
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

local Boot = {
	startFailures = 0,
}

local function collect(folder: Instance): { { name: string, module: Module } }
	local entries = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if not ok then
				error(`[Boot] Failed to load {child:GetFullName()}: {result}`, 0)
			end
			table.insert(entries, { name = child.Name, module = result :: Module })
		end
	end
	table.sort(entries, function(a, b)
		local pa, pb = a.module.Priority or 100, b.module.Priority or 100
		if pa ~= pb then
			return pa < pb
		end
		return a.name < b.name
	end)
	return entries
end

-- Returns the ordered list of module names that booted.
-- onStartFailure (optional) is called with the module name whenever a Start errors.
function Boot.run(folder: Instance, label: string, onStartFailure: ((string) -> ())?): { string }
	local entries = collect(folder)
	local names = {}

	for _, entry in entries do
		local init = entry.module.Init
		if init then
			local thread = coroutine.create(init)
			local ok, err = coroutine.resume(thread, entry.module)
			if not ok then
				error(`[Boot] {label} {entry.name}:Init failed: {err}\n{debug.traceback(thread)}`, 0)
			end
			if coroutine.status(thread) ~= "dead" then
				error(`[Boot] {label} {entry.name}:Init yielded; move yielding work to Start`, 0)
			end
		end
		table.insert(names, entry.name)
	end

	for _, entry in entries do
		local start = entry.module.Start
		if start then
			task.spawn(function()
				local ok, err = xpcall(start, debug.traceback, entry.module)
				if not ok then
					Boot.startFailures += 1
					warn(`[Boot] {label} {entry.name}:Start failed: {err}`)
					if onStartFailure then
						onStartFailure(entry.name)
					end
				end
			end)
		end
		print(`[Boot] {label} started: {entry.name}`)
	end

	return names
end

return Boot
