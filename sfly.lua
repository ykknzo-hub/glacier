local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "flyhub"
local CLEANUP_KEY = "__fly_hub_cleanup"
local FLY_BIND = "FlyHubStep"

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

local FLY_MIN, FLY_MAX = 10, 400
local flying = false
local flyBusy = false
local flySpeed = 120
local originalGravity = Workspace.Gravity

local flyGyro, flyVelocity
local flyAnimTrack, flyAnim
local flyLastDirection = "none"
local animateDisabledByFly = false
local controlsModule

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getControls()
	if controlsModule then return controlsModule end
	local ok, result = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 3)
		local module = playerScripts and playerScripts:WaitForChild("PlayerModule", 3)
		return module and require(module):GetControls()
	end)
	if ok and result then
		controlsModule = result
	end
	return controlsModule
end

local function playFlyAnim(id, timePosition, speed)
	local humanoid = getHumanoid()
	if not humanoid then return end
	pcall(function()
		if flyAnimTrack then
			flyAnimTrack:Stop(0.1)
			flyAnimTrack:Destroy()
			flyAnimTrack = nil
		end
		if flyAnim then
			flyAnim:Destroy()
			flyAnim = nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(id)
		local animTrack = humanoid:LoadAnimation(anim)
		animTrack:Play()
		if timePosition then
			animTrack.TimePosition = timePosition
		end
		if speed then
			animTrack:AdjustSpeed(speed)
		end
		flyAnim = anim
		flyAnimTrack = animTrack
	end)
end

local function stopFlyAnim()
	pcall(function()
		if flyAnimTrack then
			flyAnimTrack:Stop(0.1)
			flyAnimTrack:Destroy()
		end
		if flyAnim then
			flyAnim:Destroy()
		end
	end)
	flyAnimTrack = nil
	flyAnim = nil
	if animateDisabledByFly then
		local char = player.Character
		local animate = char and char:FindFirstChild("Animate")
		if animate then
			animate.Disabled = false
		end
		animateDisabledByFly = false
	end
end

local setFlyUi = function() end

local function stopFly()
	if not flying and not flyGyro and not flyVelocity then
		return
	end
	flying = false
	pcall(function() RunService:UnbindFromRenderStep(FLY_BIND) end)
	Workspace.Gravity = originalGravity
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.PlatformStand = false
	end
	if flyGyro then flyGyro:Destroy() flyGyro = nil end
	if flyVelocity then flyVelocity:Destroy() flyVelocity = nil end
	flyLastDirection = "none"
	stopFlyAnim()
	setFlyUi()
end

local function flyStep()
	local humanoid, root = getHumanoid(), getRoot()
	local camera = Workspace.CurrentCamera
	if not (humanoid and root and camera and flyGyro and flyVelocity) then return end

	local fwd, side = 0, 0
	local controls = getControls()
	if controls then
		local moveVector = controls:GetMoveVector()
		fwd = -moveVector.Z
		side = moveVector.X
	elseif not UserInputService:GetFocusedTextBox() then
		fwd = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
		side = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
	end
	fwd = math.clamp(fwd, -1, 1)
	side = math.clamp(side, -1, 1)

	local newDirection = "idle"
	if fwd > 0.05 then
		newDirection = "forward"
	elseif fwd < -0.05 then
		newDirection = "backward"
	elseif math.abs(side) > 0.05 then
		newDirection = "strafe"
	end

	if newDirection ~= flyLastDirection then
		flyLastDirection = newDirection
		if newDirection == "forward" or newDirection == "strafe" then
			playFlyAnim(10714177846, 4.65, 0)
		elseif newDirection == "backward" then
			playFlyAnim(10147823318, 4.11, 0)
		else
			playFlyAnim(10714347256, 4, 0)
		end
	end

	local inputVec = (camera.CFrame.LookVector * fwd) + (camera.CFrame.RightVector * side)
	local targetVelocity
	if inputVec.Magnitude > 0 then
		targetVelocity = inputVec.Unit * flySpeed
		if fwd > 0 then
			targetVelocity = targetVelocity + Vector3.new(0, fwd * 0.2 * flySpeed, 0)
		end
	else
		targetVelocity = Vector3.new(0, 0.1 + math.sin(tick() * 3) * 2, 0)
	end
	flyVelocity.Velocity = flyVelocity.Velocity:Lerp(targetVelocity, 0.25)

	local forwardTilt = 0
	if fwd > 0.05 then
		forwardTilt = -90
	elseif fwd < -0.05 then
		forwardTilt = 45
	end
	local sideTilt = side * -45
	local targetCFrame = camera.CFrame * CFrame.Angles(math.rad(forwardTilt), 0, math.rad(sideTilt))
	flyGyro.CFrame = flyGyro.CFrame:Lerp(targetCFrame, 0.2)
