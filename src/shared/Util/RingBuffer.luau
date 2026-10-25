--!strict
-- Fixed-capacity buffer. Oldest entries are overwritten when full.
-- at(1) is the newest entry, at(size) the oldest.

local RingBuffer = {}
RingBuffer.__index = RingBuffer

export type RingBuffer<T> = {
	capacity: number,
	push: (self: RingBuffer<T>, item: T) -> (),
	at: (self: RingBuffer<T>, i: number) -> T?,
	size: (self: RingBuffer<T>) -> number,
	clear: (self: RingBuffer<T>) -> (),
	findBracket: (self: RingBuffer<T>, time: number) -> (T?, T?, number),
}

function RingBuffer.new<T>(capacity: number): RingBuffer<T>
	assert(capacity >= 1, "RingBuffer capacity must be at least 1")
	local self = setmetatable({
		capacity = capacity,
		_items = table.create(capacity),
		_head = 0, -- index of the newest item
		_count = 0,
	}, RingBuffer)
	return (self :: any) :: RingBuffer<T>
end

function RingBuffer:push(item: any)
	self._head = self._head % self.capacity + 1
	self._items[self._head] = item
	self._count = math.min(self._count + 1, self.capacity)
end

function RingBuffer:at(i: number): any
	if i < 1 or i > self._count then
		return nil
	end
	local index = (self._head - i) % self.capacity + 1
	return self._items[index]
end

function RingBuffer:size(): number
	return self._count
end

function RingBuffer:clear()
	table.clear(self._items)
	self._head = 0
	self._count = 0
end

-- For entries with a numeric `time` field, pushed in increasing time order.
-- Returns (older, newer, alpha) around `time`. Clamps to the ends of the history.
function RingBuffer:findBracket(time: number): (any, any, number)
	local count = self._count
	if count == 0 then
		return nil, nil, 0
	end
	local newest = self:at(1)
	if time >= newest.time then
		return newest, newest, 0
	end
	for i = 2, count do
		local older = self:at(i)
		if older.time <= time then
			local newer = self:at(i - 1)
			local span = newer.time - older.time
			local alpha = if span > 0 then (time - older.time) / span else 0
			return older, newer, alpha
		end
	end
	local oldest = self:at(count)
	return oldest, oldest, 0
end

return RingBuffer
