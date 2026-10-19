local player = game.Players.LocalPlayer

local function giveTool()
    local mouse = player:GetMouse()
    local tool = Instance.new("Tool")
    tool.RequiresHandle = false
    tool.Name = "Glacier TP Tool"
    
    tool.Activated:Connect(function()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local pos = mouse.Hit.Position + Vector3.new(0, 2.5, 0)
            player.Character.HumanoidRootPart.CFrame = CFrame.new(pos)
        end
    end)
    
    tool.Parent = player.Backpack
end

player.CharacterAdded:Connect(function()
    task.wait(1) 
    if not player.Backpack:FindFirstChild("Tp tool (Equip to Click TP)") then
        giveTool()
    end
end)

if player.Character then
    giveTool()
end
