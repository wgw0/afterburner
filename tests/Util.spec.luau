--!strict
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Util = ctx.Shared.Util
	local Signal = require(Util.Signal)
	local Trove = require(Util.Trove)
	local Spring = require(Util.Spring)
	local RingBuffer = require(Util.RingBuffer)
	local Pool = require(Util.Pool)

	describe("Signal", function()
		it("passes arguments to every handler", function()
			local s = Signal.new()
			local total = 0
			s:Connect(function(n)
				total += n
			end)
			s:Connect(function(n)
				total += n * 10
			end)
			s:Fire(2)
			expect(total).toBe(22)
		end)
		it("stops calling a disconnected handler", function()
			local s = Signal.new()
			local calls = 0
			local c = s:Connect(function()
				calls += 1
			end)
			s:Fire()
			c:Disconnect()
			s:Fire()
			expect(calls).toBe(1)
			expect(c.Connected).toBe(false)
		end)
		it("Once fires a single time", function()
			local s = Signal.new()
			local calls = 0
			s:Once(function()
				calls += 1
			end)
			s:Fire()
			s:Fire()
			expect(calls).toBe(1)
		end)
		it("a failing handler does not stop the others", function()
			local s = Signal.new()
			local reached = false
			s:Connect(function()
				error("boom")
			end)
			s:Connect(function()
				reached = true
			end)
			s:Fire()
			expect(reached).toBe(true)
		end)
	end)

	describe("Trove", function()
		it("cleans functions, instances and nested troves", function()
			local t = Trove.new()
			local ran = false
			t:Add(function()
				ran = true
			end)
			local part = t:Add(Instance.new("Part"))
			local inner = t:Extend()
			local innerRan = false
			inner:Add(function()
				innerRan = true
			end)
			t:Clean()
			expect(ran).toBe(true)
			expect(innerRan).toBe(true)
			expect(function()
				part.Parent = workspace
			end).toThrow()
		end)
		it("disconnects signal connections", function()
			local t = Trove.new()
			local s = Signal.new()
			local calls = 0
			t:Connect(s, function()
				calls += 1
			end)
			t:Clean()
			s:Fire()
			expect(calls).toBe(0)
		end)
	end)

	describe("Spring", function()
		it("settles on the target (number)", function()
			local sp = Spring.new(0, 12, 1)
			for _ = 1, 120 do
				sp:Update(1 / 60, 10)
			end
			expect(sp.position).toBeCloseTo(10, 0.01)
		end)
		it("settles on the target (Vector3) and stays stable at low frame rates", function()
			local sp = Spring.new(Vector3.zero, 12, 1)
			for _ = 1, 20 do
				sp:Update(0.25, Vector3.new(1, 2, 3))
			end
			expect(sp.position).toBeCloseTo(Vector3.new(1, 2, 3), 0.01)
		end)
		it("a critically damped spring does not overshoot", function()
			local sp = Spring.new(0, 10, 1)
			local maxSeen = 0
			for _ = 1, 300 do
				maxSeen = math.max(maxSeen, sp:Update(1 / 60, 1))
			end
			expect(maxSeen).toBeLessThan(1.0001)
		end)
	end)

	describe("RingBuffer", function()
		it("returns newest first and wraps around", function()
			local rb = RingBuffer.new(3)
			for i = 1, 5 do
				rb:push(i)
			end
			expect(rb:size()).toBe(3)
			expect(rb:at(1)).toBe(5)
			expect(rb:at(3)).toBe(3)
			expect(rb:at(4)).toBe(nil)
		end)
		it("finds the bracket around a time and interpolates", function()
			local rb = RingBuffer.new(10)
			for i = 0, 4 do
				rb:push({ time = i, value = i * 10 })
			end
			local older, newer, alpha = rb:findBracket(2.25)
			expect(older.time).toBe(2)
			expect(newer.time).toBe(3)
			expect(alpha).toBeCloseTo(0.25)
		end)
		it("clamps to the ends of the history", function()
			local rb = RingBuffer.new(4)
			for i = 1, 6 do
				rb:push({ time = i })
			end
			local o1 = rb:findBracket(100)
			expect(o1.time).toBe(6)
			local o2 = rb:findBracket(-5)
			expect(o2.time).toBe(3) -- oldest still stored
		end)
	end)

	describe("Pool", function()
		it("reuses released objects", function()
			local made = 0
			local pool = Pool.new(function()
				made += 1
				return { id = made }
			end, 1)
			local a = pool:Get()
			pool:Release(a)
			local b = pool:Get()
			expect(b).toBe(a)
			expect(made).toBe(1)
		end)
		it("clones Instance templates and unparents on release", function()
			local template = Instance.new("Part")
			local pool = Pool.new(template, 0)
			local p = pool:Get()
			expect(p == template).toBe(false)
			p.Parent = workspace
			pool:Release(p)
			expect(p.Parent).toBe(nil)
			pool:Destroy()
			template:Destroy()
		end)
	end)
end
