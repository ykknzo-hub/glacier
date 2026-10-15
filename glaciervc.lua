local clonereference = cloneref or function(...) return ... end
local clonefunction = clonefunction or function(...) return ... end

local voicechatservice = clonereference(game:GetService("VoiceChatService"))
local voicechatinternal = clonereference(game:GetService("VoiceChatInternal"))
local startergui = game:GetService("StarterGui")
local players = game:GetService("Players")
local localplayer = players.LocalPlayer
local getconnectionsfunc = clonefunction(getconnections)

local mutedimage = "rbxasset://textures/ui/VoiceChat/MicLight/Muted.png"
local hiddenfolder = Instance.new("Folder", game:GetService("RobloxReplicatedStorage"))

local unibarcontainer, micmutebutton

pcall(function()
    for i, v in ipairs(game:GetService("CoreGui"):GetDescendants()) do
        if v.Name == "toggle_mic_mute" then
            micmutebutton = v
            unibarcontainer = v.Parent
            break
        end
    end
end)

local function geticonlabel(button)
    button = button or micmutebutton
    return button:WaitForChild("IntegrationIconFrame", 15):WaitForChild("IntegrationIcon", 15)["1"]
end

local function getcurrentmutestate()
    return voicechatinternal:IsPublishPaused()
end

local function setmutestate(state)
    voicechatinternal:PublishPause(state)
end

if not micmutebutton then 
    voicechatservice:joinVoice() 
    pcall(function()
        if unibarcontainer then
            micmutebutton = unibarcontainer:WaitForChild("toggle_mic_mute", 15)
        end
    end)
end

if not micmutebutton then return print("Mic button not found") end

startergui:SetCore("SendNotification", {Title = "created by masklol,dm me for issue", Text = "Unmute to continue.", Duration = 5})

repeat task.wait(2) until geticonlabel().Image ~= mutedimage

voicechatservice:leaveVoice()
task.wait(2)

local connections = getconnectionsfunc(voicechatinternal.StateChanged)
for i = 7, #connections do 
    if connections[i] then connections[i]:Disable() end
end

task.wait(2)
voicechatservice:joinVoice()

pcall(function()
    if unibarcontainer then
        micmutebutton = unibarcontainer:WaitForChild("toggle_mic_mute", 15)
    end
end)

if micmutebutton and unibarcontainer then
    local clonedmutebutton = micmutebutton:Clone()
    micmutebutton.Parent = hiddenfolder
    clonedmutebutton.Name = "toggle_mic_mute_new"
    clonedmutebutton.Parent = unibarcontainer

    local clonedicon = geticonlabel(clonedmutebutton)
    local originalicon = geticonlabel(micmutebutton)

    setmutestate(true)
    clonedicon.Image = mutedimage

    clonedmutebutton:WaitForChild("IconHitArea_toggle_mic_mute", 15).Activated:Connect(function()
        local newstate = not getcurrentmutestate()
        setmutestate(newstate)
        if newstate then
            clonedicon.Image = mutedimage
        else
            clonedicon.Image = originalicon.Image
        end
    end)
end