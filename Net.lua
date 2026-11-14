----------------------------------------------------------------------
-- VoidBounty: the transport. WoW Forever refuses addon messages on channels; a hidden channel
-- PER FACTION is only a member list (who runs VoidBounty right now) and messages go by addon
-- whisper to its members (WhisperNet.lua, the same design as VoidGather / VoidSweep / VoidLayer).
-- A message for "the network" goes to up to SPREAD members, paced. Its line in the Void
-- "Players online" box is "VoidBounty online".
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local PREFIX = "VBNTY"
-- The channel (the user, 2026-11-14, after a ban from "VoidBountyvh88dn"): its name is a code like
-- the other Void addons' ("Vb" + 6 letters, it said "VoidBounty" in plain words) and it changes
-- every HOUR instead of every day, so a ban or a taken-over password lasts an hour at most. The
-- password can't stop that: the channel's first member owns it and can /ban, and anyone running
-- VoidBounty (or reading its code) knows the name and password.
local TAG, SALT = "Vb", 618233
local OLD_TAG = "VoidBounty"   -- 0.x's daily channel (left at login)
local HOUR = 3600
local function hourNow() return math.floor(((GetServerTime and GetServerTime()) or time()) / HOUR) end
local SPREAD = 12          -- members one network message goes to
local GAP = 0.35           -- seconds between whispers

----------------------------------------------------------------------
-- The owner guard (the user, 2026-11-14: "communicate who is owner and force giving owner over").
-- Only a channel's owner (and moderators the owner names) can ban, and only the owner can hand
-- ownership over (SetChannelOwner from addon code on a timer works on Forever: probed live 11-14,
-- "Owner changed to Death Bobb"). Nobody can take it. So:
--   * keep it: an owner that is leaving (logout / reload) hands it to a VoidBounty player in the
--     channel who has talked on the network; VoidBounty never names moderators, so while one of
--     ours owns the channel nobody can be banned;
--   * check it: every client reads who owns the channel (member list owner flag, owner-changed
--     notices). An owner nobody has heard from gets a ping ("O"); a VoidBounty client answers
--     ("o"). No answer to two pings, or the game refusing us (banned / other password), = the
--     channel was taken: move to the next backup channel of this hour (slot 1..3) and tell the
--     players we've heard from ("M"), so a friendly owner left behind follows. Every client
--     sees the same owner, so they all reach the same answer without a vote.
-- Limits: the check proves an owner runs VoidBounty's protocol, not that it means well (a
-- griefer can run the addon); the names are still worked out from public code (backups too).
-- What it buys: a plain /join with the password can't own the channel and ban for an hour any
-- more, and a ban moves everyone on within about a minute.
----------------------------------------------------------------------
-- Known gap: a player who logs in after the others moved starts on the main channel; if the
-- griefer still owns it, their own check moves them within ~1.5 min; if the griefer left, they sit
-- there alone until the hour ends (finding the others would need a second channel each, and
-- players are near the game's channel limit). A /reload keeps the hour's backup (VoidBountyDB).
local MAX_SLOT = 3
local PING_EVERY, PING_TRIES, PING_WAIT = 30, 3, 30   -- 3 pings 30 s apart, move 30 s after the last
local PEER_FRESH = 3600   -- a player heard from within this counts as a VoidBounty client
local TELL = 12           -- players told "we moved"

local Net = ns.WhisperNet
local net, CHANNEL, PW
local curHour, slot = nil, 0
local OLD = {}
local me
local queue, pumping = {}, false
local owner                -- the current channel's owner, as last seen
local pinged = {}          -- [name] = { n = pings sent, at = time of the last }
local peers = {}           -- [name] = time we last got a VoidBounty message from them
local seen = {}            -- [name] = time they were in our channel at a member-list read
local answered = {}        -- [name] = time we last answered their ping
-- Hostile (the user, 2026-11-14, "yes build both"): a player the game says banned or kicked
-- someone in our channel or changed its password. VoidBounty never does either, and the server
-- names who did it, so it can't be forged. (Not moderator changes: the server makes those
-- itself when an owner leaves, see noteHostile.) Never trusted, never answered, never handed the channel, never whispered; owning a
-- channel = everyone leaves it at once. This session only (names aren't saved).
local hostile = {}         -- [name] = reason
local G = { }              -- the guard's state, for /vbounty net and the tests
ns.NetGuard = G

local function secret(v) return issecretvalue and issecretvalue(v) or false end

local function chatLocked()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) or false
end

