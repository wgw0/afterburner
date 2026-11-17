--!strict
-- Quick check-ins (Will: ask for feedback; a game can't catch a player on their way out, so it asks at natural
-- pauses instead): "How's Afterburner so far?" 👍 / 👎 and an optional line, after a new pilot's first sortie
-- and after their 1st and 3rd matches, each moment once (answered or dismissed). Pure: which moment is due.
-- FeedbackService records the answer (analytics event "Pulse"; any text goes in the feedback inbox).

local Pulse = {}

Pulse.MOMENTS = table.freeze({ "Sortie", "Match1", "Match3" })
Pulse.ANSWERS = table.freeze({ up = true, down = true, skip = true })
Pulse.MAX_TEXT = 200

-- Whether a moment has happened for this save.
function Pulse.reached(data: { [string]: any }, moment: string): boolean
	if moment == "Sortie" then
		return data.Lessons ~= nil and data.Lessons.Sortie == true
	elseif moment == "Match1" then
		return (data.Stats and data.Stats.Matches or 0) >= 1
	elseif moment == "Match3" then
		return (data.Stats and data.Stats.Matches or 0) >= 3
	end
	return false
end

-- The check-in to show now, if any: the latest moment reached and not yet answered (answering it marks the
-- earlier ones done too, so a pilot who's past several is asked once).
function Pulse.due(data: { [string]: any }): string?
	local done = data.Pulse or {}
	for i = #Pulse.MOMENTS, 1, -1 do
		local moment = Pulse.MOMENTS[i]
		if Pulse.reached(data, moment) then
			return if done[moment] then nil else moment
		end
	end
	return nil
end

-- Marks `moment` and every moment before it answered.
function Pulse.answer(data: { [string]: any }, moment: string)
	data.Pulse = data.Pulse or {}
	for _, m in Pulse.MOMENTS do
		data.Pulse[m] = true
		if m == moment then
			break
		end
	end
end

return Pulse
