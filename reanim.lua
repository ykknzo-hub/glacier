local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "reanimation"
local CLEANUP_KEY = "__reanimation_hub_cleanup"
local REANIM_API_URL = "https://pastebin.com/raw/3wXgrSvi"

local ANIM_REPO = "ofcWilliam/rbxscript-resources"
local ANIM_DIR = "Backup/AnimData"
local ANIM_RAW_BASE = "https://raw.githubusercontent.com/" .. ANIM_REPO .. "/main/"

local DEFAULTS = {
	WalkSpeed = 16,
	JumpPower = 50,
	FOV = 70,
}

local FOLDER_ROOT = "glacier"
local FOLDER_PATH = "glacier/customs"
local LOCAL_HOST = "https://glacier.local/"
local localFiles = {}

pcall(function()
	if type(makefolder) == "function" and type(isfolder) == "function" then
		if not isfolder(FOLDER_ROOT) then makefolder(FOLDER_ROOT) end
		if not isfolder(FOLDER_PATH) then makefolder(FOLDER_PATH) end
	end
end)

local function localLookup(url)
	local path = type(url) == "string" and localFiles[url]
	if path and type(readfile) == "function" then
		local ok, data = pcall(readfile, path)
		if ok then return data end
	end
	return nil
end

local function loadApiSandboxed(source)
	local realGame = game
	local genv = (getgenv and getgenv()) or _G
	local realRequest = genv.request or genv.http_request or (genv.syn and genv.syn.request)

	local fakeGame
	fakeGame = setmetatable({}, {
		__index = function(_, key)
			if key == "HttpGet" or key == "HttpGetAsync" then
				return function(_, url, ...)
					local data = localLookup(url)
					if data then return data end
					return realGame:HttpGet(url, ...)
				end
			end
			local value = realGame[key]
			if type(value) == "function" then
				return function(self, ...)
					if self == fakeGame then self = realGame end
					return value(self, ...)
				end
			end
			return value
		end,
		__newindex = function(_, key, value)
			realGame[key] = value
		end,
		__tostring = function()
			return tostring(realGame)
		end,
	})

	local function fakeRequest(opts, ...)
		local data = type(opts) == "table" and localLookup(opts.Url)
		if data then
			return { Success = true, StatusCode = 200, StatusMessage = "OK", Body = data, Headers = {} }
		end
		return realRequest(opts, ...)
	end

	local sandbox = setmetatable({
		game = fakeGame,
		Game = fakeGame,
		request = realRequest and fakeRequest or nil,
		http_request = realRequest and fakeRequest or nil,
	}, { __index = genv })

	local chunk = loadstring(source)
	if setfenv then setfenv(chunk, sandbox) end
	return chunk()
end

local api
do
	local ok, result = pcall(function()
		return loadApiSandboxed(game:HttpGet(REANIM_API_URL))
	end)
	if ok and type(result) == "table" then
		api = result
	else
		warn("[reanimation] Failed to load reanimation API:", result)
		api = nil
	end
end

local setReanimated
local stopEmote
local loadAndPlayEmote
local homeStatus
local animSpeed = 1
local speedBoost = true
local reversed = false

local function currentSpeed()
	return (speedBoost and animSpeed or 1) * (reversed and -1 or 1)
end

local function applySpeed()
	if api and api.set_animation_speed then
		pcall(api.set_animation_speed, currentSpeed())
	end
end
local playingName = nil
local reanimEnabled = false
local updateReanimVisual

local env = (getgenv and getgenv()) or _G

local function resetWorld()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = DEFAULTS.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = DEFAULTS.JumpPower
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = DEFAULTS.FOV
	end
end

if type(env[CLEANUP_KEY]) == "function" then
	pcall(env[CLEANUP_KEY])
end
env[CLEANUP_KEY] = nil

for _, child in ipairs(playerGui:GetChildren()) do
	if child.Name == GUI_NAME then
		child:Destroy()
	end
end

resetWorld()

local connections = {}
local function track(connection)
	table.insert(connections, connection)
	return connection
end

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local DESIGN_W, DESIGN_H = 320, 440
local FULL_SIZE = UDim2.new(0, DESIGN_W, 0, DESIGN_H)
local CORNER = UDim.new(0, 4)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local WHITE = Color3.fromRGB(255, 255, 255)
local ORANGE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)
local MIN_W, MIN_H = 240, 320
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
screenGui.Parent = playerGui

local mainFrame = Instance.new("CanvasGroup")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0, 0)
mainFrame.Position = UDim2.new(0.5, -160, 0.5, -220)
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
titleLabel.Text = "reanimation"
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

local function urlEncodePath(path)
	local parts = string.split(path, "/")
	for i, part in ipairs(parts) do
		parts[i] = HttpService:UrlEncode(part):gsub("%%2E", ".")
	end
	return table.concat(parts, "/")
end

local function fetchAllAnimDataEmotes()
	local list = {}
	local seen = {}
	local okTree, treeData = pcall(function()
		return HttpService:JSONDecode(game:HttpGet(
			"https://api.github.com/repos/" .. ANIM_REPO .. "/git/trees/main?recursive=1"
		))
	end)
	if okTree and type(treeData) == "table" and type(treeData.tree) == "table" then
		for _, node in ipairs(treeData.tree) do
			if node.type == "blob" and type(node.path) == "string" then
				local path = node.path
				if path:sub(1, #ANIM_DIR + 1) == ANIM_DIR .. "/" and path:lower():match("%.lua$") then
					local fileName = path:match("([^/]+)$") or path
					local name = fileName:gsub("%.lua$", ""):gsub("_", " ")
					if not seen[name:lower()] then
						seen[name:lower()] = true
						table.insert(list, {
							name = name,
							url = ANIM_RAW_BASE .. urlEncodePath(path),
							path = path,
						})
					end
				end
			end
		end
		return list
	end
	local page = 1
	while page <= 20 do
		local okPage, pageData = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(
				"https://api.github.com/repos/" .. ANIM_REPO .. "/contents/" .. ANIM_DIR
					.. "?ref=main&per_page=100&page=" .. tostring(page)
			))
		end)
		if not okPage or type(pageData) ~= "table" or #pageData == 0 then
			break
		end
		if pageData.message then break end
		local added = 0
		for _, file in ipairs(pageData) do
			if file.type == "file" and type(file.name) == "string" and file.name:lower():match("%.lua$") then
				local name = file.name:gsub("%.lua$", ""):gsub("_", " ")
				if not seen[name:lower()] then
					seen[name:lower()] = true
					local path = ANIM_DIR .. "/" .. file.name
					table.insert(list, {
						name = name,
						url = file.download_url or (ANIM_RAW_BASE .. path),
						path = path,
					})
					added = added + 1
				end
			end
		end
		if added == 0 or #pageData < 100 then break end
		page = page + 1
	end
	return list
end

local allEmotes = {}
local folderEmotes = {}
local customEmotes = {}
local favorites = {}
local binds = {}
local st = { idle = nil, run = nil, current = nil, enabled = true, url = nil }
local __i
local DATA_FILE = "reanimation_hub_data.json"
local GREEN = Color3.fromRGB(220, 220, 220)
local RED = Color3.fromRGB(220, 220, 220)
local BOX_COLOR = Color3.fromRGB(22, 22, 22)

local function loadData()
	if type(readfile) == "function" and type(isfile) == "function" and isfile(DATA_FILE) then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(DATA_FILE))
		end)
		if ok and type(data) == "table" then
			if type(data.favorites) == "table" then
				favorites = data.favorites
			end
			if type(data.binds) == "table" then
				binds = data.binds
			end
			if type(data.custom) == "table" then
				for _, item in ipairs(data.custom) do
					if type(item) == "table" and type(item.name) == "string" and type(item.url) == "string" then
						table.insert(customEmotes, { name = item.name, url = item.url, custom = true })
					end
				end
			end
			if type(data.idle) == "table" and type(data.idle.name) == "string" and type(data.idle.url) == "string" then
				st.idle = { name = data.idle.name, url = data.idle.url }
			end
			if type(data.run) == "table" and type(data.run.name) == "string" and type(data.run.url) == "string" then
				st.run = { name = data.run.name, url = data.run.url }
			end
			if data.stateEnabled ~= nil then
				st.enabled = data.stateEnabled and true or false
			end
		end
	end
end

local function saveData()
	if type(writefile) == "function" then
		local custom = {}
		for _, item in ipairs(customEmotes) do
			table.insert(custom, { name = item.name, url = item.url })
		end
		pcall(function()
			writefile(DATA_FILE, HttpService:JSONEncode({
				favorites = favorites,
				binds = binds,
				custom = custom,
				idle = st.idle and { name = st.idle.name, url = st.idle.url } or nil,
				run = st.run and { name = st.run.name, url = st.run.url } or nil,
				stateEnabled = st.enabled,
			}))
		end)
	end
end

loadData()

local STATUS_Y = TITLE_HEIGHT + 8
local SEARCH_Y = STATUS_Y + 36
local TAB_DIV_Y = SEARCH_Y + 34
local TAB_Y = TAB_DIV_Y + 4
local LIST_Y = TAB_Y + 30
local CUSTOM_FORM_H = 92

homeStatus = Instance.new("TextLabel")
homeStatus.Name = "Status"
homeStatus.Size = UDim2.new(0.5, -12, 0, 26)
homeStatus.Position = UDim2.new(0, 14, 0, STATUS_Y)
homeStatus.BackgroundTransparency = 1
homeStatus.Text = "Status: Off"
homeStatus.TextColor3 = MUTED
homeStatus.Font = Enum.Font.GothamMedium
homeStatus.TextSize = 12
homeStatus.TextXAlignment = Enum.TextXAlignment.Left
homeStatus.TextTruncate = Enum.TextTruncate.AtEnd
homeStatus.ZIndex = 3
homeStatus.Parent = body

local function setStatus(text, color)
	homeStatus.Text = "Status: " .. text
	homeStatus.TextColor3 = color or MUTED
end

local function refreshStatus()
	if not api then
		setStatus("API failed to load", RED)
	elseif reanimEnabled then
		setStatus("On", GREEN)
	else
		setStatus("Off", MUTED)
	end
end

local enableButton = Instance.new("TextButton")
enableButton.Name = "EnableButton"
enableButton.Size = UDim2.new(0.5, -22, 0, 26)
enableButton.Position = UDim2.new(0.5, 8, 0, STATUS_Y)
enableButton.BackgroundColor3 = WHITE
enableButton.BackgroundTransparency = 0.85
enableButton.BorderSizePixel = 0
enableButton.Text = "Enable"
enableButton.TextColor3 = WHITE
enableButton.Font = Enum.Font.GothamMedium
enableButton.TextSize = 12
enableButton.AutoButtonColor = false
enableButton.ZIndex = 3
enableButton.Parent = body
makeCorner(enableButton, 6)

