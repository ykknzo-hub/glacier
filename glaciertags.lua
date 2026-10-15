local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local player = Players.LocalPlayer

local WEBSITE_TAGS_URL = "https://lorez.co.uk/tags.json"

local FIREBASE_URL = "https://nametags-11467-default-rtdb.europe-west1.firebasedatabase.app"
local FIREBASE_SECRET = ""
local PING_SECONDS = 8
local DEAD_AFTER = 30 -- seconds without a changed lastSeen before a tag is removed
local SCRIPT_ID = "kxnzie_nametag_v1"

local DEFAULT_COLOR1 = "#000000"
local DEFAULT_COLOR2 = "#ffffff"
local DEFAULT_ALIGN  = "center"

local DEFAULT_BG_URL   = "https://i.ibb.co/R4GQRvtv/1278d4e6-3b8e-4414-bf23-15d3761cf10e.jpg"
local DEFAULT_BG_FILE  = "R4GQRvtv/1278d4e6-3b8e-4414-bf23-15d3761cf10e.jpg"
local DEFAULT_LOGO_URL = "https://i.ibb.co/C3v5WrBZ/g.png"
local DEFAULT_LOGO_FILE = "g.png"

local CARD_COLOR = Color3.fromRGB(16, 9, 24)
local HEIGHT = 1.9
local TAG_NAME = "__kxnzie_nametag"

local COLLAPSE_DISTANCE = 50
local FULL_W, FULL_H, SQUARE = 150, 50, 50

local LOGO_SIZE = 46
local LOGO_PAD = 5

local TITLE_HEIGHT = 14
local SUB_HEIGHT   = 9
local TITLE_Y_OFFSET = -8
local SUB_Y_OFFSET   = 9

local LEFT_PADDING = 10

local MAX_IMAGE_DIM = 1024

-- Verified badge
local BADGE_SIZE  = 14
local BADGE_GAP   = 3
local BADGE_COLOR = Color3.fromRGB(29, 155, 240)
-- The real Roblox verified badge image. If you ever want to be safe from the link
-- changing, upload a copy through your lorez.co.uk/tags page and paste that URL here.
local VERIFIED_BADGE_URL  = "https://en.help.roblox.com/hc/article_attachments/7997146649876/Roblox_Verified_Badge.png"
local VERIFIED_BADGE_FILE = "Roblox_Verified_Badge.png"

local env = (getgenv and getgenv()) or _G
if type(env[TAG_NAME]) == "function" then
    pcall(env[TAG_NAME])
end

do
    local pg = player:WaitForChild("PlayerGui")
    for _, child in ipairs(pg:GetChildren()) do
        if child.Name == TAG_NAME then
            child:Destroy()
        end
    end
end

local running = true

local assetCache = {}

local function loadAsset(file, url)
    if not file or not url or url == "" or url == "none" then return nil end
    local cacheKey = file .. "|" .. url
    if assetCache[cacheKey] ~= nil then
        return assetCache[cacheKey] or nil
    end
    local sum = 0
    for i = 1, #url do sum = (sum * 31 + string.byte(url, i)) % 1000000007 end

    local cleanName = (tostring(file):gsub("[^%w%._%-]", "_"))
    local safeFile = sum .. "_" .. cleanName
    local ok, result = pcall(function()
        if not (isfile and writefile and getcustomasset) then return nil end
        if not isfile(safeFile) then
            local data = game:HttpGet(url)
            if not data or #data == 0 then return nil end
            writefile(safeFile, data)
        end
        return getcustomasset(safeFile)
    end)
    assetCache[cacheKey] = (ok and result) or false
    return assetCache[cacheKey] or nil
end

local function parseColor(hex, fallback)
    local ok, color = pcall(Color3.fromHex, tostring(hex))
    if ok and color then return color end
    return fallback
end

local function cleanText(value, fallback)
    if type(value) ~= "string" then return fallback end
    return string.sub(value, 1, 24)
end

local function normalizeAlign(value)
    local v = tostring(value or ""):lower()
    if v == "left" then return "left" end
    if v == "right" then return "right" end
    return "center"
