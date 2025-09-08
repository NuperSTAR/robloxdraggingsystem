local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrabSystem = ReplicatedStorage:WaitForChild("GrabSystem")
local RequestNetworkOwnership = GrabSystem:WaitForChild("RequestNetworkOwnership")
local ReleaseNetworkOwnership = GrabSystem:WaitForChild("ReleaseNetworkOwnership")
local BreakConstraints = GrabSystem:WaitForChild("BreakConstraints")

-- Simple rate limiting and validation
local lastRequestTime = {}
local REQUEST_COOLDOWN = 0.2
local MAX_GRAB_DISTANCE = 60

local function isValidGrabbable(part)
    if not part or not part:IsA("BasePart") then return false end
    local grabValue = part:FindFirstChild("grab")
    if not (grabValue and grabValue:IsA("BoolValue") and grabValue.Value) then return false end
    return true
end

RequestNetworkOwnership.OnServerEvent:Connect(function(player, part)
    if typeof(part) ~= "Instance" then return end
    if not part or not part:IsA("BasePart") then return end

    local now = tick()
    lastRequestTime[player] = lastRequestTime[player] or 0
    if now - lastRequestTime[player] < REQUEST_COOLDOWN then
        return
    end
    lastRequestTime[player] = now

    -- validate
    if not isValidGrabbable(part) then return end

    -- check distance to player's character
    local char = player.Character
    if not char or not char.PrimaryPart then return end
    if (char.PrimaryPart.Position - part.Position).Magnitude > MAX_GRAB_DISTANCE then return end

    -- set network owner
    pcall(function()
        part:SetNetworkOwner(player)
    end)
end)

ReleaseNetworkOwnership.OnServerEvent:Connect(function(player, part)
    if typeof(part) ~= "Instance" then return end
    if not part or not part:IsA("BasePart") then return end

    -- only clear owner if the player currently owns it
    pcall(function()
        part:SetNetworkOwner(nil)
    end)
end)

BreakConstraints.OnServerEvent:Connect(function(player, part)
    if typeof(part) ~= "Instance" then return end
    if not part or not part:IsA("BasePart") then return end

    -- validate breakable
    local breakValue = part:FindFirstChild("breakable")
    if not (breakValue and breakValue:IsA("BoolValue") and breakValue.Value) then return end

    -- find Constraints and remove them safely
    for _, child in pairs(part.Parent:GetChildren()) do
        if child:IsA("WeldConstraint") or child:IsA("HingeConstraint") or child:IsA("RodConstraint") or child:IsA("BallSocketConstraint") then
            if child.Attachment0 and child.Attachment1 then
                -- only break constraints connected to this part
                if child.Attachment0.Parent == part or child.Attachment1.Parent == part then
                    child:Destroy()
                end
            end
        end
    end
end)

print("GrabSystem server running")

 