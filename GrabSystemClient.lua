local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

local GrabSystem = ReplicatedStorage:WaitForChild("GrabSystem")
local RequestNetworkOwnership = GrabSystem:WaitForChild("RequestNetworkOwnership")
local ReleaseNetworkOwnership = GrabSystem:WaitForChild("ReleaseNetworkOwnership")
local BreakConstraints = GrabSystem:WaitForChild("BreakConstraints")

local isGrabbing = false
local grabbedPart = nil
local grabAttachment = nil
local mouseAttachment = nil
local alignPosition = nil
local alignOrientation = nil
local pooledMousePart = nil -- reused between grabs to reduce allocations
local mouseAttachment = nil
local currentDistance = 10
local targetDistance = 10
local baseDistance = 10
local originalCameraMaxZoomDistance = nil
local originalCameraMinZoomDistance = nil

local function createMousePart()
    local part = Instance.new("Part")
    part.Name = "MouseGrabPart"
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Parent = workspace
    return part
end

local function createAttachments(part)
    local partAttachment = Instance.new("Attachment")
    partAttachment.Parent = part

    if not pooledMousePart or not pooledMousePart.Parent then
        pooledMousePart = pooledMousePart or createMousePart()
        pooledMousePart.Parent = workspace
    end

    local mouseAttachmentLocal = Instance.new("Attachment")
    mouseAttachmentLocal.Parent = pooledMousePart

    return partAttachment, mouseAttachmentLocal, pooledMousePart
end

local function createConstraints(partAttachment, mouseAttachment, part)
    local mass = part:GetMass()
    local baseResponsiveness = 50
    local baseMaxForce = 10000

    local massMultiplier = math.clamp(mass / 10, 0.5, 3)
    local responsiveness = math.clamp(baseResponsiveness / massMultiplier, 5, 200)
    local maxForce = math.clamp(baseMaxForce * massMultiplier, 1000, 50000)

    local alignPos = Instance.new("AlignPosition")
    alignPos.Attachment0 = partAttachment
    alignPos.Attachment1 = mouseAttachment
    alignPos.Responsiveness = responsiveness
    alignPos.MaxForce = maxForce
    alignPos.Parent = partAttachment.Parent

    return alignPos
end

local function createOrientationConstraint(partAttachment, mouseAttachment, part)
    local alignOri = Instance.new("AlignOrientation")
    alignOri.Attachment0 = partAttachment
    alignOri.Attachment1 = mouseAttachment
    alignOri.Responsiveness = 50
    alignOri.MaxTorque = 5000
    alignOri.Parent = partAttachment.Parent
    return alignOri
end

local grabbedAncestryConn = nil

local function cleanupGrab()
    if alignPosition then
        alignPosition:Destroy()
        alignPosition = nil
    end
    if alignOrientation then
        alignOrientation:Destroy()
        alignOrientation = nil
    end
    if grabAttachment then
        grabAttachment:Destroy()
        grabAttachment = nil
    end
    if mouseAttachment then
        mouseAttachment:Destroy()
        mouseAttachment = nil
    end
    -- keep pooledMousePart alive for reuse
    if mouseAttachment then
        mouseAttachment:Destroy()
        mouseAttachment = nil
    end
    if grabbedPart then
        ReleaseNetworkOwnership:FireServer(grabbedPart)
        if grabbedAncestryConn then
            grabbedAncestryConn:Disconnect()
            grabbedAncestryConn = nil
        end
        grabbedPart = nil
    end
    
    if originalCameraMaxZoomDistance then
        player.CameraMaxZoomDistance = originalCameraMaxZoomDistance
        originalCameraMaxZoomDistance = nil
    end
    if originalCameraMinZoomDistance then
        player.CameraMinZoomDistance = originalCameraMinZoomDistance
        originalCameraMinZoomDistance = nil
    end
    
    isGrabbing = false
end

local function updateMousePosition(dt)
    if not isGrabbing or not pooledMousePart then return end

    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    -- smooth distance
    currentDistance = currentDistance + (targetDistance - currentDistance) * math.clamp(dt * 12, 0, 1)
    local targetPosition = mouseRay.Origin + mouseRay.Direction * currentDistance
    pooledMousePart.CFrame = CFrame.new(targetPosition)
end

local function raycastForPart()
    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {camera, player.Character}
    
    local raycastResult = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, raycastParams)
    
    if raycastResult then
        local hitPart = raycastResult.Instance
        if hitPart and not hitPart.Anchored then
            local grabValue = hitPart:FindFirstChild("grab")
            if grabValue and grabValue:IsA("BoolValue") and grabValue.Value then
                return hitPart
            end
        end
    end
    return nil
end

local lastOwnershipRequest = 0
local ownershipRequestInterval = 0.5 -- seconds

local function startGrab()
    local targetPart = raycastForPart()
    if not targetPart then return end
    
    grabbedPart = targetPart
    isGrabbing = true
    currentDistance = baseDistance
    targetDistance = baseDistance
    
    originalCameraMaxZoomDistance = player.CameraMaxZoomDistance
    originalCameraMinZoomDistance = player.CameraMinZoomDistance
    player.CameraMaxZoomDistance = 0
    player.CameraMinZoomDistance = 0
    
    -- request ownership once at start
    RequestNetworkOwnership:FireServer(grabbedPart)
    lastOwnershipRequest = tick()
    
    grabAttachment, mouseAttachment, pooledMousePart = createAttachments(grabbedPart)
    alignPosition = createConstraints(grabAttachment, mouseAttachment, grabbedPart)

    -- optional orientation control if part requests it
    local lockRotation = grabbedPart:FindFirstChild("lockRotation")
    if lockRotation and lockRotation:IsA("BoolValue") and lockRotation.Value then
        alignOrientation = createOrientationConstraint(grabAttachment, mouseAttachment, grabbedPart)
    end
    
    local mass = grabbedPart:GetMass()
    print("Grabbed object with mass:", mass, "- Responsiveness:", alignPosition.Responsiveness, "- MaxForce:", alignPosition.MaxForce)
    
    updateMousePosition(0.016)
    
    local breakableValue = grabbedPart:FindFirstChild("breakable")
    if breakableValue and breakableValue:IsA("BoolValue") and breakableValue.Value then
        BreakConstraints:FireServer(grabbedPart)
    end

    -- cleanup if the part is removed from the world
    if grabbedPart then
        grabbedAncestryConn = grabbedPart.AncestryChanged:Connect(function()
            if not grabbedPart:IsDescendantOf(workspace) then
                cleanupGrab()
            end
        end)
    end
end

local function maintainNetworkOwnership()
    if isGrabbing and grabbedPart then
        local now = tick()
        if now - lastOwnershipRequest >= ownershipRequestInterval then
            RequestNetworkOwnership:FireServer(grabbedPart)
            lastOwnershipRequest = now
        end
    end
end

local function endGrab()
    if isGrabbing then
        cleanupGrab()
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not isGrabbing then
            startGrab()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isGrabbing then
            endGrab()
        end
    end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.UserInputType == Enum.UserInputType.MouseWheel and isGrabbing then
        targetDistance = math.max(2, math.min(50, targetDistance + input.Position.Z * 2))
        -- immediate visual update handled in RenderStepped smoothing
    end
end)



RunService.RenderStepped:Connect(function(dt)
    if isGrabbing then
        updateMousePosition(dt)
        maintainNetworkOwnership()
    end
end) 