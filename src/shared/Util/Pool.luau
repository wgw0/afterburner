--!strict
-- Object pool. Pass an Instance template (cloned on demand) or a factory function.
-- Released Instances are parented to nil until reused.

local Pool = {}
Pool.__index = Pool

export type Pool<T> = {
	Get: (self: Pool<T>) -> T,
	Release: (self: Pool<T>, obj: T) -> (),
	Available: (self: Pool<T>) -> number,
	Destroy: (self: Pool<T>) -> (),
}

function Pool.new<T>(source: T | () -> T, prewarm: number?, reset: ((T) -> ())?): Pool<T>
	local factory: () -> T
	if type(source) == "function" then
		factory = source :: () -> T
	else
		local template = source :: any
		factory = function()
			return template:Clone()
		end
	end
	local self = setmetatable({ _factory = factory, _reset = reset, _free = {} :: { T } }, Pool)
	for _ = 1, prewarm or 0 do
		table.insert(self._free, factory())
	end
	return (self :: any) :: Pool<T>
end

function Pool:Get(): any
	local obj = table.remove(self._free)
	if obj == nil then
		obj = self._factory()
	end
	return obj
end

function Pool:Release(obj: any)
	if self._reset then
		self._reset(obj)
	end
	if typeof(obj) == "Instance" then
		obj.Parent = nil
	end
	table.insert(self._free, obj)
end

function Pool:Available(): number
	return #self._free
end

function Pool:Destroy()
	for _, obj in self._free do
		if typeof(obj) == "Instance" then
			obj:Destroy()
		end
	end
	table.clear(self._free)
end

return Pool
