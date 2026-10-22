local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "mobileshiftlock"
local CLEANUP_KEY = "__mobileshiftlock_cleanup"

local imgOff = "http://www.roblox.com/asset/?id=115666586415476"
local imgOn = "http://www.roblox.com/asset/?id=135221094902079"

local env = (getgenv and getgenv()) or _G

if type(env[CLEANUP_KEY]) == "function" then
	pcall(env[CLEANUP_KEY])
end
env[CLEANUP_KEY] = nil

for _, child in ipairs(playerGui:GetChildren()) do
	if child.Name == GUI_NAME then
		child:Destroy()
	end
end

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local FULL_SIZE = UDim2.new(0, 220, 0, 90)
local CORNER = UDim.new(0, 4)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(70, 70, 70)

local minimised = false
local isAnimating = false

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local mainFrame = Instance.new("CanvasGroup")
mainFrame.Name = "MainFrame"
mainFrame.Position = UDim2.new(0.5, -110, 0.5, -45)
mainFrame.Size = FULL_SIZE
mainFrame.BackgroundColor3 = BODY_COLOR
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = CORNER
mainCorner.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
titleBar.BackgroundTransparency = 1
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 2
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "mobile shift lock"
titleLabel.TextColor3 = WHITE
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 3
titleLabel.Parent = titleBar

local body = Instance.new("CanvasGroup")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, 0)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ZIndex = 1
body.Parent = mainFrame

local function makeIconButton(name, xOffset)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, TITLE_HEIGHT, 0, TITLE_HEIGHT)
	btn.Position = UDim2.new(1, xOffset, 0, 0)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 3
	btn.Parent = titleBar

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.Size = UDim2.new(0, 8, 0, 8)
	icon.BackgroundTransparency = 1
	icon.ZIndex = 3
	icon.Parent = btn

	local horizontal = Instance.new("Frame")
	horizontal.Name = "Horizontal"
	horizontal.AnchorPoint = Vector2.new(0.5, 0.5)
	horizontal.Position = UDim2.new(0.5, 0, 0.5, 0)
	horizontal.Size = UDim2.new(1, 0, 0, 2)
	horizontal.BackgroundColor3 = WHITE
	horizontal.BorderSizePixel = 0
	horizontal.ZIndex = 3
	horizontal.Parent = icon

	local vertical = Instance.new("Frame")
	vertical.Name = "Vertical"
	vertical.AnchorPoint = Vector2.new(0.5, 0.5)
	vertical.Position = UDim2.new(0.5, 0, 0.5, 0)
	vertical.Size = UDim2.new(0, 2, 1, 0)
	vertical.BackgroundColor3 = WHITE
	vertical.BorderSizePixel = 0
	vertical.ZIndex = 3
	vertical.Parent = icon

	for _, bar in ipairs({ horizontal, vertical }) do
		local barRound = Instance.new("UICorner")
		barRound.CornerRadius = UDim.new(1, 0)
		barRound.Parent = bar
	end

	return btn, icon, vertical
end

local closeButton, closeIcon = makeIconButton("CloseButton", -TITLE_HEIGHT)
local minimiseButton, _, minimiseVertical = makeIconButton("MinimiseButton", -TITLE_HEIGHT * 2)

closeIcon.Size = UDim2.new(0, 11, 0, 11)
closeIcon.Rotation = 45
minimiseVertical.Visible = false

local locked = false
local enabled = false
local shiftDown = false
local lockGui, lockIcon
local lockConns = {}
local refreshSwitch

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function applyLock()
	if lockIcon then
		lockIcon.Image = locked and imgOn or imgOff
	end
	local hum = getHumanoid()
	if hum then
		hum.AutoRotate = not locked
	end
	if refreshSwitch then
		refreshSwitch()
	end
end

local function toggleLock()
	locked = not locked
	applyLock()
end

