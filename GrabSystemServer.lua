-- GrabSystemServer.lua
-- Improvements:
-- 1) Lightweight rate-limiting on ownership requests
-- 2) Extra sanity checks before breaking constraints
-- 3) Releases on both PlayerRemoving and CharacterRemoving

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local GrabSystem = ReplicatedStorage:WaitForChild("GrabSystem")
local RequestNetworkOwnership = GrabSystem:WaitForChild("RequestNetworkOwnership")
local ReleaseNetworkOwnership = GrabSystem:WaitForChild("ReleaseNetworkOwnership")
local BreakConstraints = GrabSystem:WaitForChild("BreakConstraints")
local ThrowObject = GrabSystem:WaitForChild("ThrowObject")

-- Basic validation
local function validatePlayerAndPart(player, part : Instance)
	if not player or not part then return false end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return false end
	if not part:IsA("BasePart") then return false end

	local playerPosition = player.Character.HumanoidRootPart.Position
	local partPosition = part.Position
	if (playerPosition - partPosition).Magnitude > 100 then return false end

	return true
end

-- Traverse connected parts by constraints, assign owner
local function setNetworkOwnershipForConnectedParts(root : BasePart, ownerPlayer)
	local connected, visited = {}, {}

	local function crawl(p : BasePart)
		if visited[p] then return end
		visited[p] = true
		if not p.Anchored then table.insert(connected, p) end

		for _, child in ipairs(p:GetChildren()) do
			if child:IsA("HingeConstraint") or child:IsA("WeldConstraint") or
			   child:IsA("BallSocketConstraint") or child:IsA("RodConstraint") or
			   child:IsA("PrismaticConstraint") or child:IsA("CylindricalConstraint") then

				local a0, a1 = child.Attachment0, child.Attachment1
				if a0 and a0.Parent and a0.Parent ~= p and a0.Parent:IsA("BasePart") then
					crawl(a0.Parent)
				end
				if a1 and a1.Parent and a1.Parent ~= p and a1.Parent:IsA("BasePart") then
					crawl(a1.Parent)
				end
			end
		end
	end

	crawl(root)
	for _, bp in ipairs(connected) do
		bp:SetNetworkOwner(ownerPlayer)
	end
end

-- Release connected parts back to server ownership
local function releaseConnectedParts(root : BasePart)
	local visited = {}
	local function crawl(p : BasePart)
		if visited[p] then return end
		visited[p] = true
		if not p.Anchored then p:SetNetworkOwner(nil) end

		for _, child in ipairs(p:GetChildren()) do
			if child:IsA("HingeConstraint") or child:IsA("WeldConstraint") or
			   child:IsA("BallSocketConstraint") or child:IsA("RodConstraint") or
			   child:IsA("PrismaticConstraint") or child:IsA("CylindricalConstraint") then

				local a0, a1 = child.Attachment0, child.Attachment1
				if a0 and a0.Parent and a0.Parent ~= p and a0.Parent:IsA("BasePart") then
					crawl(a0.Parent)
				end
				if a1 and a1.Parent and a1.Parent ~= p and a1.Parent:IsA("BasePart") then
					crawl(a1.Parent)
				end
			end
		end
	end
	crawl(root)
end

-- Simple per-player rate limit
local lastPingByPlayer : {[Player]: number} = {}
local function rateLimited(player : Player, interval : number)
	local now = os.clock()
	local last = lastPingByPlayer[player] or 0
	if now - last < interval then return true end
	lastPingByPlayer[player] = now
	return false
end

-- Collision detection system for thrown objects
local thrownObjects = {} -- Track objects that were recently thrown
local collisionCooldown = {} -- Prevent multiple hits from same object

-- Function to activate ragdoll for a player
local function activateRagdoll(player)
	local character = player.Character
	if not character then return end
	
	local isRagdoll = character:FindFirstChild("IsRagdoll")
	if not isRagdoll then
		-- Create IsRagdoll BoolValue if it doesn't exist
		isRagdoll = Instance.new("BoolValue")
		isRagdoll.Name = "IsRagdoll"
		isRagdoll.Parent = character
	end
	
	-- Activate ragdoll
	isRagdoll.Value = true
	
	-- Auto-deactivate after 10 seconds
	spawn(function()
		wait(10)
		if isRagdoll and isRagdoll.Parent then
			isRagdoll.Value = false
		end
	end)
end

