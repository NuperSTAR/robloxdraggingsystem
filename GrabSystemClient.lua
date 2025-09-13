-- GrabSystemClient.lua
-- Improvements:
-- 1) Single reusable Highlight (no leaks)
-- 2) Throttled ownership pings (no per-frame spam)
-- 3) Safer camera handling (no hard lock to 0)
-- 4) Optional constraint-break via key (F) while grabbing
-- 5) Robust cleanup if part disappears

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local mouse = player:GetMouse()

local GrabSystem = ReplicatedStorage:WaitForChild("GrabSystem")
local RequestNetworkOwnership = GrabSystem:WaitForChild("RequestNetworkOwnership")
local ReleaseNetworkOwnership = GrabSystem:WaitForChild("ReleaseNetworkOwnership")
local BreakConstraints = GrabSystem:WaitForChild("BreakConstraints")
local ThrowObject = GrabSystem:WaitForChild("ThrowObject")

-- State
local isGrabbing = false
local grabbedPart : BasePart? = nil
local grabAttachment : Attachment? = nil
local mouseAttachment : Attachment? = nil
local alignPosition : AlignPosition? = nil
local alignOrientation : AlignOrientation? = nil
local mousePart : Part? = nil
local currentDistance = 10
local baseDistance = 10

-- Gentle camera “hold” (don’t hard lock to 0)
local originalMaxZoom, originalMinZoom = nil, nil

-- Ownership throttle
local lastOwnershipPing = 0
local ownershipPingInterval = 0.35

-- Throwing system
local isChargingThrow = false
local throwChargeStartTime = 0
local throwChargeDuration = 0
local originalMousePartPosition = nil


-- ============ Helpers ============

local function createMousePart()
	local part = Instance.new("Part")
	part.Name = "MouseGrabPart"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Parent = Workspace
	return part
end

local function createAttachments(part : BasePart)
	local partAttachment = Instance.new("Attachment")
	partAttachment.Name = "Grab_Attachment"
	partAttachment.Position = Vector3.new(0, 0, 0) -- Center of the part
	partAttachment.Parent = part

	local mp = createMousePart()
	local mAttachment = Instance.new("Attachment")
	mAttachment.Name = "Mouse_Attachment"
	mAttachment.Position = Vector3.new(0, 0, 0) -- Center of the mouse part
	mAttachment.Parent = mp

	return partAttachment, mAttachment, mp
end

local function createAlign(partAttachment : Attachment, mouseAttachment : Attachment, part : BasePart)
	-- Mass-aware tuning with improved responsiveness
	local mass = part:GetMass()
	local baseResponsiveness = 30 -- Reduced for smoother movement
	local baseMaxForce = 15000 -- Increased for better control
	local massMultiplier = math.clamp(mass / 10, 0.5, 3)

	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = partAttachment
	alignPos.Attachment1 = mouseAttachment
	alignPos.Responsiveness = baseResponsiveness / massMultiplier
	alignPos.MaxForce = baseMaxForce * massMultiplier
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPos.RigidityEnabled = false
	alignPos.Parent = partAttachment.Parent

	-- Add orientation alignment for stability with lower responsiveness
	local alignOrient = Instance.new("AlignOrientation")
	alignOrient.Attachment0 = partAttachment
	alignOrient.Attachment1 = mouseAttachment
	alignOrient.Responsiveness = 10 / massMultiplier -- Lower for less aggressive orientation correction
	alignOrient.MaxTorque = 3000 * massMultiplier -- Reduced torque for smoother rotation
	alignOrient.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	alignOrient.RigidityEnabled = false
	alignOrient.Parent = partAttachment.Parent

	return alignPos, alignOrient
end

local function cleanupGrab()
	-- release server-side first (safe to call if already nil)
	-- Only release if not throwing (throwing already releases ownership)
	if grabbedPart and not isChargingThrow then
		ReleaseNetworkOwnership:FireServer(grabbedPart)
	end

	if alignPosition then alignPosition:Destroy() alignPosition = nil end
	if alignOrientation then alignOrientation:Destroy() alignOrientation = nil end
	if grabAttachment then grabAttachment:Destroy() grabAttachment = nil end
	if mouseAttachment then mouseAttachment:Destroy() mouseAttachment = nil end
	if mousePart then mousePart:Destroy() mousePart = nil end

	grabbedPart = nil
	isGrabbing = false

	-- Reset throw state
	isChargingThrow = false
	throwChargeStartTime = 0
	throwChargeDuration = 0
	originalMousePartPosition = nil

	-- restore camera zoom gently
	if originalMaxZoom then
		player.CameraMaxZoomDistance = originalMaxZoom
		originalMaxZoom = nil
	end
	if originalMinZoom then
		player.CameraMinZoomDistance = originalMinZoom
		originalMinZoom = nil
	end
end

local function updateMousePosition()
	if not isGrabbing or not mousePart then return end
	
	-- Get mouse position in world space
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local targetPosition = mouseRay.Origin + mouseRay.Direction * currentDistance
	
	-- Smooth the position to prevent jittering
	if mousePart.CFrame then
		local currentPos = mousePart.CFrame.Position
		local smoothedPos = currentPos:Lerp(targetPosition, 0.9) -- Increased responsiveness
		mousePart.CFrame = CFrame.new(smoothedPos)
	else
		mousePart.CFrame = CFrame.new(targetPosition)
	end
end

