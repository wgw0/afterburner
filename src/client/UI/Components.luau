--!strict
-- Base React components shared by every menu screen (UI-01): Panel, Label, Button, Bar, Pill.
-- Buttons show a pending state while the server answers and stay at least 44 px tall (touch). A click whose
-- handler waits (a server request) shows "…" and blocks more clicks until it returns; any click is ignored for
-- CLICK_GAP after the last, so a double-click never sends two requests (or joins and then cancels).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Sounds = require(script.Parent.Sounds)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local CLICK_GAP = 0.35 -- seconds

local Components = {}

local function corner(radius: number?)
	return e("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) })
end
Components.corner = corner

local function stroke(color: Color3?, thickness: number?, transparency: number?)
	return e("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end
Components.stroke = stroke

-- A rounded panel. props: Size, Position, AnchorPoint, Color, Transparency, StrokeColor, LayoutOrder,
-- Padding (pixels), children.
function Components.Panel(props: any)
	local children = table.clone(props.children or {})
	children.Corner = corner(props.Radius)
	children.Stroke = stroke(props.StrokeColor, props.StrokeThickness, props.StrokeTransparency)
	if props.Padding then
		children.Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, props.Padding),
			PaddingBottom = UDim.new(0, props.Padding),
			PaddingLeft = UDim.new(0, props.Padding),
			PaddingRight = UDim.new(0, props.Padding),
		})
	end
	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = props.Color or Theme.Panel,
		BackgroundTransparency = props.Transparency or 0.05,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ClipsDescendants = props.Clip,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		AutomaticSize = props.AutomaticSize,
	}, children)
end

-- Text. props: Text, Size, Position, AnchorPoint, TextSize, Color, Bold, Heavy, Align ("Left" |
-- "Center" | "Right"), Wrap, LayoutOrder, AutoHeight.
function Components.Label(props: any)
	local align = props.Align or "Left"
	return e("TextLabel", {
		Text = props.Text,
		Size = props.Size or UDim2.new(1, 0, 0, (props.TextSize or 16) + 4),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		Font = if props.Mono
			then Theme.FontMono
			elseif props.Heavy then Theme.FontHeavy
			elseif props.Bold then Theme.FontBold
			else Theme.Font,
		TextSize = props.TextSize or 16,
		TextColor3 = props.Color or Theme.Text,
		TextTransparency = props.Transparency or 0,
		TextXAlignment = Enum.TextXAlignment[align],
		TextYAlignment = props.AlignY and Enum.TextYAlignment[props.AlignY] or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrap == true,
		RichText = props.Rich == true,
		AutomaticSize = if props.AutoHeight then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
	})
end