end

local function alignToTextX(align)
    if align == "left" then return Enum.TextXAlignment.Left end
    if align == "right" then return Enum.TextXAlignment.Right end
    return Enum.TextXAlignment.Center
end

local sprites = {}

local function normalizeSprite(meta)
    if type(meta) ~= "table" then return nil end
    local frames = tonumber(meta.frames)
    local cols = tonumber(meta.cols)
    local rows = tonumber(meta.rows)
    local fw = tonumber(meta.frameWidth)
    local fh = tonumber(meta.frameHeight)
    local fps = tonumber(meta.fps) or 10
    if not (frames and cols and rows and fw and fh) then return nil end
    if frames < 1 or cols < 1 or rows < 1 or fw < 1 or fh < 1 then return nil end
    if fps < 1 then fps = 1 end
    return {
        frames = math.floor(frames),
        cols = math.floor(cols),
        rows = math.floor(rows),
        fps = fps,
        frameWidth = fw,
        frameHeight = fh,
    }
end

local function spriteKey(meta)
    if type(meta) ~= "table" then return "-" end
    return table.concat({
        tostring(meta.frames), tostring(meta.cols), tostring(meta.rows),
        tostring(meta.fps), tostring(meta.frameWidth), tostring(meta.frameHeight),
    }, ",")
end

local function setSpriteFrame(label, info, frame)
    local meta = info.meta
    local col = frame % meta.cols
    local row = math.floor(frame / meta.cols)
    local s = info.scale
    label.ImageRectSize = Vector2.new(meta.frameWidth * s, meta.frameHeight * s)
    label.ImageRectOffset = Vector2.new(col * meta.frameWidth * s, row * meta.frameHeight * s)
    info.last = frame
end

local function applySprite(label, rawMeta)
    local meta = normalizeSprite(rawMeta)
    if not meta then return end
    local sheetW = meta.frameWidth * meta.cols
    local sheetH = meta.frameHeight * meta.rows
    local scale = math.min(1, MAX_IMAGE_DIM / math.max(sheetW, sheetH))
    local info = { meta = meta, scale = scale, last = -1 }
    sprites[label] = info
    setSpriteFrame(label, info, 0)
end

local gradients = {}
local collapsing = {}
type TagEntry = {
    key: string,
    data: any,
    conn: RBXScriptConnection?,
    headConn: RBXScriptConnection?,
    gui: BillboardGui?,
    building: boolean?,
}

local tags: { [Player]: TagEntry } = {}

local function addGradient(parent, c1, c2)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(0.5, c2),
        ColorSequenceKeypoint.new(1, c1),
    })
    gradient.Parent = parent
    gradients[gradient] = true
    return gradient
end

local function teleportBehind(target)
    local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local theirRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if myRoot and theirRoot then
        myRoot.CFrame = theirRoot.CFrame * CFrame.new(0, 0, 3)
    end
end

-- Uses the real Roblox badge image when it could be downloaded, otherwise falls
-- back to a blue circle with a white check drawn from frames.
local function createVerifiedBadge(parent, asset)
    if asset then
        local img = Instance.new("ImageLabel")
        img.AnchorPoint = Vector2.new(0, 0.5)
        img.Size = UDim2.new(0, BADGE_SIZE, 0, BADGE_SIZE)
        img.BackgroundTransparency = 1
        img.BorderSizePixel = 0
        img.Image = asset
        img.ScaleType = Enum.ScaleType.Fit
        img.ZIndex = 3
        img.Parent = parent
        return img
    end

    local badge = Instance.new("Frame")
    badge.AnchorPoint = Vector2.new(0, 0.5)
    badge.Size = UDim2.new(0, BADGE_SIZE, 0, BADGE_SIZE)
    badge.BackgroundColor3 = BADGE_COLOR
    badge.BorderSizePixel = 0
    badge.ZIndex = 3
    badge.Parent = parent

    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(1, 0)
    round.Parent = badge

    local function arm(w, h, x, y, rot)
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Position = UDim2.new(x, 0, y, 0)
        f.Size = UDim2.new(0, w, 0, h)
        f.Rotation = rot
        f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        f.BorderSizePixel = 0
        f.ZIndex = 4
        f.Parent = badge
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 1)
        c.Parent = f
    end

    arm(2, 4.5, 0.38, 0.57, -45) -- short arm
    arm(2, 8,   0.60, 0.46,  45) -- long arm

    return badge