updateReanimVisual = function(animate)
	local info = TweenInfo.new(animate and 0.25 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	enableButton.Text = reanimEnabled and "Disable" or "Enable"
	TweenService:Create(enableButton, info, {
		BackgroundColor3 = reanimEnabled and ORANGE or WHITE,
		BackgroundTransparency = reanimEnabled and 0.6 or 0.85,
	}):Play()
end

stopEmote = function()
	if api and api.stop_animation then
		pcall(api.stop_animation)
	end
	playingName = nil
	st.current = nil
	st.url = nil
end

loadAndPlayEmote = function(entry)
	if not entry or not entry.url then return end

	if not api then
		setStatus("Reanimation API failed to load", RED)
		return
	end

	if not api.is_reanimated or not api.is_reanimated() then
		setStatus("Enable reanimation first", Color3.fromRGB(255, 255, 255))
		return
	end

	st.current = nil
	st.url = nil
	setStatus("Loading " .. entry.name .. "...", ORANGE)

	task.spawn(function()
		if api.set_animation_speed then
			pcall(api.set_animation_speed, currentSpeed())
		end
		local result = api.play_animation(entry.url, currentSpeed())
		if type(result) == "string" then
			setStatus(result, RED)
			playingName = nil
		else
			playingName = entry.name
			setStatus("Playing " .. entry.name, GREEN)
		end
	end)
end

setReanimated = function(enabled)
	if not api or not api.reanimate then
		setStatus("API not available", RED)
		return false
	end
	local result = api.reanimate(enabled)
	if type(result) == "string" and result ~= "" then
		setStatus(result, RED)
		return false
	end
	if not enabled then
		playingName = nil
		st.current = nil
		st.url = nil
	end
	return true
end

enableButton.MouseButton1Click:Connect(function()
	if not api then
		setStatus("API failed to load", RED)
		return
	end
	local ok = setReanimated(not reanimEnabled)
	reanimEnabled = api.is_reanimated and api.is_reanimated() or false
	updateReanimVisual(true)
	if ok then
		refreshStatus()
	end
end)

refreshStatus()

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Size = UDim2.new(1, -24, 0, 26)
searchBox.Position = UDim2.new(0, 12, 0, SEARCH_Y)
searchBox.BackgroundColor3 = BOX_COLOR
searchBox.BorderSizePixel = 0
searchBox.Text = ""
searchBox.PlaceholderText = "Search emotes..."
searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
searchBox.TextColor3 = WHITE
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 12
searchBox.ClearTextOnFocus = false
searchBox.ZIndex = 3
searchBox.Parent = body
makeCorner(searchBox, 6)

local emoteTabBar = Instance.new("Frame")
emoteTabBar.Name = "EmoteTabs"
emoteTabBar.Size = UDim2.new(1, -24, 0, 26)
emoteTabBar.Position = UDim2.new(0, 12, 0, TAB_Y)
emoteTabBar.BackgroundTransparency = 1
emoteTabBar.ZIndex = 3
emoteTabBar.Parent = body

local emoteTabNames = { "All", "Favs", "Binds", "Custom", "Speed", "Limb", "State", "AnimCopy" }
local emoteMode = "All"
local emoteTabButtons = {}

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

local function makeBox(parent, placeholder, y)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 24)
	box.Position = UDim2.new(0, 0, 0, y)
	box.BackgroundColor3 = BOX_COLOR
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
	box.TextColor3 = WHITE
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	box.ClearTextOnFocus = false
	box.ZIndex = 3
	box.Parent = parent
	makeCorner(box, 6)
	return box
end

local function makeGlassButton(parent, text, size, position)
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = WHITE
	btn.BackgroundTransparency = 0.85
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.ZIndex = 3
	btn.Parent = parent
	makeCorner(btn, 6)
	return btn
end

local customForm = Instance.new("Frame")
customForm.Name = "CustomForm"
customForm.Position = UDim2.new(0, 12, 0, LIST_Y + 4)
customForm.Size = UDim2.new(1, -24, 0, CUSTOM_FORM_H - 8)
customForm.BackgroundTransparency = 1
customForm.Visible = false
customForm.ZIndex = 3
customForm.Parent = body

local customNameBox = makeBox(customForm, "Emote name", 0)
local customUrlBox = makeBox(customForm, "Animation script URL", 28)
local customAddButton = makeGlassButton(customForm, "Add emote", UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 0, 56))

local speedPanel = Instance.new("Frame")
speedPanel.Name = "SpeedPanel"
speedPanel.Position = UDim2.new(0, 12, 0, LIST_Y + 6)
speedPanel.Size = UDim2.new(1, -24, 0, 200)
speedPanel.BackgroundTransparency = 1
speedPanel.Visible = false
speedPanel.ZIndex = 3
speedPanel.Parent = body

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.5, 0, 0, 18)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Anim Speed"
speedLabel.TextColor3 = WHITE
speedLabel.Font = Enum.Font.GothamMedium
speedLabel.TextSize = 13
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.ZIndex = 3
speedLabel.Parent = speedPanel

local speedValue = Instance.new("TextLabel")
speedValue.Size = UDim2.new(0, 40, 0, 18)
speedValue.Position = UDim2.new(1, -40, 0, 0)
speedValue.BackgroundTransparency = 1
speedValue.Text = "1.00"
speedValue.TextColor3 = Color3.fromRGB(200, 200, 200)
speedValue.Font = Enum.Font.Gotham
speedValue.TextSize = 13
speedValue.TextXAlignment = Enum.TextXAlignment.Right
speedValue.ZIndex = 3
speedValue.Parent = speedPanel

local speedHit = Instance.new("TextButton")
speedHit.Size = UDim2.new(1, 0, 0, 20)
speedHit.Position = UDim2.new(0, 0, 0, 24)
speedHit.BackgroundTransparency = 1
speedHit.Text = ""
speedHit.AutoButtonColor = false
speedHit.ZIndex = 3
speedHit.Parent = speedPanel

local speedBar = Instance.new("Frame")
speedBar.AnchorPoint = Vector2.new(0, 0.5)
speedBar.Position = UDim2.new(0, 0, 0.5, 0)
speedBar.Size = UDim2.new(1, 0, 0, 4)
speedBar.BackgroundColor3 = BOX_COLOR
speedBar.BorderSizePixel = 0
speedBar.ZIndex = 3
speedBar.Parent = speedHit
makeCorner(speedBar, 2)

local speedFill = Instance.new("Frame")
speedFill.Size = UDim2.new(0.25, 0, 1, 0)
speedFill.BackgroundColor3 = WHITE
speedFill.BorderSizePixel = 0
speedFill.ZIndex = 4
speedFill.Parent = speedBar
makeCorner(speedFill, 2)

local refreshPresets

local function setSpeedFromAlpha(alpha)
	alpha = math.clamp(alpha, 0, 1)
	local value = 0.25 + alpha * (4 - 0.25)
	value = math.floor(value * 20 + 0.5) / 20
	animSpeed = value
	speedFill.Size = UDim2.new(alpha, 0, 1, 0)
	speedValue.Text = string.format("%.2f", value)
	applySpeed()
	if refreshPresets then refreshPresets() end
end

setSpeedFromAlpha((1 - 0.25) / (4 - 0.25))

local speedDragging = false
speedHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		speedDragging = true
		setSpeedFromAlpha((input.Position.X - speedHit.AbsolutePosition.X) / speedHit.AbsoluteSize.X)
	end
end)

track(UserInputService.InputChanged:Connect(function(input)
	if not speedDragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		setSpeedFromAlpha((input.Position.X - speedHit.AbsolutePosition.X) / speedHit.AbsoluteSize.X)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		speedDragging = false
	end
end))

local bindingFor = nil

local PRESET_VALUES = { 0.5, 1, 2, 4 }
local presetButtons = {}

local function applyPreset(value, isReverse)
	speedBoost = true
	reversed = isReverse
	setSpeedFromAlpha((value - 0.25) / (4 - 0.25))
end

local presetById = {}

local function makePresetRow(title, y, isReverse)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Position = UDim2.new(0, 0, 0, y)
	label.BackgroundTransparency = 1
	label.Text = title
	label.TextColor3 = MUTED
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	label.Parent = speedPanel

	for i, value in ipairs(PRESET_VALUES) do
		local btn = makeGlassButton(
			speedPanel,
			(isReverse and "-" or "") .. tostring(value) .. "x",
			UDim2.new(0.25, -6, 0, 26),
			UDim2.new((i - 1) * 0.25, 3, 0, y + 20)
		)
		table.insert(presetButtons, { button = btn, value = value, reverse = isReverse, y = y + 48, index = i })
		btn.MouseButton1Click:Connect(function()
			applyPreset(value, isReverse)
		end)
	end
end

makePresetRow("Speed presets", 40, false)
makePresetRow("Reverse presets", 120, true)

refreshPresets = function()
	for _, item in ipairs(presetButtons) do
		local active = speedBoost and reversed == item.reverse and math.abs(animSpeed - item.value) < 0.001
		item.button.TextColor3 = active and ORANGE or WHITE
	end
end
refreshPresets()

local ROW_H = 28
local ROW_GAP = 4
local emoteRows = {}
local playButtons = {}
local layoutEmotes

local function clearEmoteRows()
	for _, row in ipairs(emoteRows) do
		row:Destroy()
	end
	table.clear(emoteRows)
	table.clear(playButtons)
end

local function combinedEntries()
	local list = {}
	for _, entry in ipairs(customEmotes) do
		table.insert(list, entry)
	end
	for _, entry in ipairs(folderEmotes) do
		table.insert(list, entry)
	end
	for _, entry in ipairs(allEmotes) do
		table.insert(list, entry)
	end
	return list
end

local function findEntry(name)
	for _, entry in ipairs(combinedEntries()) do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

local function togglePlay(entry)
	if playingName == entry.name then
		stopEmote()
		refreshStatus()
	else
		loadAndPlayEmote(entry)
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