-- A button. props: Text, OnClick, Size, Position, AnchorPoint, Style ("Primary" | "Secondary" |
-- "Ghost" | "Danger"), Disabled, Pending, TextSize, LayoutOrder, Selected, Color and TextColor (instead of
-- the style's), StrokeColor (a coloured border, e.g. what kind of action it is).
function Components.Button(props: any)
	local busy, setBusy = React.useState(false)
	local lastClick = React.useRef(0)
	local mounted = React.useRef(true)
	React.useEffect(function()
		mounted.current = true
		return function()
			mounted.current = false
		end
	end, {})
	local style = props.Style or "Secondary"
	local pending = props.Pending or busy
	local disabled = props.Disabled or pending
	local background = if style == "Primary"
		then Theme.Accent
		elseif style == "Danger" then Theme.Bad
		elseif style == "Ghost" then Theme.Panel
		else Theme.PanelLight
	if props.Color then
		background = props.Color
	end
	if props.Selected then
		background = Theme.AccentDark
	end
	local text = if pending then "…" else props.Text
	return e("TextButton", {
		Text = text,
		Size = props.Size or UDim2.new(1, 0, 0, 44),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = if disabled then Theme.Locked else background,
		BackgroundTransparency = if style == "Ghost" then 0.4 else 0,
		AutoButtonColor = not disabled,
		Font = Theme.FontBold,
		TextSize = props.TextSize or 16,
		TextColor3 = if disabled
			then Theme.Text
			elseif props.TextColor then props.TextColor
			elseif style == "Primary" then Color3.fromRGB(20, 14, 8)
			else Theme.Text,
		TextTransparency = if disabled then 0.35 else 0,
		LayoutOrder = props.LayoutOrder,
		Selectable = not disabled,
		ZIndex = props.ZIndex,
		[React.Event.Activated] = function()
			local now = os.clock()
			if disabled or not props.OnClick or now - lastClick.current < CLICK_GAP then
				return
			end
			lastClick.current = now
			Sounds.play("UIClick")
			-- Run the handler in its own thread: if it waits on the server, the button shows "…" until it's done
			local finished = false
			task.spawn(function()
				local ok, err = pcall(props.OnClick)
				finished = true
				if mounted.current then
					setBusy(false)
				end
				if not ok then
					warn(err)
				end
			end)
			if not finished then
				setBusy(true)
			end
		end,
	}, {
		Corner = corner(),
		Stroke = if props.StrokeColor and not disabled
			then stroke(props.StrokeColor, 2)
			elseif style == "Ghost" or props.Selected then stroke(Theme.Accent, 1.5)
			else nil,
	})
end

-- A fixed-size design that shrinks to fit the room it's given, never overlapping what's either side of it
-- (the side panels, on a narrow screen or a large Menu scale). props: Width, Height (the design, in menu
-- units), Sides (what to keep clear across the screen's width, e.g. both side panels), Position,
-- AnchorPoint, children (laid out in Width x Height as usual, anchored to its bottom centre). The frame's
-- height is a fixed Height, so its width over its height gives the room in the menu's own units.
function Components.Fit(props: any)
	local room, setRoom = React.useState(props.Width)
	local fit = math.clamp(room / props.Width, 0.4, 1)
	local children = table.clone(props.children or {})
	children.Scale = e("UIScale", { Scale = fit })
	return e("Frame", {
		Size = UDim2.new(1, -(props.Sides or 0), 0, props.Height),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex,
		[React.Change.AbsoluteSize] = function(frame: Frame)
			if frame.AbsoluteSize.Y > 0 then
				setRoom(frame.AbsoluteSize.X / frame.AbsoluteSize.Y * props.Height)
			end
		end,
	}, {
		Inner = e("Frame", {
			Size = UDim2.fromOffset(props.Width, props.Height),
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
		}, children),
	})
end

-- A progress bar. props: Value (0..1), Size, Position, Color, LayoutOrder, Text (optional, over it).
function Components.Bar(props: any)
	local value = math.clamp(props.Value or 0, 0, 1)
	-- Transparent: no track, so two bars can overlap (stock over upgraded)
	return e("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 8),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = if props.Transparent then 1 else 0,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
	}, {
		Corner = corner(4),
		Fill = e("Frame", {
			Size = UDim2.fromScale(value, 1),
			BackgroundColor3 = props.Color or Theme.Good,
			BorderSizePixel = 0,
			ZIndex = props.ZIndex,
		}, { Corner = corner(4) }),
		Text = if props.Text
			then e("TextLabel", {
				Text = props.Text,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.FontBold,
				TextSize = 12,
				TextColor3 = Theme.Text,
				TextStrokeTransparency = 0.5,
			})
			else nil,
	})
end

-- A small rounded tag. props: Text, Color, TextColor, LayoutOrder, Size, Position, AnchorPoint.
function Components.Pill(props: any)
	return e("TextLabel", {
		Text = props.Text,
		Size = props.Size or UDim2.fromOffset(90, 22),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = props.Color or Theme.PanelLight,
		BorderSizePixel = 0,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = props.TextColor or Theme.Text,
		LayoutOrder = props.LayoutOrder,
	}, { Corner = corner(11) })
end

-- A vertical or horizontal list layout. props: Horizontal, Gap, Align ("Center" | ...).
function Components.List(props: any)
	return e("UIListLayout", {
		FillDirection = if props.Horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, props.Gap or Theme.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = props.Align and Enum.HorizontalAlignment[props.Align] or Enum.HorizontalAlignment.Left,
		VerticalAlignment = props.AlignY and Enum.VerticalAlignment[props.AlignY] or Enum.VerticalAlignment.Top,
	})
end

-- "12,345"
function Components.number(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

return Components