end

local function buildTag(head, data, target)
    local c1 = parseColor(data.color1, Color3.fromRGB(150, 70, 255))
    local c2 = parseColor(data.color2, Color3.fromRGB(255, 122, 24))
    local title = cleanText(data.title, "")
    local subtitle = cleanText(data.subtitle, "")
    local align = normalizeAlign(data.textAlign or DEFAULT_ALIGN)

    local bgAsset = loadAsset(
        data.imageFile or DEFAULT_BG_FILE,
        data.image or DEFAULT_BG_URL
    )

    local logoAsset = nil
    if data.logo == "none" then
        logoAsset = nil
    elseif data.logo and data.logo ~= "" then
        logoAsset = loadAsset(data.logoFile or DEFAULT_LOGO_FILE, data.logo)
    else
        logoAsset = loadAsset(DEFAULT_LOGO_FILE, DEFAULT_LOGO_URL)
    end

    local gui = Instance.new("BillboardGui")
    gui.Name = TAG_NAME
    gui.Adornee = head
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.Size = UDim2.new(0, FULL_W, 0, FULL_H)
    gui.StudsOffsetWorldSpace = Vector3.new(0, HEIGHT, 0)
    gui.Active = true
    gui.Parent = player:WaitForChild("PlayerGui")

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 1, 0)
    card.BackgroundColor3 = CARD_COLOR
    card.BackgroundTransparency = bgAsset and 1 or 0.1
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = card

    if bgAsset then
        local bg = Instance.new("ImageLabel")
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundTransparency = 1
        bg.Image = bgAsset
        bg.ScaleType = Enum.ScaleType.Crop
        bg.ZIndex = 1
        bg.Parent = card
        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(0, 4)
        bgCorner.Parent = bg
        applySprite(bg, data.imageSprite)
    end

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Parent = card
    addGradient(stroke, c1, c2)

    local logo = nil
    local logoWidth = 0

    if logoAsset then
        logo = Instance.new("ImageLabel")
        logo.BackgroundTransparency = 1
        logo.AnchorPoint = Vector2.new(0, 0.5)
        logo.Position = UDim2.new(0, LOGO_PAD, 0.5, 0)
        logo.Size = UDim2.new(0, LOGO_SIZE, 0, LOGO_SIZE)
        logo.Image = logoAsset
        logo.ScaleType = Enum.ScaleType.Fit
        logo.ZIndex = 2
        logo.Parent = card
        applySprite(logo, data.logoSprite)
        logoWidth = LOGO_PAD + LOGO_SIZE + 4
    end

    local TEXT_LEFT  = logoWidth
    local TEXT_RIGHT = 4
    local TEXT_ZONE_PIXEL_W = FULL_W - TEXT_LEFT - TEXT_RIGHT

    local xAnchor, xPos
    if align == "left" then
        xAnchor = Vector2.new(0, 0.5)
        xPos = UDim2.new(0, TEXT_LEFT + LEFT_PADDING, 0.5, 0)
    elseif align == "right" then
        xAnchor = Vector2.new(1, 0.5)
        xPos = UDim2.new(0, TEXT_LEFT + TEXT_ZONE_PIXEL_W, 0.5, 0)
    else
        xAnchor = Vector2.new(0.5, 0.5)
        xPos = UDim2.new(0, TEXT_LEFT + TEXT_ZONE_PIXEL_W / 2, 0.5, 0)
    end

    local labelW = TEXT_ZONE_PIXEL_W
    if align == "left" then
        labelW = TEXT_ZONE_PIXEL_W - LEFT_PADDING
    end

    local textX = alignToTextX(align)

    local texts = {}
    local badge = nil

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.AnchorPoint = xAnchor
    titleLabel.Position = UDim2.new(
        xPos.X.Scale, xPos.X.Offset,
        0.5, subtitle ~= "" and TITLE_Y_OFFSET or 0
    )
    titleLabel.Size = UDim2.new(0, labelW, 0, TITLE_HEIGHT)
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextScaled = true
    titleLabel.TextStrokeTransparency = 1
    titleLabel.TextXAlignment = textX
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.ZIndex = 2
    titleLabel.Parent = card
    addGradient(titleLabel, c1, c2)
    table.insert(texts, titleLabel)

    -- Verified badge: shrink the title to its text width and put the badge
    -- right after it, keeping the group aligned like the rest of the text.
    if data.verified == true then
        local yOff = (subtitle ~= "") and TITLE_Y_OFFSET or 0
        local badgeSpace = BADGE_SIZE + BADGE_GAP

        local okSize, bounds = pcall(function()
            return TextService:GetTextSize(
                title, TITLE_HEIGHT, Enum.Font.GothamBold, Vector2.new(1000, TITLE_HEIGHT)
            )
        end)
        local measured = okSize and bounds.X or labelW
        local titleW = math.clamp(measured, 1, math.max(1, labelW - badgeSpace))
        local groupW = titleW + badgeSpace

        local zoneLeft = TEXT_LEFT + (align == "left" and LEFT_PADDING or 0)
        local startX
        if align == "left" then
            startX = zoneLeft
        elseif align == "right" then
            startX = zoneLeft + labelW - groupW
        else
            startX = zoneLeft + (labelW - groupW) / 2
        end

        titleLabel.AnchorPoint = Vector2.new(0, 0.5)
        titleLabel.Position = UDim2.new(0, startX, 0.5, yOff)
        titleLabel.Size = UDim2.new(0, titleW, 0, TITLE_HEIGHT)
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left

        badge = createVerifiedBadge(card, loadAsset(VERIFIED_BADGE_FILE, VERIFIED_BADGE_URL))
        badge.Position = UDim2.new(0, startX + titleW + BADGE_GAP, 0.5, yOff)
    end

    if subtitle ~= "" then
        local sub = Instance.new("TextLabel")
        sub.BackgroundTransparency = 1
        sub.AnchorPoint = xAnchor
        sub.Position = UDim2.new(
            xPos.X.Scale, xPos.X.Offset,
            0.5, SUB_Y_OFFSET
        )
        sub.Size = UDim2.new(0, labelW, 0, SUB_HEIGHT)
        sub.Text = subtitle
        sub.TextColor3 = Color3.fromRGB(255, 255, 255)
        sub.Font = Enum.Font.Gotham
        sub.TextScaled = true
        sub.TextStrokeTransparency = 1
        sub.TextXAlignment = textX
        sub.TextYAlignment = Enum.TextYAlignment.Center
        sub.ZIndex = 2
        sub.Parent = card
        addGradient(sub, c1, c2)
        table.insert(texts, sub)
    end

    if target ~= player then
        local click = Instance.new("TextButton")
        click.Size = UDim2.new(1, 0, 1, 0)
        click.BackgroundTransparency = 1
        click.Text = ""
        click.ZIndex = 5
        click.Parent = card
        click.MouseButton1Click:Connect(function()
            teleportBehind(target)
        end)
    end

    collapsing[gui] = {
        gui = gui,
        head = head,
        logo = logo,
        hasLogo = logoAsset ~= nil,
        texts = texts,
        badge = badge,
    }
    return gui
