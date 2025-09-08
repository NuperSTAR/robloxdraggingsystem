local function createExampleParts()
    local function createGrabbablePart(position, size, color, material, mass, isBreakable, name)
        local part = Instance.new("Part")
        part.Position = position
        part.Size = size
        part.Color = color
        part.Material = material
        part.Anchored = false
        part.CanCollide = true
        part.Name = name
        part.Parent = workspace
        
        if mass then
            part.CustomPhysicalProperties = PhysicalProperties.new(mass, 0.3, 0.5, 1, 1)
        end
        
        local grabValue = Instance.new("BoolValue")
        grabValue.Name = "grab"
        grabValue.Value = true
        grabValue.Parent = part
        
        if isBreakable then
            local breakableValue = Instance.new("BoolValue")
            breakableValue.Name = "breakable"
            breakableValue.Value = true
            breakableValue.Parent = part
        end
        
        return part
    end
    
    local function createConnectedParts()
        local basePart = createGrabbablePart(
            Vector3.new(0, 5, 0), 
            Vector3.new(2, 1, 2), 
            Color3.fromRGB(255, 0, 0), 
            Enum.Material.Metal, 
            25, 
            true, 
            "HeavyBreakableBase"
        )
        local connectedPart = createGrabbablePart(
            Vector3.new(0, 6.5, 0), 
            Vector3.new(1, 1, 1), 
            Color3.fromRGB(0, 255, 0), 
            Enum.Material.Plastic, 
            5, 
            false, 
            "LightConnectedPart"
        )
        
        local attachment1 = Instance.new("Attachment")
        attachment1.Parent = basePart
        attachment1.Position = Vector3.new(0, 0.5, 0)
        
        local attachment2 = Instance.new("Attachment")
        attachment2.Parent = connectedPart
        attachment2.Position = Vector3.new(0, -0.5, 0)
        
        local weldConstraint = Instance.new("WeldConstraint")
        weldConstraint.Attachment0 = attachment1
        weldConstraint.Attachment1 = attachment2
        weldConstraint.Parent = basePart
        
        return basePart
    end
    
    local function createMassDemo()
        local demoParts = {
            {pos = Vector3.new(-10, 5, 0), size = Vector3.new(1, 1, 1), color = Color3.fromRGB(255, 255, 255), material = Enum.Material.Plastic, mass = 1, name = "Feather (1 mass)"},
            {pos = Vector3.new(-8, 5, 0), size = Vector3.new(1.2, 1.2, 1.2), color = Color3.fromRGB(200, 200, 200), material = Enum.Material.Wood, mass = 5, name = "Wood Block (5 mass)"},
            {pos = Vector3.new(-6, 5, 0), size = Vector3.new(1.5, 1.5, 1.5), color = Color3.fromRGB(150, 150, 150), material = Enum.Material.Concrete, mass = 15, name = "Concrete Block (15 mass)"},
            {pos = Vector3.new(-4, 5, 0), size = Vector3.new(1.8, 1.8, 1.8), color = Color3.fromRGB(100, 100, 100), material = Enum.Material.Metal, mass = 30, name = "Metal Block (30 mass)"},
            {pos = Vector3.new(-2, 5, 0), size = Vector3.new(2, 2, 2), color = Color3.fromRGB(50, 50, 50), material = Enum.Material.DiamondPlate, mass = 50, name = "Heavy Block (50 mass)"}
        }
        
        for _, partData in pairs(demoParts) do
            createGrabbablePart(
                partData.pos, 
                partData.size, 
                partData.color, 
                partData.material, 
                partData.mass, 
                false, 
                partData.name
            )
        end
    end
    
    local function createSpecialObjects()
        createGrabbablePart(Vector3.new(8, 5, 0), Vector3.new(2, 2, 2), Color3.fromRGB(0, 255, 255), Enum.Material.Ice, 3, false, "Ice Block (Light)")
        createGrabbablePart(Vector3.new(10, 5, 0), Vector3.new(1.5, 3, 1.5), Color3.fromRGB(255, 165, 0), Enum.Material.Neon, 8, true, "Breakable Neon")
        createGrabbablePart(Vector3.new(12, 5, 0), Vector3.new(3, 1, 1), Color3.fromRGB(128, 0, 128), Enum.Material.Slate, 40, false, "Heavy Slate")
    end
    
    local function createInfoSign()
        local sign = Instance.new("Part")
        sign.Position = Vector3.new(0, 8, 0)
        sign.Size = Vector3.new(8, 1, 0.2)
        sign.Color = Color3.fromRGB(0, 0, 0)
        sign.Material = Enum.Material.Neon
        sign.Anchored = true
        sign.CanCollide = false
        sign.Name = "MassDemoInfo"
        sign.Parent = workspace
        
        local surfaceGui = Instance.new("SurfaceGui")
        surfaceGui.Parent = sign
        surfaceGui.Face = Enum.NormalId.Front
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = "MASS-BASED DRAGGING DEMO\nTry grabbing different objects!\nHeavier objects are harder to move."
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.GothamBold
        textLabel.Parent = surfaceGui
    end
    
    createMassDemo()
    createSpecialObjects()
    createConnectedParts()
    createInfoSign()
    
    print("=== MASS-BASED GRABBING SYSTEM DEMO ===")
    print("Created demo objects with varying masses:")
    print("- Feather (1 mass): Very light and responsive")
    print("- Wood Block (5 mass): Light and nimble")
    print("- Concrete Block (15 mass): Medium weight")
    print("- Metal Block (30 mass): Heavy and slow")
    print("- Heavy Block (50 mass): Very heavy, requires effort")
    print("- Special objects: Ice, Neon, and Slate with unique properties")
    print("- Connected parts: Heavy base with light connected part")
    print("Try grabbing different objects to feel the mass-based physics!")
end

createExampleParts() 