local function netIndex() return CHANNEL and (GetChannelName(CHANNEL) or 0) > 0 end

-- this hour's channel: slot 0 = the main one, 1..MAX_SLOT = the backups
local function channelFor(hour, s)
    return Net.DailyChannel(TAG, SALT + (s or 0), hour)
end

-- channels to leave; capped (one more every hour)
local function addOld(name)
    if not name or name == CHANNEL then return end
    for _, o in ipairs(OLD) do if o == name then return end end
    OLD[#OLD + 1] = name
    while #OLD > 24 do table.remove(OLD, 1) end
end

-- Our channel's join / leave / owner lines stay out of chat (a new channel lands in the main
-- chat window for a moment before join() takes it out; hourly that would be 24 lines a day).
local function ours(name)
    if type(name) ~= "string" then return false end
    name = name:lower()
    if CHANNEL and name == CHANNEL:lower() then return true end
    for _, o in ipairs(OLD) do if name == o:lower() then return true end end
    return false
end
function ns.HideNetNotice(_, _, notice, _, _, full, _, _, _, _, base)
    if secret(notice) or secret(full) or secret(base) then return false end
    local name = type(base) == "string" and base ~= "" and base
        or type(full) == "string" and full:match("^%d+%.%s*(.+)$") or full
    return ours(name)
end

-- VoidBountyDB.netLog (last 50): the game's ban / kick / owner / password notices on our
-- channels (2026-11-14: banned with no trace of who) and the guard's own moves.
local function logLine(kind, a, b, ch)
    VoidBountyDB = VoidBountyDB or {}
    local log = VoidBountyDB.netLog or {}
    VoidBountyDB.netLog = log
    log[#log + 1] = { t = time(), k = kind, a = a, b = b, ch = ch }
    while #log > 50 do table.remove(log, 1) end
end

local function pump()
    if pumping then return end
    pumping = true
    local function step()
        local job = table.remove(queue, 1)
        if not job then pumping = false return end
        -- turned hostile after it was queued: drop it
        while job and hostile[job.to] do job = table.remove(queue, 1) end
        if not job then pumping = false return end
        if chatLocked() and job.keep then
            -- guard traffic waits out the lockdown instead of being dropped
            table.insert(queue, 1, job)
            C_Timer.After(5, step)
            return
        end
        if not chatLocked() then
            net:Noted(job.to)
            local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, job.msg, "WHISPER", job.to)
            net:Sent(job.to, ok and res or nil)
        end
        C_Timer.After(GAP, step)
    end
    step()
end