local bin = { pending = nil, asset = nil }
__i = function()
	local BIN_FILE = FOLDER_ROOT .. "/bin.png"
	local BIN_B64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAIX0lEQVR42tWbPYwkRxXHf9W7s3t3sLv2zFnGhhMBtsAC2WAyLEQABiEhS7blCEicgEnAKSB0EYEjkM5IpEgQQECCOMTJASdBYHOBJSRjCSxh8Sl29m5nrbv9mn4O+tXtm7dVPd09vb7bklo7s1Nd9erV/338X1dDj02g0L+PCvxM4F8CUwHpeE0F/qljPWrnuOuaWfwzAptmEYcLXnGcscCzd6USzOIfF9hVgfcX2Hl/xbF2BT7VpxKWe9bFd4FV4AAYABPgGlB2HK8APg2s65irOsdzd9PuB/27oTAt9fqvwGM9jP+YjhXH3RTYsHOfGAIUZgX1ExVS7fCHgPfr/wLw+wCvS7VrnRGgY1wBvlaJxBrwQYGbZu6aJVCGmj7LNbsa9May4U5tmUkDsK2a2OsBaDfM2ADXQ2USbXyUhKP78wqQauFC5XQ+BnwOuL8GBUEFuw9YMv2eELhofpeWiw7m3ifM/5aA7wn83/ye2/3/AX8I8Fe3trn2/D6Bl41HP83XrsBPRM3T+43gYa/e+9fAl/WnfdNPahAQHKJKYDpnl5qgQHTXbdg7NHPmZIryrujny8DTGk2Om4NUkyDwompuT73uaUdAafKIb9u13tZUtA2pdvB1KtuPmv8p8JuOdnynWkTzV4BvGCS+AXwyVBnmkT8wmdwFgVtm51/hlDeBVwwSbglcsGv26eSq8/abnP42dshYSYXBCO1/66IfVCf2lMDzwK/oIet67zef54CndC2BKnT+x67ZRoGlUNHPH1E5i32jrckp3f11E8lWgB8H+E5c67FsSSAIfEDgLUNly1MeASKlfkvXFrJM0iRCjwi8aooS5SlTRJQ3FmNeFXikNhGySAjVzQOlnhfVhgrgH8Cb6jvutpAYNEH6KPBhI/NF4IcBDuLamniPZYOEqYHRpb5o6AnS8peN+U7Nzi/nCg6pNtUB99SBxMzpvhxyjB8Z2EyrTmCBZb1Cg/5LOnYdKbMyLqnse3rPtFU9QDPDsSrhjP57FOWxgmjfGfpsM61MX1HI4rLRmb7mt2lcRKZv6WREZR/7vk0QENsucN18H2kIiTFU7IIEHpCKqj5tyUbs5/oOBL4l8ILAwP4WHFnR357RsR/wfZ3pDo28W7qGzvZUCLxmvOvbomgwfYJe5wT+bPp+1RMPl3ZfMn0vpQqdhqB93fR9TecKVgb9e1ZltH2LOr9V1MA/QtqmkvcAZ3133YULwONqdwJ8KVNsKXWnnuQI1k8KLOtvKUG/qGPua5H0Qjiiw7adVRlvp8FxzFwhpJgTViKMLLceJjg3wDtUdbqB/nbO1AVSYx+oo1rSz6mFl2ZhsVZxU+eyc8d771UZxfGAUFd2nqeAOMhUBz+f6b+jTi3YNLSmBBXq8hF374ZT3E5mzPOqpGkfCijcIBFyw8ygXrB1b6Md/VAwOX1U9EFGmSOV2yOg6KIASdBJH2ZwZSpLmjZ0NxZtA6eAiQ2frg3d962aUl5nBZzPIOAwlsKNCfTx5GnZmAA6x2EGAecztYBOCvBa9FoO1k71r0XAmi8+dGwr5oELwI6bsw4B47lPXhoioDRaHnrvbuL3xO3c2jwn1MAJeyRtJ3IGceYZmA3hC5nApglZFmapQSdGOR66XVv0JWVNccYrIIbW3kxg13laHK0s7O4YBaz3oIA1Has0UWBG9gQPCCrz1iImYAnFDWtnifQyOOFiyFzvyQTsLm77kr4xCRuhbtDguWQTBey76vAo4dy8cL4m10ddz5uZJJzlyFW09zsrwHja0kHpXkOPU9lgSvhFELCRUYBvZ1I8YE42Wo8ASWeDq4lwc5IIWHPftzMIGKpsYsP3vKM0RcNd8HxglNnZScKD942AnZokaMXwgM0mcxcNTcTzgVGGEe4wS1PXahjhvFY6FMUcf5JhgkNmnxZvNVnjPAW05QMxTS0yHrwlHzrmRw4TZpaTadxk7qYK2MpMFuYooK9EyCpg0hcPaBoG4fhD0joTOPBOMHQwAXPPWqYWkDKBVjygLQKkjg+YmsA71oN3qQm0rAWUCZImfZtALI8v+fJ4QgF9UmKfTm8nFCDOBOLzgF5NYMzsWaFRBtqposiiCthIlN1SpmIRsNeEB7RRwK7jAyNTsg4nWBNYcYnQtp2rhgdcp+HzgKYK2HdOZeTLXYmagLhiRmjnA28rcGBgPMlkd75YO27CA+YqwPGBseMDq5nbrAIWrQlEE5JMFhjbquMBW014QCMEZPjAGVVCate2nQIW4QNrTgHbGTQNVaaZxK3JkfqiBRwtHxgkiqNFoirUtSZgawEhUQ0qXL9okq14QFcFCLNOJ5UM9cUI59UCcs8Dtpqur81bF7nqMBm6ukhNIGQU0JQHzH0e0EYB8wiRR8DEfJYaBEjms1eeHasOAanUXfpEwDwFWJhG4hIyNQExNjt1oc72vcdwgODS7IV5QBcESELrpet3DXib6oluCfwx9tPkpQiVcq5w9HT4ip7fLTRsxTGv6udzVAe0rrm5UtVgaWMCTVYfK8AP6dn7eFzu5z7UmMzsYYHvC3zBEyHTZ6CnQ76pJ9Jy/T4v8AOBhxJ9omy/MMfjdgU+0jQMtmFmQ4GJOX3xW3M65Jjgue9d5k59t3MLXDZyTURzlCZztyEqN5UPxNz8QXOIqXAebcmEpWmNIMuGROWUEMeaMnvYKZ5gQaqzzbHdAG7RV3OavmqOn+7HNznvZBN4VmWJx3qvppDZGQHquOJB6t8BnzXV4V8K/Em1/l6/zlpqOv4ZdX7xPOPl+PJHqEFWV0c4FPj7Cbwa29ertX8TDYm9n2Y1Svi4wF/cG96Hd+iyb6a/IfCJ3rz/HCXcL/CSwJt3GAn7KsNLUr3b2Hrx7wL6H2Ze+LjvgwAAAABJRU5ErkJggg=="

	local function b64decode(data)
		local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local out, buf, bits = {}, 0, 0
		for i = 1, #data do
			local c = data:sub(i, i)
			if c == "=" then break end
			local v = chars:find(c, 1, true)
			if v then
				buf = buf * 64 + (v - 1)
				bits = bits + 6
				if bits >= 8 then
					bits = bits - 8
					local byte = math.floor(buf / 2 ^ bits)
					buf = buf % 2 ^ bits
					out[#out + 1] = string.char(byte)
				end
			end
		end
		return table.concat(out)
	end

	function bin.get()
		if bin.asset then return bin.asset end
		if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then return nil end
		local ok, asset = pcall(function()
			if not (type(isfile) == "function" and isfile(BIN_FILE)) then
				writefile(BIN_FILE, b64decode(BIN_B64))
			end
			return getcustomasset(BIN_FILE)
		end)
		if ok and asset and asset ~= "" then
			bin.asset = asset
		end
		return bin.asset
	end
end
__i()
task.spawn(bin.get)

local speedBindRefreshers = {}

local function refreshSpeedBinds()
	for _, refresh in ipairs(speedBindRefreshers) do
		refresh()
	end
end

local function makeKeyButton(parent, bindId, xFromRight, y)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 64, 0, 22)
	btn.Position = UDim2.new(1, -(xFromRight + 64), 0, y)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.TextXAlignment = Enum.TextXAlignment.Right
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Position = UDim2.new(1, 0, 0.5, 0)
	icon.Size = UDim2.new(0, 18, 0, 18)
	icon.BackgroundTransparency = 1
	icon.ImageColor3 = WHITE
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 5
	icon.Parent = btn

	local function refresh()
		local keyName = binds[bindId]
		local logo = getLogoAsset()
		icon.Image = logo or ""
		if bindingFor == bindId then
			btn.Text = "press key"
			btn.TextColor3 = ORANGE
			icon.Visible = false
		elseif keyName then
			btn.Text = keyName
			btn.TextColor3 = ORANGE
			icon.Visible = false
		else
			btn.Text = logo and "" or "bind"
			btn.TextColor3 = WHITE
			icon.Visible = logo ~= nil
		end
	end

	btn.MouseButton1Click:Connect(function()
		if binds[bindId] then
			binds[bindId] = nil
			saveData()
		else
			bindingFor = bindId
		end
		refreshSpeedBinds()
	end)

	table.insert(speedBindRefreshers, refresh)
	refresh()
	return btn
end

