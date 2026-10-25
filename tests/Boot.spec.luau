--!strict
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Boot = require(ctx.Shared.Boot)

	local function makeModule(folder: Instance, name: string, source: string)
		local module = Instance.new("ModuleScript")
		module.Name = name
		module.Source = source
		module.Parent = folder
	end

	describe("Boot.run", function()
		it("orders modules by Priority, then name", function()
			local folder = Instance.new("Folder")
			makeModule(folder, "Zeta", "return { Priority = 1 }")
			makeModule(folder, "Beta", "return {}")
			makeModule(folder, "Alpha", "return {}")
			local names = Boot.run(folder, "Test")
			expect(names).toEqual({ "Zeta", "Alpha", "Beta" })
			folder:Destroy()
		end)

		it("refuses an Init that yields", function()
			local folder = Instance.new("Folder")
			makeModule(folder, "Yielder", "return { Init = function() task.wait() end }")
			expect(function()
				Boot.run(folder, "Test")
			end).toThrow("yielded")
			folder:Destroy()
		end)

		it("reports which module failed to Init", function()
			local folder = Instance.new("Folder")
			makeModule(folder, "Broken", "return { Init = function() error('nope') end }")
			expect(function()
				Boot.run(folder, "Test")
			end).toThrow("Broken:Init failed")
			folder:Destroy()
		end)
	end)
end
