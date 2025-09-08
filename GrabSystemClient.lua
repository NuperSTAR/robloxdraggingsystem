--!strict
-- GrabSystemClient.lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local GrabSystem = ReplicatedStorage:WaitForChild("GrabSystem")
local RequestGrab = GrabSystem:WaitForChild("RequestGrab") :: RemoteFunction
local UpdateTarget = GrabSystem:WaitForChild("UpdateTarget") :: RemoteEvent
local ReleaseGrab = GrabSystem:WaitForChild("ReleaseGrab") :: RemoteEvent

-- CONFIG
local BASE_DISTANCE = 10
local DIST_STEP = 2
local SLOW_MULT = 0.25 -- Shift
local FAST_MULT = 2.0   -- Ctrl
local RAY_LENGTH = 300
local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType = Enum.RaycastFilterType.Blacklist
RAY_PARAMS.IgnoreWater = true

-- State
local grabbing = false
local grabbedPart: BasePart? = nil
local distance = BASE_DISTANCE
local last = os.clock()

-- Utility
local function getAimCFrame(): CFrame
	local cam = Workspace.CurrentCamera
	if not cam then return CFrame.new() end
	-- Ray from camera through mouse (or center on touch)
	local origin = cam.CFrame.Position
	local dir: Vector3
	if UserInputService.TouchEnabled and #UserInputService:GetTouches() > 0 then
		dir = (cam.CFrame.LookVector) * RAY_LENGTH
	else
		local unitRay = cam:ScreenPointToRay(mouse.X, mouse.Y)
		dir = unitRay.Direction * RAY_LENGTH
	end

	local result = Workspace:Raycast(origin, dir, RAY_PARAMS)
	local targetPos = result and result.Position or (origin + dir)
	return CFrame.lookAt(targetPos, targetPos + cam.CFrame.LookVector)
end

local function scaleByModifiers(step: number): number
	local mult = 1
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		mult *= SLOW_MULT
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		mult *= FAST_MULT
	end
	return step * mult
end

local function startGrab(targetPart: BasePart?)
	if grabbing then return end
	if not targetPart then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	-- Estimate initial distance
	local origin = cam.CFrame.Position
	local d = (targetPart.Position - origin).Magnitude
	distance = math.clamp(d, 2, 60)

	local ok = false
	local success, res = pcall(function()
		return RequestGrab:InvokeServer(targetPart, targetPart.Position, distance)
	end)
	if success and res == true then
		grabbing = true
		grabbedPart = targetPart
	else
		grabbing = false
		grabbedPart = nil
	end
	last = os.clock()
end

local function stopGrab()
	if not grabbing then return end
	grabbing = false
	grabbedPart = nil
	ReleaseGrab:FireServer()
end

-- Input
local function onInputBegan(input: InputObject, gpe: boolean)
	if gpe then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = mouse.Target
		if target and target:IsA("BasePart") then
			startGrab(target)
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local touchTarget = mouse.Target -- Roblox syncs this reasonably for taps
		if touchTarget and touchTarget:IsA("BasePart") then
			startGrab(touchTarget)
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		if mouse.Target and mouse.Target:IsA("BasePart") then
			startGrab(mouse.Target)
		end
	end
end

local function onInputEnded(input: InputObject, gpe: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.E then
		stopGrab()
	end
end

local function onWheel(input: InputObject, gpe: boolean)
	if not grabbing then return end
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	distance += scaleByModifiers((input.Position.Z > 0) and DIST_STEP or -DIST_STEP)
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
UserInputService.InputChanged:Connect(onWheel)

-- Per-frame target update (client → server)
RunService.RenderStepped:Connect(function()
	if not grabbing then return end
	local now = os.clock()
	local dt = math.max(1/240, math.min(1/30, now - last))
	last = now

	local aim = getAimCFrame()
	-- push a point distance in front of the camera along aim
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local origin = cam.CFrame.Position
	local targetPos = origin + (aim.LookVector * distance)
	local world = CFrame.lookAt(targetPos, targetPos + aim.LookVector)

	UpdateTarget:FireServer(world, distance, dt)
end)