for _, item in ipairs(presetButtons) do
	local id = "__preset_" .. (item.reverse and "r" or "s") .. tostring(item.value)
	presetById[id] = item
	local keyBtn = makeKeyButton(speedPanel, id, 0, item.y)
	keyBtn.Size = UDim2.new(0.25, -6, 0, 22)
	keyBtn.Position = UDim2.new((item.index - 1) * 0.25, 3, 0, item.y)
	keyBtn.TextXAlignment = Enum.TextXAlignment.Center
	local icon = keyBtn:FindFirstChildOfClass("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
end
task.delay(2, refreshSpeedBinds)

local limbPanel = Instance.new("ScrollingFrame")
limbPanel.Name = "LimbPanel"
limbPanel.Position = UDim2.new(0, 12, 0, LIST_Y + 6)
limbPanel.Size = UDim2.new(1, -24, 1, -(LIST_Y + 12))
limbPanel.BackgroundTransparency = 1
limbPanel.BorderSizePixel = 0
limbPanel.ScrollBarThickness = 3
limbPanel.ScrollBarImageColor3 = WHITE
limbPanel.ScrollBarImageTransparency = 0.65
limbPanel.ScrollingDirection = Enum.ScrollingDirection.Y
limbPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
limbPanel.Visible = false
limbPanel.ZIndex = 3
limbPanel.Parent = body

local limbToggle, scrollToggle, limbLeftToggle, torsoToggle, headToggle
local turnButtons = {}

__i = function()
	local CARD_BG = Color3.fromRGB(18, 18, 18)

	local function makeFeatureCard(parent, y, height)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, height)
		card.Position = UDim2.new(0, 0, 0, y)
		card.BackgroundColor3 = CARD_BG
		card.BorderSizePixel = 0
		card.ZIndex = 3
		card.Parent = parent
		makeCorner(card, 8)
		return card
	end

	local function makeCardDesc(parent, text, y)
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -16, 0, 28)
		desc.Position = UDim2.new(0, 8, 0, y)
		desc.BackgroundTransparency = 1
		desc.Text = text
		desc.TextColor3 = MUTED
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.ZIndex = 4
		desc.Parent = parent
	end

	local function makeCardBindRow(parent, labelText, bindId, y)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.5, 0, 0, 22)
		label.Position = UDim2.new(0, 8, 0, y)
		label.BackgroundTransparency = 1
		label.Text = labelText
		label.TextColor3 = MUTED
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 11
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 4
		label.Parent = parent
		makeKeyButton(parent, bindId, 8, y)
	end

	local rightCard = makeFeatureCard(limbPanel, 0, 100)
	limbToggle = makeGlassButton(rightCard, "Right arm stretch: Off", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(rightCard, "Stretches your right arm toward the cursor. Enable reanimation first.", 38)
	makeCardBindRow(rightCard, "Keybind", "__limb_toggle", 70)

	local scrollCard = makeFeatureCard(limbPanel, 108, 88)
	scrollToggle = makeGlassButton(scrollCard, "Scroll stretch: Off", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(scrollCard, "Use the mouse wheel to control how far the right arm reaches while stretched. Enable reanimation first.", 38)

	local leftCard = makeFeatureCard(limbPanel, 204, 100)
	limbLeftToggle = makeGlassButton(leftCard, "Left arm stretch: Off", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(leftCard, "Stretches your left arm toward the cursor. Enable reanimation first.", 38)
	makeCardBindRow(leftCard, "Keybind", "__limb_left_toggle", 70)

	local torsoCard = makeFeatureCard(limbPanel, 312, 130)
	torsoToggle = makeGlassButton(torsoCard, "Torso follow: Off", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(torsoCard, "Turns your upper torso toward the camera. Enable reanimation first.", 38)
	makeCardBindRow(torsoCard, "Keybind", "__torso_toggle", 70)

	local maxTurnLabel = Instance.new("TextLabel")
	maxTurnLabel.Size = UDim2.new(0.35, 0, 0, 22)
	maxTurnLabel.Position = UDim2.new(0, 8, 0, 98)
	maxTurnLabel.BackgroundTransparency = 1
	maxTurnLabel.Text = "Max turn"
	maxTurnLabel.TextColor3 = MUTED
	maxTurnLabel.Font = Enum.Font.GothamMedium
	maxTurnLabel.TextSize = 11
	maxTurnLabel.TextXAlignment = Enum.TextXAlignment.Left
	maxTurnLabel.ZIndex = 4
	maxTurnLabel.Parent = torsoCard

	for i, opt in ipairs({ { label = "90", deg = 90 }, { label = "180", deg = 180 }, { label = "360", deg = 360 } }) do
		local btn = makeGlassButton(
			torsoCard,
			opt.label .. "°",
			UDim2.new(0.22, -3, 0, 22),
			UDim2.new(0.34 + (i - 1) * 0.22, 0, 0, 98)
		)
		turnButtons[opt.deg] = btn
	end

	local headCard = makeFeatureCard(limbPanel, 450, 100)
	headToggle = makeGlassButton(headCard, "Head follow: Off", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(headCard, "Turns your head toward the camera. Enable reanimation first.", 38)
	makeCardBindRow(headCard, "Keybind", "__head_toggle", 70)

	limbPanel.CanvasSize = UDim2.new(0, 0, 0, 560)
end
__i()

st.panel, st.refreshLists = (function()
	local CARD_BG = Color3.fromRGB(18, 18, 18)
	local COLLAPSED_H = 70
	local EXPANDED_H = 240
	local CARD_GAP = 8

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "StatePanel"
	panel.Position = UDim2.new(0, 12, 0, LIST_Y + 6)
	panel.Size = UDim2.new(1, -24, 1, -(LIST_Y + 12))
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 3
	panel.ScrollBarImageColor3 = WHITE
	panel.ScrollBarImageTransparency = 0.65
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	panel.Visible = false
	panel.ZIndex = 3
	panel.Parent = body

	local function makeFeatureCard(parent, y, height)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, height)
		card.Position = UDim2.new(0, 0, 0, y)
		card.BackgroundColor3 = CARD_BG
		card.BorderSizePixel = 0
		card.ZIndex = 3
		card.Parent = parent
		makeCorner(card, 8)
		return card
	end

	local function makeCardDesc(parent, text, y)
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -16, 0, 28)
		desc.Position = UDim2.new(0, 8, 0, y)
		desc.BackgroundTransparency = 1
		desc.Text = text
		desc.TextColor3 = MUTED
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.ZIndex = 4
		desc.Parent = parent
	end

	local enableCard = makeFeatureCard(panel, 0, 88)
	local enableBtn = makeGlassButton(enableCard, "State animations: On", UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 8))
	makeCardDesc(enableCard, "Auto-plays idle when standing still and run when moving. Enable reanimation first.", 38)

	local function refreshEnable()
		enableBtn.Text = "State animations: " .. (st.enabled and "On" or "Off")
		enableBtn.TextColor3 = st.enabled and ORANGE or WHITE
	end
	refreshEnable()

	enableBtn.MouseButton1Click:Connect(function()
		st.enabled = not st.enabled
		refreshEnable()
		saveData()
		if not st.enabled then
			st.current = nil
			st.url = nil
			if playingName then
				local isIdle = st.idle and playingName == st.idle.name
				local isRun = st.run and playingName == st.run.name
				if isIdle or isRun then
					stopEmote()
					refreshStatus()
				end
			end
		end
	end)

	local sections = {}

	local function relayoutSections()
		local y = 96
		for _, sec in ipairs(sections) do
			sec.card.Position = UDim2.new(0, 0, 0, y)
			sec.card.Size = UDim2.new(1, 0, 0, sec.expanded and EXPANDED_H or COLLAPSED_H)
			y = y + (sec.expanded and EXPANDED_H or COLLAPSED_H) + CARD_GAP
		end
		panel.CanvasSize = UDim2.new(0, 0, 0, y + 4)
	end

	local function makeSection(title, getSelected, setSelected)
		local card = makeFeatureCard(panel, 0, COLLAPSED_H)
		local expanded = false

		local headerBtn = Instance.new("TextButton")
		headerBtn.Size = UDim2.new(1, -66, 0, 54)
		headerBtn.Position = UDim2.new(0, 0, 0, 0)
		headerBtn.BackgroundTransparency = 1
		headerBtn.Text = ""
		headerBtn.AutoButtonColor = false
		headerBtn.ZIndex = 4
		headerBtn.Parent = card

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(0.55, 0, 0, 18)
		titleLbl.Position = UDim2.new(0, 10, 0, 8)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Text = title
		titleLbl.TextColor3 = WHITE
		titleLbl.Font = Enum.Font.GothamMedium
		titleLbl.TextSize = 13
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.ZIndex = 5
		titleLbl.Parent = card

		local chevron = Instance.new("TextLabel")
		chevron.Size = UDim2.new(0, 18, 0, 18)
		chevron.Position = UDim2.new(1, -74, 0, 8)
		chevron.BackgroundTransparency = 1
		chevron.Text = "›"
		chevron.TextColor3 = MUTED
		chevron.Font = Enum.Font.GothamBold
		chevron.TextSize = 16
		chevron.TextXAlignment = Enum.TextXAlignment.Center
		chevron.Rotation = 0
		chevron.ZIndex = 5
		chevron.Parent = card

		local selectedLbl = Instance.new("TextLabel")
		selectedLbl.Size = UDim2.new(1, -20, 0, 18)
		selectedLbl.Position = UDim2.new(0, 10, 0, 32)
		selectedLbl.BackgroundTransparency = 1
		selectedLbl.Text = "None — tap to choose"
		selectedLbl.TextColor3 = MUTED
		selectedLbl.Font = Enum.Font.Gotham
		selectedLbl.TextSize = 12
		selectedLbl.TextXAlignment = Enum.TextXAlignment.Left
		selectedLbl.TextTruncate = Enum.TextTruncate.AtEnd
		selectedLbl.ZIndex = 5
		selectedLbl.Parent = card

		local clearBtn = makeGlassButton(card, "Clear", UDim2.new(0, 50, 0, 22), UDim2.new(1, -58, 0, 8))
		clearBtn.TextSize = 11

		local dropBody = Instance.new("Frame")
		dropBody.Size = UDim2.new(1, -16, 0, EXPANDED_H - COLLAPSED_H - 4)
		dropBody.Position = UDim2.new(0, 8, 0, COLLAPSED_H - 4)
		dropBody.BackgroundTransparency = 1
		dropBody.Visible = false
		dropBody.ZIndex = 4
		dropBody.Parent = card

		local search = Instance.new("TextBox")
		search.Size = UDim2.new(1, 0, 0, 24)
		search.Position = UDim2.new(0, 0, 0, 0)
		search.BackgroundColor3 = BOX_COLOR
		search.BorderSizePixel = 0
		search.Text = ""
		search.PlaceholderText = "Search animations..."
		search.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
		search.TextColor3 = WHITE
		search.Font = Enum.Font.Gotham
		search.TextSize = 12
		search.ClearTextOnFocus = false
		search.ZIndex = 5
		search.Parent = dropBody
		makeCorner(search, 6)

		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, 0, 0, EXPANDED_H - COLLAPSED_H - 34)
		list.Position = UDim2.new(0, 0, 0, 30)
		list.BackgroundColor3 = BOX_COLOR
		list.BackgroundTransparency = 0.3
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 3
		list.ScrollBarImageColor3 = WHITE
		list.ScrollBarImageTransparency = 0.65
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.ZIndex = 5
		list.Parent = dropBody
		makeCorner(list, 6)

		local rows = {}
		local sec = { card = card, expanded = false }

		local function setExpanded(value)
			expanded = value
			sec.expanded = value
			dropBody.Visible = value
			chevron.Rotation = value and 90 or 0
			chevron.TextColor3 = value and WHITE or MUTED
			if value then
				for _, other in ipairs(sections) do
					if other ~= sec and other.expanded then
						other.setExpanded(false)
					end
				end
			end
			relayoutSections()
		end
		sec.setExpanded = setExpanded

		headerBtn.MouseButton1Click:Connect(function()
			setExpanded(not expanded)
		end)

		local function refreshList()
			for _, r in ipairs(rows) do
				pcall(function()
					r:Destroy()
				end)
			end
			table.clear(rows)
			local query = string.lower(search.Text or "")
			local y = 2
			local shown = 0
			local source = combinedEntries()
			for _, entry in ipairs(source) do
				if type(entry) == "table" and type(entry.name) == "string" then
					if query == "" or string.find(string.lower(entry.name), query, 1, true) then
						if shown >= 80 then
							break
						end
						local row = Instance.new("TextButton")
						row.Size = UDim2.new(1, -6, 0, 22)
						row.Position = UDim2.new(0, 3, 0, y)
						row.BackgroundTransparency = 1
						row.Text = entry.name
						row.TextColor3 = WHITE
						row.Font = Enum.Font.Gotham
						row.TextSize = 12
						row.TextXAlignment = Enum.TextXAlignment.Left
						row.AutoButtonColor = false
						row.ZIndex = 6
						row.Parent = list
						local sel = getSelected()
						if sel and sel.name == entry.name then
							row.TextColor3 = ORANGE
						end
						row.MouseButton1Click:Connect(function()
							setSelected({ name = entry.name, url = entry.url })
							selectedLbl.Text = entry.name
							selectedLbl.TextColor3 = ORANGE
							saveData()
							refreshList()
							if st.current == string.lower(title) then
								st.current = nil
								st.url = nil
							end
							setExpanded(false)
						end)
						table.insert(rows, row)
						y = y + 24
						shown = shown + 1
					end
				end
			end
			list.CanvasSize = UDim2.new(0, 0, 0, y + 4)
		end

		clearBtn.MouseButton1Click:Connect(function()
			setSelected(nil)
			selectedLbl.Text = "None — tap to choose"
			selectedLbl.TextColor3 = MUTED
			saveData()
			if st.current == string.lower(title) then
				st.current = nil
				st.url = nil
				stopEmote()
				refreshStatus()
			end
			refreshList()
		end)

		search:GetPropertyChangedSignal("Text"):Connect(refreshList)

		local function syncLabel()
			local sel = getSelected()
			if sel and sel.name then
				selectedLbl.Text = sel.name
				selectedLbl.TextColor3 = ORANGE
			else
				selectedLbl.Text = "None — tap to choose"
				selectedLbl.TextColor3 = MUTED
			end
		end

		table.insert(sections, sec)
		return refreshList, syncLabel
	end

	local idleRefresh, idleSync = makeSection("Idle", function()
		return st.idle
	end, function(v)
		st.idle = v
	end)
	local runRefresh, runSync = makeSection("Run", function()
		return st.run
	end, function(v)
		st.run = v
	end)

	relayoutSections()
	idleSync()
	runSync()

	local function refresh()
		pcall(idleRefresh)
		pcall(runRefresh)
	end

	local STATE_IDLE_THRESHOLD = 1.5
	local lastStateCheck = 0

	local function playStateAnim(entry, stateName)
		if not entry or not entry.url or not api or not reanimEnabled then
			return
		end
		if type(api.is_reanimated) ~= "function" or not api.is_reanimated() then
			return
		end
		if playingName and st.current == nil then
			return
		end
		if st.url == entry.url and playingName == entry.name then
			return
		end
		task.spawn(function()
			if api.set_animation_speed then
				pcall(api.set_animation_speed, currentSpeed())
			end
			local ok, result = pcall(function()
				return api.play_animation(entry.url, currentSpeed())
			end)
			if ok and type(result) ~= "string" then
				playingName = entry.name
				st.current = stateName
				st.url = entry.url
				setStatus("State: " .. stateName .. " (" .. entry.name .. ")", GREEN)
			end
		end)
	end

	local function updateMovementState()
		if not st.enabled or not reanimEnabled or not api then
			return
		end
		if type(api.is_reanimated) ~= "function" or not api.is_reanimated() then
			return
		end
		if playingName and st.current == nil then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local vel = hrp.Velocity
		pcall(function()
			local alv = hrp.AssemblyLinearVelocity
			if alv then
				vel = alv
			end
		end)
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local desired = (speed > STATE_IDLE_THRESHOLD) and "run" or "idle"
		local entry = (desired == "run") and st.run or st.idle
		if not entry then
			if st.current then
				st.current = nil
				st.url = nil
				stopEmote()
				refreshStatus()
			end
			return
		end
		if st.current ~= desired or playingName ~= entry.name then
			playStateAnim(entry, desired)
		end
	end

	track(RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastStateCheck < 0.15 then
			return
		end
		lastStateCheck = now
		pcall(updateMovementState)
	end))

	return panel, refresh
end)()