end

-- Hides (or restores) the default Roblox overhead display name for a player
local function setNameHidden(target, hidden)
    local char = target.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local want = hidden and Enum.HumanoidDisplayDistanceType.None
        or Enum.HumanoidDisplayDistanceType.Viewer
    if hum.DisplayDistanceType ~= want then
        hum.DisplayDistanceType = want
    end
end

local function removeTag(target)
    local entry = tags[target]
    if not entry then return end
    tags[target] = nil
    setNameHidden(target, false)
    if entry.conn then entry.conn:Disconnect() end
    if entry.headConn then entry.headConn:Disconnect() end
    if entry.gui then
        collapsing[entry.gui] = nil
        entry.gui:Destroy()
    end
end

local function rebuildGui(target, entry, head, data)
    if entry.building then return end
    entry.building = true
    local ok, gui = pcall(buildTag, head, data, target)
    entry.building = false

    if not ok then
        warn("[nametag] build failed: " .. tostring(gui))
        return
    end

    if tags[target] ~= entry then
        collapsing[gui] = nil
        gui:Destroy()
        return
    end

    local old = entry.gui
    entry.gui = gui
    if old and old ~= gui then
        collapsing[old] = nil
        old:Destroy()
    end
end

local function dataKey(data)
    return table.concat({
        tostring(data.title),
        tostring(data.subtitle),
        tostring(data.color1),
        tostring(data.color2),
        tostring(data.image),
        tostring(data.imageFile),
        tostring(data.logo),
        tostring(data.logoFile),
        tostring(data.textAlign),
        tostring(data.verified),
        spriteKey(data.imageSprite),
        spriteKey(data.logoSprite),
    }, "|")
