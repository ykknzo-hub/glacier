local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "ugcemoteshub"
local CLEANUP_KEY = "__ugc_emotes_hub_cleanup"
local GLACIER_DIR = "glacier"
local FAVE_DIR = GLACIER_DIR .. "/favemotes"
local FAV_FILE = FAVE_DIR .. "/favourites.json"
local OLD_FAV_FILES = { GLACIER_DIR .. "/favemotes.json", "FavoritedEmotes.txt" }
local BIND_FILE = "EmoteKeybinds.txt"
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

local alive = true

local emotes = {}
local loading = true
local favorites = {}
local keybinds = {}
local currentPage = "all"
local waitingForBind = nil
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

local function ensureFaveFolder()
	if type(makefolder) ~= "function" or type(isfolder) ~= "function" then return end
	pcall(function()
		if not isfolder(GLACIER_DIR) then makefolder(GLACIER_DIR) end
		if not isfolder(FAVE_DIR) then makefolder(FAVE_DIR) end
	end)
end

local emoteIds = {}

local function addEmote(name, id, price, direct)
	if not (name and id) then return end
	if emoteIds[id] then return end
	emoteIds[id] = true
	table.insert(emotes, { name = tostring(name), id = id, price = price or 0, direct = direct })
end

local VIP_EMOTES = {
	{ "Handstand", 13027233338 },
	{ "VIP 01", 124072584017964 },
	{ "VIP 03", 137445502103066 },
	{ "VIP 08", 11137338685 },
	{ "Ghostly", 124385779438289 },
	{ "Oof", 134763058840745 },
	{ "Die", 14852161489 },
	{ "Log", 116818881329505 },
}
for _, vip in ipairs(VIP_EMOTES) do
	addEmote(vip[1], vip[2], 0, true)
end

local DEFAULT_EMOTES = {
	{ "Wave", 507770239 },
	{ "Point", 507770453 },
	{ "Laugh", 507770818 },
	{ "Cheer", 507770677 },
	{ "Dance", 507771019 },
	{ "Dance2", 507776043 },
	{ "Dance3", 507777268 },
}
for _, d in ipairs(DEFAULT_EMOTES) do
	addEmote(d[1], d[2], 0, true)
end

local EMOTE_JSON_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/EmoteSniper.json"

local function fetchBody(url)
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if req then
		local ok, res = pcall(function() return req({ Url = url, Method = "GET" }) end)
		if ok and res then
			local body = res.Body or res.body
			if type(body) == "string" and #body > 0 then return body end
		end
	end
	local ok2, body2 = pcall(function() return game:HttpGet(url) end)
	if ok2 and type(body2) == "string" and #body2 > 0 then return body2 end
	return nil
end

local function parseEmoteJSON(body)
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(data) ~= "table" then return {} end
	local list = {}
	local container = data.emotes or data.data or data.Emotes or data
	for k, v in pairs(container) do
		if type(v) == "table" then
			local rawId = v.id or v.assetId or v.animId or v.AnimationId or v.EmoteId or v.asset_id
			local id = rawId and tonumber((tostring(rawId):gsub("%D", ""))) or nil
			local name = v.name or v.Name or v.title or v.title_name or tostring(k)
			if id then
				table.insert(list, { name = tostring(name), id = id })
			end
		elseif type(v) == "number" or type(v) == "string" then
			local num = tonumber((tostring(v):gsub("%D", "")))
			if num then
				table.insert(list, { name = tostring(k), id = num })
			end
		end
	end
	return list
end

local function isFav(id)
	return table.find(favorites, id) ~= nil
end

local function saveFavorites()
	pcall(function()
		if type(writefile) == "function" then
			ensureFaveFolder()
			writefile(FAV_FILE, HttpService:JSONEncode(favorites))
		end
	end)
end

local function saveKeybinds()
	pcall(function()
		if type(writefile) == "function" then
			writefile(BIND_FILE, HttpService:JSONEncode(keybinds))
		end
	end)