end

local function startFly()
	local humanoid, root = getHumanoid(), getRoot()
	if not humanoid or not root then return end

	flying = true
	setFlyUi()
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	task.wait(0.1)

	humanoid, root = getHumanoid(), getRoot()
	if not flying or not humanoid or not root then
		stopFly()
		return
	end

	originalGravity = Workspace.Gravity > 0 and Workspace.Gravity or originalGravity
	Workspace.Gravity = 0
	humanoid.PlatformStand = true

	for _, playing in ipairs(humanoid:GetPlayingAnimationTracks()) do
		playing:Stop(0.1)
	end
	local animate = player.Character and player.Character:FindFirstChild("Animate")
	if animate and not animate.Disabled then
		animate.Disabled = true
		animateDisabledByFly = true
	end

	flyLastDirection = "idle"
	playFlyAnim(10714347256, 4, 0)

	flyGyro = Instance.new("BodyGyro")
	flyGyro.Name = "FlyGyro"
	flyGyro.P = 90000
	flyGyro.MaxTorque = Vector3.new(8999999488, 8999999488, 8999999488)
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.Name = "FlyVelocity"
	flyVelocity.Velocity = Vector3.new(0, 0.1, 0)
	flyVelocity.MaxForce = Vector3.new(8999999488, 8999999488, 8999999488)
	flyVelocity.Parent = root

	RunService:BindToRenderStep(FLY_BIND, Enum.RenderPriority.Camera.Value, flyStep)
end

local function toggleFly()
	if flyBusy then return end
	flyBusy = true
	if flying then
		stopFly()
	else
		startFly()
	end
	flyBusy = false
end

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local FULL_SIZE = UDim2.new(0, 220, 0, 100)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local BOX_COLOR = Color3.fromRGB(22, 22, 22)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 998
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Position = UDim2.new(0.5, -110, 0.5, -50)
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

local function makeCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 0, TITLE_HEIGHT)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Superman Fly"
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

local flyLabel = Instance.new("TextLabel")
flyLabel.Position = UDim2.new(0, 14, 0, 4)
flyLabel.Size = UDim2.new(0, 100, 0, 24)
flyLabel.BackgroundTransparency = 1
flyLabel.Text = "Fly"
flyLabel.TextColor3 = WHITE
flyLabel.Font = Enum.Font.GothamMedium
flyLabel.TextSize = 12
flyLabel.TextXAlignment = Enum.TextXAlignment.Left
flyLabel.ZIndex = 3
flyLabel.Parent = body

local flyButton = Instance.new("TextButton")
flyButton.Size = UDim2.new(0, 44, 0, 22)
flyButton.Position = UDim2.new(1, -56, 0, 5)
flyButton.BackgroundTransparency = 1
flyButton.Text = "Off"
flyButton.TextColor3 = MUTED
flyButton.Font = Enum.Font.GothamMedium
flyButton.TextSize = 12
flyButton.AutoButtonColor = false
flyButton.ZIndex = 4
flyButton.Parent = body

setFlyUi = function()
	flyButton.Text = flying and "On" or "Off"
	flyButton.TextColor3 = flying and WHITE or MUTED
	flyButton.Font = flying and Enum.Font.GothamBold or Enum.Font.GothamMedium
end

flyButton.MouseButton1Click:Connect(toggleFly)

local speedLabel = Instance.new("TextLabel")
speedLabel.Position = UDim2.new(0, 14, 0, 34)
speedLabel.Size = UDim2.new(0, 44, 0, 24)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Speed"
speedLabel.TextColor3 = WHITE
speedLabel.Font = Enum.Font.GothamMedium
speedLabel.TextSize = 12
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.ZIndex = 3
speedLabel.Parent = body

