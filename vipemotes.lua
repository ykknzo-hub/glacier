local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "edance"
local CLEANUP_KEY = "__edance_hub_cleanup"

local VIP_EMOTES = {
	{ name = "Handstand", id = "rbxassetid://13027233338" },
	{ name = "VIP 01", id = "rbxassetid://124072584017964" },
	{ name = "VIP 03", id = "rbxassetid://137445502103066" },
	{ name = "VIP 08", id = "rbxassetid://11137338685" },
	{ name = "Ghostly", id = "rbxassetid://124385779438289" },
	{ name = "Oof", id = "rbxassetid://134763058840745" },
	{ name = "Die", id = "rbxassetid://14852161489" },
	{ name = "Log", id = "rbxassetid://116818881329505" },
}

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

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local DESIGN_W, DESIGN_H = 260, 320
local FULL_SIZE = UDim2.new(0, DESIGN_W, 0, DESIGN_H)
local MINI_SIZE = UDim2.new(0, 260, 0, TITLE_HEIGHT)
local CORNER = UDim.new(0, 4)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local WHITE = Color3.fromRGB(255, 255, 255)
local ORANGE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)
local MIN_W, MIN_H = 200, 260
local MAX_W, MAX_H = 600, 700

local BUTTON_SIZE = 50
local IMAGE_PADDING = 10

local minimised = false
local isOpen = true
local isAnimating = false

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = guiParent

local mainFrame = Instance.new("CanvasGroup")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0, 0)
mainFrame.Position = UDim2.new(0.5, -130, 0.5, -160)
mainFrame.Size = FULL_SIZE
mainFrame.BackgroundColor3 = BODY_COLOR
mainFrame.BorderSizePixel = 0
mainFrame.GroupTransparency = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = CORNER
mainCorner.Parent = mainFrame

local content = Instance.new("CanvasGroup")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.GroupTransparency = 0
content.ZIndex = 2
content.Parent = mainFrame

local contentScale = Instance.new("UIScale")
contentScale.Parent = content

local function updateContentScale()
	local size = mainFrame.AbsoluteSize
	if minimised then return end
	if size.Y < 200 then return end
	local scale = math.clamp(math.min(size.X / DESIGN_W, size.Y / DESIGN_H), 0.7, 2)
	contentScale.Scale = scale
	content.Size = UDim2.new(1 / scale, 0, 1 / scale, 0)
end

mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContentScale)

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
titleBar.Position = UDim2.new(0, 0, 0, 0)
titleBar.BackgroundTransparency = 1
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 2
titleBar.Parent = content

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -90, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "e-dance"
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
body.GroupTransparency = 0
body.ZIndex = 1
body.Parent = content

local function makeDivider(y)
	local line = Instance.new("Frame")
	line.Name = "Divider"
	line.Position = UDim2.new(0, 10, 0, y)
	line.Size = UDim2.new(1, -20, 0, 1)
	line.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	line.BackgroundTransparency = 0.6
	line.BorderSizePixel = 0
	line.ZIndex = 3
	line.Parent = body
	return line
end

local function makeCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

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

local GRIP_SIZE = 28
local gripButton = Instance.new("TextButton")
gripButton.Name = "ResizeGrip"
gripButton.AnchorPoint = Vector2.new(0, 0)
gripButton.Size = UDim2.new(0, GRIP_SIZE, 0, GRIP_SIZE)
gripButton.BackgroundTransparency = 1
gripButton.Text = ""
gripButton.AutoButtonColor = false
gripButton.ZIndex = 10
gripButton.Parent = screenGui

local ARROW_COLOR = Color3.fromRGB(255, 255, 255)

local function makeArrowPart(size, position, rotation)
	local part = Instance.new("Frame")
	part.BackgroundColor3 = ARROW_COLOR
	part.BackgroundTransparency = 0
	part.BorderSizePixel = 0
	part.Size = size
	part.Position = position
	part.Rotation = rotation or 0
	part.ZIndex = 10
	part.Parent = gripButton
	return part
end

makeArrowPart(UDim2.new(0, 15, 0, 2), UDim2.new(0, 3, 0, 9), 45)
makeArrowPart(UDim2.new(0, 7, 0, 2), UDim2.new(0, 11, 0, 15))
makeArrowPart(UDim2.new(0, 2, 0, 7), UDim2.new(0, 16, 0, 10))

