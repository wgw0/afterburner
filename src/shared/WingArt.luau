--!strict
-- Wing art (SHP-07, Config/Cosmetics "WingArt"): a decal on top of each wing, mid-span, its top towards the
-- nose so it reads from above, pointing outboard. Wings differ in span, chord and sweep, so the spot and size
-- are searched for: the biggest decal (twice as long as high, laid along the span) whose corners all lie on
-- the wing's top on both sides (HullDecal.fits), trying spots across the span (from the WingtipL / WingtipR
-- attachments) and along the chord found there. Shared like KillMarkers: the server paints spawned jets and the client its
-- menu previews (call once the model is in the world).

local Catalogue = require(script.Parent.Config.Cosmetics)
local HullDecal = require(script.Parent.HullDecal)

local WingArt = {}

local NAME = "WingArt"
local SPAN = { 0.55, 0.5, 0.6, 0.45, 0.65, 0.4 } -- of the way from the centreline to the tip, best first
local CHORD = { 0, 0.1, -0.1, 0.2, -0.2 } -- forward of mid-chord, of the chord there, best first
local LARGEST, SMALLEST = 0.22, 0.06 -- the decal's height (chordwise), in semi-spans
local SHRINK = 0.85
local FLAT = 0.1 -- how far a corner may sit off the skin, of the decal's height

-- The plate's frame on the wing's top at `spot` (facing up out of the skin, its top towards the nose), or nil.
local function top(c: HullDecal.Caster, spot: Vector3): CFrame?
	local up = c.root.CFrame.UpVector
	local hit = c.cast(spot + up * 20, up * -40)
	if not hit or hit.Normal:Dot(up) < 0.7 then
		return nil
	end
	return CFrame.lookAt(hit.Position + hit.Normal * 0.03, hit.Position + hit.Normal, c.root.CFrame.LookVector)
end

-- Where the wing's top is along the chord at each span station: { [span] = { mid, length } } in root-space Z.
-- Swept wings leave the tip attachment well aft of the wing further in, so the wing is followed in from
-- the tip: at each station, the run of top skin nearest the last one (not a canard or tailplane).
local function chords(c: HullDecal.Caster, tip: Vector3, semi: number): { [number]: { number } }
	local root = c.root.CFrame
	local step = semi / 40
	local found = {}
	local near = tip.Z
	for s = 18, 8, -1 do
		local span = s / 20
		local runs, from, last = {}, nil, nil
		for z = tip.Z - semi * 1.5, tip.Z + semi * 0.5, step do
			if top(c, root:PointToWorldSpace(Vector3.new(tip.X * span, tip.Y, z))) then
				from = from or z
				last = z
			elseif from then
				table.insert(runs, { from, last })
				from = nil
			end
		end
		if from then
			table.insert(runs, { from, last })
		end
		local best, gap = nil, math.huge
		for _, run in runs do
			local d = math.max(run[1] - near, near - run[2], 0)
			if d < gap then
				best, gap = run, d
			end
		end
		if best and gap <= semi * 0.25 then
			near = (best[1] + best[2]) / 2
			found[s] = { near, best[2] - best[1] }
		end
	end
	return found
end

-- The biggest fitting decal: its frame on each wing and its size, or nil if nothing fits.
local function search(c: HullDecal.Caster, tipR: Vector3, tipL: Vector3): ({ CFrame }?, Vector2?)
	local root = c.root.CFrame
	local semi = (math.abs(tipR.X) + math.abs(tipL.X)) / 2
	local wings = { chords(c, tipR, semi), chords(c, tipL, semi) }
	local h = semi * LARGEST
	while h >= semi * SMALLEST do
		local size = Vector2.new(h * 2, h)
		for _, chord in CHORD do
			for _, span in SPAN do
				local frames = {}
				for i, tip in { tipR, tipL } do
					local station = wings[i][math.round(span * 20)]
					if not station then
						break
					end
					local z = station[1] - chord * station[2]
					local spot = root:PointToWorldSpace(Vector3.new(tip.X * span, tip.Y, z))
					local frame = top(c, spot)
					if not (frame and HullDecal.fits(c, frame, size, h * FLAT)) then
						break
					end
					frames[i] = frame
				end
				if #frames == 2 then
					return frames, size
				end
			end
		end
		h *= SHRINK
	end
	return nil, nil
end

-- Paints a jet's wing art (removing any old), or just clears it for nil / an unknown id.
function WingArt.apply(model: Model, id: string?)
	HullDecal.clear(model, NAME)
	local item = id and Catalogue.get(id)
	local root = model.PrimaryPart
	local tipR = root and root:FindFirstChild("WingtipR") :: Attachment?
	local tipL = root and root:FindFirstChild("WingtipL") :: Attachment?
	if not (item and item.Kind == "WingArt" and item.Images and tipR and tipL) then
		return
	end
	local c = HullDecal.caster(model)
	if not c then
		return
	end
	local frames, size = search(c, tipR.Position, tipL.Position)
	c.done()
	if not (frames and size) then
		return
	end
	local images = item.Images
	for i, frame in frames do
		HullDecal.plate(model, NAME, frame, size, function(gui)
			local image = Instance.new("ImageLabel")
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = images[i]
			image.Parent = gui
		end)
	end
end

return WingArt
