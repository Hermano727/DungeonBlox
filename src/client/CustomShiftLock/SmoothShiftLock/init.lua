

local SmoothShiftLock = {};
SmoothShiftLock.__index = SmoothShiftLock;

--// [ Locals: ]

--// Services
local Workspace = game:GetService("Workspace");
local Players = game:GetService("Players");
local RunService = game:GetService("RunService");
local ContextActionService = game:GetService("ContextActionService");
local UserInputService = game:GetService("UserInputService");

--// Utilities
local Maid = require(script:WaitForChild("Maid"));
local Spring = require(script:WaitForChild("Spring"));

--// Instances
local LocalPlayer = Players.LocalPlayer;
local PlayerMouse = LocalPlayer:GetMouse();
local Camera = Workspace.CurrentCamera;

--// Configuration
local Config = {
	MOBILE_SUPPORT              = false,                      --// Adds a button to toggle the shift lock for touchscreen devices
	SMOOTH_CHARACTER_ROTATION   = true,                       --// If your character should rotate smoothly or not
	CHARACTER_ROTATION_SPEED    = 3,                          --// How quickly character rotates smoothly
	TRANSITION_SPRING_DAMPER    = 0.7,                        --// Camera transition spring damper, test it out to see what works for you
	CAMERA_TRANSITION_IN_SPEED  = 10,                         --// How quickly locked camera moves to offset position
	CAMERA_TRANSITION_OUT_SPEED = 14,                         --// How quickly locked camera moves back from offset position
	LOCKED_CAMERA_OFFSET        = Vector3.new(1.75, 0.25, 0), --// Locked camera offset
	LOCKED_MOUSE_ICON           =                             --// Locked mouse icon
		"rbxasset://textures/MouseLockedCursor.png",
	SHIFT_LOCK_KEYBINDS         =                             --// Shift lock keybinds
		{} --// was {LeftControl}; that collides with this game's FreeLookClient/CursorManager,
		   --// which already uses LeftControl to release the cursor (see ReplicatedStorage.KeybindConfig.FreeLook).
		   --// Toggling shift lock on Ctrl fought that every frame and re-locked/hid the cursor.
};

--// [ Constructor: ]
function SmoothShiftLock.new()
	local self = setmetatable({}, SmoothShiftLock);

	--// Utilities
	self._runtimeMaid = Maid.new();
	self._shiftlockMaid = Maid.new();
	self._cameraOffsetSpring = Spring.new(Vector3.new(0, 0, 0));
	self._cameraOffsetSpring.Damper = Config.TRANSITION_SPRING_DAMPER;

	--// Variables
	self.Enabled = false;

	--// Setup
	self:Enable();

	return self;
end;

--// [ Module Functions: ]
function SmoothShiftLock:Enable()
	self:_refreshCharacterVariables();
	self._runtimeMaid:GiveTask(LocalPlayer.CharacterAdded:Connect(function()
		self:_refreshCharacterVariables();
	end));

	--// Bind Keybinds
	ContextActionService:BindActionAtPriority("ShiftLockSwitchAction", function(Name, State, Input)
		return self:_doShiftLockSwitch(Name, State, Input);
	end, Config.MOBILE_SUPPORT, Enum.ContextActionPriority.Medium.Value, unpack(Config.SHIFT_LOCK_KEYBINDS));

	--// Camera Offset
	self._runtimeMaid:GiveTask(RunService.RenderStepped:Connect(function()
		if self.Head.LocalTransparencyModifier > 0.6 then return; end;

		local CameraCFrame = Camera.CoordinateFrame;
		local Distance = (self.Head.Position - CameraCFrame.p).magnitude;

		--// Camera offset
		if Distance > 1 then
			Camera.CFrame = (Camera.CFrame * CFrame.new(self._cameraOffsetSpring.Position));
			if self.Enabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
				self:_updateMouseState();
			end;
		end;
	end));
end;

function SmoothShiftLock:Disable()
	self._runtimeMaid:DoCleaning();
	self._shiftlockMaid:DoCleaning();

	--// Unbind Keybinds
	ContextActionService:UnbindAction("ShiftLockSwitchAction");
end;

--// [ Internal Functions: ]
function SmoothShiftLock:_refreshCharacterVariables()
	self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait();
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart");
	self.Humanoid = self.Character:WaitForChild("Humanoid");
	self.Head = self.Character:WaitForChild("Head");
end;

--// Internal function for ContextActionService
function SmoothShiftLock:_doShiftLockSwitch(_, State: Enum.UserInputState)
	if State == Enum.UserInputState.Begin then
		self:ToggleShiftLock();
		return Enum.ContextActionResult.Sink;
	end;

	return Enum.ContextActionResult.Pass;
end;

--// Update the mouse behaviour
function SmoothShiftLock:_updateMouseState()
	UserInputService.MouseBehavior = (self.Enabled and Enum.MouseBehavior.LockCenter) or Enum.MouseBehavior.Default;
end;

--// Update the mouse icon
function SmoothShiftLock:_updateMouseIcon()
	PlayerMouse.Icon = (self.Enabled and Config.LOCKED_MOUSE_ICON :: string) or "";
end;

--// Transition the camera to lock offset
function SmoothShiftLock:_transitionLockOffset()
	if self.Enabled then
		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_IN_SPEED;
		self._cameraOffsetSpring.Target = Config.LOCKED_CAMERA_OFFSET;
	else
		self._cameraOffsetSpring.Speed = Config.CAMERA_TRANSITION_OUT_SPEED;
		self._cameraOffsetSpring.Target = Vector3.new(0, 0, 0);
	end;
end;

--// [ External Functions: ]
function SmoothShiftLock:IsEnabled(): boolean
	return self.Enabled;
end;

--// ShiftLock toggle function
function SmoothShiftLock:ToggleShiftLock(Enable: boolean?)
	if Enable ~= nil then
		self.Enabled = Enable;
	else
		self.Enabled = not self.Enabled;
	end;

	self:_updateMouseState();
	self:_updateMouseIcon();
	self:_transitionLockOffset();
	if self.Enabled then
		self._shiftlockMaid:GiveTask(RunService.RenderStepped:Connect(function(Delta: number)
			if (self.Humanoid and self.RootPart) then
				self.Humanoid.AutoRotate = not self.Enabled;
			end;

			--// Rotate the character
			if self.Humanoid.Sit then return; end;
			if Config.SMOOTH_CHARACTER_ROTATION then
				local x, y, z = Camera.CFrame:ToOrientation();
				self.RootPart.CFrame = self.RootPart.CFrame:Lerp(CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0), Delta * 5 * Config.CHARACTER_ROTATION_SPEED);
			else
				local x, y, z = Camera.CFrame:ToOrientation();
				self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0);
			end;
		end));
	else
		self.Humanoid.AutoRotate = true;
		self._shiftlockMaid:DoCleaning();
	end;
end;

return SmoothShiftLock.new();