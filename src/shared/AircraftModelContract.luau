--!strict
-- The rules every aircraft model must follow (DEVELOPMENT.md §5.3, docs/art/AIRCRAFT_PIPELINE.md).
-- validate() returns a list of problems (empty = OK). Checked at server boot for every airframe, by
-- Model.spec in tests and by scripts/validate-models.luau in CI.

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
Contract.MAX_PARTS = 60
-- Parts hinged on a Motor6D (control surfaces, gear) say what drives them in a Control attribute
Contract.HINGE_ATTRIBUTES = { "Control", "HingeAxis", "HingeMin", "HingeMax" }

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
				-- Joined straight to Root: a WeldConstraint, or a Motor6D (Part0 = Root) for moving parts
				local welded, hinged = false, false
				for _, joint in d:GetChildren() do
					if joint:IsA("WeldConstraint") and (joint.Part0 == root or joint.Part1 == root) then
						welded = true
					elseif joint:IsA("Motor6D") and joint.Part0 == root and joint.Part1 == d then
						hinged = true
					end
				end
				if not (welded or hinged) then
					fail(`{d.Name} must be welded or hinged (Motor6D) directly to Root`)
				elseif hinged then
					for _, attribute in Contract.HINGE_ATTRIBUTES do
						if d:GetAttribute(attribute) == nil then
							fail(`hinged part {d.Name} is missing its {attribute} attribute`)
						end
					end
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