local function destroyButton()
	for _, c in ipairs(lockConns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(lockConns)
	if lockGui then
		pcall(function() lockGui:Destroy() end)
	end
	lockGui, lockIcon = nil, nil
end

local function createButton()
	if lockGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftLockGui"
	gui.ResetOnSpawn = false
	local ok = pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = playerGui
	end
	lockGui = gui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 100, 0, 100)
	frame.Position = UDim2.new(0.8, 0, 0.7, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local btn = Instance.new("ImageButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Parent = frame

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = btn

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.Image = locked and imgOn or imgOff
	icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
	icon.BackgroundTransparency = 1
	icon.Parent = btn
	lockIcon = icon

	table.insert(lockConns, btn.MouseButton1Click:Connect(toggleLock))

	table.insert(lockConns, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.LeftShift and not shiftDown then
			shiftDown = true
			toggleLock()
		end
	end))

	table.insert(lockConns, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			shiftDown = false
		end
	end))

	table.insert(lockConns, RunService.RenderStepped:Connect(function()
		if not locked then return end
		local cam = workspace.CurrentCamera
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (cam and hrp) then return end
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.001 then return end
		hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flat.Unit)
	end))

	table.insert(lockConns, player.CharacterAdded:Connect(function(char)
		shiftDown = false
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.AutoRotate = not locked
		end
	end))
end

local function setShiftLock(state)
	enabled = state
	locked = false
	if state then
		createButton()
		applyLock()
	else
		applyLock()
		destroyButton()
	end
end

local ROW_Y = TITLE_HEIGHT + 16

local row = Instance.new("Frame")
row.Name = "ToggleRow"
row.Position = UDim2.new(0, 12, 0, ROW_Y)
row.Size = UDim2.new(1, -24, 0, 28)
row.BackgroundTransparency = 1
row.ZIndex = 3
row.Parent = body

local rowLabel = Instance.new("TextLabel")
rowLabel.Size = UDim2.new(1, -56, 1, 0)
rowLabel.Position = UDim2.new(0, 4, 0, 0)
rowLabel.BackgroundTransparency = 1
rowLabel.Text = "Shift Lock"
rowLabel.TextColor3 = WHITE
rowLabel.Font = Enum.Font.GothamMedium
rowLabel.TextSize = 12
rowLabel.TextXAlignment = Enum.TextXAlignment.Left
rowLabel.ZIndex = 3
rowLabel.Parent = row

local switch = Instance.new("TextButton")
switch.Name = "Switch"
switch.AnchorPoint = Vector2.new(1, 0.5)
switch.Position = UDim2.new(1, 0, 0.5, 0)
switch.Size = UDim2.new(0, 40, 0, 20)
switch.BackgroundColor3 = MUTED
switch.BorderSizePixel = 0
switch.Text = ""
switch.AutoButtonColor = false
switch.ZIndex = 4
switch.Parent = row

local switchCorner = Instance.new("UICorner")
switchCorner.CornerRadius = UDim.new(1, 0)
switchCorner.Parent = switch

local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.AnchorPoint = Vector2.new(0, 0.5)
knob.Position = UDim2.new(0, 2, 0.5, 0)
knob.Size = UDim2.new(0, 16, 0, 16)
knob.BackgroundColor3 = WHITE
knob.BorderSizePixel = 0
knob.ZIndex = 5
knob.Parent = switch

local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

local SWITCH_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

refreshSwitch = function()
	TweenService:Create(knob, SWITCH_TWEEN, {
		Position = enabled and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
	}):Play()
	TweenService:Create(switch, SWITCH_TWEEN, {
		BackgroundColor3 = enabled and Color3.fromRGB(60, 190, 90) or MUTED,
	}):Play()
end

switch.MouseButton1Click:Connect(function()
	setShiftLock(not enabled)
	refreshSwitch()
end)

local minimiseRestoreSize

minimiseButton.MouseButton1Click:Connect(function()
	if isAnimating then return end
	minimised = not minimised
	minimiseVertical.Visible = minimised
	body.Visible = not minimised

	local goal
	if minimised then
		minimiseRestoreSize = mainFrame.Size
		goal = UDim2.new(minimiseRestoreSize.X.Scale, minimiseRestoreSize.X.Offset, 0, TITLE_HEIGHT)
	else
		goal = minimiseRestoreSize or FULL_SIZE
	end
	TweenService:Create(mainFrame, TWEEN_INFO, { Size = goal }):Play()
end)

env[CLEANUP_KEY] = function()
	setShiftLock(false)
	if screenGui then
		pcall(function()
			screenGui:Destroy()
		end)
	end
end

closeButton.MouseButton1Click:Connect(function()
	if type(env[CLEANUP_KEY]) == "function" then
		pcall(env[CLEANUP_KEY])
		env[CLEANUP_KEY] = nil
	end
end)
