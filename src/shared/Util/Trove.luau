--!strict
-- Owns things that need cleaning up (instances, connections, functions, threads, objects with Destroy).

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _items: { any } }, Trove))

function Trove.new(): Trove
	return setmetatable({ _items = {} }, Trove)
end

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and coroutine.running() ~= item then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Trove.Add<T>(self: Trove, item: T): T
	table.insert(self._items, item)
	return item
end

function Trove.Connect(self: Trove, signal: any, fn: (...any) -> ()): any
	return self:Add(signal:Connect(fn))
end

function Trove.Remove(self: Trove, item: any)
	local index = table.find(self._items, item)
	if index then
		table.remove(self._items, index)
		cleanup(item)
	end
end

function Trove.Extend(self: Trove): Trove
	return self:Add(Trove.new())
end

function Trove.Clean(self: Trove)
	-- Clean newest first, mirroring construction order.
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		cleanup(items[i])
	end
end

Trove.Destroy = Trove.Clean

return Trove
