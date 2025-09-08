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
    
    print("GrabSystem setup complete!")
end

createGrabSystem() 