local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function createGrabSystem()
    local grabSystem = Instance.new("Folder")
    grabSystem.Name = "GrabSystem"
    grabSystem.Parent = ReplicatedStorage
    
    local requestNetworkOwnership = Instance.new("RemoteEvent")
    requestNetworkOwnership.Name = "RequestNetworkOwnership"
    requestNetworkOwnership.Parent = grabSystem
    
    local releaseNetworkOwnership = Instance.new("RemoteEvent")
    releaseNetworkOwnership.Name = "ReleaseNetworkOwnership"
    releaseNetworkOwnership.Parent = grabSystem
    
    local breakConstraints = Instance.new("RemoteEvent")
    breakConstraints.Name = "BreakConstraints"
    breakConstraints.Parent = grabSystem
    
    local throwObject = Instance.new("RemoteEvent")
    throwObject.Name = "ThrowObject"
    throwObject.Parent = grabSystem
    
    print("GrabSystem setup complete!")
end

local function createRagdollSystem()
    local activateRagdoll = Instance.new("RemoteEvent")
    activateRagdoll.Name = "ActivateRagdoll"
    activateRagdoll.Parent = ReplicatedStorage
    
    activateRagdoll.OnServerEvent:Connect(function(player)
        local character = player.Character
        if character then
            local activateBoolValue = character:FindFirstChild("IsRagdoll")
            if activateBoolValue then
                activateBoolValue.Value = not activateBoolValue.Value
            end
        end
    end)
    
    print("Ragdoll system setup complete!")
end

createGrabSystem()
createRagdollSystem() 