-- Sharing without the channel (the user, 2026-11-14): the channel only FINDS players, messages
-- are whispers. Network messages go to members of the channel and, to fill up to SPREAD (or all
-- of it when we've lost the channel: banned, stuck), to players we heard from or saw in our
-- channel within the hour. So a ban costs finding NEW players, not the network. Names live in
-- memory only.
local function extras(k, used)
    local now, pool, out = time(), {}, {}
    for n, t in pairs(peers) do if now - t < PEER_FRESH then pool[#pool + 1] = n end end
    for n, t in pairs(seen) do
        local p = peers[n]
        if now - t < PEER_FRESH and (not p or now - p >= PEER_FRESH) then pool[#pool + 1] = n end
    end
    for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
    for _, n in ipairs(pool) do
        if #out >= k then break end
        if not used[n] and n ~= me and not hostile[n] and net:Reachable(n) then out[#out + 1] = n; used[n] = true end
    end
    return out
end

local function transport(msg, to, first)
    if not net then return false end
    if to then
        if hostile[to] then return false end
        -- guard traffic (ping / answer / moved) jumps the queue and survives a lockdown
        table.insert(queue, first and 1 or #queue + 1, { msg = msg, to = to, keep = first or nil })
    else
        local picks, used = {}, {}
        for _, name in ipairs(net:Pick(SPREAD)) do
            if not hostile[name] then picks[#picks + 1] = name; used[name] = true end
        end
        for _, name in ipairs(extras(SPREAD - #picks, used)) do picks[#picks + 1] = name end
        if #picks == 0 then return false end
        for _, name in ipairs(picks) do queue[#queue + 1] = { msg = msg, to = name } end
    end
    pump()
    return true
end

-- network housekeeping messages (ping / answer / moved) go straight out, never through the
-- writ switch or the demo board
local function sendTo(to, ...)
    local msg = ns.Bus.Pack(...)
    if msg and to then return transport(msg, to, true) end
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

local function freshPeer(name)
    local t = name and not hostile[name] and peers[name]
    return t and time() - t < PEER_FRESH or false
end

-- the owner flag from the member list; only called while WhisperNet is reading OUR list (the
-- list belongs to the selected channel, and the game can't say which one that is; see readOwner)
local function rosterOwner()
    local i = net and net:DisplayIndex()
    if not (i and C_ChatInfo and C_ChatInfo.GetChannelRosterInfo) then return nil end
    local _, _, _, _, count = GetChannelDisplayInfo(i)
    for r = 1, math.min(tonumber(count) or 0, 300) do
        local ok, name, isOwner = pcall(C_ChatInfo.GetChannelRosterInfo, i, r)
        if ok and isOwner == true and not secret(name) then return Net.Canon(name) end
    end
end

local guard, move

-- go to channel (hour, s): leave the one we're in, forget its owner, join, read its members
local function switchTo(hour, s)
    local name, pw = channelFor(hour, s)
    if name == CHANNEL then return end
    local was = CHANNEL
    CHANNEL, PW, curHour, slot = name, pw, hour, s
    addOld(was)
    owner, pinged = nil, {}
    G.channel, G.slot, G.owner = CHANNEL, slot, nil
    -- a /reload keeps this hour's backup (a new hour starts on the main channel anyway)
    VoidBountyDB = VoidBountyDB or {}
    VoidBountyDB.netSlot = s > 0 and { hour = hour, slot = s } or nil
    net:SetChannel(name)
    -- leave only once the queued "we moved" whispers are out (receivers check we were a member)
    C_Timer.After(2 + #queue * GAP, function() join(); C_Timer.After(3, function() net:RequestRoster(true) end) end)
end

-- "we moved to backup s": to the players heard from this hour that were in the channel with us
-- first (one may own it), then the others heard from; each client passes it on once (its own
-- move only happens once per slot, so it can't echo)
local function tellMoved(s)
    local told, n = {}, 0
    local function tell(name)
        if n < TELL and name and name ~= me and not told[name] and freshPeer(name) then
            told[name] = true; n = n + 1; sendTo(name, "M", s, curHour)
        end
    end
    tell(owner)
    -- from a random place in the member list: every player passing it on reaches different ones
    local list = net.roster or {}
    local start = #list > 0 and math.random(#list) or 1
    for k = 0, #list - 1 do tell(list[(start - 1 + k) % #list + 1]) end
    for name in pairs(peers) do tell(name) end
end

-- the channel was taken (or we're shut out): everyone on to this hour's next backup
function move(reason)
    if slot >= MAX_SLOT then
        if not G.stuck then G.stuck = true; logLine("NO_BACKUP_LEFT", reason, nil, CHANNEL) end
        return
    end
    logLine("MOVED", reason, nil, CHANNEL)
    local to = slot + 1
    tellMoved(to)
    switchTo(curHour, to)
    G.moves = (G.moves or 0) + 1
end

function guard()
    if not (net and CHANNEL) then return end
    if Net.Blocked(CHANNEL) or Net.Refused(CHANNEL) then return move("refused") end
    local o = owner
    if o and hostile[o] then return move("owner " .. o .. " is hostile (" .. hostile[o] .. ")") end
    if not o or o == me or freshPeer(o) then return end
    local p = pinged[o] or { n = 0, at = -PING_EVERY }
    pinged[o] = p
    local now = time()
    -- while the game holds whispers back (some fights) neither a ping nor its answer gets
    -- through: don't count, don't judge; the wait starts again after it
    if chatLocked() then
        if p.n > 0 then p.at = now end
        if not G.lockWait then
            G.lockWait = true
            C_Timer.After(PING_WAIT, function() G.lockWait = nil; guard() end)
        end
        return
    end
    if p.n >= PING_TRIES then
        if now - p.at >= PING_WAIT then return move("owner " .. o .. " never answered") end
        return
    end
    if now - p.at < PING_EVERY then return end
    p.n, p.at = p.n + 1, now
    logLine("PING", o, tostring(p.n), CHANNEL)
    sendTo(o, "O", CHANNEL)
    C_Timer.After(PING_EVERY + 1, guard)
end

local function setOwner(name)
    name = Net.Canon(name)
    if not name or secret(name) then return end
    owner = name
    G.owner = name
    guard()
end

local reading = false   -- true while WhisperNet reads our member list (see Net.New below)
local function freshCount()
    local n, now = 0, time()
    for name, t in pairs(peers) do
        if now - t < PEER_FRESH and not hostile[name] and (not net or net:Reachable(name)) then n = n + 1 end
    end
    return n
end
-- An owner keeps a successor ready (live 11-14: on a quiet network the members never message
-- the owner, so at logout it had nobody it knew to hand the channel to): at each read of the
-- member list it pings up to 2 members it hasn't heard from (each at most every 10 min); their
-- answers make them players it can hand the channel to.
local SUCCESSOR_PINGS, SUCCESSOR_EVERY = 2, 600
local successorAsked = {}
local function readySuccessor()
    if not (owner and owner == me) then return end
    local now, n = time(), 0
    for _, name in ipairs(net.roster or {}) do
        if n >= SUCCESSOR_PINGS then return end
        if name ~= me and not hostile[name] and not freshPeer(name)
            and now - (successorAsked[name] or -SUCCESSOR_EVERY) >= SUCCESSOR_EVERY then
            successorAsked[name] = now
            n = n + 1
            sendTo(name, "O", CHANNEL)
        end
    end
end

local function publish()
    if net then
        if reading then
            local now = time()
            for _, name in ipairs(net.roster or {}) do seen[name] = now end
        end
        local o = reading and rosterOwner()
        if o then setOwner(o) else guard() end
        if reading then readySuccessor() end
    end
    if not (_G.VoidPresence and net) then return end
    local others, note = net:Others(), Net.BlockNote(CHANNEL)
    -- sharing reaches the channel's members AND the players heard from this hour (a ban or a
    -- move to an empty backup doesn't cut them off): count whichever is more, no "blocked"
    local fc = freshCount()
    if fc > 0 then others, note = math.max(others or 0, fc), nil end
    _G.VoidPresence:Set("VoidBounty", "VoidBounty online", others or 0, false, others ~= nil, note)
end

-- the game's word on who did what in our channel (arg2 / arg5 as in its chat code: "x banned
-- y" = arg2 banned by arg5)
local function noteHostile(kind, a2, a5)
    local who, why
    if kind == "PLAYER_BANNED" or kind == "PLAYER_KICKED" then
        who, why = a5, kind == "PLAYER_BANNED" and "banned " .. tostring(a2) or "kicked " .. tostring(a2)
    elseif kind == "PASSWORD_CHANGED" then
        who, why = a2, "changed the password"
    end
    -- NOT SET_MODERATOR (live 11-14, 0.3.4 bug): the server itself names a moderator when the owner
    -- leaves ("SET_MODERATOR Vede", then "OWNER_CHANGED Vede Tinkerline" at the hourly switch), so
    -- the departing VoidBounty owner was marked hostile and the network split every hour.
    who = Net.Canon(who)
    if not who or who == me or hostile[who] then return end
    hostile[who] = why
    G.hostile = hostile
    logLine("HOSTILE", who, why, CHANNEL)
    C_Timer.After(1, guard)
end

-- leaving (logout or /reload: the game can't tell them apart here) while we own the channel:
-- hand it to a VoidBounty player in it, so it doesn't fall to whoever the server picks
local function handOver()
    if not (net and CHANNEL and owner and owner == me) then return end
    for _, name in ipairs(net.roster or {}) do
        if name ~= me and freshPeer(name) then
            pcall(SetChannelOwner, CHANNEL, name)
            return name
        end
    end
end
G.HandOver = handOver
G.Check = function() guard() end

-- ping / answer / moved
ns.Bus.On("O", function(f, sender)   -- "are you VoidBounty?": answer, at most every 30 s each
    if hostile[sender] then return end
    local now = time()
    if answered[sender] and now - answered[sender] < 30 then return end
    answered[sender] = now
    sendTo(sender, "o", f[2])
end)
ns.Bus.On("o", function() end)        -- the answer: hearing it at all is the point (peers[])
ns.Bus.On("M", function(f, sender)    -- "we moved to backup s of hour h"
    local s, h = tonumber(f[2]), tonumber(f[3])
    if not (s and h) or s ~= math.floor(s) or h ~= curHour or s <= slot or s > MAX_SLOT then return end
    -- only from a player heard from (within the hour) before this message who was in our channel
    -- at the last read of its members: a channel-mate saw it taken. (A griefer who runs the
    -- protocol and sits in the channel can still move everyone, at most MAX_SLOT times an hour.)
    if not G.knewSender then return end
    local mate = false
    for _, name in ipairs(net and net.roster or {}) do if name == sender then mate = true break end end
    if not mate then return end
    logLine("FOLLOWED", sender, tostring(s), CHANNEL)
    tellMoved(s)   -- pass it on once (players the mover didn't reach)
    switchTo(curHour, s)
end)

function ns.NetOthers() return net and net:Others() end
function ns.NetReport()
    local o = net and net:Others()
    ns.say(("network: %s other VoidBounty player%s online · sent %d, heard %d from %d player%s."):format(
        o and tostring(o) or "?", o == 1 and "" or "s", ns.Bus.sent, ns.Bus.heard,
        (function() local n = 0 for _ in pairs(ns.Bus.people) do n = n + 1 end return n end)(),
        ""))
    if CHANNEL then
        ns.say(("channel %s%s · owner %s"):format(slot > 0 and "backup " or "", slot > 0 and tostring(slot) or "main",
            owner and (owner == me and "you" or owner .. (freshPeer(owner) and " (VoidBounty)" or " (not heard from)")) or "not seen yet"))
    end
    local why = CHANNEL and Net.BlockReason(CHANNEL)
    if why then
        ns.say(why .. (freshCount() > 0 and (" Still sharing by whisper with %d player%s heard from this hour."):format(freshCount(), freshCount() == 1 and "" or "s") or ""))
    end
    for name, reason in pairs(hostile) do ns.say(("hostile: %s (%s); avoided this session."):format(name, reason)) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
f:SetScript("OnEvent", function(_, ev, prefix, msg, dist, sender, a5, _, _, _, a9)
    if ev == "CHAT_MSG_CHANNEL_NOTICE_USER" then
        -- arg1 = what ("PLAYER_BANNED", "OWNER_CHANGED", "CHANNEL_OWNER", ...), arg2 = the player
        -- it names, arg5 = the second one ("x banned y"), arg9 = the channel
        if secret(prefix) or secret(msg) or secret(a5) or secret(a9) or type(prefix) ~= "string" or not ours(a9) then return end
        logLine(prefix, type(msg) == "string" and msg or nil, type(a5) == "string" and a5 ~= "" and a5 or nil, a9)
        if CHANNEL and a9:lower() == CHANNEL:lower() then
            if prefix == "OWNER_CHANGED" or prefix == "CHANNEL_OWNER" then setOwner(msg) end
            noteHostile(prefix, type(msg) == "string" and msg or nil, type(a5) == "string" and a5 ~= "" and a5 or nil)
        end
        return
    elseif ev == "CHAT_MSG_CHANNEL_NOTICE" then
        -- refused at the door (banned / other password): on to the backup, no need to wait.
        -- NOT_ALLOWED_IN_CHANNEL names no channel: check a moment later (guard asks the game
        -- whether ours is the one listed disabled)
        if secret(prefix) or secret(a9) or not CHANNEL then return end
        if prefix == "NOT_ALLOWED_IN_CHANNEL" then C_Timer.After(2, guard) return end
        if type(a9) == "string" and a9:lower() == CHANNEL:lower() and (prefix == "WRONG_PASSWORD" or prefix == "BANNED") then
            C_Timer.After(1, guard)
        end
        return
    elseif ev == "PLAYER_LOGOUT" then
        handOver()
        return
    end
    if ev == "PLAYER_LOGIN" then
        if not (Net and Net.Active()) then return end
        local hour = hourNow()
        -- after a /reload: the backup of this hour we were on
        local kept = type(VoidBountyDB) == "table" and type(VoidBountyDB.netSlot) == "table" and VoidBountyDB.netSlot
        local s0 = kept and kept.hour == hour and tonumber(kept.slot) or 0
        if s0 ~= math.floor(s0) or s0 < 0 or s0 > MAX_SLOT then s0 = 0 end
        curHour, slot = hour, s0
        CHANNEL, PW = channelFor(hour, s0)
        G.channel, G.slot = CHANNEL, s0
        for _, old in ipairs(Net.OldDailyChannels(TAG, SALT, hour)) do addOld(old) end
        for _, old in ipairs(Net.OldDailyChannels(OLD_TAG, SALT)) do addOld(old) end
        addOld((Net.DailyChannel(OLD_TAG, SALT)))
        -- every other channel of this hour and the last (main + backups), a reload may have left us in
        for s = 0, MAX_SLOT do addOld((channelFor(hour, s))); addOld((channelFor(hour - 1, s))) end
        local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
        if addFilter then
            addFilter("CHAT_MSG_CHANNEL_NOTICE", ns.HideNetNotice)
            addFilter("CHAT_MSG_CHANNEL_NOTICE_USER", ns.HideNetNotice)
        end
        net = Net.New(CHANNEL, publish, {})
        -- the owner is read only inside a real read of OUR member list (WhisperNet calls publish
        -- from it, but also after whisper bounces, when another channel may be selected)
        local readRoster = net.ReadRoster
        net.ReadRoster = function(self, ...)
            reading = true
            local ok, err = pcall(readRoster, self, ...)
            reading = false
            if not ok then error(err, 0) end
        end
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
        -- on the hour (server time): everyone moves to the new hour's main channel together;
        -- checked every 15 s so players are apart for seconds, not a minute
        C_Timer.NewTicker(15, function()
            local h = hourNow()
            if h ~= curHour then G.stuck = nil; switchTo(h, 0) end
        end)
    elseif ev == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or dist ~= "WHISPER" then return end
        local who = ns.Bus.CleanName(Net.Canon(sender))
        G.knewSender = who and freshPeer(who) or false
        local accepted = ns.Bus.Receive(msg, Net.Canon(sender), me)
        G.knewSender = nil
        -- a message the bus accepted (known kind, valid, under the rate limit) proves its sender
        -- runs VoidBounty: an owner we hear from is fine
        if accepted and who and who ~= me then
            local new = not freshPeer(who)
            peers[who] = time()
            if who == owner then pinged[who] = nil end
            -- a player we hadn't heard from: the box counts them now, not at the next member-list
            -- read (up to 5 min; the user, 11-14: "why does it still say 0 on my screen")
            if new then publish() end
        end
    end
end)
