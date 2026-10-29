--!strict
-- Reporting a cheater (DEVELOPMENT.md §32, CMP-03). Pure rules shared by the report window and ReportService.
-- A report is logged with the target's recent anti-cheat data for review; nothing happens to the target
-- automatically. Anything that isn't cheating (chat, behaviour) goes through Roblox's own report flow.

local Reports = {}

Reports.COOLDOWN = 30 -- seconds between one pilot's reports
Reports.KEPT = 20 -- reports kept per reported pilot, newest last
Reports.RECENT_STRIKES = 10 -- anti-cheat strikes attached to each report

Reports.REASONS = {
	{ id = "Movement", label = "Speed or teleporting" },
	{ id = "Weapons", label = "Weapon or aim hacks" },
	{ id = "Invincible", label = "Can't be shot down" },
	{ id = "Other", label = "Other cheating" },
}

Reports.ROBLOX_HINT = "For chat or behaviour, use Roblox's own report: Esc menu, then Report."

function Reports.reasonLabel(id: string): string?
	for _, reason in Reports.REASONS do
		if reason.id == id then
			return reason.label
		end
	end
	return nil
end

-- Whether a report may be sent. lastReport: when this reporter last reported (os.time), or nil.
-- reported: the targets this reporter has already reported on this server.
function Reports.validate(
	reporterId: number,
	targetUserId: number,
	reason: string,
	now: number,
	lastReport: number?,
	reported: { [number]: boolean }
): (boolean, string?)
	if targetUserId == reporterId then
		return false, "You can't report yourself."
	end
	if targetUserId <= 0 then
		return false, "AI pilots can't be reported."
	end
	if not Reports.reasonLabel(reason) then
		return false, "Pick a reason."
	end
	if reported[targetUserId] then
		return false, "You've already reported this pilot."
	end
	if lastReport and now - lastReport < Reports.COOLDOWN then
		return false, `Wait {Reports.COOLDOWN - (now - lastReport)} s before reporting again.`
	end
	return true, nil
end

-- Adds an entry to a pilot's stored report record (DataStore value), keeping the newest KEPT.
-- A reporter counts once towards `reporters` however many times they report the same pilot.
function Reports.add(record: any, entry: any): any
	record = if type(record) == "table" then record else {}
	record.count = (record.count or 0) + 1
	record.entries = record.entries or {}
	local seen = false
	for _, old in record.entries do
		if old.reporter == entry.reporter then
			seen = true
			break
		end
	end
	if not seen then
		record.reporters = (record.reporters or 0) + 1
	end
	table.insert(record.entries, entry)
	while #record.entries > Reports.KEPT do
		table.remove(record.entries, 1)
	end
	return record
end

return Reports