local function updateGripPosition()
	local pos = mainFrame.AbsolutePosition
	local size = mainFrame.AbsoluteSize
	gripButton.Position = UDim2.new(0, pos.X + size.X + 2, 0, pos.Y + size.Y + 2)
end

track(RunService.RenderStepped:Connect(updateGripPosition))

local resizing = false
local resizeStartMouse
local resizeStartSize

gripButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		resizing = true
		resizeStartMouse = Vector2.new(input.Position.X, input.Position.Y)
		resizeStartSize = Vector2.new(mainFrame.AbsoluteSize.X, mainFrame.AbsoluteSize.Y)
	end
end)

track(UserInputService.InputChanged:Connect(function(input)
	if not resizing then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local deltaX = input.Position.X - resizeStartMouse.X
	local deltaY = input.Position.Y - resizeStartMouse.Y
	local newW = math.clamp(resizeStartSize.X + deltaX, MIN_W, MAX_W)
	local newH = math.clamp(resizeStartSize.Y + deltaY, MIN_H, MAX_H)
	mainFrame.Size = UDim2.new(0, newW, 0, newH)
end))

track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		resizing = false
	end
end))

local activeTracks = {}
local activeOrder = {}
local MAX_TRACKS = 32

local BOX_COLOR = Color3.fromRGB(22, 22, 22)

local binds = {}
local DATA_FILE = "edance_hub_data.json"

local function loadData()
	if type(readfile) == "function" and type(isfile) == "function" and isfile(DATA_FILE) then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(DATA_FILE))
		end)
		if ok and type(data) == "table" and type(data.binds) == "table" then
			binds = data.binds
		end
	end
end

local function saveData()
	if type(writefile) == "function" then
		pcall(function()
			writefile(DATA_FILE, HttpService:JSONEncode({ binds = binds }))
		end)
	end
end

loadData()

local function getHumanoid()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function stopAnim(id)
	local entry = activeTracks[id]
	if not entry then return end
	pcall(function()
		entry.track:Stop()
		entry.track:Destroy()
	end)
	if entry.anim then
		pcall(function() entry.anim:Destroy() end)
	end
	activeTracks[id] = nil
	for i, value in ipairs(activeOrder) do
		if value == id then
			table.remove(activeOrder, i)
			break
		end
	end
end

local function clearAllTracks()
	for id in pairs(activeTracks) do
		stopAnim(id)
	end
end

local function freeSlotIfNeeded()
	if #activeOrder < MAX_TRACKS then
		return true
	end
	if #activeOrder > 0 then
		stopAnim(activeOrder[1])
		return true
	end
	return false
end

local function toggleVip(entry)
	if not entry then return end
	local id = entry.id
	if activeTracks[id] then
		stopAnim(id)
		return
	end
	if not freeSlotIfNeeded() then return end
	local humanoid = getHumanoid()
	if not humanoid then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local success, track = pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			return animator:LoadAnimation(anim)
		else
			return humanoid:LoadAnimation(anim)
		end
	end)
	if not success or not track then
		pcall(function() anim:Destroy() end)
		return
	end
	pcall(function() track:Play() end)
	activeTracks[id] = { track = track, anim = anim }
	table.insert(activeOrder, id)
end

local LIST_Y = TITLE_HEIGHT + 12

local emotesScroll = Instance.new("ScrollingFrame")
emotesScroll.Name = "EmotesScroll"
emotesScroll.Position = UDim2.new(0, 0, 0, LIST_Y)
emotesScroll.Size = UDim2.new(1, 0, 1, -(LIST_Y + 6))
emotesScroll.BackgroundTransparency = 1
emotesScroll.BorderSizePixel = 0
emotesScroll.ScrollBarThickness = 3
emotesScroll.ScrollBarImageColor3 = WHITE
emotesScroll.ScrollBarImageTransparency = 0.65
emotesScroll.ScrollingDirection = Enum.ScrollingDirection.Y
emotesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
emotesScroll.ZIndex = 2
emotesScroll.Parent = body

local ROW_H = 28
local ROW_GAP = 4
local emoteRows = {}
local playButtons = {}
local bindingFor = nil

local function clearEmoteRows()
	for _, row in ipairs(emoteRows) do
		row:Destroy()
	end
	table.clear(emoteRows)
	table.clear(playButtons)
end

local function findEntry(name)
	for _, entry in ipairs(VIP_EMOTES) do
		if entry.name == name then
			return entry
		end
	end
