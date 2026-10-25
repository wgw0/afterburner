--!strict
-- Lightweight signal. Handlers run in their own thread so one error or yield can't break the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

type Handler = { fn: (...any) -> (), connection: Connection }

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} :: { Handler } }, Signal)
	return (self :: any) :: Signal
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local connection = { Connected = true } :: any
	local handler = { fn = fn, connection = connection }
	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, handler)
	return connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Copy so handlers that disconnect during Fire don't skip their neighbours.
	for _, handler in table.clone(self._handlers) do
		if handler.connection.Connected then
			task.spawn(handler.fn, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, handler in self._handlers do
		handler.connection.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
