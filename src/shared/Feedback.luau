--!strict
-- Report a bug (Will): a player sends a bug, lag report, idea or anything else, with their device info
-- attached; FeedbackService stores it for Will to read (admin feedback.recent). Pure: the limits, checking a
-- report, and tidying the device info a client sends (never trusted, so every field is clamped).

local Feedback = {}

Feedback.KINDS = table.freeze({ "Bug", "Lag", "Idea", "Other" })
Feedback.MAX_LENGTH = 500
Feedback.MIN_LENGTH = 3
Feedback.COOLDOWN = 120 -- seconds between a player's reports
Feedback.PER_DAY = 5
Feedback.DAY_CAP = 500 -- reports kept per day (the store's record would grow too big past this)

export type Info = {
	fps: number?,
	memory: number?, -- MB
	graphics: number?, -- quality level, 0 = automatic
	input: string?,
	screen: string?, -- "1920x1080"
	ping: number?, -- ms
	role: string?,
	mode: string?,
	jet: string?,
	version: string?,
}

-- Checks a report. Returns the text to store (trimmed), or nil and why not.
-- now / last: seconds; today: the player's reports so far today.
function Feedback.validate(kind: any, text: any, now: number, last: number?, today: number): (string?, string?)
	if type(kind) ~= "string" or not table.find(Feedback.KINDS, kind) then
		return nil, "Pick a type first."
	end
	if type(text) ~= "string" then
		return nil, "Say what happened."
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if #trimmed < Feedback.MIN_LENGTH then
		return nil, "Say what happened (a few words is fine)."
	end
	if utf8.len(trimmed) == nil then
		return nil, "That text couldn't be read."
	end
	if last and now - last < Feedback.COOLDOWN then
		return nil, `Thanks! You can send another in {math.ceil(Feedback.COOLDOWN - (now - last))} s.`
	end
	if today >= Feedback.PER_DAY then
		return nil, "That's the most for today, thank you! Try again tomorrow."
	end
	if utf8.len(trimmed) :: number > Feedback.MAX_LENGTH then
		trimmed = string.sub(trimmed, 1, utf8.offset(trimmed, Feedback.MAX_LENGTH + 1) - 1)
	end
	return trimmed, nil
end

local function number(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.round(value * 10) / 10, low, high)
end

local function word(value: any, length: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local cleaned = string.gsub(value, "[^%w%s%-%._x]", "")
	return string.sub(cleaned, 1, length)
end

-- The device info a client sent, with every field checked and clamped.
function Feedback.cleanInfo(raw: any): Info
	if type(raw) ~= "table" then
		return {}
	end
	return {
		fps = number(raw.fps, 0, 1000),
		memory = number(raw.memory, 0, 100000),
		graphics = number(raw.graphics, 0, 21),
		input = word(raw.input, 20),
		screen = word(raw.screen, 20),
		ping = number(raw.ping, 0, 10000),
		role = word(raw.role, 20),
		mode = word(raw.mode, 30),
		jet = word(raw.jet, 30),
		version = word(raw.version, 20),
	}
end

return Feedback