st.copyPanel, st.copyStop = (function()
	local RS_NAME = "animcopy_mirror"

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "AnimCopyPanel"
	panel.Position = UDim2.new(0, 12, 0, LIST_Y + 6)
	panel.Size = UDim2.new(1, -24, 1, -(LIST_Y + 12))
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 3
	panel.ScrollBarImageColor3 = WHITE
	panel.ScrollBarImageTransparency = 0.65
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 280)
	panel.Visible = false
	panel.ZIndex = 3
	panel.Parent = body

	local target = nil
	local copying = false
	local side = "Front"
	local lock = true
	local dist = 4
	local runConns = {}
	local cachedT, cachedC
	local jointPairs = {}
	local warnedRig = false
    local modeSetting = "Auto" 
    local partMode = false
    local myMotors = {}
    local tparts = {}
    local modeCheck = 0

	local targetBtn = makeGlassButton(panel, "Select player...", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 0))
	local copyBtn = makeGlassButton(panel, "Copy", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 34))

	local posLabel = Instance.new("TextLabel")
	posLabel.Size = UDim2.new(1, 0, 0, 16)
	posLabel.Position = UDim2.new(0, 0, 0, 68)
	posLabel.BackgroundTransparency = 1
	posLabel.Text = "Position"
	posLabel.TextColor3 = MUTED
	posLabel.Font = Enum.Font.GothamMedium
	posLabel.TextSize = 11
	posLabel.TextXAlignment = Enum.TextXAlignment.Left
	posLabel.ZIndex = 3
	posLabel.Parent = panel

	local sideNames = { "Front", "Behind", "Left", "Right" }
	local sideButtons = {}
	for i, name in ipairs(sideNames) do
		sideButtons[name] = makeGlassButton(
			panel, name,
			UDim2.new(0.25, -4, 0, 24),
			UDim2.new((i - 1) * 0.25, 2, 0, 86)
		)
	end

	local lockBtn = makeGlassButton(panel, "Stay beside: On", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 118))

	local distLabel = Instance.new("TextLabel")
	distLabel.Size = UDim2.new(0.5, 0, 0, 24)
	distLabel.Position = UDim2.new(0, 0, 0, 152)
	distLabel.BackgroundTransparency = 1
	distLabel.Text = "Distance: 4"
	distLabel.TextColor3 = WHITE
	distLabel.Font = Enum.Font.GothamMedium
	distLabel.TextSize = 12
	distLabel.TextXAlignment = Enum.TextXAlignment.Left
	distLabel.ZIndex = 3
	distLabel.Parent = panel

	local minusBtn = makeGlassButton(panel, "-", UDim2.new(0.25, -4, 0, 24), UDim2.new(0.5, 2, 0, 152))
	local plusBtn = makeGlassButton(panel, "+", UDim2.new(0.25, -4, 0, 24), UDim2.new(0.75, 2, 0, 152))

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 40)
	infoLabel.Position = UDim2.new(0, 0, 0, 218)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "Pick a player, then press Copy. Enable reanimation first."
	infoLabel.TextColor3 = MUTED
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 11
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextYAlignment = Enum.TextYAlignment.Top
	infoLabel.TextWrapped = true
	infoLabel.ZIndex = 3
	infoLabel.Parent = panel

    local modeBtn = makeGlassButton(panel, "Mode: Auto", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 186))

	local function info(text, color)
		infoLabel.Text = text
		infoLabel.TextColor3 = color or MUTED
	end

	local dd = Instance.new("Frame")
	dd.Size = UDim2.new(1, 0, 0, 160)
	dd.Position = UDim2.new(0, 0, 0, 30)
	dd.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
	dd.BorderSizePixel = 0
	dd.Visible = false
	dd.ZIndex = 8
	dd.Parent = panel
	makeCorner(dd, 6)

	local ddSearch = Instance.new("TextBox")
	ddSearch.Size = UDim2.new(1, -8, 0, 24)
	ddSearch.Position = UDim2.new(0, 4, 0, 4)
	ddSearch.BackgroundColor3 = BOX_COLOR
	ddSearch.BorderSizePixel = 0
	ddSearch.Text = ""
	ddSearch.PlaceholderText = "Search players..."
	ddSearch.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
	ddSearch.TextColor3 = WHITE
	ddSearch.Font = Enum.Font.Gotham
	ddSearch.TextSize = 12
	ddSearch.ClearTextOnFocus = false
	ddSearch.ZIndex = 9
	ddSearch.Parent = dd
	makeCorner(ddSearch, 6)

	local ddList = Instance.new("ScrollingFrame")
	ddList.Size = UDim2.new(1, -8, 1, -36)
	ddList.Position = UDim2.new(0, 4, 0, 32)
	ddList.BackgroundTransparency = 1
	ddList.BorderSizePixel = 0
	ddList.ScrollBarThickness = 3
	ddList.ScrollBarImageColor3 = WHITE
	ddList.ScrollBarImageTransparency = 0.65
	ddList.ScrollingDirection = Enum.ScrollingDirection.Y
	ddList.CanvasSize = UDim2.new(0, 0, 0, 0)
	ddList.ZIndex = 9
	ddList.Parent = dd

	local rows = {}

	local function restoreMotors()
	for _, m in ipairs(myMotors) do
		pcall(function()
			if m[1].Parent then m[1].C0 = m[2] end
		end)
	end
end

local function jointsAlive(tchar)
	local n = 0
	for _, d in ipairs(tchar:GetDescendants()) do
		if d:IsA("Motor6D") and d.Enabled and d.Part0 and d.Part1
			and d.Part0:IsDescendantOf(tchar) and d.Part1:IsDescendantOf(tchar) then
			n = n + 1
		end
	end
	return n
end

local function rebuild(tchar, char)
	restoreMotors()
	cachedT, cachedC = tchar, char
	table.clear(jointPairs)
	table.clear(myMotors)
	table.clear(tparts)
	local mine = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			mine[d.Name] = d
			table.insert(myMotors, { d, d.C0 })
		end
	end
	for _, d in ipairs(tchar:GetDescendants()) do
		if d:IsA("Motor6D") and d.Enabled and mine[d.Name] then
			table.insert(jointPairs, { mine[d.Name], d })
		elseif d:IsA("BasePart") then
			tparts[d.Name] = d
		end
	end
	if modeSetting == "Parts" then
		partMode = true
	elseif modeSetting == "Joints" then
		partMode = false
	else
		partMode = jointsAlive(tchar) < 3
	end
	if partMode then
		info("Target is reanimated - copying by body parts.", MUTED)
	elseif #jointPairs < 3 and not warnedRig then
		warnedRig = true
		info("Rig types differ (R6 vs R15) - only a few joints can be copied.", RED)
	end
end

local function applyParts(tchar, char)
	local tHrp = tchar:FindFirstChild("HumanoidRootPart")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (tHrp and hrp) then return end
	local function desired(part)
		local tp = tparts[part.Name]
		if tp and tp.Parent then
			return hrp.CFrame * tHrp.CFrame:ToObjectSpace(tp.CFrame)
		end
	end
	for _, m in ipairs(myMotors) do
		local motor = m[1]
		if motor.Parent and motor.Part0 and motor.Part1 then
			local d0, d1 = desired(motor.Part0), desired(motor.Part1)
			if d0 and d1 then
				motor.C0 = d0:ToObjectSpace(d1) * motor.C1
				motor.Transform = CFrame.new()
			end
		end
	end
end

	local function snap()
		local tchar = target and target.Character
		local char = player.Character
		if not (tchar and char) then return end
		local tHrp = tchar:FindFirstChild("HumanoidRootPart")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (tHrp and hrp) then return end

		local offset
		if side == "Front" then
			offset = CFrame.new(0, 0, -dist)
		elseif side == "Behind" then
			offset = CFrame.new(0, 0, dist)
		elseif side == "Left" then
			offset = CFrame.new(-dist, 0, 0)
		elseif side == "Right" then
			offset = CFrame.new(dist, 0, 0)
		else
			offset = CFrame.new(0, 0, -dist)
		end

		hrp.CFrame = tHrp.CFrame * offset
	end

	local stopCopy

	local function run()
	if not copying then return end
	if not reanimEnabled then
		stopCopy("Reanimation turned off - copy stopped")
		return
	end
	local tchar = target and target.Character
	local char = player.Character
	if not (tchar and char) then return end
	if tchar ~= cachedT or char ~= cachedC then
		rebuild(tchar, char)
	end
	local now = os.clock()
	if modeSetting == "Auto" and now - modeCheck > 0.5 then
		modeCheck = now
		if (jointsAlive(tchar) < 3) ~= partMode then
			rebuild(tchar, char)
		end
	end
	if lock then snap() end
	if partMode then
		applyParts(tchar, char)
	else
		for _, pair in ipairs(jointPairs) do
			local mine, theirs = pair[1], pair[2]
			if mine.Parent and theirs.Parent then
				mine.Transform = theirs.Transform
			end
		end
	end
end

	local function startCopy()
		if not target or not target.Parent then
			info("Select a player first.", RED)
			return
		end
		if not api then
			info("Reanimation API failed to load.", RED)
			return
		end
		if not reanimEnabled then
			info("Enable reanimation first.", RED)
			return
		end
		if copying then return end
		stopEmote()
		copying = true
		warnedRig = false
		cachedT, cachedC = nil, nil
		snap()
		for _, signal in ipairs({ RunService.Stepped, RunService.Heartbeat }) do
			table.insert(runConns, signal:Connect(function()
				pcall(run)
			end))
		end
		pcall(RunService.UnbindFromRenderStep, RunService, RS_NAME)
		RunService:BindToRenderStep(RS_NAME, Enum.RenderPriority.Camera.Value + 2, function()
			pcall(run)
		end)
		copyBtn.Text = "Stop copying"
		info("Copying " .. target.DisplayName .. " (" .. side .. ")", GREEN)
		setStatus("Copying " .. target.DisplayName, GREEN)
	end

	stopCopy = function(reason)
    restoreMotors()
		for _, c in ipairs(runConns) do pcall(function() c:Disconnect() end) end
		table.clear(runConns)
		pcall(RunService.UnbindFromRenderStep, RunService, RS_NAME)
		local was = copying
		copying = false
		cachedT, cachedC = nil, nil
		table.clear(jointPairs)
		copyBtn.Text = "Copy"
		if was then
			info(reason or "Stopped copying.", MUTED)
			refreshStatus()
		end
	end

	local function selectTarget(plr)
		target = plr
		targetBtn.Text = "Target: " .. plr.DisplayName
		dd.Visible = false
		cachedT = nil
		if copying then
			info("Copying " .. plr.DisplayName .. " (" .. side .. ")", GREEN)
			setStatus("Copying " .. plr.DisplayName, GREEN)
			snap()
		else
			info("Press Copy to start.", MUTED)
		end
	end

	local function refreshList()
		for _, r in ipairs(rows) do pcall(function() r:Destroy() end) end
		table.clear(rows)
		local q = string.lower(ddSearch.Text or "")
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)
		local y = 2
		for _, plr in ipairs(list) do
			if plr ~= player then
				local label = plr.DisplayName .. " (@" .. plr.Name .. ")"
				if q == "" or string.find(label:lower(), q, 1, true) then
					local row = Instance.new("TextButton")
					row.Size = UDim2.new(1, -6, 0, 22)
					row.Position = UDim2.new(0, 3, 0, y)
					row.BackgroundTransparency = 1
					row.Text = label
					row.TextColor3 = (plr == target) and ORANGE or WHITE
					row.Font = Enum.Font.Gotham
					row.TextSize = 12
					row.TextXAlignment = Enum.TextXAlignment.Left
					row.TextTruncate = Enum.TextTruncate.AtEnd
					row.AutoButtonColor = false
					row.ZIndex = 10
					row.Parent = ddList
					row.MouseButton1Click:Connect(function()
						selectTarget(plr)
					end)
					table.insert(rows, row)
					y = y + 24
				end
			end
		end
		if #rows == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, -8, 0, 22)
			empty.Position = UDim2.new(0, 4, 0, 2)
			empty.BackgroundTransparency = 1
			empty.Text = "No players found."
			empty.TextColor3 = MUTED
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 12
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.ZIndex = 10
			empty.Parent = ddList
			table.insert(rows, empty)
			y = y + 24
		end
		ddList.CanvasSize = UDim2.new(0, 0, 0, y + 4)
	end

	targetBtn.MouseButton1Click:Connect(function()
		dd.Visible = not dd.Visible
		if dd.Visible then
			ddSearch.Text = ""
			refreshList()
		end
	end)
	ddSearch:GetPropertyChangedSignal("Text"):Connect(refreshList)

	track(Players.PlayerAdded:Connect(function()
		if dd.Visible then refreshList() end
	end))
	track(Players.PlayerRemoving:Connect(function(plr)
		if plr == target then
			stopCopy("Target left the game")
			target = nil
			targetBtn.Text = "Select player..."
		end
		task.defer(function()
			if dd.Visible then refreshList() end
		end)
	end))

	copyBtn.MouseButton1Click:Connect(function()
		dd.Visible = false
		if copying then stopCopy() else startCopy() end
	end)

	local function refreshSides()
		for name, btn in pairs(sideButtons) do
			local on = name == side
			btn.BackgroundColor3 = WHITE
			btn.BackgroundTransparency = on and 0.45 or 0.85
			btn.TextColor3 = on and WHITE or MUTED
		end
	end
	for name, btn in pairs(sideButtons) do
		btn.MouseButton1Click:Connect(function()
			side = name
			refreshSides()
			if copying then
				snap()
				info("Copying " .. target.DisplayName .. " (" .. side .. ")", GREEN)
			end
		end)
	end
	refreshSides()

	lockBtn.MouseButton1Click:Connect(function()
		lock = not lock
		lockBtn.Text = "Stay beside: " .. (lock and "On" or "Off")
		lockBtn.TextColor3 = lock and ORANGE or WHITE
	end)

	local function setDist(v)
		dist = math.clamp(v, 2, 15)
		distLabel.Text = "Distance: " .. dist
		if copying then snap() end
	end
	minusBtn.MouseButton1Click:Connect(function() setDist(dist - 1) end)
	plusBtn.MouseButton1Click:Connect(function() setDist(dist + 1) end)