-- Function to calculate impact force and determine if ragdoll should activate
local function calculateImpactForce(object, hitPlayer)
	local objectMass = object:GetMass()
	local objectVelocity = object.Velocity
	local speed = objectVelocity.Magnitude
	
	-- Calculate impact force (mass * velocity^2 for kinetic energy approximation)
	local impactForce = objectMass * (speed * speed) * 0.1 -- Scale factor for realistic thresholds
	
	-- Minimum force required to ragdoll (adjustable)
	local minRagdollForce = 100
	
	-- Check if force is sufficient and player isn't on cooldown
	local playerId = hitPlayer.UserId
	if impactForce > minRagdollForce and not collisionCooldown[object] then
		-- Apply cooldown to prevent multiple hits
		collisionCooldown[object] = true
		spawn(function()
			wait(0.1)
			collisionCooldown[object] = nil
		end)
		
		-- Activate ragdoll
		activateRagdoll(hitPlayer)
		
		-- Apply enhanced knockback force to the hit player
		local hitCharacter = hitPlayer.Character
		if hitCharacter and hitCharacter:FindFirstChild("HumanoidRootPart") then
			local hitRootPart = hitCharacter.HumanoidRootPart
			
			-- Calculate enhanced knockback direction (from object to player)
			local knockbackDirection = (hitRootPart.Position - object.Position).Unit
			
			-- Enhanced main knockback force (increased from 40% to 60%)
			local playerKnockbackForce = knockbackDirection * (impactForce * 0.6)
			hitRootPart:ApplyImpulse(playerKnockbackForce)
			
			-- Enhanced upward force for more dramatic launch effect
			local upwardForce = Vector3.new(0, impactForce * 0.25, 0)
			hitRootPart:ApplyImpulse(upwardForce)
			
			-- Add horizontal spread for more chaotic knockback
			local spreadForce = Vector3.new(
				math.random(-impactForce * 0.1, impactForce * 0.1),
				0,
				math.random(-impactForce * 0.1, impactForce * 0.1)
			)
			hitRootPart:ApplyImpulse(spreadForce)
			
			-- Enhanced angular impulse for more dramatic tumbling
			local tumbleForce = Vector3.new(
				math.random(-impactForce * 0.15, impactForce * 0.15),
				math.random(-impactForce * 0.15, impactForce * 0.15),
				math.random(-impactForce * 0.15, impactForce * 0.15)
			)
			hitRootPart:ApplyAngularImpulse(tumbleForce)
			
			-- Add secondary impulse after a short delay for sustained effect
			spawn(function()
				wait(0.1)
				if hitRootPart and hitRootPart.Parent then
					-- Secondary knockback with reduced force
					local secondaryKnockback = knockbackDirection * (impactForce * 0.2)
					hitRootPart:ApplyImpulse(secondaryKnockback)
					
					-- Additional upward force for sustained lift
					local secondaryUpward = Vector3.new(0, impactForce * 0.1, 0)
					hitRootPart:ApplyImpulse(secondaryUpward)
				end
			end)
			
			-- Add tertiary impulse for even more dramatic effect
			spawn(function()
				wait(0.2)
				if hitRootPart and hitRootPart.Parent then
					-- Final push with even more spread
					local finalSpread = Vector3.new(
						math.random(-impactForce * 0.05, impactForce * 0.05),
						math.random(0, impactForce * 0.05),
						math.random(-impactForce * 0.05, impactForce * 0.05)
					)
					hitRootPart:ApplyImpulse(finalSpread)
				end
			end)
		end
		
		-- Apply enhanced force back to the object (bounce effect)
		local bounceDirection = (object.Position - hitPlayer.Character.HumanoidRootPart.Position).Unit
		local bounceForce = bounceDirection * (impactForce * 0.4) -- Increased bounce force
		object:ApplyImpulse(bounceForce)
		
		-- Add upward bounce for more dramatic object reaction
		local upwardBounce = Vector3.new(0, impactForce * 0.2, 0)
		object:ApplyImpulse(upwardBounce)
		
		-- Add random spread to object bounce for more chaotic effect
		local bounceSpread = Vector3.new(
			math.random(-impactForce * 0.1, impactForce * 0.1),
			0,
			math.random(-impactForce * 0.1, impactForce * 0.1)
		)
		object:ApplyImpulse(bounceSpread)
		
		-- Add enhanced angular impulse to object for more dramatic spinning
		local objectSpin = Vector3.new(
			math.random(-impactForce * 0.2, impactForce * 0.2),
			math.random(-impactForce * 0.2, impactForce * 0.2),
			math.random(-impactForce * 0.2, impactForce * 0.2)
		)
		object:ApplyAngularImpulse(objectSpin)
		
		return true
	end
	
	return false
