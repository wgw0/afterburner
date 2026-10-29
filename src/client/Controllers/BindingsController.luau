--!strict
-- Key and button bindings on the client (DEVELOPMENT.md §7.1, INP-05). Every controller asks this instead of
-- naming keys: IsDown(action) for held actions, Matches(input, action) in InputBegan / InputEnded, Label(action)
-- for on-screen hints. The actions and defaults are in Config/Bindings; SettingsController hands over the
-- player's saved overrides (SetOverrides). Capture() waits for the next key or button, for rebinding.
-- Requires nothing else (SettingsController and InputController both use it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bindings = require(Shared.Config.Bindings)
local Signal = require(Shared.Util.Signal)

local GAMEPAD = Enum.UserInputType.Gamepad1

local BindingsController = {
	Priority = 5, -- before SettingsController
	overrides = {} :: { [string]: any },
	capturing = false, -- true while waiting for a key to bind (other controllers ignore input then)
	Changed = Signal.new(), -- () the bindings changed
}

local resolved: { [string]: { keyboard: string?, gamepad: string? } } = {}
local lastCaptureAt = -math.huge

local function rebuild()
	table.clear(resolved)
	for _, action in Bindings.ACTIONS do
		resolved[action.id] = {
			keyboard = Bindings.resolve(BindingsController.overrides, action.id, "keyboard"),
			gamepad = Bindings.resolve(BindingsController.overrides, action.id, "gamepad"),
		}
	end
end
rebuild()

local function isMouseButton(name: string): boolean
	return name:sub(1, 11) == "MouseButton"
end

function BindingsController:SetOverrides(overrides: { [string]: any })
	self.overrides = overrides
	rebuild()
	self.Changed:Fire()
end

-- The key or button bound to an action for "keyboard" or "gamepad" (nil if none).
function BindingsController:Name(id: string, device: string): string?
	local binding = resolved[id]
	return binding and (binding :: any)[device]
end

-- Is the action's key, mouse button or gamepad button held right now?
function BindingsController:IsDown(id: string): boolean
	if self.capturing then
		return false
	end
	local binding = resolved[id]
	if not binding then
		return false
	end
	local key = binding.keyboard
	if key then
		if isMouseButton(key) then
			if UserInputService:IsMouseButtonPressed((Enum.UserInputType :: any)[key]) then
				return true
			end
		elseif UserInputService:IsKeyDown((Enum.KeyCode :: any)[key]) then
			return true
		end
	end
	local button = binding.gamepad
	return button ~= nil and UserInputService:IsGamepadButtonDown(GAMEPAD, (Enum.KeyCode :: any)[button])
end

-- Does this InputObject (from InputBegan / InputEnded) belong to the action?
function BindingsController:Matches(input: InputObject, id: string): boolean
	if self.capturing then
		return false
	end
	local binding = resolved[id]
	if not binding then
		return false
	end
	if input.UserInputType == GAMEPAD then
		return binding.gamepad ~= nil and input.KeyCode.Name == binding.gamepad
	end
	local key = binding.keyboard
	if not key then
		return false
	end
	if isMouseButton(key) then
		return input.UserInputType.Name == key
	end
	return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == key
end

-- The hint for an action on the device in use ("Space", "X", "LMB"…), or "—" if it's unbound.
function BindingsController:Label(id: string): string
	local gamepad = UserInputService:GetLastInputType() == GAMEPAD
	return Bindings.label(self:Name(id, if gamepad then "gamepad" else "keyboard"))
end

-- Waits for the next key or mouse button ("keyboard") or gamepad button ("gamepad") and calls back with
-- its name, or nil if cancelled (Escape, or nothing within 8 s). Returns false if a capture just ended
-- (the press that finished it can also click the button that starts one).
function BindingsController:Capture(device: string, callback: (string?) -> ()): boolean
	if self.capturing or os.clock() - lastCaptureAt < 0.4 then
		return false
	end
	self.capturing = true
	local connection: RBXScriptConnection
	local done = false
	local function finish(name: string?)
		if done then
			return
		end
		done = true
		connection:Disconnect()
		self.capturing = false
		lastCaptureAt = os.clock()
		callback(name)
	end
	local startedAt = os.clock()
	connection = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - startedAt < 0.15 then
			return -- the press that started it
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			finish(nil)
		elseif device == "gamepad" and input.UserInputType == GAMEPAD then
			if Bindings.validGamepad(input.KeyCode.Name) then
				finish(input.KeyCode.Name)
			end
		elseif device == "keyboard" and input.UserInputType == Enum.UserInputType.Keyboard then
			if Bindings.validKeyboard(input.KeyCode.Name) then
				finish(input.KeyCode.Name)
			end
		elseif device == "keyboard" and isMouseButton(input.UserInputType.Name) then
			finish(input.UserInputType.Name)
		end
	end)
	task.delay(8, finish, nil)
	return true
end

return BindingsController