modeBtn.MouseButton1Click:Connect(function()
	modeSetting = (modeSetting == "Auto") and "Parts" or (modeSetting == "Parts") and "Joints" or "Auto"
	modeBtn.Text = "Mode: " .. modeSetting
	cachedT = nil
end)

	return panel, stopCopy
end)()

local LIMB_LENGTH = 75000
local LIMB_SINK = 1
local PART_MAX = 2048

local function buildArmStretch(opts)
	local self = {}
	local enabled = false
	local stepConn
	local current
	local scrollMode = false
	local scrollReach = 20
	local shownScroll = 20
	local blend = 0
	local lastTick = os.clock()
	local stopConns
	local savedZoom
	local _lastCast = 0
	local _cachedReach
	local _peopleParts = {}
	local _peopleTime = 0
	local _CAST_INTERVAL = 0

	local function restore()
		_cachedReach = nil
		if not current then return end
		local c = current
		current = nil
		for _, part in ipairs({ { c.upper, c.upperSize }, { c.lower, c.lowerSize }, { c.hand, c.handSize } }) do
			pcall(function() part[1].Size = part[2] end)
		end
		for _, m in ipairs(c.motors) do
			pcall(function()
				m.motor.Enabled = true
				m.motor.C0 = m.c0
				m.motor.C1 = m.c1
			end)
		end
	end

	local function capture(char)
		local torso = char:FindFirstChild("UpperTorso")
		local upper = char:FindFirstChild(opts.upper)
		local lower = char:FindFirstChild(opts.lower)
		local hand = char:FindFirstChild(opts.hand)
		if not (torso and upper and lower and hand) then return false end
		local shoulder = upper:FindFirstChild(opts.shoulder)
		local elbow = lower:FindFirstChild(opts.elbow)
		local wrist = hand:FindFirstChild(opts.wrist)
		if not (shoulder and elbow and wrist) then return false end
		current = {
			char = char, torso = torso, upper = upper, lower = lower, hand = hand,
			upperSize = upper.Size, lowerSize = lower.Size, handSize = hand.Size,
			shoulder = shoulder, elbow = elbow, wrist = wrist,
			motors = {
				{ motor = shoulder, c0 = shoulder.C0, c1 = shoulder.C1 },
				{ motor = elbow, c0 = elbow.C0, c1 = elbow.C1 },
				{ motor = wrist, c0 = wrist.C0, c1 = wrist.C1 },
			},
		}
		return true
	end

	local function step()
		local now0 = os.clock()
		local dt = math.min(now0 - lastTick, 0.1)
		lastTick = now0
		local ease = 1 - math.exp(-10 * dt)
		blend = blend + ((enabled and 1 or 0) - blend) * ease
		shownScroll = shownScroll * (scrollReach / shownScroll) ^ ease
		if not enabled and blend < 0.01 then
			blend = 0
			if stopConns then stopConns() end
			restore()
			return
		end
		local char = player.Character
		if not char then return end
		if current and current.char ~= char then
			current = nil
		end
		if not current and not capture(char) then return end
		local c = current
		if not (c.torso.Parent and c.upper.Parent and c.lower.Parent and c.hand.Parent) then
			current = nil
			return
		end

		local cam = Workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }

		local ignore = { char }
		local hit
		for _ = 1, 8 do
			params.FilterDescendantsInstances = ignore
			local okCast, h = pcall(Workspace.Raycast, Workspace, ray.Origin, ray.Direction * 5000, params)
			if not (okCast and h) then break end
			if h.Instance.Transparency >= 0.95 then
				table.insert(ignore, h.Instance)
			else
				hit = h
				break
			end
		end
		local target = hit and hit.Position or (ray.Origin + ray.Direction * 5000)

		local start = c.torso.CFrame:PointToWorldSpace(c.motors[1].c0.Position)
		local offset = target - start
		if offset.Magnitude < 0.01 then return end
		local dir = offset.Unit
		local upperLen = c.upperSize.Y
		local handFull = c.handSize.Y * 3

		local maxReach = hit and (offset.Magnitude + LIMB_SINK) or LIMB_LENGTH
		if scrollMode then

			maxReach = math.min(shownScroll, maxReach)
		end

		local avail = math.max(maxReach - upperLen, 0.1)
		local handLen = math.min(handFull, avail)

		local middle = math.max(avail - handLen / 2 + (hit and handLen / 2 or 0), 0.05)
		local lowerLen = math.min(middle, PART_MAX)
		local gap = middle - lowerLen

		lowerLen = c.lowerSize.Y + (lowerLen - c.lowerSize.Y) * blend
		handLen = c.handSize.Y + (handLen - c.handSize.Y) * blend
		gap = gap * blend

		for _, p in ipairs({ c.upper, c.lower, c.hand }) do
			p.CanCollide = false
			p.CanTouch = false
			p.Massless = true
		end
		c.lower.Size = Vector3.new(c.lowerSize.X, lowerLen, c.lowerSize.Z)
		c.hand.Size = Vector3.new(c.handSize.X, handLen, c.handSize.Z)

		local upperPos = start + dir * (upperLen / 2)
		local upperCF = CFrame.lookAt(upperPos, upperPos + dir) * CFrame.Angles(math.pi / 2, 0, 0)

		local topOfUpper = CFrame.new(0, upperLen / 2, 0)
		local m1, m2, m3 = c.motors[1], c.motors[2], c.motors[3]
		c.shoulder.C0 = m1.c0:Lerp(c.torso.CFrame:ToObjectSpace(upperCF * topOfUpper), blend)
		c.shoulder.C1 = m1.c1:Lerp(topOfUpper, blend)
		c.shoulder.Transform = CFrame.new()

		c.elbow.C0 = m2.c0:Lerp(CFrame.new(0, -upperLen / 2, 0), blend)
		c.elbow.C1 = m2.c1:Lerp(CFrame.new(0, lowerLen / 2, 0), blend)
		c.elbow.Transform = CFrame.new()

		c.wrist.C0 = m3.c0:Lerp(CFrame.new(0, -(lowerLen / 2 + gap), 0), blend)
		c.wrist.C1 = m3.c1:Lerp(CFrame.new(0, handLen / 2, 0), blend)
		c.wrist.Transform = CFrame.new()
	end

	local function refreshVisual()
		opts.toggleButton.Text = opts.label .. ": " .. (enabled and "On" or "Off")
		opts.toggleButton.TextColor3 = enabled and ORANGE or WHITE
	end

	local CAS = game:GetService("ContextActionService")

	local function updateScrollBind()
		if not opts.scrollButton then return end
		pcall(CAS.UnbindAction, CAS, opts.action)
		local cam = Workspace.CurrentCamera
		if enabled and scrollMode then

			CAS:BindActionAtPriority(opts.action, function(_, state, input)
				if state == Enum.UserInputState.Change then
					scrollReach = math.clamp(scrollReach * (1.25 ^ input.Position.Z), 2, LIMB_LENGTH)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value + 100, Enum.UserInputType.MouseWheel)
			if not savedZoom and cam then
				savedZoom = { min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance }
				local d = (cam.CFrame.Position - cam.Focus.Position).Magnitude
				pcall(function()
					player.CameraMinZoomDistance = d
					player.CameraMaxZoomDistance = d
				end)
			end
		elseif savedZoom then
			local z = savedZoom
			savedZoom = nil
			pcall(function()
				player.CameraMaxZoomDistance = z.max
				player.CameraMinZoomDistance = z.min
			end)
		end
	end

	stopConns = function()
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
	end

	local function startConns()
		if stepConn then return end
		lastTick = os.clock()
		local conns = {}
		for _, signal in ipairs({ RunService.Stepped, RunService.Heartbeat }) do
			table.insert(conns, signal:Connect(function()
				pcall(step)
			end))
		end

		pcall(RunService.UnbindFromRenderStep, RunService, opts.action)
		RunService:BindToRenderStep(opts.action, Enum.RenderPriority.Camera.Value + 1, function()
			pcall(step)
		end)
		stepConn = {
			Disconnect = function()
				for _, cn in ipairs(conns) do cn:Disconnect() end
				pcall(RunService.UnbindFromRenderStep, RunService, opts.action)
			end,
		}
	end

	function self.set(value)
		if value == enabled then return end
		if value and not reanimEnabled then
			setStatus("enable reanim first", MUTED)
			return
		end
		enabled = value
		if enabled then
			startConns()
		end

		updateScrollBind()
		refreshVisual()
		setStatus(opts.statusName .. " " .. (enabled and "on" or "off"), MUTED)
	end

	function self.kill()
		enabled = false
		blend = 0
		stopConns()
		restore()
		updateScrollBind()
	end

	function self.scrollOn()
		return scrollMode
	end

	function self.setScroll(value)
		if not opts.scrollButton then return end
		scrollMode = value
		opts.scrollButton.Text = "Scroll stretch: " .. (value and "On" or "Off")
		opts.scrollButton.TextColor3 = value and ORANGE or WHITE
		updateScrollBind()
		setStatus("Scroll stretch " .. (value and "on" or "off"), MUTED)
	end
	function self.toggle()
		self.set(not enabled)
	end

	return self
end

local limb = buildArmStretch({
	label = "Right arm stretch",
	statusName = "Right arm stretch",
	upper = "RightUpperArm", lower = "RightLowerArm", hand = "RightHand",
	shoulder = "RightShoulder", elbow = "RightElbow", wrist = "RightWrist",
	toggleButton = limbToggle, scrollButton = scrollToggle, action = "limbScroll",
})
local limbLeft = buildArmStretch({
	label = "Left arm stretch",
	statusName = "Left arm stretch",
	upper = "LeftUpperArm", lower = "LeftLowerArm", hand = "LeftHand",
	shoulder = "LeftShoulder", elbow = "LeftElbow", wrist = "LeftWrist",
	toggleButton = limbLeftToggle, action = "limbScrollLeft",
})
limbToggle.MouseButton1Click:Connect(limb.toggle)
scrollToggle.MouseButton1Click:Connect(function()
	limb.setScroll(not limb.scrollOn())
end)
limbLeftToggle.MouseButton1Click:Connect(limbLeft.toggle)

