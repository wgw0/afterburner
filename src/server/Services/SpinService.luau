--!strict
-- The free spin (Shared/Spin, retention). Every TICK seconds each player with a loaded save gets that much
-- play time toward their next spin. Two player attributes tell the client what to show:
--   SpinsBanked: spins ready to use;
--   SpinNextAt: the server time (workspace:GetServerTimeNow()) the next spin is earned if they stay, or 0
--     while the bank is full. Refreshed whenever a spin is earned or used, so the client's countdown can't
--     drift from the server's.
-- SpinWheel rolls with the server's random generator and grants the prize in the same save update.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Spin = require(Shared.Spin)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)

local SpinService = {
	Priority = 56,
}

local TICK = 5 -- seconds between play-time updates
local rng = Random.new()

local function publish(player: Player, state: Spin.State)
	player:SetAttribute("SpinsBanked", state.Banked)
	local left = Spin.secondsToNext(state)
	player:SetAttribute("SpinNextAt", if left then workspace:GetServerTimeNow() + left else 0)
end

-- Uses a banked spin. Returns the prize, or nil and why not.
function SpinService:Spin(player: Player): (Spin.Prize?, string?)
	if not DataService:IsLoaded(player) then
		return nil, "Your data isn't loaded yet"
	end
	local prize, why, state = DataService:Update(player, function(data)
		local p, w = Spin.take(data, rng:NextNumber(), rng:NextNumber())
		return p, w, data.Spin
	end)
	if prize then
		publish(player, state)
		if prize.Kind == "Credits" or prize.Kind == "Wings" then
			local data = DataService:GetData(player)
			local balance = if data then (if prize.Kind == "Credits" then data.Credits else data.Wings) else 0
			Telemetry.economy(
				player,
				"Source",
				prize.Kind :: any,
				prize.Amount :: number,
				balance,
				Telemetry.SOURCES.Spin,
				prize.Rarity
			)
		end
		Telemetry.event("Spin", 1, { rarity = prize.Rarity, kind = prize.Kind, item = prize.Item or "" }, player)
	end
	return prize, why
end

-- Test servers (admin spin.give): bank spins, up to the bank's limit. Returns how many are banked.
function SpinService:Give(player: Player, count: number): number?
	local banked, state = DataService:Update(player, function(data)
		data.Spin.Banked = math.clamp(data.Spin.Banked + count, 0, Spin.BANK)
		return data.Spin.Banked, data.Spin
	end)
	if state then
		publish(player, state)
	end
	return banked
end

function SpinService:Init()
	Net.Server.handle("SpinWheel", function(player: Player)
		return self:Spin(player)
	end)
	DataService.ProfileLoaded:Connect(function(player, data)
		publish(player, data.Spin)
	end)
end

function SpinService:Start()
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, player in Players:GetPlayers() do
				if DataService:IsLoaded(player) then
					local earned, state = DataService:Update(player, function(data)
						return Spin.accrue(data.Spin, TICK), data.Spin
					end)
					if earned then
						publish(player, state)
					end
				end
			end
		end
	end)
end

return SpinService