-- Cache raycast params (updated each call for dynamic filters)
local function raycastForPart()
	local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {camera, player.Character}
	local hit = Workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, params)
	if not hit then return nil end

	local part = hit.Instance
	if not part or part.Anchored then return nil end
	local grabValue = part:FindFirstChild("grab")
	if grabValue and grabValue:IsA("BoolValue") and grabValue.Value then
		return part
	end
	return nil
end


-- ============ Core flow ============

local function startGrab()
	local target = raycastForPart()
	if not target then return end

	grabbedPart = target
	isGrabbing = true
	
	-- Calculate the actual distance from camera to the part when grabbed
	local cameraToPart = (grabbedPart.Position - camera.CFrame.Position).Magnitude
	currentDistance = cameraToPart
	baseDistance = cameraToPart

	-- soft lock zoom to current distance (no jarring jump to 0)
	if originalMaxZoom == nil then originalMaxZoom = player.CameraMaxZoomDistance end
	if originalMinZoom == nil then originalMinZoom = player.CameraMinZoomDistance end
	local currentZoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	player.CameraMinZoomDistance = math.max(0.5, math.min(currentZoom, 15))
	player.CameraMaxZoomDistance = math.max(player.CameraMinZoomDistance + 0.5, currentZoom)

	-- Request ownership once immediately
	RequestNetworkOwnership:FireServer(grabbedPart)
	lastOwnershipPing = time()

	grabAttachment, mouseAttachment, mousePart = createAttachments(grabbedPart)
	alignPosition, alignOrientation = createAlign(grabAttachment, mouseAttachment, grabbedPart)

	-- Set initial mouse position to the part's current position
	mousePart.CFrame = grabbedPart.CFrame

end

local function tickOwnership()
	if not (isGrabbing and grabbedPart) then return end
	if time() - lastOwnershipPing >= ownershipPingInterval then
		RequestNetworkOwnership:FireServer(grabbedPart)
		lastOwnershipPing = time()
	end
end

local function startThrowCharge()
	if not isGrabbing or not grabbedPart then return end
	
	isChargingThrow = true
	throwChargeStartTime = time()
	
	-- Store original mouse part position
	if mousePart then
		originalMousePartPosition = mousePart.CFrame.Position
	end
end

local function updateThrowCharge()
	if not isChargingThrow or not isGrabbing or not grabbedPart or not mousePart then return end
	
	throwChargeDuration = time() - throwChargeStartTime
	local maxChargeTime = 2.0 -- Maximum 2 seconds charge
	
	-- Move object closer to humanoid while charging (not camera)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local humanoidPosition = player.Character.HumanoidRootPart.Position
		local currentPos = mousePart.CFrame.Position
		local directionToHumanoid = (humanoidPosition - currentPos).Unit
		
		-- Move closer by a small amount based on charge time
		local pullDistance = math.min(throwChargeDuration * 2, 3) -- Max 3 studs closer
		local newPosition = currentPos + directionToHumanoid * pullDistance
		
		mousePart.CFrame = CFrame.new(newPosition)
	end
end

local function endGrab()
	if isGrabbing then
		cleanupGrab()
	end
end

local function executeThrow()
	if not isChargingThrow or not isGrabbing or not grabbedPart then return end
	
	-- Calculate throw strength based on charge time and object mass
	local mass = grabbedPart:GetMass()
	local maxChargeTime = 2.0
	local chargeRatio = math.min(throwChargeDuration / maxChargeTime, 1.0)
	
	-- Base throw strength (will be multiplied by mass on server for realistic scaling)
	local baseThrowStrength = 50
	local massMultiplier = math.clamp(1 / (mass / 10), 0.3, 2) -- Heavier objects get less strength
	local throwStrength = baseThrowStrength * chargeRatio * massMultiplier
	
	-- Get throw direction (from humanoid to object)
	local throwDirection = Vector3.new(0, 0, 0)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local humanoidPosition = player.Character.HumanoidRootPart.Position
		local objectPosition = grabbedPart.Position
		throwDirection = (objectPosition - humanoidPosition).Unit
		
		-- Add some upward arc for realistic trajectory
		throwDirection = throwDirection + Vector3.new(0, 0.3, 0)
		throwDirection = throwDirection.Unit
	end
	
	-- Send throw request to server with direction and strength separately
	-- Server will handle wobble, momentum carry-through, and mass scaling
	ThrowObject:FireServer(grabbedPart, throwDirection, throwStrength)
	
	-- End the grab
	endGrab()
end

-- Optional: break constraints while grabbing (press F)
local function requestBreakIfApplicable()
	if isGrabbing and grabbedPart and grabbedPart.Parent then
		-- Only ask server to break if object explicitly allows it
		local breakable = grabbedPart:FindFirstChild("breakable")
		if breakable and breakable:IsA("BoolValue") and breakable.Value then
			BreakConstraints:FireServer(grabbedPart)
		end
	end
end

-- ============ Input bindings ============

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not isGrabbing then
			startGrab()
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		requestBreakIfApplicable()
	elseif input.KeyCode == Enum.KeyCode.E then
		if isGrabbing and not isChargingThrow then
			startThrowCharge()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isGrabbing then
			endGrab()
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		if isChargingThrow then
			executeThrow()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if gp then return end
	-- Distance control removed for realistic grabbing
end)

-- ============ Heartbeat ============

RunService.RenderStepped:Connect(function()
	-- If the grabbed part was destroyed mid-grab, bail safely
	if isGrabbing and (not grabbedPart or not grabbedPart.Parent) then
		endGrab()
		return
	end

	if isGrabbing then
		updateMousePosition()
		tickOwnership()
		if isChargingThrow then
			updateThrowCharge()
		end
	end
end)