local follow = {}

__i = function()
	local enabled = { torso = false, head = false }
	local maxTurn = math.rad(90)
	local current
	local yawTorso, yawHead, pitchTorso, pitchHead = 0, 0, 0, 0

	local function findMotor(char, partName)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("Motor6D") and d.Part1 and d.Part1.Name == partName then
				return d
			end
		end
		return nil
	end

	local function restore()
		if not current then return end
		local c = current
		current = nil
		pcall(function() if c.waist.Parent then c.waist.C0 = c.waistC0 end end)
		pcall(function() if c.neck.Parent then c.neck.C0 = c.neckC0 end end)
	end

	local function capture(char)
		local upper = char:FindFirstChild("UpperTorso")
		local headPart = char:FindFirstChild("Head")
		if not (upper and headPart) then return false end
		local waist = findMotor(char, "UpperTorso")
		local neck = findMotor(char, "Head")
		if not (waist and neck) then return false end
		current = {
			char = char, upper = upper, head = headPart,
			waist = waist, neck = neck,
			waistC0 = waist.C0, neckC0 = neck.C0,
		}
		return true
	end

	local function applyMotor(motor, restC0, yaw, pitch)
		pcall(function()
			if motor and motor.Parent then
				motor.C0 = restC0 * CFrame.Angles(pitch, yaw, 0)
			end
		end)
	end

	local function wrapAngle(a)
		return (a + math.pi) % (math.pi * 2) - math.pi
	end

	local function refreshVisual()
		torsoToggle.Text = "Torso follow: " .. (enabled.torso and "On" or "Off")
		torsoToggle.TextColor3 = enabled.torso and ORANGE or WHITE
		headToggle.Text = "Head follow: " .. (enabled.head and "On" or "Off")
		headToggle.TextColor3 = enabled.head and ORANGE or WHITE
	end

	local function step(dt)
		if not (enabled.torso or enabled.head) then return end
		if not reanimEnabled then
			restore()
			yawTorso, yawHead, pitchTorso, pitchHead = 0, 0, 0, 0
			return
		end
		local char = player.Character
		if not char then return end
		if current and current.char ~= char then
			current = nil
		end
		if not current and not capture(char) then return end
		local c = current
		if not (c.upper.Parent and c.head.Parent and c.waist.Parent and c.neck.Parent) then
			current = nil
			return
		end
		local cam = Workspace.CurrentCamera
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (cam and hrp) then return end

		local lookLocal = hrp.CFrame:VectorToObjectSpace(cam.CFrame.LookVector)
		local desiredYaw = math.atan2(-lookLocal.X, -lookLocal.Z)
		local desiredPitch = math.asin(math.clamp(lookLocal.Y, -1, 1))

		local alpha = 1 - math.exp(-48 * math.min(dt or 0.016, 0.1))

		local YAW_BOOST = 1
		local _PITCH_DOWN_BOOST = 3.4
		local PITCH_UP_BOOST = 1.8
		local targetYawTorso, targetPitchTorso = 0, 0
		if enabled.torso then
			targetYawTorso = math.clamp(desiredYaw * YAW_BOOST, -maxTurn, maxTurn)

			local downLimit = math.rad(175)
			local upLimit = math.min(maxTurn, math.rad(95))
			if desiredPitch < 0 then

				local t = math.clamp((-desiredPitch) / (math.pi * 0.5), 0, 1)
				targetPitchTorso = -downLimit * (t ^ 0.75)
			else
				targetPitchTorso = math.clamp(desiredPitch * PITCH_UP_BOOST, 0, upLimit)
			end
		end
		yawTorso = yawTorso + (targetYawTorso - yawTorso) * alpha
		pitchTorso = pitchTorso + (targetPitchTorso - pitchTorso) * alpha

		local targetYawHead, targetPitchHead = 0, 0
		if enabled.head then
			local remainYaw = wrapAngle(desiredYaw * YAW_BOOST - (enabled.torso and yawTorso or 0))
			local remainPitch = desiredPitch - (enabled.torso and pitchTorso or 0)
			local headLimit = math.min(maxTurn, math.rad(80))
			targetYawHead = math.clamp(remainYaw, -headLimit, headLimit)
			targetPitchHead = math.clamp(remainPitch, -headLimit, headLimit)
		end
		yawHead = yawHead + (targetYawHead - yawHead) * alpha
		pitchHead = pitchHead + (targetPitchHead - pitchHead) * alpha

		if enabled.torso then
			applyMotor(c.waist, c.waistC0, yawTorso, pitchTorso)
		else
			applyMotor(c.waist, c.waistC0, 0, 0)
		end
		if enabled.head then
			applyMotor(c.neck, c.neckC0, yawHead, pitchHead)
		else
			applyMotor(c.neck, c.neckC0, 0, 0)
		end

	end

	function follow.setTorso(value)
		if value == enabled.torso then return end
		if value and not reanimEnabled then
			setStatus("enable reanim first", MUTED)
			return
		end
		enabled.torso = value
		if not value then
			yawTorso, pitchTorso = 0, 0
			local c = current
			if c and c.waist.Parent then
				pcall(function() c.waist.C0 = c.waistC0 end)
			end
		end
		refreshVisual()
		setStatus("Torso follow " .. (value and "on" or "off"), MUTED)
	end

	function follow.setHead(value)
		if value == enabled.head then return end
		if value and not reanimEnabled then
			setStatus("enable reanim first", MUTED)
			return
		end
		enabled.head = value
		if not value then
			yawHead, pitchHead = 0, 0
			local c = current
			if c and c.neck.Parent then
				pcall(function() c.neck.C0 = c.neckC0 end)
			end
		end
		refreshVisual()
		setStatus("Head follow " .. (value and "on" or "off"), MUTED)
	end

	function follow.toggleTorso()
		follow.setTorso(not enabled.torso)
	end

	function follow.toggleHead()
		follow.setHead(not enabled.head)
	end

	function follow.setMaxTurn(deg)
		maxTurn = math.rad(deg)
		for d, btn in pairs(turnButtons) do
			local on = (d == deg)
			btn.TextColor3 = on and WHITE or MUTED
			btn.BackgroundColor3 = on and ORANGE or WHITE
			btn.BackgroundTransparency = on and 0.45 or 0.85
		end
	end

	function follow.kill()
		enabled.torso = false
		enabled.head = false
		yawTorso, yawHead, pitchTorso, pitchHead = 0, 0, 0, 0
		restore()
		refreshVisual()
	end

	torsoToggle.MouseButton1Click:Connect(follow.toggleTorso)
	headToggle.MouseButton1Click:Connect(follow.toggleHead)
	for deg, btn in pairs(turnButtons) do
		btn.MouseButton1Click:Connect(function()
			follow.setMaxTurn(deg)
		end)
	end
	follow.setMaxTurn(90)
	refreshVisual()

	track(RunService.Heartbeat:Connect(function(dt)
		pcall(step, dt)
	end))
end
__i()

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

local function makeRow(entry, y, mode)
	local row = Instance.new("Frame")
	row.Name = "EmoteRow"
	row.Size = UDim2.new(1, -24, 0, ROW_H)
	row.Position = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1
	row.ZIndex = 3
	row.Parent = emotesScroll

	local hasStar = mode == "All" or mode == "Favs" or (mode == "Custom" and entry.fromFolder)
	local isFolderCustom = mode == "Custom" and entry.fromFolder
	local shift = isFolderCustom and 26 or 0
	local reserve = (hasStar and 134 or 90) + shift

	if hasStar then
		local isFav = favorites[entry.name] == true
		local star = Instance.new("TextButton")
		star.Name = "Star"
		star.Size = UDim2.new(0, 22, 1, 0)
		star.Position = UDim2.new(1, -(66 + shift), 0, 0)
		star.BackgroundTransparency = 1
		star.Text = isFav and "★" or "☆"
		star.TextColor3 = WHITE
		star.Font = Enum.Font.GothamBold
		star.TextSize = 14
		star.AutoButtonColor = false
		star.ZIndex = 4
		star.Parent = row

		star.MouseButton1Click:Connect(function()
			if favorites[entry.name] then
				favorites[entry.name] = nil
			else
				favorites[entry.name] = true
			end
			saveData()
			layoutEmotes()
		end)
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -(reserve + 4), 1, 0)
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

	if hasStar then
		local playBtn = makeRowButton(row, "Play", 44, shift)
		table.insert(playButtons, { button = playBtn, name = entry.name })
		playBtn.MouseButton1Click:Connect(function()
			togglePlay(entry)
		end)

		local keyName = binds[entry.name]
		local bindBtn = makeRowButton(row, "bind", 60, 76 + shift)
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
	elseif mode == "Binds" then
		local keyName = binds[entry.name]
		local pill = makeRowButton(row, "bind", 60, 24)
		pill.BackgroundTransparency = 0.85
		pill.BackgroundColor3 = WHITE
		makeCorner(pill, 6)
		if bindingFor == entry.name then
			pill.Text = "press key"
			pill.TextColor3 = ORANGE
		elseif keyName then
			pill.Text = keyName
			pill.TextColor3 = ORANGE
		else
			pill.TextColor3 = MUTED
		end
		pill.MouseButton1Click:Connect(function()
			if binds[entry.name] then
				binds[entry.name] = nil
				saveData()
			else
				bindingFor = entry.name
			end
			layoutEmotes()
		end)

		if keyName then
			local clear = makeRowButton(row, "x", 20, 0)
			clear.TextColor3 = RED
			clear.MouseButton1Click:Connect(function()
				binds[entry.name] = nil
				saveData()
				layoutEmotes()
			end)
		end
	elseif mode == "Custom" then
		local playBtn = makeRowButton(row, "Play", 40, 36)
		table.insert(playButtons, { button = playBtn, name = entry.name })
		playBtn.MouseButton1Click:Connect(function()
			togglePlay(entry)
		end)

		local del = makeRowButton(row, "del", 32, 0)
		del.TextColor3 = RED
		del.MouseButton1Click:Connect(function()
			for i, item in ipairs(customEmotes) do
				if item == entry then
					table.remove(customEmotes, i)
					break
				end
			end
			favorites[entry.name] = nil
			binds[entry.name] = nil
			saveData()
			layoutEmotes()
		end)
	end

	if isFolderCustom then
		local delBtn = makeRowButton(row, "", 22, 0)
		local armed = bin.pending == entry.path
		local binImg = bin.get()
		if binImg then
			local icon = Instance.new("ImageLabel")
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.Size = armed and UDim2.new(0, 20, 0, 20) or UDim2.new(0, 15, 0, 15)
			icon.BackgroundTransparency = 1
			icon.Image = binImg
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ZIndex = 5
			icon.Parent = delBtn
		else
			delBtn.Text = armed and "?" or "del"
			delBtn.TextColor3 = RED
		end

		delBtn.MouseButton1Click:Connect(function()
			local path = entry.path
			if bin.pending ~= path then
				bin.pending = path
				setStatus("Click the bin again to delete " .. entry.name, MUTED)
				layoutEmotes()
				task.delay(3, function()
					if bin.pending == path then
						bin.pending = nil
						refreshStatus()
						layoutEmotes()
					end
				end)
				return
			end
			bin.pending = nil
			local ok = type(delfile) == "function" and pcall(delfile, path)
			if ok then
				for i, item in ipairs(folderEmotes) do
					if item == entry then
						table.remove(folderEmotes, i)
						break
					end
				end
				if playingName == entry.name then
					stopEmote()
				end
				favorites[entry.name] = nil
				binds[entry.name] = nil
				saveData()
				setStatus("Deleted " .. entry.name, MUTED)
			else
				setStatus("Could not delete (executor has no delfile)", RED)
			end
			layoutEmotes()
		end)
	end

	table.insert(emoteRows, row)