end

ensureFaveFolder()

pcall(function()
	if type(isfile) ~= "function" then return end
	if isfile(FAV_FILE) then
		local data = HttpService:JSONDecode(readfile(FAV_FILE))
		if type(data) == "table" then
			favorites = data
		end
	else
		for _, oldPath in ipairs(OLD_FAV_FILES) do
			if isfile(oldPath) then
				local data = HttpService:JSONDecode(readfile(oldPath))
				if type(data) == "table" then
					favorites = data
				end
				break
			end
		end
		saveFavorites()
	end
end)

pcall(function()
	if type(isfile) == "function" and isfile(BIND_FILE) then
		local data = HttpService:JSONDecode(readfile(BIND_FILE))
		if type(data) == "table" then
			for k, v in pairs(data) do
				keybinds[tonumber(k) or k] = v
			end
		end
	end
end)

local function findKeyCode(name)
	name = string.lower(name or "")
	for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
		if item.Name ~= "Unknown" and string.lower(item.Name) == name then
			return item
		end
	end
	return nil
end

local function getBindName(emoteId)
	return keybinds[emoteId]
end

local currentDirect, currentDirectId

local function stopDirect()
	if currentDirect then
		pcall(function()
			currentDirect:Stop(0.1)
			currentDirect:Destroy()
		end)
	end
	currentDirect, currentDirectId = nil, nil
end

local function playDirect(humanoid, entry)
	if currentDirectId == entry.id then
		stopDirect()
		return
	end
	stopDirect()
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(entry.id)
	local ok, trackObj = pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			return animator:LoadAnimation(anim)
		end
		return humanoid:LoadAnimation(anim)
	end)
	if not ok or not trackObj then return end
	pcall(function()
		trackObj.Priority = Enum.AnimationPriority.Action4
		trackObj:Play()
	end)
	currentDirect = trackObj
	currentDirectId = entry.id
end

local function playEmote(entry)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and entry.direct then
		playDirect(humanoid, entry)
		return
	end
	stopDirect()
	if not humanoid or humanoid.RigType == Enum.HumanoidRigType.R6 then
		return
	end
	local description = humanoid:FindFirstChildOfClass("HumanoidDescription")
	if not description then
		description = Instance.new("HumanoidDescription")
		description.Parent = humanoid
	end
	local ok = pcall(function()
		humanoid:PlayEmoteAndGetAnimTrackById(entry.id)
	end)
	if not ok then
		pcall(function()
			description:AddEmote(entry.name, entry.id)
			humanoid:PlayEmoteAndGetAnimTrackById(entry.id)
		end)
	end
end

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_HEIGHT = 30
local FULL_SIZE = UDim2.new(0, 300, 0, 380)
local BODY_COLOR = Color3.fromRGB(8, 8, 8)
local BOX_COLOR = Color3.fromRGB(22, 22, 22)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(150, 150, 150)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 995
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Position = UDim2.new(0.5, -150, 0.5, -190)
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
titleLabel.Text = "UGC Emotes"
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

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Position = UDim2.new(0, 12, 0, 4)
tabBar.Size = UDim2.new(1, -24, 0, 26)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 3
tabBar.Parent = body

local function makeTab(name, text, x)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 70, 0, 24)
	btn.Position = UDim2.new(0, x, 0, 1)
	btn.BackgroundColor3 = BOX_COLOR
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = MUTED
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	btn.AutoButtonColor = false
	btn.ZIndex = 4
	btn.Parent = tabBar
	makeCorner(btn, 6)
	return btn
end

local allTab = makeTab("AllTab", "All", 0)
local favsTab = makeTab("FavsTab", "Favs", 76)

local function updateTabs()
	if currentPage == "all" then
		allTab.TextColor3 = WHITE
		allTab.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		favsTab.TextColor3 = MUTED
		favsTab.BackgroundColor3 = BOX_COLOR
	else
		favsTab.TextColor3 = WHITE
		favsTab.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		allTab.TextColor3 = MUTED
		allTab.BackgroundColor3 = BOX_COLOR
	end