end

local LOGO_FILE = "keyboardbind.png"
local LOGO_URL = "https://file.garden/an4tZIrGtwwEohVh/keyboard%20(1).png"
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

task.spawn(getLogoAsset)

local function makeRowButton(row, text, width, xFromRight)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, width, 0, 22)
	btn.Position = UDim2.new(1, -(xFromRight + width), 0.5, -11)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = row
	return btn
end

local layoutEmotes

local function makeRow(entry, y)
	local row = Instance.new("Frame")
	row.Name = "EmoteRow"
	row.Size = UDim2.new(1, -24, 0, ROW_H)
	row.Position = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1
	row.ZIndex = 3
	row.Parent = emotesScroll

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -(134 + 4), 1, 0)
	nameLabel.Position = UDim2.new(0, 4, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.name
	nameLabel.TextColor3 = WHITE
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 3
	nameLabel.Parent = row

	local playBtn = makeRowButton(row, "Play", 44, 0)
	table.insert(playButtons, { button = playBtn, id = entry.id })
	playBtn.MouseButton1Click:Connect(function()
		toggleVip(entry)
	end)

	local keyName = binds[entry.name]
	local bindBtn = makeRowButton(row, "bind", 60, 76)
	bindBtn.TextColor3 = WHITE
	bindBtn.TextXAlignment = Enum.TextXAlignment.Right
	local logo = getLogoAsset()
	if logo and not keyName and bindingFor ~= entry.name then
		bindBtn.Text = ""
		local icon = Instance.new("ImageLabel")
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(1, 0, 0.5, 0)
		icon.Size = UDim2.new(0, 18, 0, 18)
		icon.BackgroundTransparency = 1
		icon.Image = logo
		icon.ImageColor3 = WHITE
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 5
		icon.Parent = bindBtn
	end
	if bindingFor == entry.name then
		bindBtn.Text = "press key"
		bindBtn.TextColor3 = ORANGE
	elseif keyName then
		bindBtn.Text = keyName
		bindBtn.TextColor3 = ORANGE
	end
	bindBtn.MouseButton1Click:Connect(function()
		if binds[entry.name] then
			binds[entry.name] = nil
			saveData()
		else
			bindingFor = entry.name
		end
		layoutEmotes()
	end)

	table.insert(emoteRows, row)
end

layoutEmotes = function()
	local savedScroll = emotesScroll.CanvasPosition
	clearEmoteRows()
	local y = 4
	for _, entry in ipairs(VIP_EMOTES) do
		makeRow(entry, y)
		y = y + ROW_H + ROW_GAP
	end
	emotesScroll.CanvasSize = UDim2.new(0, 0, 0, y + 6)
	emotesScroll.CanvasPosition = savedScroll
end

track(UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if bindingFor then
		local name = bindingFor
		bindingFor = nil
		if input.KeyCode ~= Enum.KeyCode.Escape then
			local keyName = input.KeyCode.Name
			for other, existingKey in pairs(binds) do
				if existingKey == keyName then
					binds[other] = nil
				end
			end
			binds[name] = keyName
			saveData()
		end
		layoutEmotes()
		return
	end
	if UserInputService:GetFocusedTextBox() then return end
	local keyName = input.KeyCode.Name
	for name, boundKey in pairs(binds) do
		if boundKey == keyName then
			local entry = findEntry(name)
			if entry then
				toggleVip(entry)
			end
			break
		end
	end
end))

track(RunService.Heartbeat:Connect(function()
	for _, item in ipairs(playButtons) do
		local playing = activeTracks[item.id] ~= nil
		local text = playing and "Stop" or "Play"
		if item.button.Text ~= text then
			item.button.Text = text
			item.button.TextColor3 = playing and ORANGE or WHITE
		end
	end
end))

layoutEmotes()

track(player.CharacterAdded:Connect(function()
	clearAllTracks()
end))

minimiseVertical.Visible = false
local BODY_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local bodyTween
local minimiseRestoreSize

local function setBodyVisible(visible, instant)
	if bodyTween then
		bodyTween:Cancel()
		bodyTween = nil
	end
	if instant then
		body.GroupTransparency = visible and 0 or 1
		body.Visible = visible
		return
	end
	if visible then
		body.Visible = true
		bodyTween = TweenService:Create(body, BODY_FADE, { GroupTransparency = 0 })
		bodyTween:Play()
	else
		local fade = TweenService:Create(body, BODY_FADE, { GroupTransparency = 1 })
		bodyTween = fade
		fade.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				body.Visible = false
			end
		end)
		fade:Play()
	end
