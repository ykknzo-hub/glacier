local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "triphub"
local CLEANUP_KEY = "__trip_hub_cleanup"
local BIND_FILE = "trip_bind.txt"
local LOGO_FILE = "keyboardbind.png"
local LOGO_URL = "https://file.garden/an4tZIrGtwwEohVh/keyboard%20(1).png"

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

local function trip()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if hum and root then
		hum:ChangeState(Enum.HumanoidStateType.FallingDown)
		root.AssemblyLinearVelocity = root.CFrame.LookVector * 35
	end
end

local function findKeyCode(name)
	name = string.lower(name or "")
	for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
		if item.Name ~= "Unknown" and string.lower(item.Name) == name then
			return item
		end
	end
	return nil
end

local boundKey = findKeyCode("T")
pcall(function()
	if type(isfile) == "function" and isfile(BIND_FILE) then
		local saved = readfile(BIND_FILE)
		boundKey = (saved == "none") and nil or (findKeyCode(saved) or boundKey)
	end
end)

local function saveBind()
	pcall(function()
		if type(writefile) == "function" then
			writefile(BIND_FILE, boundKey and boundKey.Name or "none")
		end
	end)
end

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local FULL_SIZE = UDim2.new(0, 220, 0, 100)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 997
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

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -70, 0, TITLE_HEIGHT)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Trip"
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
	label.Size = UDim2.new(0, 100, 0, 24)
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

local function makeRowButton(text, width, xFromRight, y)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, width, 0, 22)
	btn.Position = UDim2.new(1, -(xFromRight + width), 0, y + 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = body
	return btn
end

makeRowLabel("Trip", 4)
local tripButton = makeRowButton("Trip", 44, 12, 4)
tripButton.MouseButton1Click:Connect(trip)

makeRowLabel("Keybind", 34)
local bindButton = makeRowButton("bind", 70, 12, 34)
bindButton.TextXAlignment = Enum.TextXAlignment.Right

local bindIcon = Instance.new("ImageLabel")
bindIcon.AnchorPoint = Vector2.new(1, 0.5)
bindIcon.Position = UDim2.new(1, 0, 0.5, 0)
bindIcon.Size = UDim2.new(0, 18, 0, 18)
bindIcon.BackgroundTransparency = 1
bindIcon.ImageColor3 = WHITE
bindIcon.ScaleType = Enum.ScaleType.Fit
bindIcon.ZIndex = 5
bindIcon.Visible = false
bindIcon.Parent = bindButton

local waitingForKey = false
local logoAsset

local function getLogoAsset()
	if logoAsset then return logoAsset end
	if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then return nil end
	local ok, asset = pcall(function()
		if not (type(isfile) == "function" and isfile(LOGO_FILE)) then
			writefile(LOGO_FILE, game:HttpGet(LOGO_URL))
		end
		return getcustomasset(LOGO_FILE)
	end)
	if ok and asset and asset ~= "" then
		logoAsset = asset
	end
	return logoAsset
end

local function refreshBind()
	if waitingForKey then
		bindButton.Text = "press key"
		bindButton.TextColor3 = WHITE
		bindIcon.Visible = false
	elseif boundKey then
		bindButton.Text = boundKey.Name
		bindButton.TextColor3 = WHITE
		bindIcon.Visible = false
	else
		local logo = getLogoAsset()
		bindIcon.Image = logo or ""
		bindButton.Text = logo and "" or "bind"
		bindButton.TextColor3 = WHITE
		bindIcon.Visible = logo ~= nil
	end
end

task.spawn(function()
	getLogoAsset()
	refreshBind()
end)
refreshBind()

bindButton.MouseButton1Click:Connect(function()
	if boundKey then
		boundKey = nil
		waitingForKey = false
		saveBind()
	else
		waitingForKey = true
	end
	refreshBind()
end)

track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if waitingForKey then
		waitingForKey = false
		if input.KeyCode ~= Enum.KeyCode.Escape then
			boundKey = input.KeyCode
			saveBind()
		end
		refreshBind()
		return
	end

	if UserInputService:GetFocusedTextBox() then return end
	if boundKey and input.KeyCode == boundKey then
		trip()
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

track(player.Chatted:Connect(function(message)
	if string.lower(message) == ";trip" then
		trip()
	end
end))

local function cleanup()
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
