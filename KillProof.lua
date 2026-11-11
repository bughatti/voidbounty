----------------------------------------------------------------------
-- VoidBounty: kill proof from the combat log FILE (stage 2).
--
-- WoW Forever seals the combat log from addons (C_CombatLogSecure, |K-wrapped chat lines), but
-- the client's WoWCombatLog file writes a PARTY_KILL line for every killing blow, with both
-- players' GUIDs. The VoidScout desktop program (for now tools/cmd/vb-kills -watch) reads it and
-- writes YOUR killing blows on players into Kills.lua (VoidBountyKills); a /reload loads it.
-- Proven 2026-11-10: "Bh Ko" killed 23:12:24 -> Kills.lua -> in game, matched to the HK counter.
--
-- Auto logging (the user: "check if its on first, then if its not turn it on"):
--   on   PvP-flagged, out in the world, not resting, logging off -> we turn it on and own it
--   off  only a log we own, 5 min unflagged / resting, out of combat, never in an instance;
--        zoning into an instance hands it over (left on), so VoidScout's dungeon log isn't cut
-- The game buffers the file for MINUTES and a /reload doesn't write it out (11:09 -> 11:14 in
-- WSG): after a fight with an enemy player, if we own the log, close and reopen it (that's what
-- writes it) so the kill reaches the file now.
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local OFF_AFTER = 300

function ns.Kills() return _G.VoidBountyKills or {} end

local calmSince
local function clState()
    local d = ns.realDB()
    if not LoggingCombat then return end
    if not ns.KILLS then
        -- no kill reader on this PC: the log only proves kills, so never touch it; one we turned
        -- on before (an earlier version) goes back off, once
        -- clOwned stays until it really went off (in combat it waits for the next check; Codex 11-11)
        if d.clOwned and not LoggingCombat() then d.clOwned = nil end
        if d.clOwned and not IsInInstance() and not InCombatLockdown() then LoggingCombat(false); d.clOwned = nil end
        if d.clOwned and IsInInstance() then d.clOwned = nil end   -- a dungeon log is the player's to keep
        calmSince = nil
        return
    end
    local inInstance = IsInInstance()
    local on = LoggingCombat()
    if inInstance then
        d.clOwned, calmSince = nil, nil   -- hand over, leave it as it is
        return
    end
    if ns.char().autolog == false then return end
    local want = UnitIsPVP("player") and not IsResting()
    if want then
        calmSince = nil
        if not on and pcall(LoggingCombat, true) and LoggingCombat() then
            d.clOwned = true
            ns.Log("log", "combat log turned ON (PvP-flagged)")
            ns.say("combat log ON (you're PvP-flagged): it's how your kills are proven. Off again 5 min after you're not.")
        end
    elseif d.clOwned and on then
        calmSince = calmSince or GetTime()
        if GetTime() - calmSince >= OFF_AFTER and not InCombatLockdown() then
            LoggingCombat(false)
            d.clOwned, calmSince = nil, nil
            ns.Log("log", "combat log turned OFF (5 min after PvP)")
        end
    else
        calmSince = nil
        if d.clOwned and not on then d.clOwned = nil; ns.Log("log", "someone else turned the combat log off") end   -- someone else turned it off
    end
end
ns.LogState = clState

-- write the buffered log to disk now: close + reopen (only our own log)
local lastFlush = 0
function ns.FlushLog(why)
    if not ns.KILLS then return false end
    local d = ns.realDB()
    if not (LoggingCombat and d.clOwned and LoggingCombat()) or GetTime() - lastFlush < 20 then return false end
    lastFlush = GetTime()
    ns.Log("log", "flushed after " .. tostring(why))
    LoggingCombat(false)
    C_Timer.After(0.3, function()
        if d.clOwned and not IsInInstance() then pcall(LoggingCombat, true) end
    end)
    return true
end

local function myWrits()
    local me, n = ns.Me or GetUnitName("player"), 0
    for _, w in pairs(ns.Writs()) do
        if w.hunters and w.hunters[me] and ns.Status(w) == "open" then n = n + 1 end
    end
    return n
end

-- after a fight that had an enemy player in it: write the log so the kill is on disk
local pvpFight = false
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_FLAGS_CHANGED")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(f.RegisterEvent, f, "PLAYER_PVP_KILLS_CHANGED")
f:SetScript("OnEvent", function(_, ev, unit)
    if ev == "PLAYER_LOGIN" then
        local d = ns.realDB()
        d.mine = d.mine or {}
        local g = UnitGUID("player")
        if g and not ns.secret(g) then d.mine[g] = true end
        C_Timer.NewTicker(15, clState)
        -- kills the reader wrote since the last load: claim writs we hold
        C_Timer.After(12, function()
            if not ns.KILLS then return end
            local seen = d.killsSeen or {}
            d.killsSeen = seen
            for _, k in ipairs(ns.Kills()) do
                local key = (k.victim or "") .. "@" .. tostring(k.t)
                if k.killer == g and not seen[key] then
                    seen[key] = true
                    ns.Log("kill", ("from the log file: %s at %s in %s"):format(k.name or "?", date("%m-%d %H:%M", math.floor(k.t or 0)), k.zone or "?"))
                    ns.ClaimFromLog(k)
                end
            end
        end)
    elseif ev == "PLAYER_FLAGS_CHANGED" and unit ~= "player" then
        return
    elseif ev == "PLAYER_REGEN_DISABLED" then
        pvpFight = false
        return
    elseif ev == "PLAYER_REGEN_ENABLED" then
        if pvpFight and not ns.InBattle() and ns.FlushLog("fight") and myWrits() > 0 then
            ns.say("fight written to the combat log. /reload when it suits you to check your writ kills.")
        end
        pvpFight = false
        return
    elseif ev == "PLAYER_PVP_KILLS_CHANGED" then
        pvpFight = true
        if not ns.InBattle() then ns.Log("hk", "honorable kill (log " .. (LoggingCombat and LoggingCombat() and "on" or "OFF") .. ")") end
        return
    end
    clState()
end)

-- an enemy player near you during a fight marks it as a PvP fight
ns.OnChange(function(what)
    if what == "near" and InCombatLockdown() then pvpFight = true end
end)
