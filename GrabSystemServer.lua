--!strict
-- GrabSystemServer.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrabSystem = Instance.new("Folder")
GrabSystem.Name = "GrabSystem"
GrabSystem.Parent = ReplicatedStorage

local RequestGrab = Instance.new("RemoteFunction")
RequestGrab.Name = "RequestGrab"
RequestGrab.Parent = GrabSystem

local UpdateTarget = Instance.new("RemoteEvent")
UpdateTarget.Name = "UpdateTarget"
UpdateTarget.Parent = GrabSystem

local ReleaseGrab = Instance.new("RemoteEvent")
ReleaseGrab.Name = "ReleaseGrab"
ReleaseGrab.Parent = GrabSystem

-- CONFIG
local MAX_DISTANCE = 60
local MIN_DISTANCE = 2
local MAX_LINEAR_SPEED = 120       -- studs/s clamp
local MAX_ANGULAR_SPEED = math.rad(240) -- rad/s clamp
local MAX_MASS = 200               -- kg
local REQUIRE_TAG = false          -- if true, only parts tagged "Grabbable" are allowed
local TAG_NAME = "Grabbable"

-- Per-player state
type GrabState = {
	part: BasePart?,
	att0: Attachment?,
	att1: Attachment?,
	alignPos: AlignPosition?,
	alignOri: AlignOrientation?,
	connections: { RBXScriptConnection },
	dist: number,
	lastUpdateTick: number
}

local state: { [Player]: GrabState } = {}

local function isGrabbable(part: BasePart): boolean
	if part.Anchored then return false end
	if part.AssemblyMass > MAX_MASS then return false end
	if REQUIRE_TAG and not CollectionService:HasTag(part, TAG_NAME) then return false end
	return true
end

local function cleanup(p: Player)
	local s = state[p]
	if not s then return end
	if s.alignPos then s.alignPos:Destroy() end
	if s.alignOri then s.alignOri:Destroy() end
	if s.att0 then s.att0:Destroy() end
	-- keep att1 on the part if it still exists (safe to destroy too)
	if s.att1 and s.att1.Parent then s.att1:Destroy() end
	for _,c in ipairs(s.connections) do c:Disconnect() end
	state[p] = nil
end

Players.PlayerRemoving:Connect(cleanup)

ReleaseGrab.OnServerEvent:Connect(function(p)
	cleanup(p)
end)

RequestGrab.OnServerInvoke = function(p: Player, part: BasePart, hitPos: Vector3, distance: number)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return false end
	if not isGrabbable(part) then return false end

	distance = math.clamp(distance, MIN_DISTANCE, MAX_DISTANCE)

	-- Create attachments/constraints
	local att0 = Instance.new("Attachment")
	att0.Name = "Grab_Att_Player"
	att0.Parent = workspace.Terrain -- unattached; world handle

	local att1 = Instance.new("Attachment")
	att1.Name = "Grab_Att_Part"
	att1.Parent = part

	local ap = Instance.new("AlignPosition")
	ap.RigidityEnabled = false
	ap.MaxForce = 1e6
	ap.Responsiveness = 80
	ap.Attachment0 = att0
	ap.Attachment1 = att1
	ap.ApplyAtCenterOfMass = true
	ap.Parent = part

	local ao = Instance.new("AlignOrientation")
	ao.RigidityEnabled = false
	ao.MaxTorque = 1e6
	ao.Responsiveness = 60
	ao.Attachment0 = att0
	ao.Attachment1 = att1
	ao.Parent = part

	-- network ownership
	if part:IsDescendantOf(workspace) then
		pcall(function() part:SetNetworkOwner(p) end)
	end

	state[p] = {
		part = part,
		att0 = att0,
		att1 = att1,
		alignPos = ap,
		alignOri = ao,
		connections = {},
		dist = distance,
		lastUpdateTick = 0
	}

	return true
end

-- Clamp helper
local function clampDelta(pos0: Vector3, pos1: Vector3, dt: number): Vector3
	local delta = pos1 - pos0
	local maxStep = math.max(0, MAX_LINEAR_SPEED * dt)
	if delta.Magnitude > maxStep and maxStep > 0 then
		delta = delta.Unit * maxStep
	end
	return pos0 + delta
end

UpdateTarget.OnServerEvent:Connect(function(p: Player, worldCFrame: CFrame, desiredDist: number, dt: number)
	local s = state[p]
	if not s or not s.att0 or not s.alignPos then return end

	desiredDist = math.clamp(desiredDist, MIN_DISTANCE, MAX_DISTANCE)
	s.dist = desiredDist

	-- Rate limit
	local now = os.clock()
	if now - s.lastUpdateTick < 1/90 then return end -- ~90Hz cap
	s.lastUpdateTick = now

	dt = math.clamp(dt or 1/60, 1/240, 1/15)

	-- Clamp linear travel
	local current = s.att0.WorldPosition
	local target = worldCFrame.Position
	local nextPos = clampDelta(current, target, dt)

	s.att0.WorldPosition = nextPos

	-- Clamp angular velocity by slerping small step
	local currentRot = s.att0.WorldCFrame - s.att0.WorldCFrame.Position
	local targetRot = worldCFrame - worldCFrame.Position

	-- compute small slerp factor from angular speed limit
	local _, _, _, m00,m01,m02,m10,m11,m12,m20,m21,m22 = (currentRot:ToOrientation())
	-- cheap factor: dt * (MAX_ANGULAR_SPEED / pi) ~ fraction per frame
	local t = math.clamp((MAX_ANGULAR_SPEED / math.pi) * dt, 0.02, 0.5)
	s.att0.WorldCFrame = currentRot:Lerp(targetRot, t) + nextPos
end)
