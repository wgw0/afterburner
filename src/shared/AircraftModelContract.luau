--!strict
-- The rules every aircraft model must follow (DEVELOPMENT.md §5.3). validate() returns a list of
-- problems (empty = OK). Checked at server boot for every airframe and by Model.spec in tests.

local Contract = {}

Contract.HITBOXES = { "Cockpit", "Fuselage", "Engine", "WingL", "WingR", "Tail" }
Contract.ATTACHMENTS = {
	"CockpitEye",
	"GunMuzzle",
	"WingtipL",
	"WingtipR",
	"FlareDispenser",
	"ChaffDispenser",
	"ChaseCam",
	"Nozzle1",
	"Hardpoint1",
}
Contract.MAX_PARTS = 40

function Contract.validate(model: Instance): { string }
	local problems = {}
	local function fail(message: string)
		table.insert(problems, `{model.Name}: {message}`)
	end

	if not model:IsA("Model") then
		return { `{model.Name}: must be a Model` }
	end

	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		fail("missing Root part")
		return problems
	end
	if model.PrimaryPart ~= root then
		fail("PrimaryPart must be Root")
	end
	if root.Transparency < 1 or root.CanCollide or root.Anchored then
		fail("Root must be invisible, non-colliding and unanchored")
	end

	local hull = model:FindFirstChild("Hull")
	if not (hull and hull:IsA("BasePart") and hull.CanCollide) then
		fail("missing collidable Hull part")
	end

	local hitboxes = model:FindFirstChild("Hitboxes")
	if not hitboxes then
		fail("missing Hitboxes folder")
	else
		for _, name in Contract.HITBOXES do
			local box = hitboxes:FindFirstChild(name)
			if not (box and box:IsA("BasePart")) then
				fail(`missing hitbox {name}`)
			elseif box.CanCollide or box.CanTouch or not box.CanQuery or box.Transparency < 1 then
				fail(`hitbox {name} must be invisible, CanQuery only`)
			end
		end
	end

	for _, name in Contract.ATTACHMENTS do
		if not root:FindFirstChild(name) then
			fail(`Root is missing attachment {name}`)
		end
	end
	local muzzle = root:FindFirstChild("GunMuzzle")
	-- CFrame.Position rather than Position: same value in Roblox, and Position isn't stored in the file,
	-- so the CI check (Lune, outside Roblox) can't read it.
	if muzzle and muzzle:IsA("Attachment") and muzzle.CFrame.Position.Z >= 0 then
		fail("GunMuzzle is behind the centre of mass; the nose must point along -Z")
	end

	local partCount = 0
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			fail(`contains a script ({d:GetFullName()})`)
		elseif d:IsA("BasePart") then
			partCount += 1
			if d ~= root then
				if d.Anchored then
					fail(`{d.Name} must be unanchored`)
				end
				if not d.Massless then
					fail(`{d.Name} must be Massless`)
				end
				local isHitbox = hitboxes ~= nil and d.Parent == hitboxes
				if d ~= hull and not isHitbox and (d.CanCollide or d.CanTouch or d.CanQuery) then
					fail(`visual part {d.Name} must have CanCollide, CanTouch and CanQuery off`)
				end
				local welded = false
				for _, weld in d:GetChildren() do
					if weld:IsA("WeldConstraint") and (weld.Part0 == root or weld.Part1 == root) then
						welded = true
					end
				end
				if not welded then
					fail(`{d.Name} must be welded directly to Root`)
				end
			end
		end
	end
	if partCount > Contract.MAX_PARTS then
		fail(`has {partCount} parts (max {Contract.MAX_PARTS})`)
	end

	return problems
end

return Contract