end

minimiseButton.MouseButton1Click:Connect(function()
	if isAnimating or not isOpen then return end
	minimised = not minimised
	minimiseVertical.Visible = minimised
	gripButton.Visible = not minimised
	setBodyVisible(not minimised)
	local goal
	if minimised then
		minimiseRestoreSize = mainFrame.Size
		goal = UDim2.new(
			minimiseRestoreSize.X.Scale, minimiseRestoreSize.X.Offset,
			0, math.ceil(TITLE_HEIGHT * contentScale.Scale)
		)
	else
		goal = minimiseRestoreSize or FULL_SIZE
	end
	TweenService:Create(mainFrame, TWEEN_INFO, { Size = goal }):Play()
end)

local floatingButton = Instance.new("ImageButton")
floatingButton.Name = "FloatingButton"
floatingButton.Size = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE)
floatingButton.Position = UDim2.new(0.5, -BUTTON_SIZE / 2, 0.5, -BUTTON_SIZE / 2)
floatingButton.BackgroundColor3 = Color3.fromRGB(16, 9, 24)
floatingButton.Image = ""
floatingButton.AutoButtonColor = false
floatingButton.Visible = false
floatingButton.Active = true
floatingButton.ZIndex = 100
floatingButton.Parent = screenGui

local floatingCorner = Instance.new("UICorner")
floatingCorner.CornerRadius = UDim.new(1, 0)
floatingCorner.Parent = floatingButton

local floatingImage = Instance.new("ImageLabel")
floatingImage.Name = "FloatingImage"
floatingImage.AnchorPoint = Vector2.new(0.5, 0.5)
floatingImage.Position = UDim2.new(0.5, 0, 0.5, 0)
floatingImage.Size = UDim2.new(1, -IMAGE_PADDING * 2, 1, -IMAGE_PADDING * 2)
floatingImage.BackgroundTransparency = 1
floatingImage.Image = "rbxassetid://78182530339167"
floatingImage.ImageColor3 = WHITE
floatingImage.ScaleType = Enum.ScaleType.Fit
floatingImage.ZIndex = 101
floatingImage.Parent = floatingButton

local MORPH_TIME = 0.45
local MORPH_INFO = TweenInfo.new(MORPH_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
local CROSSFADE = 0.2
local CIRCLE_RADIUS = UDim.new(0.5, 0)
local BUTTON_UDIM = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE)
local savedPosition = mainFrame.Position
local savedSize = FULL_SIZE

