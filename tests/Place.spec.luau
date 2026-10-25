--!strict
-- Checks the live place (not the sandbox): the synced code is where it should be, and nothing
-- unexpected is hiding in it. Stray scripts usually mean a Toolbox model brought a backdoor in,
-- or a Studio edit was made outside Rojo and will be lost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect

	local managedRoots: { Instance? } = {
		ReplicatedStorage:FindFirstChild("Shared"),
		ServerScriptService:FindFirstChild("Server"),
		ServerStorage:FindFirstChild("Tests"),
		ServerStorage:FindFirstChild("TestSandbox"), -- the runner's own temporary copy
		StarterPlayer.StarterPlayerScripts:FindFirstChild("Client"),
	}

	local function isManaged(instance: Instance): boolean
		for _, root in managedRoots do
			if root and (instance == root or instance:IsDescendantOf(root)) then
				return true
			end
		end
		-- Escape hatch for assets that legitimately carry scripts (set on the asset's root).
		local ancestor: Instance? = instance
		while ancestor do
			if ancestor:GetAttribute("AllowScripts") == true then
				return true
			end
			ancestor = ancestor.Parent
		end
		return false
	end

	describe("synced code", function()
		it("all Rojo roots exist", function()
			expect(ReplicatedStorage:FindFirstChild("Shared") ~= nil).toBe(true)
			expect(ServerScriptService:FindFirstChild("Server") ~= nil).toBe(true)
			expect(StarterPlayer.StarterPlayerScripts:FindFirstChild("Client") ~= nil).toBe(true)
		end)

		it("entry points have the right classes", function()
			local serverMain = ServerScriptService.Server:FindFirstChild("Main")
			local clientMain = StarterPlayer.StarterPlayerScripts.Client:FindFirstChild("Main")
			expect(serverMain and serverMain.ClassName).toBe("Script")
			expect(clientMain and clientMain.ClassName).toBe("LocalScript")
		end)

		it("no two siblings share a name (require-by-name would break)", function()
			for _, root in managedRoots do
				if root then
					for _, node in { root, table.unpack(root:GetDescendants()) } do
						local seen: { [string]: boolean } = {}
						for _, child in node:GetChildren() do
							if seen[child.Name] then
								error(`duplicate "{child.Name}" under {node:GetFullName()}`, 0)
							end
							seen[child.Name] = true
						end
					end
				end
			end
		end)
	end)

	describe("place hygiene", function()
		it("no scripts outside the Rojo-managed folders", function()
			local stray = {}
			local containers = {
				workspace,
				ReplicatedStorage,
				game:GetService("ReplicatedFirst"),
				ServerScriptService,
				ServerStorage,
				game:GetService("StarterGui"),
				game:GetService("StarterPack"),
				StarterPlayer,
				game:GetService("Lighting"),
				game:GetService("SoundService"),
				game:GetService("Teams"),
			}
			for _, container in containers do
				for _, d in container:GetDescendants() do
					if d:IsA("LuaSourceContainer") and not isManaged(d) then
						table.insert(stray, d:GetFullName())
					end
				end
			end
			if #stray > 0 then
				error("stray scripts:\n      " .. table.concat(stray, "\n      "), 0)
			end
		end)

		it("the test range is present", function()
			expect(workspace:FindFirstChild("TestRange") ~= nil).toBe(true)
		end)
	end)
end
