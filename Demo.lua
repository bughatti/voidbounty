----------------------------------------------------------------------
-- VoidBounty: a demo board, to see the posters before anyone has posted a writ.
--   /vbounty demo     swaps in a made-up board (enemies, writs, notoriety, debts, hunts)
--   /vbounty undemo   back to the real one
-- Nothing of the demo is saved or sent: ns.db()/ns.char() return the demo tables (the
-- SavedVariables globals are never touched) and Bus.Send refuses while it's on. /reload ends it too.
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local function me() return ns.Me or GetUnitName("player") end

-- made-up players (obviously fake names, never real ones)
local PEOPLE = {
    { "Demo Grimshade",  "ROGUE",   38, "Human",     "Demo Guild",  1424, 15, { 22, 23, 0 } },
    { "Demo Ironvale",   "WARRIOR", 41, "Dwarf",     "Demo Guild",  1417, 9,  { 20, 21 } },
    { "Demo Starfall",   "MAGE",    35, "Gnome",     nil,           1434, 5,  { 19, 20, 21 } },
    { "Demo Brightwood", "HUNTER",  33, "Night Elf", "Other Demo",  1440, 3,  { 17, 18 } },
    { "Demo Holystone",  "PALADIN", 44, "Human",     "Demo Guild",  1446, 1,  { 12, 13 } },
    { "Demo Thornroot",  "DRUID",   30, "Night Elf", nil,           1441, 0,  { 8, 9 } },
    { "Demo Ashveil",    "WARLOCK", 36, "Human",     "Other Demo",  1424, 7,  { 1, 2, 3 } },
    { "Demo Coldmire",   "PRIEST",  40, "Dwarf",     nil,           1418, 2,  { 21 } },
}

local function zoneName(map)
    local i = C_Map.GetMapInfo(map)
    return i and i.name or "?"
end

local function build()
    local now, myName = time(), me()
    local db = { seen = {}, noto = {}, writs = {} }
    local real = ns.realChar and ns.realChar() or {}
    local char = { marked = {}, track = {} }
    for _, k in ipairs({ "alerts", "sound", "quiet", "autolog", "shareSeen", "shareDeaths" }) do char[k] = real[k] end
    local fac = UnitFactionGroup("player") or "?"
    db.writs[fac] = {}
    local writs = db.writs[fac]
    local enemy = fac == "Horde" and "Alliance" or "Horde"

    for i, p in ipairs(PEOPLE) do
        local guid = ("Player-0-DE%06X"):format(i)
        local zone = zoneName(p[6])
        local e = { name = p[1], class = p[2], level = p[3], race = p[4], guild = p[5], faction = enemy,
            first = now - 86400 * 3, last = now - i * 420, n = 10 + i, how = "demo", map = p[6], where = zone, zone = zone,
            ax = 8 + i, ay = 6 + i, zones = { [zone] = 12, [zoneName(1416)] = 4, [zoneName(1417)] = 2 }, hours = {} }
        for _, h in ipairs(p[8]) do e.hours[h] = 6 end
        db.seen[guid] = e
        if p[7] > 0 then
            local n = { name = p[1], class = p[2], level = p[3], kills = {} }
            for k = 1, p[7] do n.kills[#n.kills + 1] = { t = now - k * 3000, map = (k % 3 == 0) and 1416 or p[6] } end
            db.noto[guid] = n
        end
        -- one or more writs on most of them
        local function writ(author, size, ago, extra)
            local posted = now - ago
            local w = { id = author .. "#" .. posted, author = author, tguid = guid, tname = p[1], tlvl = p[3], tcls = p[2],
                size = size, cap = ns.Cap(size, 30 + i), posted = posted, kills = 1 + (i % 3), confirmed = true, hunters = {} }
            for k, v in pairs(extra or {}) do w[k] = v end
            writs[w.id] = w
            return w
        end
        if i == 1 then
            writ("Demo Poster", "L", 3600)
            writ("Demo Other", "M", 7200, { hunters = { ["Demo Hunter"] = now - 600 } })
            writ(myName, "S", 1800)                                    -- YOUR WRIT stamp
        elseif i == 2 then
            writ("Demo Poster", "M", 5400, { hunters = { [myName] = now - 900 } })   -- My hunts: taken
        elseif i == 3 then
            writ("Demo Other", "L", 86400, { hunters = { [myName] = now - 80000 },
                claim = { hunter = myName, t = now - 70000, victim = guid, zone = zone, firsthand = true, accepted = true } })
        elseif i == 4 then
            writ("Demo Burner", "S", 5 * 86400, { hunters = { ["Demo Hunter"] = now - 4 * 86400 },
                claim = { hunter = "Demo Hunter", t = now - 4 * 86400, victim = guid, zone = zone, firsthand = true } })
            writ("Demo Burner", "M", 3600)                              -- BURNED poster
        elseif i == 5 then
            writ("Demo Poster", "S", 600)
        elseif i == 6 then
            writ("Demo Other", "M", 2 * 86400)
        elseif i == 7 then
            writ("Demo Poster", "L", 1200); writ("Demo Other", "L", 1500); writ("Demo Third", "M", 1700)
        else
            writ("Demo Third", "S", 4000)
        end
        -- blood debts: three of them killed you
        if i == 1 or i == 3 or i == 7 then
            char.marked[guid] = { name = p[1], first = now - 86400 * 2, kills = (i == 1) and 3 or 1, how = "killed you",
                level = p[3], class = p[2], race = p[4], guild = p[5], lastSeen = e.last, lastWhere = zone }
        end
    end
    -- a claimed writ you posted (Pay / Shop flow) and a settled one for the ledger
    local g8 = ("Player-0-DE%06X"):format(8)
    local w = { id = myName .. "#" .. (now - 90000), author = myName, tguid = g8, tname = PEOPLE[8][1], tlvl = 40, tcls = "PRIEST",
        size = "M", cap = ns.Cap("M", UnitLevel("player")), posted = now - 90000, kills = 1, confirmed = true,
        hunters = { ["Demo Hunter"] = now - 88000 },
        claim = { hunter = "Demo Hunter", t = now - 50000, victim = g8, zone = zoneName(1418), firsthand = true } }
    writs[w.id] = w
    local w2 = { id = "Demo Poster#" .. (now - 200000), author = "Demo Poster", tguid = g8, tname = PEOPLE[8][1], tlvl = 40,
        tcls = "PRIEST", size = "S", cap = ns.Cap("S", 40), posted = now - 200000, kills = 1, confirmed = true,
        hunters = { [myName] = now - 190000 },
        claim = { hunter = myName, t = now - 180000, victim = g8, zone = zoneName(1418), firsthand = true }, recv = now - 150000 }
    writs[w2.id] = w2
    char.track[("Player-0-DE%06X"):format(1)] = now - 3000
    return db, char
end

function ns.DemoOn()
    if ns.demoDB then return end
    ns.demoDB, ns.demoChar = build()
    ns.say("|cffffd200demo board on|r: made-up players and writs, nothing saved or sent. |cffffd200/vbounty undemo|r (or /reload) ends it.")
    if ns.Changed then ns.Changed("writ") end
end

function ns.DemoOff()
    if not ns.demoDB then return end
    ns.demoDB, ns.demoChar = nil, nil
    ns.say("demo board off.")
    if ns.Changed then ns.Changed("writ") end
end