end

updateTabs()

local countLabel = Instance.new("TextLabel")
countLabel.Name = "CountLabel"
countLabel.Position = UDim2.new(0, 12, 0, 32)
countLabel.Size = UDim2.new(1, -24, 0, 14)
countLabel.BackgroundTransparency = 1
countLabel.Text = "0 out of 0 emotes loaded"
countLabel.TextColor3 = MUTED
countLabel.Font = Enum.Font.Gotham
countLabel.TextSize = 11
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.ZIndex = 3
countLabel.Parent = body

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -24, 0, 26)
searchBox.Position = UDim2.new(0, 12, 0, 50)
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

local LIST_Y = 84
local list = Instance.new("ScrollingFrame")
list.Name = "EmoteList"
list.Position = UDim2.new(0, 0, 0, LIST_Y)
list.Size = UDim2.new(1, 0, 1, -(LIST_Y + 6))
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.ScrollBarImageColor3 = WHITE
list.ScrollBarImageTransparency = 0.65
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.ZIndex = 2
list.Parent = body

local ROW_H = 28
local ROW_GAP = 4
local PAGE_SIZE = 30
local visibleLimit = PAGE_SIZE
local hasMore = false
local rows = {}

local function clearRows()
	for _, row in ipairs(rows) do
		row:Destroy()
	end
	table.clear(rows)
end

local layout

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