end

local function setTag(target, data)
    local key = dataKey(data)
    local entry = tags[target]

    -- Same data already registered: keep it. The watchdog rebuilds the GUI
    -- if the head isn't loaded yet or the GUI got destroyed.
    if entry and entry.key == key then
        local char = target.Character
        local head = char and char:FindFirstChild("Head")
        if head and entry.gui and entry.gui.Adornee ~= head then
            entry.gui.Adornee = head
            if collapsing[entry.gui] then
                collapsing[entry.gui].head = head
            end
        end
        return
    end

    removeTag(target)

    local newEntry: TagEntry = { key = key, data = data }
    tags[target] = newEntry
    setNameHidden(target, true)

    local function attach(character)
        task.spawn(function()
            local head = character:WaitForChild("Head", 10)
            if not head or tags[target] ~= newEntry then return end

            if newEntry.gui and newEntry.gui.Parent and newEntry.gui.Adornee == head then
                return
            end
            rebuildGui(target, newEntry, head, data)

            if tags[target] ~= newEntry then return end
            if newEntry.headConn then
                newEntry.headConn:Disconnect()
            end
            newEntry.headConn = character.ChildAdded:Connect(function(child)
                if child.Name == "Head" and child:IsA("BasePart") then
                    task.defer(function()
                        local e = tags[target]
                        if e == newEntry and e.gui then
                            e.gui.Adornee = child
                            if collapsing[e.gui] then
                                collapsing[e.gui].head = child
                            end
                        end
                    end)
                end
            end)
        end)
    end

    newEntry.conn = target.CharacterAdded:Connect(attach)

    if target.Character then
        attach(target.Character)
    end
end

local lastWebsiteTags = {}

local function fetchWebsiteTags()
    local ok, result = pcall(function()
        return game:HttpGet(WEBSITE_TAGS_URL .. "?t=" .. tostring(os.time()))
    end)
    if not ok or not result or result == "null" then return lastWebsiteTags end
    local success, decoded = pcall(function()
        return HttpService:JSONDecode(result)
    end)
    if success and type(decoded) == "table" then
        lastWebsiteTags = decoded
    end
    return lastWebsiteTags
end

local function lookupWeb(websiteTags, name)
    local direct = websiteTags[name]
    if direct then return direct end
    local lower = string.lower(name)
    for k, v in pairs(websiteTags) do
        if type(k) == "string" and string.lower(k) == lower then
            return v
        end
    end
    return nil
end

