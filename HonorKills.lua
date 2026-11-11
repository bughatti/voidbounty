----------------------------------------------------------------------
-- VoidBounty: your kills, in game, for every player (the user, 11-11: "why cant others have it
-- to, to record who they killed"; "build the in-game kill list for everyone").
--
-- Forever seals the combat log from addons, and the honorable-kill event doesn't say who died.
-- So: watch the enemy players around you (target, focus, mouseover, nameplates, your party's
-- targets) and note the moment one of them is dead. When the honorable-kill counter goes up a
-- moment later, the most recent of those deaths is your kill.
--
-- An honorable kill is HONOR CREDIT (you helped), not the killing blow. Where the combat log
-- reader runs (KillProof.lua, ns.KILLS), a kill that also shows in the log file is marked
-- "killing blow". Only the open world counts: in a battleground or dungeon the kill is only
-- counted there (and battlegrounds hide who players are anyway).
--
-- VoidBountyCharDB.hks = { { t, guid, name, level, class, zone }, ... } (last 200)
-- VoidBountyCharDB.hkElsewhere = { bg = n, instance = n }
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local KEEP = 200
local MATCH_FOR = 6        -- seconds between a death we saw and the honorable kill
local safe, secret, plain = ns.safe, ns.secret, ns.plain

local deaths = {}          -- [guid] = GetTime() we saw them dead
local credited = {}        -- [guid] = time() of the last kill recorded on them

local function units()
    local u = { "target", "focus", "mouseover" }
    for i = 1, 40 do u[#u + 1] = "nameplate" .. i end
    for i = 1, 4 do u[#u + 1] = "party" .. i .. "target" end
    return u
end
local UNITS = units()

-- an enemy player who is dead right now: remember when
local function check(unit)
    if not ns.IsEnemy(unit) then return end
    local guid = safe(UnitGUID, unit)
    if not guid or secret(guid) or not guid:find("^Player%-") then return end
    local dead = plain(safe(UnitIsDeadOrGhost, unit))
    if dead and not deaths[guid] then deaths[guid] = GetTime() end
    if not dead and deaths[guid] and GetTime() - deaths[guid] > 30 then deaths[guid] = nil end   -- back up
end

local function scan()
    if ns.InBattle() then return end
    for _, u in ipairs(UNITS) do
        if safe(UnitExists, u) then check(u) end
    end
end

local function hkList()
    local c = ns.char()
    c.hks = c.hks or {}
    return c.hks
end
ns.HonorKills = hkList

local function elsewhere(kind)
    local c = ns.char()
    c.hkElsewhere = c.hkElsewhere or { bg = 0, instance = 0 }
    c.hkElsewhere[kind] = (c.hkElsewhere[kind] or 0) + 1
end

-- one honorable kill (the counter went up)
local function oneKill()
    local inside, kind = IsInInstance()
    if inside then
        elsewhere((kind == "pvp" or kind == "arena") and "bg" or "instance")
        ns.Log("hk", ("honorable kill in a %s (counted there, not listed)"):format((kind == "pvp" or kind == "arena") and "battleground" or "dungeon"))
        if ns.Changed then ns.Changed("hk") end
        return
    end
    scan()   -- the death may be this very frame
    local now, best, bestT = GetTime(), nil, -1
    for guid, t in pairs(deaths) do
        if now - t <= MATCH_FOR and t > bestT and not (credited[guid] and time() - credited[guid] < 60) then best, bestT = guid, t end
    end
    local e = best and ns.db().seen[best]
    local rec = { t = time(), zone = GetZoneText and GetZoneText() or "?" }
    if best then
        credited[best] = time()
        rec.guid, rec.name = best, e and e.name
        rec.level, rec.class = e and e.level, e and e.class
    end
    local c = ns.char()
    c.hkWorld = (c.hkWorld or #hkList()) + 1   -- the running total (the list keeps the last KEEP)
    local list = hkList()
    table.insert(list, rec)
    while #list > KEEP do table.remove(list, 1) end
    ns.Log("hk", ("honorable kill: %s in %s"):format(rec.name or "someone we didn't see die", rec.zone))
    if ns.Changed then ns.Changed("hk") end
end

-- the event can fire without a new kill (login, zoning): count only what the game's own counter
-- (honorable kills today) went up by. Two kills at once count twice.
local lastHK
local function sessionHK()
    local n = plain(safe(GetPVPSessionStats))
    return type(n) == "number" and n or nil
end
local function onHonorKill()
    local n = sessionHK()
    if not n then oneKill() return end   -- no counter: trust the event
    local delta = lastHK and (n - lastHK) or 0
    lastHK = n
    -- every kill is counted; past 10 at once only the count goes up (Codex 11-11: extras were lost)
    for i = 1, math.max(delta, 0) do
        if i <= 10 then oneKill()
        else
            local c = ns.char()
            local inside, kind = IsInInstance()
            if not inside then c.hkWorld = (c.hkWorld or #hkList()) + 1
            else elsewhere((kind == "pvp" or kind == "arena") and "bg" or "instance") end
        end
    end
end

-- a kill from the log file on the same player within a minute = the killing blow was yours
function ns.KillingBlow(rec)
    if not (ns.KILLS and rec.guid) then return false end
    for _, k in ipairs(ns.Kills and ns.Kills() or {}) do
        if k.victim == rec.guid and math.abs((k.t or 0) - rec.t) <= 60 then return true end
    end
    return false
end

-- open-world honorable kills (with a name or not)
function ns.HonorKillCount()
    return ns.char().hkWorld or #hkList()
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_PVP_KILLS_CHANGED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
pcall(f.RegisterEvent, f, "UNIT_HEALTH")
pcall(f.RegisterEvent, f, "UNIT_FLAGS")
local tracked = {}
for _, u in ipairs(UNITS) do tracked[u] = true end
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, ev, unit)
    if ev == "PLAYER_ENTERING_WORLD" then lastHK = sessionHK()   -- the baseline (it resets each day)
    elseif ev == "PLAYER_PVP_KILLS_CHANGED" then onHonorKill()
    elseif ev == "PLAYER_TARGET_CHANGED" then check("target")
    elseif ev == "UPDATE_MOUSEOVER_UNIT" then check("mouseover")
    elseif unit and tracked[unit] and not ns.InBattle() then check(unit) end
end)
-- old deaths go
C_Timer.NewTicker(30, function()
    local now = GetTime()
    for g, t in pairs(deaths) do if now - t > 120 then deaths[g] = nil end end
    local t0 = time()
    for g, t in pairs(credited) do if t0 - t > 120 then credited[g] = nil end end   -- Codex 11-11: it never shrank
end)
