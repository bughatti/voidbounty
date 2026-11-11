----------------------------------------------------------------------
-- VoidBounty: the data (WoW Forever only). Stage 1, 2026-11-10: local only, nothing is sent.
--
--   Sightings  enemy players seen by nameplate, target or mouseover in the open world
--              (battlegrounds hide who players are; skipped). Account-wide: VoidBountyDB.seen.
--   Nearby     who is around right now (in memory): drives the alert (Alert.lua).
--   Marked     per character (VoidBountyCharDB.marked): everyone who killed you, read from the
--              death recap, plus anyone you mark by hand. The blood debt a writ needs later.
--
-- Measured on Forever (VoidDev PvpProbe, 11-10): enemy name / level / class / race / guild /
-- PvP flag are readable in the open world; GUIDs are secret in battlegrounds; the death recap
-- names the killer ("Max Package") but has no GUID. Names have two parts: UnitName's second
-- return is the surname, not a realm (same server ID gave "Bi" and "Kekyy"); the server is
-- the number in the GUID (Player-<server>-...).
--
-- The user OK'd keeping ENEMY player names for this feature only (2026-11-10).
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end   -- WoW Forever only

local MAX_SEEN = 1000          -- sightings kept (oldest dropped)
local NEAR_FOR = 25            -- seconds someone stays "nearby" after we last saw them
ns.NEAR_FOR = NEAR_FOR

local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function plain(v) if secret(v) then return nil end return v end
ns.safe, ns.secret, ns.plain = safe, secret, plain

function ns.db()
    if ns.demoDB then return ns.demoDB end     -- Demo.lua: a made-up board, never saved
    return ns.realDB()
end

-- the saved one, demo or not (KillProof: log ownership, my GUIDs, kills already claimed)
function ns.realDB()
    VoidBountyDB = VoidBountyDB or {}
    local d = VoidBountyDB
    d.seen = d.seen or {}
    return d
end

function ns.char()
    if ns.demoChar then return ns.demoChar end
    return ns.realChar()
end

function ns.realChar()
    VoidBountyCharDB = VoidBountyCharDB or {}
    local c = VoidBountyCharDB
    c.marked = c.marked or {}
    c.track = c.track or {}
    if c.shareSeen == nil then c.shareSeen = true end      -- send my sightings to my side
    if c.shareDeaths == nil then c.shareDeaths = true end  -- notoriety: "killed by X" to my side (the user: on by default)
    if c.alerts == nil then c.alerts = true end          -- the nearby line
    if c.sound == nil then c.sound = true end            -- a sound when a Marked player shows up
    if c.quiet == nil then c.quiet = true end
    if c.flash == nil then c.flash = true end            -- the red box flashes (the user, 11-11)            -- unmarked enemies: one quiet line
    return c
end

function ns.say(msg) print("|cff00c7ffVoidBounty|r: " .. msg) end

