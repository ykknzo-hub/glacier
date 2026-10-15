local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "touchflinghub"
local CLEANUP_KEY = "__touchfling_hub_cleanup"

local env = (getgenv and getgenv()) or _G

local function getGuiParent()
	if type(gethui) == "function" then
		local ok, result = pcall(gethui)
		if ok and typeof(result) == "Instance" then
			return result
		end
	end
	local ok, coreGui = pcall(function()
		local cg = game:GetService("CoreGui")
		local probe = Instance.new("Folder")
		probe.Parent = cg
		probe:Destroy()
		return cg
	end)
	if ok and coreGui then
		return coreGui
	end
	return playerGui
end

local guiParent = getGuiParent()

if type(env[CLEANUP_KEY]) == "function" then
	pcall(env[CLEANUP_KEY])
end
env[CLEANUP_KEY] = nil

for _, container in ipairs({ playerGui, guiParent }) do
	for _, child in ipairs(container:GetChildren()) do
		if child.Name == GUI_NAME then
			child:Destroy()
		end
	end
end

local connections = {}
local function track(connection)
	table.insert(connections, connection)
	return connection
end

local flingEnabled = false
local collisionEnabled = false
local flingStrength = 500000
local movementDelta = 0.1
local lastVelocity = nil
local isResetting = false
local charAlive = true

local function handleFling()
	if not flingEnabled or isResetting or not charAlive then return end
	local char = player.Character
	if not char or not char.Parent then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not root or not root.Parent then return end
	if not humanoid or humanoid.Health <= 0 then
		charAlive = false
		return
	end

	lastVelocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = lastVelocity * flingStrength + Vector3.new(0, flingStrength, 0)
	RunService.RenderStepped:Wait()

	if char and char.Parent and root and root.Parent then
		root.AssemblyLinearVelocity = lastVelocity
	end

	RunService.Stepped:Wait()

	if char and char.Parent and root and root.Parent then
		root.AssemblyLinearVelocity = lastVelocity + Vector3.new(0, movementDelta, 0)
		movementDelta = movementDelta * -1
	end
end

local function handleCollisions()
	if not collisionEnabled then return end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			pcall(function()
				for _, part in ipairs(other.Character:GetChildren()) do
					if part:IsA("BasePart") and part.CanCollide then
						part.CanCollide = false
						if part.Name == "Torso" or part.Name == "UpperTorso" then
							part.Massless = true
						end
						part.AssemblyLinearVelocity = Vector3.zero
						part.AssemblyAngularVelocity = Vector3.zero
					end
				end
			end)
		end
	end
end

local function setupCharacter()
	local char = player.Character
	if char then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				charAlive = false
			end)
		end
		charAlive = true
	end
end

setupCharacter()
track(player.CharacterAdded:Connect(function()
	isResetting = true
	task.wait(0.2)
	setupCharacter()
	isResetting = false
end))

track(RunService.Heartbeat:Connect(handleFling))
track(RunService.Stepped:Connect(handleCollisions))

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local FULL_SIZE = UDim2.new(0, 220, 0, 110)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)
local ON_COLOR = Color3.fromRGB(0, 180, 80)
local OFF_COLOR = Color3.fromRGB(40, 40, 40)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 996
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Position = UDim2.new(0.5, -110, 0.5, -55)
mainFrame.Size = FULL_SIZE
mainFrame.BackgroundColor3 = BODY_COLOR
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 4)
mainCorner.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 0, TITLE_HEIGHT)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "TouchFling"
titleLabel.TextColor3 = WHITE
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 3
titleLabel.Parent = mainFrame

local function makeTitleButton(name, text, xOffset)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, TITLE_HEIGHT, 0, TITLE_HEIGHT)
	btn.Position = UDim2.new(1, xOffset, 0, 0)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.ZIndex = 3
	btn.Parent = mainFrame
	return btn
end

local closeButton = makeTitleButton("Close", "×", -TITLE_HEIGHT)
local minimiseButton = makeTitleButton("Minimise", "–", -TITLE_HEIGHT * 2)

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, TITLE_HEIGHT)
body.Size = UDim2.new(1, 0, 1, -TITLE_HEIGHT)
body.BackgroundTransparency = 1
body.Parent = mainFrame

local function makeRowLabel(text, y)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 14, 0, y)
	label.Size = UDim2.new(0, 80, 0, 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = WHITE
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	label.Parent = body
	return label
end

local function makeToggleBtn(text, y)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 70, 0, 22)
	btn.Position = UDim2.new(1, -(12 + 70), 0, y + 1)
	btn.BackgroundColor3 = OFF_COLOR
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = MUTED
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = body
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	return btn
end

makeRowLabel("Fling", 6)
local flingBtn = makeToggleBtn("OFF", 6)

makeRowLabel("No-Clip", 38)
local noclipBtn = makeToggleBtn("OFF", 38)

local function updateToggle(btn, enabled)
	btn.Text = enabled and "ON" or "OFF"
	btn.TextColor3 = enabled and WHITE or MUTED
	btn.BackgroundColor3 = enabled and ON_COLOR or OFF_COLOR
end

flingBtn.MouseButton1Click:Connect(function()
	flingEnabled = not flingEnabled
	updateToggle(flingBtn, flingEnabled)
end)

noclipBtn.MouseButton1Click:Connect(function()
	collisionEnabled = not collisionEnabled
	updateToggle(noclipBtn, collisionEnabled)
end)

local minimised = false
minimiseButton.MouseButton1Click:Connect(function()
	minimised = not minimised
	body.Visible = not minimised
	TweenService:Create(mainFrame, TWEEN_INFO, {
		Size = minimised and UDim2.new(0, FULL_SIZE.X.Offset, 0, TITLE_HEIGHT) or FULL_SIZE,
	}):Play()
end)

track(player.Chatted:Connect(function(message)
	local msg = string.lower(message)
	if msg == ";fling" or msg == ";touchfling" then
		mainFrame.Visible = not mainFrame.Visible
	end
end))

local function cleanup()
	flingEnabled = false
	collisionEnabled = false
	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(connections)
	pcall(function()
		screenGui:Destroy()
	end)
end

env[CLEANUP_KEY] = cleanup

closeButton.MouseButton1Click:Connect(function()
	if env[CLEANUP_KEY] == cleanup then
		env[CLEANUP_KEY] = nil
	end
	cleanup()
end)