local function makeTagData(username, displayName, webData)
    if type(webData) == "table" then
        return {
            title     = webData.title or displayName,
            subtitle  = webData.subtitle or ("@" .. username),
            color1    = webData.color1 or DEFAULT_COLOR1,
            color2    = webData.color2 or DEFAULT_COLOR2,
            image     = webData.image or DEFAULT_BG_URL,
            imageFile = webData.imageFile or DEFAULT_BG_FILE,
            logo      = webData.logo or DEFAULT_LOGO_URL,
            logoFile  = webData.logoFile or DEFAULT_LOGO_FILE,
            textAlign = webData.textAlign or DEFAULT_ALIGN,
            imageSprite = webData.image and webData.imageSprite or nil,
            logoSprite  = webData.logo and webData.logoSprite or nil,
            verified  = webData.verified == true,
        }
    end
    return {
        title     = displayName,
        subtitle  = "@" .. username,
        color1    = DEFAULT_COLOR1,
        color2    = DEFAULT_COLOR2,
        image     = DEFAULT_BG_URL,
        imageFile = DEFAULT_BG_FILE,
        logo      = DEFAULT_LOGO_URL,
        logoFile  = DEFAULT_LOGO_FILE,
        textAlign = DEFAULT_ALIGN,
        verified  = false,
    }
end

local MY_TAG = makeTagData(player.Name, player.DisplayName, nil)
setTag(player, MY_TAG)

-- Watchdog: repairs every player's tag (missing GUI, destroyed GUI, wrong head)
-- and keeps the default Roblox display name hidden for anyone with a tag
task.spawn(function()
    while running do
        task.wait(0.5)
        for target, entry in pairs(tags) do
            local char = target.Character
            local head = char and char:FindFirstChild("Head")
            setNameHidden(target, true)
            if head and not entry.building
                and (not entry.gui or not entry.gui.Parent or entry.gui.Adornee ~= head) then
                rebuildGui(target, entry, head, entry.data)
            end
        end
        if not tags[player] then
            setTag(player, MY_TAG)
        end
    end
end)

local function firebasePath(jobId, userId)
    local base = FIREBASE_URL .. "/nametags/" .. HttpService:UrlEncode(jobId)
    if userId then
        base = base .. "/" .. tostring(userId)
    end
    base = base .. ".json"
    if FIREBASE_SECRET ~= "" then
        base = base .. "?auth=" .. FIREBASE_SECRET
    end
    return base
end

