--!strict
-- Report a bug (Will; rules in Shared/Feedback). A player sends a bug, lag report, idea or other note with
-- their device info; it's stored in the "Feedback" DataStore under the day it arrived (day:<n>, newest
-- last, up to Feedback.DAY_CAP a day), with a per-player count per day (n:<userId>:<day>) so the daily limit
-- holds across servers. Only UserIds are stored (§32 privacy). Will reads them with admin feedback.recent.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Feedback = require(Shared.Feedback)
local Pulse = require(Shared.Pulse)
local Net = require(Shared.Net)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)

local FeedbackService = {
	Priority = 50,
}

local STORE = "Feedback"
local lastSent: { [Player]: number } = {}

local function store(): DataStore?
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	return if ok then result else nil
end

local function today(): number
	return os.time() // 86400
end

-- Files a report. Returns (ok, message for the player).
function FeedbackService:Send(player: Player, kind: any, text: any, rawInfo: any): (boolean, string)
	local feedback = store()
	if not feedback then
		return false, "Reports aren't working just now. Try again in a moment."
	end
	local now, day = os.time(), today()
	local countKey = `n:{player.UserId}:{day}`
	local okCount, sentToday = pcall(feedback.GetAsync, feedback, countKey)
	local cleaned, err = Feedback.validate(kind, text, now, lastSent[player], if okCount then sentToday or 0 else 0)
	if not cleaned then
		return false, err :: string
	end
	lastSent[player] = now
	local entry = {
		at = now,
		user = player.UserId,
		kind = kind,
		text = cleaned,
		info = Feedback.cleanInfo(rawInfo),
		placeId = game.PlaceId,
		jobId = game.JobId,
	}
	local full = false
	local ok, saveErr = pcall(function()
		feedback:UpdateAsync(`day:{day}`, function(list)
			list = list or {}
			if #list >= Feedback.DAY_CAP then
				full = true
				return nil -- leave it as it is
			end
			table.insert(list, entry)
			return list
		end)
	end)
	if not ok then
		warn(`[Feedback] Couldn't save a report from {player.UserId}: {saveErr}`)
		lastSent[player] = nil
		return false, "Couldn't send that just now. Try again in a moment."
	end
	if full then
		return false, "We've had a lot of reports today. Thank you! Try again tomorrow."
	end
	pcall(feedback.UpdateAsync, feedback, countKey, function(count)
		return (count or 0) + 1
	end)
	Telemetry.event("Feedback", 1, { kind = kind }, player)
	return true, "Thanks! Your report has been sent."
end

-- The newest reports from today and yesterday, newest first: up to `count`, of one kind if given.
function FeedbackService:Recent(count: number, kind: string?): { any }
	local feedback = store()
	if not feedback then
		return {}
	end
	local found = {}
	for day = today(), today() - 1, -1 do
		local ok, list = pcall(feedback.GetAsync, feedback, `day:{day}`)
		if ok and type(list) == "table" then
			for i = #list, 1, -1 do
				local entry = list[i]
				if not kind or string.lower(entry.kind or "") == string.lower(kind) then
					table.insert(found, entry)
					if #found >= count then
						return found
					end
				end
			end
		end
	end
	return found
end

-- A quick check-in answered (Shared/Pulse): remembered so it isn't asked again, logged as an analytics
-- event (value 1 thumbs up, 0 down; skips counted apart), and any line goes in the feedback inbox.
local function onPulse(player: Player, moment: string, answer: string, text: string?)
	if not table.find(Pulse.MOMENTS, moment) or not Pulse.ANSWERS[answer] then
		return
	end
	local fresh = false
	DataService:Update(player, function(data)
		if not (data.Pulse and data.Pulse[moment]) then
			Pulse.answer(data, moment)
			fresh = true
		end
	end)
	if not fresh then
		return
	end
	Telemetry.event("Pulse", if answer == "up" then 1 else 0, { moment = moment, answer = answer }, player)
	local line = if type(text) == "string" then string.match(text, "^%s*(.-)%s*$") else nil
	if answer ~= "skip" and line and #line >= Feedback.MIN_LENGTH then
		local mark = if answer == "up" then "👍" else "👎"
		FeedbackService:Send(player, "Idea", `[check-in {moment} {mark}] {string.sub(line, 1, Pulse.MAX_TEXT)}`, {})
	end
end

function FeedbackService:Init()
	Net.Server.on("PulseAnswer", onPulse)
	Net.Server.handle("SendFeedback", function(player: Player, kind: string, text: string, info: any)
		return self:Send(player, kind, text, info)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

return FeedbackService