end

-- Function to track thrown objects for collision detection
local function trackThrownObject(object, thrower)
	-- Add to tracking list
	thrownObjects[object] = {
		thrower = thrower,
		thrownTime = time()
	}
	
	-- Set up collision detection
	local connection
	connection = object.Touched:Connect(function(hit)
		local hitCharacter = hit.Parent
		local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		
		-- Check if hit is a player (not the thrower) and object is still being tracked
		if hitPlayer and hitPlayer ~= thrower and thrownObjects[object] then
			-- Check if hit part is part of character (not accessories)
			if hitCharacter:FindFirstChild("Humanoid") and hitCharacter:FindFirstChild("HumanoidRootPart") then
				calculateImpactForce(object, hitPlayer)
			end
		end
	end)
	
	-- Clean up tracking after 5 seconds
	spawn(function()
		wait(5)
		thrownObjects[object] = nil
		if connection then
			connection:Disconnect()
		end
	end)
end

-- ============ Signals ============

RequestNetworkOwnership.OnServerEvent:Connect(function(player, part)
	if rateLimited(player, 0.15) then return end
	if not validatePlayerAndPart(player, part) then return end

	local grabValue = part:FindFirstChild("grab")
	if not (grabValue and grabValue:IsA("BoolValue") and grabValue.Value) then return end

	-- Assign only if different owner; keeps calls idempotent
	if part:GetNetworkOwner() ~= player then
		setNetworkOwnershipForConnectedParts(part, player)
	end
end)

ReleaseNetworkOwnership.OnServerEvent:Connect(function(player, part)
	if not validatePlayerAndPart(player, part) then return end
	releaseConnectedParts(part)
end)

BreakConstraints.OnServerEvent:Connect(function(player, part)
	if not validatePlayerAndPart(player, part) then return end

	local grabValue = part:FindFirstChild("grab")
	local breakableValue = part:FindFirstChild("breakable")
	if not (grabValue and grabValue:IsA("BoolValue") and grabValue.Value) then return end
	if not (breakableValue and breakableValue:IsA("BoolValue") and breakableValue.Value) then return end

	-- Optional safety: require current owner to be the caller
	if part:GetNetworkOwner() ~= player then return end

	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("HingeConstraint") or d:IsA("WeldConstraint") or
		   d:IsA("BallSocketConstraint") or d:IsA("RodConstraint") or
		   d:IsA("PrismaticConstraint") or d:IsA("CylindricalConstraint") then
			d:Destroy()
		end
	end
end)

ThrowObject.OnServerEvent:Connect(function(player, part, throwDirection, throwStrength)
	if not validatePlayerAndPart(player, part) then return end

	local grabValue = part:FindFirstChild("grab")
	if not (grabValue and grabValue:IsA("BoolValue") and grabValue.Value) then return end

	-- Optional safety: require current owner to be the caller
	if part:GetNetworkOwner() ~= player then return end

	-- Release network ownership first
	releaseConnectedParts(part)

	-- Get part mass for realistic force scaling
	local mass = part:GetMass()
	
	-- Add realistic wobble to simulate hand-release imperfection
	local wobble = Vector3.new(
		math.random(-10, 10) / 200,  -- Small random offset
		math.random(-10, 10) / 200,
		math.random(-10, 10) / 200
	)
	local finalDirection = (throwDirection + wobble).Unit
	
	-- Add player momentum carry-through for realistic physics
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		finalDirection = finalDirection + root.Velocity * 0.3
	end
	
	-- Apply realistic impulse force (scales with mass)
	local impulseForce = finalDirection * mass * throwStrength
	part:ApplyImpulse(impulseForce)
	
	-- Add angular impulse for realistic spin and wobble
	local angularImpulse = Vector3.new(
		math.random(-5, 5) * mass,
		math.random(-5, 5) * mass,
		math.random(-5, 5) * mass
	)
	part:ApplyAngularImpulse(angularImpulse)
	
	-- Start tracking this object for collision detection
	trackThrownObject(part, player)
end)

-- Safety: release any parts owned by player on leave / respawn
local function releaseAllFromPlayer(p : Player)
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetNetworkOwner() == p then
			inst:SetNetworkOwner(nil)
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	releaseAllFromPlayer(p)
	lastPingByPlayer[p] = nil
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterRemoving:Connect(function()
		releaseAllFromPlayer(p)
	end)
end)
