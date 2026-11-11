----------------------------------------------------------------------
-- VoidBounty: the transport. WoW Forever refuses addon messages on channels; a hidden daily
-- channel PER FACTION is only a member list (who runs VoidBounty right now) and messages go by
-- addon whisper to its members (WhisperNet.lua, the same design as VoidGather / VoidSweep /
-- VoidLayer). A message for "the network" goes to up to SPREAD members, paced. Its line in the
-- Void "Players online" box is "VoidBounty online".
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local PREFIX = "VBNTY"
local TAG, SALT = "VoidBounty", 618233
local SPREAD = 12          -- members one network message goes to
local GAP = 0.35           -- seconds between whispers

local Net = ns.WhisperNet
local net, CHANNEL, PW
local OLD = {}
local me
local queue, pumping = {}, false

local function chatLocked()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) or false
end

local function netIndex() return CHANNEL and (GetChannelName(CHANNEL) or 0) > 0 end

local function publish()
    if not (_G.VoidPresence and net) then return end
    local others = net:Others()
    _G.VoidPresence:Set("VoidBounty", "VoidBounty online", others or 0, false, others ~= nil, Net.BlockNote(CHANNEL))
end

local function pump()
    if pumping then return end
    pumping = true
    local function step()
        local job = table.remove(queue, 1)
        if not job then pumping = false return end
        if not chatLocked() then
            net:Noted(job.to)
            local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, job.msg, "WHISPER", job.to)
            net:Sent(job.to, ok and res or nil)
        end
        C_Timer.After(GAP, step)
    end
    step()
end

local function transport(msg, to)
    if not net then return false end
    if to then
        queue[#queue + 1] = { msg = msg, to = to }
    else
        local picks = net:Pick(SPREAD)
        if #picks == 0 then return false end
        for _, name in ipairs(picks) do queue[#queue + 1] = { msg = msg, to = name } end
    end
    pump()
    return true
end

local function join()
    if chatLocked() then C_Timer.After(30, join) return end
    for _, old in ipairs(OLD) do
        if (GetChannelName(old) or 0) > 0 then LeaveChannelByName(old) end
    end
    if not netIndex() then JoinTemporaryChannel(CHANNEL, PW) end
    C_Timer.After(1, function()
        if netIndex() and ChatFrame_RemoveChannel then
            for i = 1, (NUM_CHAT_WINDOWS or 10) do
                local cf = _G["ChatFrame" .. i]
                if cf then ChatFrame_RemoveChannel(cf, CHANNEL) end
            end
        end
    end)
end

function ns.NetOthers() return net and net:Others() end
function ns.NetReport()
    local o = net and net:Others()
    ns.say(("network: %s other VoidBounty player%s online · sent %d, heard %d from %d player%s."):format(
        o and tostring(o) or "?", o == 1 and "" or "s", ns.Bus.sent, ns.Bus.heard,
        (function() local n = 0 for _ in pairs(ns.Bus.people) do n = n + 1 end return n end)(),
        ""))
    local why = CHANNEL and Net.BlockReason(CHANNEL)
    if why then ns.say(why) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, ev, prefix, msg, dist, sender)
    if ev == "PLAYER_LOGIN" then
        if not (Net and Net.Active()) then return end
        local today
        CHANNEL, PW, today = Net.DailyChannel(TAG, SALT)
        for _, old in ipairs(Net.OldDailyChannels(TAG, SALT, today)) do OLD[#OLD + 1] = old end
        net = Net.New(CHANNEL, publish, {})
        me = Net.Me()
        ns.Me = me
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        ns.Bus.transport = transport
        C_Timer.After(9, function()
            join()
            C_Timer.After(3, function()
                net:RequestRoster(true)
                C_Timer.After(5, function() publish(); if ns.OnNetReady then ns.OnNetReady() end end)
            end)
        end)
        C_Timer.NewTicker(300, function() net:RequestRoster(false); publish() end)
        if _G.VoidPresence then _G.VoidPresence:Listen(function() net:RequestRoster(true); publish() end) end
        -- 00:00 UTC: everyone moves to the new day's channel together
        C_Timer.NewTicker(60, function()
            local name, pw = Net.DailyChannel(TAG, SALT)
            if name == CHANNEL then return end
            OLD[#OLD + 1] = CHANNEL
            CHANNEL, PW = name, pw
            net:SetChannel(name)
            C_Timer.After(2, function() join(); C_Timer.After(3, function() net:RequestRoster(true) end) end)
        end)
    elseif ev == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or dist ~= "WHISPER" then return end
        ns.Bus.Receive(msg, Net.Canon(sender), me)
    end
end)