local speedValue = Instance.new("TextLabel")
speedValue.Position = UDim2.new(1, -52, 0, 34)
speedValue.Size = UDim2.new(0, 40, 0, 24)
speedValue.BackgroundTransparency = 1
speedValue.Text = tostring(flySpeed)
speedValue.TextColor3 = WHITE
speedValue.Font = Enum.Font.GothamMedium
speedValue.TextSize = 12
speedValue.TextXAlignment = Enum.TextXAlignment.Right
speedValue.ZIndex = 3
speedValue.Parent = body

local sliderHit = Instance.new("TextButton")
sliderHit.Position = UDim2.new(0, 62, 0, 34)
sliderHit.Size = UDim2.new(1, -(62 + 56), 0, 24)
sliderHit.BackgroundTransparency = 1
sliderHit.Text = ""
sliderHit.AutoButtonColor = false
sliderHit.ZIndex = 4
sliderHit.Parent = body

local sliderBar = Instance.new("Frame")
sliderBar.AnchorPoint = Vector2.new(0, 0.5)
sliderBar.Position = UDim2.new(0, 0, 0.5, 0)
sliderBar.Size = UDim2.new(1, 0, 0, 4)
sliderBar.BackgroundColor3 = BOX_COLOR
sliderBar.BorderSizePixel = 0
sliderBar.ZIndex = 4
sliderBar.Parent = sliderHit
makeCorner(sliderBar, 2)

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0, 0, 1, 0)
sliderFill.BackgroundColor3 = WHITE
sliderFill.BorderSizePixel = 0
sliderFill.ZIndex = 5
sliderFill.Parent = sliderBar
makeCorner(sliderFill, 2)

local sliderKnob = Instance.new("Frame")
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Size = UDim2.new(0, 10, 0, 10)
sliderKnob.BackgroundColor3 = WHITE
sliderKnob.BorderSizePixel = 0
sliderKnob.ZIndex = 6
sliderKnob.Parent = sliderHit
makeCorner(sliderKnob, 5)

local function setSpeed(value)
	flySpeed = math.clamp(math.floor(value + 0.5), FLY_MIN, FLY_MAX)
	local percent = (flySpeed - FLY_MIN) / (FLY_MAX - FLY_MIN)
	speedValue.Text = tostring(flySpeed)
	sliderFill.Size = UDim2.new(percent, 0, 1, 0)
	sliderKnob.Position = UDim2.new(percent, 0, 0.5, 0)
end

setSpeed(flySpeed)

local sliderDragging = false

local function updateSlider(mouseX)
	local barW = math.max(sliderHit.AbsoluteSize.X, 1)
	local percent = math.clamp((mouseX - sliderHit.AbsolutePosition.X) / barW, 0, 1)
	setSpeed(FLY_MIN + percent * (FLY_MAX - FLY_MIN))
end

sliderHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		sliderDragging = true
		updateSlider(input.Position.X)
	end
end)

track(UserInputService.InputChanged:Connect(function(input)
	if not sliderDragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		updateSlider(input.Position.X)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		sliderDragging = false
	end
end))

local minimised = false
minimiseButton.MouseButton1Click:Connect(function()
	minimised = not minimised
	body.Visible = not minimised
	TweenService:Create(mainFrame, TWEEN_INFO, {
		Size = minimised and UDim2.new(0, FULL_SIZE.X.Offset, 0, TITLE_HEIGHT) or FULL_SIZE,
	}):Play()
end)

track(player.CharacterAdded:Connect(function()
	stopFly()
end))

track(player.Chatted:Connect(function(message)
	local args = string.split(string.lower(message), " ")
	local cmd = args[1]
	if cmd == ";fly" then
		if not flying then toggleFly() end
	elseif cmd == ";unfly" then
		if flying then toggleFly() end
	elseif cmd == ";flyspeed" then
		local n = tonumber(args[2])
		if n then setSpeed(n) end
	end
end))

local function cleanup()
	stopFly()
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