end

local PAGE_SIZE = 25
local visibleLimit = PAGE_SIZE
local hasMore = false

layoutEmotes = function()
	local savedScroll = emotesScroll.CanvasPosition
	clearEmoteRows()
	hasMore = false
	if emoteMode == "Speed" or emoteMode == "AnimCopy" then
		emotesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		return
	end

	local query = string.lower(searchBox.Text or "")
	local source
	if emoteMode == "Custom" then
		source = {}
		for _, e in ipairs(folderEmotes) do table.insert(source, e) end
		for _, e in ipairs(customEmotes) do table.insert(source, e) end
	else
		source = combinedEntries()
	end
	local y = 4
	local shown = 0

	for _, entry in ipairs(source) do
		local skip = false
		if emoteMode == "Favs" and favorites[entry.name] ~= true then
			skip = true
		elseif emoteMode == "Binds" and not binds[entry.name] and query == "" then
			skip = true
		elseif query ~= "" and not string.find(string.lower(entry.name), query, 1, true) then
			skip = true
		end
		if not skip then
			if shown >= visibleLimit then
				hasMore = true
				break
			end
			makeRow(entry, y, emoteMode)
			y = y + ROW_H + ROW_GAP
			shown = shown + 1
		end
	end

	emotesScroll.CanvasSize = UDim2.new(0, 0, 0, y + 6)
	emotesScroll.CanvasPosition = savedScroll

	if shown == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -24, 0, 40)
		empty.Position = UDim2.new(0, 12, 0, 12)
		empty.BackgroundTransparency = 1
		if emoteMode == "Favs" then
			empty.Text = "No favourites yet. Tap the star to pin emotes."
		elseif emoteMode == "Custom" then
			empty.Text = "No custom emotes yet. Drop .lua files into workspace/" .. FOLDER_PATH
		elseif emoteMode == "Binds" then
			empty.Text = "No binds yet. Search for an emote to bind it."
		else
			empty.Text = "No emotes match your search."
		end
		empty.TextColor3 = MUTED
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.TextWrapped = true
		empty.ZIndex = 3
		empty.Parent = emotesScroll
		table.insert(emoteRows, empty)
	end
end

local function scanFolder()
	if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(FOLDER_PATH) then
		return
	end
	local ok, files = pcall(listfiles, FOLDER_PATH)
	if not ok or type(files) ~= "table" then return end

	local newList = {}
	local map = {}
	for _, rawPath in ipairs(files) do
		local path = tostring(rawPath):gsub("\\", "/")
		local fileName = path:match("([^/]+)$")
		local lower = fileName and fileName:lower()
		if lower and (lower:match("%.luau?$") or lower:match("%.txt$")) then
			local name = fileName:gsub("%.[^%.]+$", ""):gsub("_", " ")
			local key = LOCAL_HOST .. HttpService:UrlEncode(fileName)
			map[key] = path
			table.insert(newList, {
				name = name,
				url = key,
				path = path,
				custom = true,
				fromFolder = true,
			})
		end
	end
	table.clear(localFiles)
	for k, v in pairs(map) do localFiles[k] = v end
	table.sort(newList, function(a, b) return a.name:lower() < b.name:lower() end)

	local changed = #newList ~= #folderEmotes
	if not changed then
		for i, e in ipairs(newList) do
			if e.path ~= folderEmotes[i].path then
				changed = true
				break
			end
		end
	end
	if changed then
		folderEmotes = newList
		if emoteMode == "Custom" or emoteMode == "All" then
			layoutEmotes()
		end
	end
end

scanFolder()

local scanTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
	scanTimer = scanTimer + dt
	if scanTimer < 1.5 then return end
	scanTimer = 0
	pcall(scanFolder)
end))

local function setActiveTab(tabName)
	emoteMode = tabName
	bindingFor = nil
	refreshSpeedBinds()
	for name, btn in pairs(emoteTabButtons) do
		local active = name == tabName
		btn.TextColor3 = active and WHITE or MUTED
		local under = btn:FindFirstChild("Underline")
		if under then under.Visible = active end
	end

	local isSpeed = tabName == "Speed"
local isLimb = tabName == "Limb"
local isState = tabName == "State"
local isCopy = tabName == "AnimCopy"
local isCustom = tabName == "Custom"
speedPanel.Visible = isSpeed
limbPanel.Visible = isLimb
st.panel.Visible = isState
st.copyPanel.Visible = isCopy
customForm.Visible = isCustom
emotesScroll.Visible = not (isSpeed or isLimb or isState or isCopy)
searchBox.Visible = not (isSpeed or isLimb or isState or isCopy)
	local top = isCustom and (LIST_Y + CUSTOM_FORM_H) or LIST_Y
	emotesScroll.Position = UDim2.new(0, 0, 0, top)
	emotesScroll.Size = UDim2.new(1, 0, 1, -(top + 6))
	visibleLimit = PAGE_SIZE
	emotesScroll.CanvasPosition = Vector2.new(0, 0)
	if isState then
		st.refreshLists()
	end
	layoutEmotes()
end

emotesScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if not hasMore then return end
	local bottom = emotesScroll.CanvasPosition.Y + emotesScroll.AbsoluteWindowSize.Y
	if bottom >= emotesScroll.AbsoluteCanvasSize.Y - 60 then
		visibleLimit = visibleLimit + PAGE_SIZE
		layoutEmotes()
	end
end)

for i, tabName in ipairs(emoteTabNames) do
	local tab = Instance.new("TextButton")
	tab.Name = tabName .. "Tab"
	tab.Size = UDim2.new(1 / #emoteTabNames, -4, 1, 0)
	tab.Position = UDim2.new((i - 1) / #emoteTabNames, 2, 0, 0)
	tab.BackgroundTransparency = 1
	tab.Text = (tabName == "AnimCopy") and "Copy" or tabName
	tab.Font = Enum.Font.GothamMedium
	tab.TextSize = 10
	tab.TextColor3 = MUTED
	tab.AutoButtonColor = false
	tab.ZIndex = 3
	tab.Parent = emoteTabBar

	local under = Instance.new("Frame")
	under.Name = "Underline"
	under.Size = UDim2.new(1, 0, 0, 2)
	under.Position = UDim2.new(0, 0, 1, -2)
	under.BackgroundColor3 = WHITE
	under.BorderSizePixel = 0
	under.Visible = false
	under.ZIndex = 4
	under.Parent = tab

	emoteTabButtons[tabName] = tab
	tab.MouseButton1Click:Connect(function()
		setActiveTab(tabName)
	end)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	visibleLimit = PAGE_SIZE
	emotesScroll.CanvasPosition = Vector2.new(0, 0)
	layoutEmotes()
end)

customAddButton.MouseButton1Click:Connect(function()
	local name = customNameBox.Text:match("^%s*(.-)%s*$")
	local url = customUrlBox.Text:match("^%s*(.-)%s*$")
	if name == "" or not url:match("^https?://") then
		setStatus("Custom emote needs a name and a URL", Color3.fromRGB(255, 255, 255))
		return
	end
	local existing
	for _, item in ipairs(customEmotes) do
		if item.name == name then
			existing = item
			break
		end
	end
	if existing then
		existing.url = url
	else
		table.insert(customEmotes, { name = name, url = url, custom = true })
	end
	customNameBox.Text = ""
	customUrlBox.Text = ""
	saveData()
	refreshStatus()
	layoutEmotes()
end)

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
		refreshSpeedBinds()
		return
	end

	if UserInputService:GetFocusedTextBox() then return end

	local keyName = input.KeyCode.Name
	for name, boundKey in pairs(binds) do
		if boundKey == keyName then
			if name == "__limb_toggle" then
				limb.toggle()
			elseif name == "__limb_left_toggle" then
				limbLeft.toggle()
			elseif name == "__torso_toggle" then
				follow.toggleTorso()
			elseif name == "__head_toggle" then
				follow.toggleHead()
			elseif name:sub(1, 9) == "__preset_" then
				local info = presetById[name]
				if info then
					applyPreset(info.value, info.reverse)
					setStatus((info.reverse and "-" or "") .. info.value .. "x", MUTED)
				end
			else
				local entry = findEntry(name)
				if entry then
					togglePlay(entry)
				end
			end
			break
		end
	end
end))

local syncTimer = 0
track(RunService.Heartbeat:Connect(function(dt)
	syncTimer = syncTimer + dt
	if syncTimer < 0.2 then return end
	syncTimer = 0
	for _, item in ipairs(playButtons) do
		local playing = playingName == item.name
		local text = playing and "Stop" or "Play"
		if item.button.Text ~= text then
			item.button.Text = text
			item.button.TextColor3 = playing and ORANGE or WHITE
		end
	end
end))

local function reloadEmotes()
	setStatus("Loading emotes...", MUTED)
	allEmotes = {}
	layoutEmotes()

	task.spawn(function()
		local ok, result = pcall(fetchAllAnimDataEmotes)
		if ok and type(result) == "table" then
			allEmotes = result
		else
			warn("emote fetch failed:", result)
		end
		table.sort(allEmotes, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
		if #allEmotes > 0 then
			refreshStatus()
		else
			setStatus("Failed to load emotes", Color3.fromRGB(255, 255, 255))
		end
		layoutEmotes()
		st.refreshLists()
	end)
end

if api then
	if api.on_animation_play then
		api.on_animation_play(function(url)
			local name = url and tostring(url):match("([^/]+)$") or "emote"
			name = name:gsub("%.lua$", ""):gsub("_", " ")
			playingName = name
			if st.current then
				setStatus("State: " .. st.current .. " (" .. name .. ")", GREEN)
			else
				setStatus("Playing " .. name, GREEN)
			end
		end)
	end
	if api.on_animation_stop then
		api.on_animation_stop(function()
			local wasState = st.current
			playingName = nil
			st.url = nil
			st.current = nil
			if not (wasState and st.enabled and reanimEnabled) then
				refreshStatus()
			end
		end)
	end
end

track(player.CharacterAdded:Connect(function()
	stopEmote()
	if follow then follow.kill() end
    pcall(st.copyStop, "Respawned - copy stopped")
	task.delay(0.5, function()
		reanimEnabled = api and api.is_reanimated and api.is_reanimated() or false
		updateReanimVisual(false)
		refreshStatus()
	end)
end))

updateReanimVisual(false)
setActiveTab("All")
reloadEmotes()

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

__i = function()
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
end
__i()

__i = function()
	local drag = { active = false, moved = false, startMouse = nil, startPos = nil }

	floatingButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			drag.active = true
			drag.moved = false
			drag.startMouse = Vector2.new(input.Position.X, input.Position.Y)
			drag.startPos = floatingButton.Position
		end
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if not drag.active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.startMouse
		if not drag.moved and delta.Magnitude > 5 then
			drag.moved = true
		end
		if drag.moved then
			floatingButton.Position = UDim2.new(
				drag.startPos.X.Scale,
				drag.startPos.X.Offset + delta.X,
				drag.startPos.Y.Scale,
				drag.startPos.Y.Offset + delta.Y
			)
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			drag.active = false
		end
	end))

	floatingButton.Activated:Connect(function()
		if drag.moved then return end
		setOpen(true)
	end)
end
__i()

env[CLEANUP_KEY] = function()
	pcall(limb.kill)
	pcall(limbLeft.kill)
	pcall(follow.kill)
    pcall(st.copyStop)
	stopEmote()
	if api and api.reanimate and api.is_reanimated and api.is_reanimated() then
		pcall(api.reanimate, false)
	end
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
	resetWorld()
end
