--!strict
-- Roblox text filtering for everything players write that other players see (DEVELOPMENT.md §32, CMP-01):
-- callsigns now, squadron names when squadrons exist. Text is filtered for broadcast (shown to everyone on
-- the server, whatever their age), so a viewer never needs their own copy. If the filter can't be reached
-- the text is refused, never shown unfiltered.

local TextService = game:GetService("TextService")

local TextFilterService = {
	Priority = 6,
}

local ATTEMPTS = 3

-- The broadcast-filtered text, or nil if Roblox's filter couldn't be reached (after ATTEMPTS tries). Yields.
function TextFilterService:Filter(text: string, fromUserId: number): string?
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(function()
			local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
			return filtered:GetNonChatStringForBroadcastAsync()
		end)
		if ok then
			return result
		end
		warn(`[TextFilter] filter failed for {fromUserId}, try {attempt}: {result}`)
		if attempt < ATTEMPTS then
			task.wait(attempt)
		end
	end
	return nil
end

return TextFilterService