local function makeRow(entry, y, isRandom)
	local row = Instance.new("Frame")
	row.Name = "EmoteRow"
	row.Size = UDim2.new(1, -24, 0, ROW_H)
	row.Position = UDim2.new(0, 12, 0, y)
	row.BackgroundTransparency = 1
	row.ZIndex = 3
	row.Parent = list

	local rightSpace = isRandom and 52 or 120

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -rightSpace, 1, 0)
	nameLabel.Position = UDim2.new(0, 4, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = isRandom and "Random" or entry.name
	nameLabel.TextColor3 = WHITE
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 3
	nameLabel.Parent = row

	local isPlayingDirect = (not isRandom) and entry.direct and currentDirectId == entry.id
	local playBtn = makeRowButton(row, isPlayingDirect and "Stop" or "Play", 40, 0)
	playBtn.MouseButton1Click:Connect(function()
		if isRandom then
			if #emotes > 0 then
				playEmote(emotes[math.random(1, #emotes)])
			end
		else
			playEmote(entry)
		end
		layout()
	end)

	if not isRandom then
		local bindName = getBindName(entry.id)
		local isWaiting = waitingForBind and waitingForBind.id == entry.id

		local bindBtn = makeRowButton(row, "", 48, 44)
		bindBtn.TextSize = 11

		local bindIcon = Instance.new("ImageLabel")
		bindIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		bindIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		bindIcon.Size = UDim2.new(0, 16, 0, 16)
		bindIcon.BackgroundTransparency = 1
		bindIcon.ImageColor3 = WHITE
		bindIcon.ScaleType = Enum.ScaleType.Fit
		bindIcon.ZIndex = 5
		bindIcon.Visible = false
		bindIcon.Parent = bindBtn

		if isWaiting then
			bindBtn.Text = "..."
			bindBtn.TextColor3 = Color3.fromRGB(255, 200, 80)
			bindIcon.Visible = false
		elseif bindName then
			bindBtn.Text = bindName
			bindBtn.TextColor3 = Color3.fromRGB(120, 200, 255)
			bindIcon.Visible = false
		else
			local logo = getLogoAsset()
			if logo then
				bindIcon.Image = logo
				bindIcon.Visible = true
				bindBtn.Text = ""
			else
				bindBtn.Text = "Bind"
				bindBtn.TextColor3 = WHITE
				bindIcon.Visible = false
			end
		end

		bindBtn.MouseButton1Click:Connect(function()
			if waitingForBind and waitingForBind.id == entry.id then
				waitingForBind = nil
			elseif bindName then
				keybinds[entry.id] = nil
				saveKeybinds()
				waitingForBind = nil
			else
				waitingForBind = entry
			end
			layout()
		end)

		local star = makeRowButton(row, isFav(entry.id) and "★" or "☆", 22, 96)
		star.Font = Enum.Font.GothamBold
		star.TextSize = 14
		star.MouseButton1Click:Connect(function()
			local index = table.find(favorites, entry.id)
			if index then
				table.remove(favorites, index)
			else
				table.insert(favorites, entry.id)
			end
			saveFavorites()
			layout()
		end)
	end

	table.insert(rows, row)
end

local function addMessage(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 0, 40)
	label.Position = UDim2.new(0, 12, 0, 12)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = MUTED
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextWrapped = true
	label.ZIndex = 3
	label.Parent = list
	table.insert(rows, label)
end

layout = function()
	if not alive then return end
	local savedScroll = list.CanvasPosition
	clearRows()
	hasMore = false

	if loading and #emotes == 0 then
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		countLabel.Text = "0 out of 0 emotes loaded"
		addMessage("Loading emotes...")
		return
	end

	local query = string.lower(searchBox.Text or "")
	local filtered = {}

	if currentPage == "favs" then
		for _, entry in ipairs(emotes) do
			if isFav(entry.id) then
				if query == "" or string.find(string.lower(entry.name), query, 1, true) then
					table.insert(filtered, entry)
				end
			end
		end
	else
		for _, entry in ipairs(emotes) do
			if query == "" or string.find(string.lower(entry.name), query, 1, true) then
				table.insert(filtered, entry)
			end
		end
	end

	if currentPage == "all" then
		local favs, rest = {}, {}
		for _, entry in ipairs(filtered) do
			if isFav(entry.id) then
				table.insert(favs, entry)
			else
				table.insert(rest, entry)
			end
		end
		filtered = {}
		for _, e in ipairs(favs) do table.insert(filtered, e) end
		for _, e in ipairs(rest) do table.insert(filtered, e) end
	end

	local y = 4
	local shown = 0

	if currentPage == "all" and query == "" then
		makeRow(nil, y, true)
		y = y + ROW_H + ROW_GAP
	end

	for _, entry in ipairs(filtered) do
		if shown >= visibleLimit then
			hasMore = true
			break
		end
		makeRow(entry, y, false)
		y = y + ROW_H + ROW_GAP
		shown = shown + 1
	end

	list.CanvasSize = UDim2.new(0, 0, 0, y + 6)
	list.CanvasPosition = savedScroll
	countLabel.Text = shown .. " out of " .. #filtered .. " emotes loaded"

	if shown == 0 then
		if currentPage == "favs" then
			if query ~= "" then
				addMessage("No favorited emotes match your search.")
			else
				addMessage("No favorited emotes yet.\nTap the ★ on any emote to add it here.")
			end
		elseif query ~= "" then
			addMessage("No emotes match your search.")
		end
	end
end

allTab.MouseButton1Click:Connect(function()
	if currentPage ~= "all" then
		currentPage = "all"
		visibleLimit = PAGE_SIZE
		list.CanvasPosition = Vector2.new(0, 0)
		updateTabs()
		layout()
	end
end)

favsTab.MouseButton1Click:Connect(function()
	if currentPage ~= "favs" then
		currentPage = "favs"
		visibleLimit = PAGE_SIZE
		list.CanvasPosition = Vector2.new(0, 0)
		updateTabs()
		layout()
	end
end)

list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if not hasMore then return end
	local bottom = list.CanvasPosition.Y + list.AbsoluteWindowSize.Y
	if bottom >= list.AbsoluteCanvasSize.Y - 60 then
		visibleLimit = visibleLimit + PAGE_SIZE
		layout()
	end
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	visibleLimit = PAGE_SIZE
	list.CanvasPosition = Vector2.new(0, 0)
	layout()
end)

task.spawn(function()
	getLogoAsset()
	layout()
end)
layout()

task.spawn(function()
	local jsonBody
	for _ = 1, 5 do
		if not alive then return end
		jsonBody = fetchBody(EMOTE_JSON_URL)
		if jsonBody then break end
		task.wait(3)
	end
	if not jsonBody or not alive then return end
	for _, e in ipairs(parseEmoteJSON(jsonBody)) do
		addEmote(e.name, e.id, 0)
	end
	table.sort(emotes, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	layout()
end)

task.spawn(function()
	local params = CatalogSearchParams.new()
	params.AssetTypes = { Enum.AvatarAssetType.EmoteAnimation }
	params.SortType = Enum.CatalogSortType.RecentlyCreated
	params.SortAggregation = Enum.CatalogSortAggregation.AllTime
	params.IncludeOffSale = true
	params.CreatorName = "Roblox"
	params.Limit = 120

	local catalogPage
	for _ = 1, 10 do
		if not alive then return end
		local ok, result = pcall(function()
			return AvatarEditorService:SearchCatalog(params)
		end)
		if ok and result then
			catalogPage = result
			break
		end
		task.wait(5)
	end

	local found = {}
	if catalogPage then
		while alive do
			for _, emote in pairs(catalogPage:GetCurrentPage()) do
				table.insert(found, emote)
			end
			if catalogPage.IsFinished then break end
			local advanced = false
			for _ = 1, 10 do
				if not alive then return end
				if pcall(function() catalogPage:AdvanceToNextPageAsync() end) then
					advanced = true
					break
				end
				task.wait(5)
			end
			if not advanced then break end
		end
	end

	if not alive then return end

	for _, emote in ipairs(found) do
		addEmote(emote.Name, emote.Id, emote.Price)
	end
	addEmote("Arm Wave", 5915773155)
	addEmote("Head Banging", 5915779725)
	addEmote("Face Calisthenics", 9830731012)

	table.sort(emotes, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	local converted = {}
	local needsConvert = false
	for _, value in ipairs(favorites) do
		if type(value) == "string" then
			needsConvert = true
			for _, emote in ipairs(emotes) do
				if emote.name == value then
					table.insert(converted, emote.id)
					break
				end
			end
		else
			table.insert(converted, value)
		end
	end
	if needsConvert then
		favorites = converted
		saveFavorites()
	end

	loading = false
	layout()
end)

local function toggleWindow()
	mainFrame.Visible = not mainFrame.Visible
end

track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if waitingForBind then
		if input.KeyCode == Enum.KeyCode.Escape then
			waitingForBind = nil
			layout()
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift
			or input.KeyCode == Enum.KeyCode.RightShift
			or input.KeyCode == Enum.KeyCode.LeftControl
			or input.KeyCode == Enum.KeyCode.RightControl
			or input.KeyCode == Enum.KeyCode.LeftAlt
			or input.KeyCode == Enum.KeyCode.RightAlt
			or input.KeyCode == Enum.KeyCode.LeftMeta
			or input.KeyCode == Enum.KeyCode.RightMeta
		then
			return
		end

		local keyName = input.KeyCode.Name
		for id, name in pairs(keybinds) do
			if name == keyName then
				keybinds[id] = nil
			end
		end
		keybinds[waitingForBind.id] = keyName
		waitingForBind = nil
		saveKeybinds()
		layout()
		return
	end

	if gameProcessed or UserInputService:GetFocusedTextBox() then return end

	local keyName = input.KeyCode.Name
	for _, entry in ipairs(emotes) do
		if keybinds[entry.id] == keyName then
			playEmote(entry)
			break
		end
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
	if string.lower(message) == ";emotes" or string.lower(message) == ";ugcemotes" then
		toggleWindow()
	end
end))

track(player.CharacterAdded:Connect(function()
	stopDirect()
	layout()
end))

local function cleanup()
	alive = false
	stopDirect()
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
	mainFrame.Visible = false
end)
