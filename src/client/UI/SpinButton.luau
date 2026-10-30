--!strict
-- The free-spin button on the hangar (Shared/Spin). A gold button with a sweeping shine: "FREE SPIN" and how
-- many are ready, or a live countdown to the next one. It reads the SpinsBanked / SpinNextAt attributes the
-- server keeps on the player (SpinService), so the countdown matches the server's clock.
-- props: OnOpen()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local GOLD = Theme.Rarity.Legendary

-- Spins ready and seconds to the next (nil: the bank is full, or not known yet).
local function readSpin(): (number, number?)
	local player = Players.LocalPlayer
	local banked = (player:GetAttribute("SpinsBanked") :: number?) or 0
	local nextAt = player:GetAttribute("SpinNextAt") :: number?
	if not nextAt or nextAt == 0 then
		return banked, nil
	end
	return banked, math.max(nextAt - workspace:GetServerTimeNow(), 0)
end

local function clock(seconds: number): string
	local s = math.ceil(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

local function SpinButton(props: { OnOpen: () -> () })
	local banked, setBanked = React.useState(0)
	local left, setLeft = React.useState(nil :: number?)
	local gradient = React.useRef(nil)
	local stroke = React.useRef(nil)

	React.useEffect(function()
		local accumulator = 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			-- The shine sweeps across every couple of seconds; the border pulses while a spin is ready
			local t = os.clock()
			if gradient.current then
				gradient.current.Offset = Vector2.new(((t * 0.6) % 2) - 1, 0)
			end
			if stroke.current then
				stroke.current.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * 5))
			end
			accumulator += dt
			if accumulator >= 0.25 then
				accumulator = 0
				local b, l = readSpin()
				setBanked(b)
				setLeft(if l then math.ceil(l) else nil)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local ready = banked > 0
	local title = if ready then "FREE SPIN" else "NEXT FREE SPIN"
	local detail = if ready
		then (if banked > 1 then `{banked} SPINS READY` else "READY TO SPIN")
		elseif left and left > 0 then clock(left)
		elseif left then "ANY SECOND NOW"
		else ""
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(300, 84),
		Position = UDim2.new(1, -20, 1, -20),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = if ready then GOLD else Theme.Panel,
		AutoButtonColor = true,
		ClipsDescendants = true,
		[React.Event.Activated] = function()
			props.OnOpen()
		end,
	}, {
		Corner = C.corner(12),
		Stroke = e("UIStroke", {
			Color = if ready then Color3.new(1, 1, 1) else GOLD,
			Thickness = if ready then 3 else 1.5,
			ref = stroke,
		}),
		-- The shine: a bright band sliding across
		Shine = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = if ready then 0.55 else 0.85,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = C.corner(12),
			Gradient = e("UIGradient", {
				Rotation = 20,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.42, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.58, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				ref = gradient,
			}),
		}),
		Title = e(C.Label, {
			Text = title,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 12),
			Heavy = true,
			TextSize = if ready then 30 else 18,
			Align = "Center",
			Color = if ready then Theme.Background else GOLD,
			ZIndex = 3,
		}),
		Detail = e(C.Label, {
			Text = detail,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, if ready then 48 else 40),
			Bold = true,
			Mono = not ready,
			TextSize = if ready then 15 else 26,
			Align = "Center",
			Color = if ready then Theme.Background else Theme.Text,
			ZIndex = 3,
		}),
	})
end

return SpinButton