-- Writs (posters, taking, claims, tribute, payments, the auto combat log that proves kills) are
-- "coming soon" (the user, 11-11: release the warnings and tracking now, the bounty parts once
-- they're tested better). Off: their pages are hidden, the network neither sends nor takes their
-- messages (Bus.lua), and the combat log is never touched. A dev client can turn them on with
-- VoidBountyDB.devWrits = true (/vbounty writs, then /reload).
ns.WRITS = false
ns.KILLS = false
do
    local lf = CreateFrame("Frame")
    lf:RegisterEvent("ADDON_LOADED")
    lf:SetScript("OnEvent", function(self, _, name)
        if name ~= ADDON then return end
        ns.WRITS = (VoidBountyDB and VoidBountyDB.devWrits == true) or false
        -- kills from the combat log FILE (KillProof.lua): only where a reader program writes Kills.lua
        -- and marks it (the user, 11-11: "record kills, that is a part that needs to be tested").
        -- The Kills.lua that ships is empty and unmarked: other players' combat log is never touched.
        ns.KILLS = ns.WRITS or _G.VoidBountyKillsReader == true
        self:UnregisterAllEvents()
    end)
end

-- A quiet test log (the user, 11-11: "we will test it for a few days"): what happened, read from
-- the SavedVariables afterwards, so the player never has to remember or report anything. Last 300.
function ns.Log(kind, text)
    local d = ns.realDB()
    d.log = d.log or {}
    local z = GetZoneText and GetZoneText() or "?"
    table.insert(d.log, { t = time(), k = kind, z = z, s = text })
    while #d.log > 300 do table.remove(d.log, 1) end
end

-- Battlegrounds / arenas: identities are hidden there and it isn't world PvP.
local function inBattle()
    local inside, kind = IsInInstance()
    return inside and (kind == "pvp" or kind == "arena")
end
ns.InBattle = inBattle

local myFaction
local function isEnemy(unit)
    if not safe(UnitIsPlayer, unit) then return false end
    myFaction = myFaction or UnitFactionGroup("player")
    local fac = safe(UnitFactionGroup, unit)
    if not fac or secret(fac) then return false end
    return fac ~= myFaction and (fac == "Alliance" or fac == "Horde")
end
ns.IsEnemy = isEnemy

-- "Jungle Bear": first name + surname (UnitName's second return on Forever)
local function fullName(unit)
    local n, sur = safe(UnitName, unit)
    if not n or secret(n) or n == "" or n == UNKNOWNOBJECT then return nil end
    if sur and not secret(sur) and sur ~= "" then return n .. " " .. sur end
    return n
end
ns.FullName = fullName

function ns.Server(guid)
    return guid and tonumber(guid:match("^Player%-(%d+)%-"))
end

local function where()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local zone = GetZoneText and GetZoneText() or ""
    if sub ~= "" and sub ~= zone then return sub .. ", " .. zone end
    return zone
end
ns.Where = where

----------------------------------------------------------------------
-- Sightings + nearby
----------------------------------------------------------------------
ns.near = {}            -- [guid] = GetTime() last seen
local listeners = {}
function ns.OnChange(fn) listeners[#listeners + 1] = fn end
local function changed(what, guid, isNew)
    for _, fn in ipairs(listeners) do pcall(fn, what, guid, isNew) end
end

local function trim(s)
    local n, oldest, oldestT = 0, nil, math.huge
    for g, e in pairs(s) do
        n = n + 1
        if (e.last or 0) < oldestT then oldest, oldestT = g, e.last or 0 end
    end
    if n > MAX_SEEN and oldest then s[oldest] = nil end
end

ns.TrimSeen = function() trim(ns.db().seen) end

local function look(unit, how)
    if inBattle() or not isEnemy(unit) then return end
    local guid = safe(UnitGUID, unit)
    if not guid or secret(guid) or not guid:find("^Player%-") then return end
    local name = fullName(unit)
    if not name then return end
    local s = ns.db().seen
    local e = s[guid]
    if not e then
        e = { first = time(), last = time(), n = 0 }   -- last first: trim drops the oldest (Codex 11-11)
        s[guid] = e
        trim(s)
    end
    local _, cls = safe(UnitClass, unit)
    local lvl = plain(safe(UnitLevel, unit))
    e.name = name
    e.class = plain(cls) or e.class
    e.race = plain(safe(UnitRace, unit)) or e.race
    e.guild = plain(safe(GetGuildInfo, unit)) or e.guild
    if lvl and lvl > 0 then e.level = lvl end
    e.faction = plain(safe(UnitFactionGroup, unit)) or e.faction
    e.last, e.n, e.how = time(), (e.n or 0) + 1, how
    e.where, e.map, e.zone = where(), C_Map.GetBestMapForUnit("player"), GetZoneText and GetZoneText() or nil
    -- where you were: an AREA (5% grid), never a live position (anti-harassment rule)
    local pos = e.map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(e.map, "player")
    if pos then
        local px, py = pos:GetXY()
        if px and px > 0 then e.ax, e.ay = math.floor(px * 20 + 0.5), math.floor(py * 20 + 0.5) end
    end
    ns.Habit(e, e.zone, time())
    -- keep a Marked entry's details fresh; a killer known only by name gets their GUID now
    local marked = ns.char().marked
    if not marked[guid] and marked["name:" .. name] then
        marked[guid], marked["name:" .. name] = marked["name:" .. name], nil
    end
    local m = marked[guid]
    if m then
        m.name, m.level, m.class, m.race, m.guild = e.name, e.level or m.level, e.class, e.race, e.guild or m.guild
        m.lastSeen, m.lastWhere = e.last, e.where
    end
    local was = ns.near[guid]
    ns.near[guid] = GetTime()
    local isNew = not was or GetTime() - was > 120
    if isNew then ns.TrackHit(guid, nil, e.where) end
    changed("near", guid, isNew)
end

-- Habits for the poster's detail side: where they hunt (zone counts) and when they're on (hour
-- counts). One count per player per 5 minutes, so standing in view doesn't pile it up.
function ns.Habit(e, zone, t)
    if (t or 0) - (e.habitAt or 0) < 300 then return end
    e.habitAt = t
    e.zones = e.zones or {}
    if zone and zone ~= "" then
        e.zones[zone] = (e.zones[zone] or 0) + 1
        local n, low, lowK = 0, math.huge, nil
        for k, v in pairs(e.zones) do n = n + 1; if v < low then low, lowK = v, k end end
        if n > 10 and lowK ~= zone then e.zones[lowK] = nil end
    end
    e.hours = e.hours or {}
    local h = tonumber(date("%H", t))
    if h then e.hours[h] = (e.hours[h] or 0) + 1 end
end

-- Tracked players: a sighting anywhere (yours or another VoidBounty player's) alerts you.
local trackAt = {}
function ns.TrackHit(guid, by, whereText)
    local tr = ns.char().track
    if not (tr and tr[guid]) then return end
    if trackAt[guid] and GetTime() - trackAt[guid] < 120 then return end
    trackAt[guid] = GetTime()
    local e = ns.db().seen[guid] or {}
    ns.Log("tracked", ("%s %s %s"):format(e.name or "?", by and ("seen by a VoidBounty player in") or "near you in", whereText or "?"))
    ns.say(("|cffffd200Tracked|r |cffff5555%s|r %s%s."):format(e.name or "?", by and ("seen by " .. by .. " in ") or "is near you · ",
        whereText or "?"))
    if ns.char().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

function ns.Nearby()
    local now, out = GetTime(), {}
    for g, t in pairs(ns.near) do
        if now - t <= NEAR_FOR then
            local e = ns.db().seen[g]
            if e then out[#out + 1] = { guid = g, e = e, ago = now - t } end
        else
            ns.near[g] = nil
        end
    end
    table.sort(out, function(a, b) return (a.e.level or 0) > (b.e.level or 0) end)
    return out
end

----------------------------------------------------------------------
-- Marked list
----------------------------------------------------------------------
function ns.IsMarked(guid) return guid and ns.char().marked[guid] ~= nil end

-- guid may be nil for a killer we never saw (recap gives only a name): keyed "name:<name>" then
local function markKey(guid, name) return guid or ("name:" .. name) end

function ns.Mark(guid, name, info, how)
    local marked = ns.char().marked
    local key = markKey(guid, name)
    -- a name-only entry gets its GUID once we see that player
    if guid and marked["name:" .. name] then
        marked[guid] = marked["name:" .. name]
        marked["name:" .. name] = nil
    end
    local m = marked[key]
    if not m then
        m = { name = name, first = time(), kills = 0, how = how }
        marked[key] = m
    end
    if info then
        m.level, m.class, m.race, m.guild = info.level or m.level, info.class or m.class, info.race or m.race, info.guild or m.guild
        m.lastSeen, m.lastWhere = info.last or m.lastSeen, info.where or m.lastWhere
    end
    if how == "manual" then m.manual = true end
    changed("marked", key)
    return m
end

function ns.Unmark(key)
    ns.char().marked[key] = nil
    changed("marked", key)
end

function ns.MarkTarget()
    if not isEnemy("target") then ns.say("target an enemy player first.") return end
    local guid = safe(UnitGUID, "target")
    if not guid or secret(guid) then ns.say("can't read that player here.") return end
    look("target", "target")
    local e = ns.db().seen[guid]
    local name = e and e.name or fullName("target")
    if not name then ns.say("can't read that player's name here.") return end
    local m = ns.Mark(guid, name, e, "manual")
    ns.say(("marked %s."):format(m.name))
end

-- Find a sighting by full name (the recap has names only). The most recent wins.
local function byName(name)
    local best, bestT
    for g, e in pairs(ns.db().seen) do
        if e.name == name and (e.last or 0) > (bestT or -1) then best, bestT = g, e.last or 0 end
    end
    return best
end

-- Who killed me: the death recap. The player source of the killing blow (overkill), else the
-- player source with the most damage. Only ENEMY players we can tie to a sighting count; a name
-- we never saw is kept by name (a nameplate later fills in the rest).
local function readRecap()
    if inBattle() then ns.Log("death", "in a battleground: skipped") return end
    local R = C_DeathRecap
    if not (R and R.GetRecapEvents) then ns.Log("death", "no death recap API") return end
    local events = safe(R.GetRecapEvents) or {}
    local dmg, blow = {}, nil
    for _, ev in ipairs(events) do
        local src = type(ev) == "table" and plain(ev.sourceName)
        if src and src ~= "" then
            local amt = tonumber(plain(ev.amount)) or 0
            dmg[src] = (dmg[src] or 0) + amt
            local ok = tonumber(plain(ev.overkill))
            if ok and ok >= 0 then blow = src end
        end
    end
    -- test log: every source with its damage, the killing blow, and whether we knew them
    local parts = {}
    for n, d in pairs(dmg) do
        local g = byName(n)
        local e = g and ns.db().seen[g]
        parts[#parts + 1] = ("%s=%d%s"):format(n, d, e and (e.faction == UnitFactionGroup("player") and "(own)" or "(enemy)") or "(?)")
    end
    ns.Log("death", ("%d recap events; blow=%s; %s"):format(#events, tostring(blow), table.concat(parts, ", ")))
    local function isPlayerEnemyName(n)
        local g = byName(n)
        local e = g and ns.db().seen[g]
        return e and e.faction and e.faction ~= UnitFactionGroup("player"), g
    end
    local killer = blow and isPlayerEnemyName(blow) and blow
    if not killer then
        local top = 0
        for n, d in pairs(dmg) do
            if d > top and isPlayerEnemyName(n) then killer, top = n, d end
        end
    end
    if not killer then ns.Log("death", "no enemy player we saw: nothing marked") return end
    local _, guid = isPlayerEnemyName(killer)
    ns.Log("killed", ("by %s (%s)"):format(killer, guid and "known" or "name only"))
    local e = guid and ns.db().seen[guid]
    local m = ns.Mark(guid, killer, e, "killed you")
    m.kills = (m.kills or 0) + 1
    m.lastKill, m.killWhere = time(), where()
    ns.char().lastKiller = { key = markKey(guid, killer), t = time() }
    if guid and ns.OnDeathBy then ns.OnDeathBy(guid, e) end
    changed("killed", markKey(guid, killer))
    ns.say(("|cffff5555%s|r killed you%s. Marked (%d×)."):format(killer,
        e and e.level and (" (" .. e.level .. " " .. (e.class and e.class:lower() or "") .. ")") or "", m.kills))
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, ev, a1)
    if ev == "PLAYER_LOGIN" then
        ns.db(); ns.char()
        myFaction = UnitFactionGroup("player")
    elseif ev == "NAME_PLATE_UNIT_ADDED" then look(a1, "nameplate")
    elseif ev == "PLAYER_TARGET_CHANGED" then look("target", "target")
    elseif ev == "UPDATE_MOUSEOVER_UNIT" then look("mouseover", "mouseover")
    elseif ev == "PLAYER_DEAD" then C_Timer.After(1.5, function() pcall(readRecap) end)
    end
end)
-- nameplates that stay up keep someone "nearby"
C_Timer.NewTicker(5, function()
    if inBattle() then return end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and isEnemy(u) then
            local g = safe(UnitGUID, u)
            if g and not secret(g) and ns.near[g] then ns.near[g] = GetTime() end
        end
    end
    changed("tick")
end)

-- for tests: /vbounty test adds a made-up Marked enemy nearby
function ns.Test()
    local g = "Player-0-TEST0001"
    local s = ns.db().seen
    s[g] = { name = "Test Dummy", level = UnitLevel("player") + 2, class = "WARRIOR", race = "Human", guild = "Test Guild",
        faction = myFaction == "Horde" and "Alliance" or "Horde", first = time(), last = time(), n = 1, how = "test", where = where() }
    local m = ns.Mark(g, "Test Dummy", s[g], "killed you")
    m.kills = (m.kills or 0) + 1
    ns.near[g] = GetTime()
    changed("near", g, true)
end