local function firebasePut(jobId, userId, data)
    local url = firebasePath(jobId, userId)
    local body = HttpService:JSONEncode(data)

    local requestFunc = (syn and syn.request) or http_request or (fluxus and fluxus.request) or request
    if requestFunc then
        local ok = pcall(function()
            return requestFunc({
                Url = url,
                Method = "PUT",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        return ok
    end
    return false
end

-- Returns nil on request failure (so callers can keep current state)
local function firebaseGet(jobId)
    local url = firebasePath(jobId)
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok or not result then return nil end
    if result == "null" then return {} end
    local success, decoded = pcall(function()
        return HttpService:JSONDecode(result)
    end)
    return (success and type(decoded) == "table") and decoded or nil
end

local seen = {} -- [player] = {value = lastSeen, at = os.clock()}

task.spawn(function()
    while running do
        local okLoop, errLoop = pcall(function()
            local websiteTags = fetchWebsiteTags()

            MY_TAG = makeTagData(player.Name, player.DisplayName, lookupWeb(websiteTags, player.Name))
            setTag(player, MY_TAG)

            local jobId = (game.JobId ~= "" and game.JobId) or tostring(game.PlaceId)

            -- NOTE: "verified" is intentionally NOT broadcast through Firebase.
            -- It is only ever read from the website's tags.json, so nobody can fake it.
            firebasePut(jobId, player.UserId, {
                id = SCRIPT_ID,
                t = cleanText(MY_TAG.title, "") ~= "" and cleanText(MY_TAG.title, "") or player.DisplayName,
                s = cleanText(MY_TAG.subtitle, "") ~= "" and cleanText(MY_TAG.subtitle, "") or ("@" .. player.Name),
                c1 = tostring(MY_TAG.color1),
                c2 = tostring(MY_TAG.color2),
                img = MY_TAG.image,
                imgF = MY_TAG.imageFile,
                imgS = MY_TAG.imageSprite,
                logo = MY_TAG.logo,
                logoF = MY_TAG.logoFile,
                logoS = MY_TAG.logoSprite,
                align = MY_TAG.textAlign,
                lastSeen = os.time(),
            })

            local users = firebaseGet(jobId)
            if users == nil then return end -- request failed: keep every tag as is

            local clock = os.clock()
            local broadcasting = {}
            for userIdStr, data in pairs(users) do
                local uid = tonumber(userIdStr)
                if uid and type(data) == "table"
                    and data.id == SCRIPT_ID
                    and data.lastSeen
                    and uid ~= player.UserId
                then
                    local other = Players:GetPlayerByUserId(uid)
                    if other then
                        local s = seen[other]
                        if not s or s.value ~= data.lastSeen then
                            seen[other] = { value = data.lastSeen, at = clock }
                        end
                        if clock - seen[other].at <= DEAD_AFTER then
                            broadcasting[other] = data
                        end
                    end
                end
            end

            for other, data in pairs(broadcasting) do
                local webData = lookupWeb(websiteTags, other.Name)
                local tagData
                if type(webData) == "table" then
                    tagData = makeTagData(other.Name, other.DisplayName, webData)
                else
                    tagData = {
                        title     = (data.t and data.t ~= "") and data.t or other.DisplayName,
                        subtitle  = (data.s and data.s ~= "") and data.s or ("@" .. other.Name),
                        color1    = data.c1 or DEFAULT_COLOR1,
                        color2    = data.c2 or DEFAULT_COLOR2,
                        image     = data.img or DEFAULT_BG_URL,
                        imageFile = data.imgF or DEFAULT_BG_FILE,
                        logo      = data.logo or DEFAULT_LOGO_URL,
                        logoFile  = data.logoF or DEFAULT_LOGO_FILE,
                        textAlign = data.align or DEFAULT_ALIGN,
                        imageSprite = data.imgS,
                        logoSprite  = data.logoS,
                        verified  = false,
                    }
                end
                setTag(other, tagData)
            end

            for target in pairs(tags) do
                if target ~= player and not broadcasting[target] then
                    removeTag(target)
                end
            end
        end)
        if not okLoop then
            warn("[nametag] sync error: " .. tostring(errLoop))
        end
        task.wait(PING_SECONDS)
    end
end)

local animConnection = RunService.Heartbeat:Connect(function()
    local clock = os.clock()
    local offset = ((clock * 0.6) % 2) - 1
    local camera = workspace.CurrentCamera

    for gradient in pairs(gradients) do
        if gradient.Parent then
            gradient.Offset = Vector2.new(offset, 0)
        else
            gradients[gradient] = nil
        end
    end

    for label, info in pairs(sprites) do
        if not label.Parent then
            sprites[label] = nil
        else
            local frame = math.floor(clock * info.meta.fps) % info.meta.frames
            if frame ~= info.last then
                setSpriteFrame(label, info, frame)
            end
        end
    end

    if camera then
        for gui, info in pairs(collapsing) do
            if not gui.Parent then
                collapsing[gui] = nil
            elseif info.head and info.head.Parent then
                local distance = (camera.CFrame.Position - info.head.Position).Magnitude

                local a = distance >= COLLAPSE_DISTANCE and 1 or 0

                local width = FULL_W + (SQUARE - FULL_W) * a
                gui.Size = UDim2.new(0, width, 0, FULL_H)

                if info.hasLogo and info.logo then
                    local logoLeft = LOGO_PAD + ((SQUARE - LOGO_SIZE) / 2 - LOGO_PAD) * a
                    info.logo.Position = UDim2.new(0, logoLeft, 0.5, 0)
                end

                for _, label in ipairs(info.texts) do
                    label.TextTransparency = a
                end

                if info.badge then
                    info.badge.Visible = (a == 0)
                end
            end
        end
    end
end)

local removingConn = Players.PlayerRemoving:Connect(function(leaving)
    removeTag(leaving)
    seen[leaving] = nil
end)

env[TAG_NAME] = function()
    running = false
    animConnection:Disconnect()
    removingConn:Disconnect()
    for target in pairs(tags) do
        removeTag(target)
    end
    table.clear(collapsing)
    table.clear(seen)
    table.clear(sprites)
end