local function closePanel()
	savedPosition = mainFrame.Position
	savedSize = minimised and FULL_SIZE or mainFrame.Size
	gripButton.Visible = false
	mainFrame.Draggable = false
	resizing = false
	floatingButton.Visible = true
	floatingButton.BackgroundTransparency = 1
	floatingImage.ImageTransparency = 1
	local fadeDelay = MORPH_TIME - CROSSFADE
	local fadeInfo = TweenInfo.new(CROSSFADE, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, fadeDelay)
	local morph = TweenService:Create(mainFrame, MORPH_INFO, {
		Position = floatingButton.Position,
		Size = BUTTON_UDIM,
	})
	TweenService:Create(mainCorner, MORPH_INFO, { CornerRadius = CIRCLE_RADIUS }):Play()
	TweenService:Create(content, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 1,
	}):Play()
	TweenService:Create(mainFrame, fadeInfo, { GroupTransparency = 1 }):Play()
	TweenService:Create(floatingButton, fadeInfo, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(floatingImage, fadeInfo, { ImageTransparency = 0 }):Play()
	morph:Play()
	morph.Completed:Wait()
	mainFrame.Visible = false
	minimised = false
	minimiseVertical.Visible = false
	setBodyVisible(true, true)
end

local function openPanel()
	mainFrame.Position = floatingButton.Position
	mainFrame.Size = BUTTON_UDIM
	mainCorner.CornerRadius = CIRCLE_RADIUS
	mainFrame.GroupTransparency = 1
	content.GroupTransparency = 1
	mainFrame.Visible = true
	local fadeInfo = TweenInfo.new(CROSSFADE, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	TweenService:Create(content, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, MORPH_TIME * 0.6), {
		GroupTransparency = 0,
	}):Play()
	TweenService:Create(mainFrame, fadeInfo, { GroupTransparency = 0 }):Play()
	TweenService:Create(floatingButton, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(floatingImage, fadeInfo, { ImageTransparency = 1 }):Play()
	local morph = TweenService:Create(mainFrame, MORPH_INFO, {
		Position = savedPosition,
		Size = savedSize,
	})
	TweenService:Create(mainCorner, MORPH_INFO, { CornerRadius = CORNER }):Play()
	morph:Play()
	morph.Completed:Wait()
	floatingButton.Visible = false
	floatingButton.BackgroundTransparency = 0
	floatingImage.ImageTransparency = 0
	content.GroupTransparency = 0
	mainFrame.Draggable = true
	gripButton.Visible = true
end

local function setOpen(open)
	if isAnimating then return end
	if open == isOpen then return end
	isAnimating = true
	if open then
		openPanel()
	else
		closePanel()
	end
	isOpen = open
	isAnimating = false
end

closeButton.MouseButton1Click:Connect(function()
	if isAnimating then return end
	if type(env[CLEANUP_KEY]) == "function" then
		pcall(env[CLEANUP_KEY])
		env[CLEANUP_KEY] = nil
	end
end)

local BUTTON_VEC = Vector2.new(BUTTON_SIZE, BUTTON_SIZE)
local panelFrac = nil
local buttonFrac = nil
local lastViewport = Vector2.new(0, 0)

local function posToFrac(obj, size)
	local viewport = screenGui.AbsoluteSize
	local rel = obj.AbsolutePosition - screenGui.AbsolutePosition
	local freeX = math.max(viewport.X - size.X, 0)
	local freeY = math.max(viewport.Y - size.Y, 0)
	return Vector2.new(
		freeX > 0 and math.clamp(rel.X / freeX, 0, 1) or 0.5,
		freeY > 0 and math.clamp(rel.Y / freeY, 0, 1) or 0.5
	)
end

local function fracToPos(frac, size)
	local viewport = screenGui.AbsoluteSize
	local freeX = math.max(viewport.X - size.X, 0)
	local freeY = math.max(viewport.Y - size.Y, 0)
	return UDim2.fromOffset(math.floor(frac.X * freeX + 0.5), math.floor(frac.Y * freeY + 0.5))
end

track(RunService.RenderStepped:Connect(function()
	local viewport = screenGui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end
	if not panelFrac then
		lastViewport = viewport
		panelFrac = posToFrac(mainFrame, mainFrame.AbsoluteSize)
		buttonFrac = posToFrac(floatingButton, BUTTON_VEC)
		return
	end
	if isAnimating then return end
	if viewport ~= lastViewport then
		lastViewport = viewport
		floatingButton.Position = fracToPos(buttonFrac, BUTTON_VEC)
		if isOpen then
			mainFrame.Position = fracToPos(panelFrac, mainFrame.AbsoluteSize)
		else
			savedPosition = fracToPos(panelFrac, Vector2.new(savedSize.X.Offset, savedSize.Y.Offset))
		end
	elseif isOpen then
		panelFrac = posToFrac(mainFrame, mainFrame.AbsoluteSize)
	elseif floatingButton.Visible then
		buttonFrac = posToFrac(floatingButton, BUTTON_VEC)
	end
end))

local draggingButton = false
local dragMoved = false
local dragStartMouse
local dragStartPos

floatingButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingButton = true
		dragMoved = false
		dragStartMouse = Vector2.new(input.Position.X, input.Position.Y)
		dragStartPos = floatingButton.Position
	end
end)

track(UserInputService.InputChanged:Connect(function(input)
	if not draggingButton then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartMouse
	if not dragMoved and delta.Magnitude > 5 then
		dragMoved = true
	end
	if dragMoved then
		floatingButton.Position = UDim2.new(
			dragStartPos.X.Scale,
			dragStartPos.X.Offset + delta.X,
			dragStartPos.Y.Scale,
			dragStartPos.Y.Offset + delta.Y
		)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingButton = false
	end
end))

floatingButton.Activated:Connect(function()
	if dragMoved then return end
	setOpen(true)
end)

env[CLEANUP_KEY] = function()
	clearAllTracks()
	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(connections)
	if screenGui then
		pcall(function()
			screenGui:Destroy()
		end)
	end
end
