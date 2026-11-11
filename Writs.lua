----------------------------------------------------------------------
-- VoidBounty: shared sightings and the writ ledger (stage 2, 2026-11-10).
--
-- Sightings (S): a new enemy you see goes to the network (at most once per player per 3 min, a
-- few a minute). A Marked player seen by someone else gives you a chat line: who saw them and
-- where. Shared sightings never trigger the "nearby" alert (they're somewhere else).
--
-- Writs (the user's design, memory project-forever-pvp-wanted-idea):
--   * only on a player who KILLED you (blood debt: on your Marked list with kills >= 1)
--   * the poster picks a tribute SIZE (S / M / L = a vendor-value cap from the poster's level);
--     the hunter picks the goods (Tribute.lua), paid face to face in the trade window
--   * grey kills count; only the killing blow counts (no group credit)
--   * claims come from the hunter's own combat log (KillProof.lua); a claim is "claimed (log)",
--     the website check (stage 3) makes it "verified"
--   * the poster has PAY_DAYS days after a claim; unpaid after that = Burned (lifts when paid)
--   * a writ expires after OPEN_DAYS days without a claim
-- Messages (a field "~" each; the SENDER is checked against who the message is about):
--   W id author tguid tname tlvl tcls size cap posted kills     post (sender = author)
--   w ...same...                                                 relay of a writ (catch-up)
--   A id                                                         accept (sender = hunter)
--   C id killT victimGUID zone                                   claim (sender = an accepted hunter)
--   T id item:count,item:count                                   tribute pick (sender = claimer)
--   P id      R id      X id                                     paid (poster) / received (claimer) / withdrawn (poster)
--   Q                                                            "what's on the board?" (answered with w lines)
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local B = ns.Bus
local OPEN_DAYS, PAY_DAYS = 7, 3
local MAX_OPEN_PER_POSTER = 3
local SIZE_MULT = { S = 2, M = 5, L = 12 }   -- cap (copper) = poster level^2 * this
ns.OPEN_DAYS, ns.PAY_DAYS = OPEN_DAYS, PAY_DAYS

local function me() return ns.Me or (GetUnitName and GetUnitName("player")) or UnitName("player") end

function ns.Cap(size, level)
    return math.max(50, (level or 1) ^ 2 * (SIZE_MULT[size] or 0))
end

function ns.Money(c)
    c = math.floor(c or 0)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return ("%dg %ds"):format(g, s) end
    if s > 0 then return ("%ds %dc"):format(s, cp) end
    return cp .. "c"
end

-- the writs of your faction's network
function ns.Writs()
    local d = ns.db()
    d.writs = d.writs or {}
    local fac = UnitFactionGroup("player") or "?"
    d.writs[fac] = d.writs[fac] or {}
    return d.writs[fac]
end

function ns.Status(w, now)
    now = now or time()
    if w.withdrawn then return "withdrawn" end
    if w.paid or w.recv then return "paid" end
    if w.claim then
        if now - w.claim.t > PAY_DAYS * 86400 then return "overdue" end
        return "claimed"
    end
    if now - w.posted > OPEN_DAYS * 86400 then return "expired" end
    return "open"
end

-- Burned: a first-hand claim on one of their writs, past the deadline, never paid
function ns.Burned(poster)
    for _, w in pairs(ns.Writs()) do
        if w.author == poster and ns.Status(w) == "overdue" and w.claim.firsthand then return true end
    end
    return false
end

local function changed(what) if ns.Changed then ns.Changed(what) end end

----------------------------------------------------------------------
-- Shared sightings
----------------------------------------------------------------------
local shareAt, shareMinute, shareCount = {}, 0, 0
ns.OnChange(function(what, guid, isNew)
    if what ~= "near" or not isNew or ns.InBattle() or ns.char().shareSeen == false then return end
    if guid:find("^Player%-0%-TEST") then return end
    local e = ns.db().seen[guid]
    if not e or e.how == "shared" then return end
    local now = time()
    if shareAt[guid] and now - shareAt[guid] < 180 then return end
    local m = math.floor(now / 60)
    if m ~= shareMinute then shareMinute, shareCount = m, 0 end
    if shareCount >= 6 then return end
    shareAt[guid], shareCount = now, shareCount + 1
    B.Send(B.Pack("S", guid, e.name, e.level or 0, e.class or "", e.map or 0, e.guild or "", e.ax or "", e.ay or ""))
end)

ns.CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true, EVOKER = true }

-- a map id from the network: a whole number in range, else 0 ("1e309" is a number too; Codex 11-11)
local function mapID(v)
    v = tonumber(v)
    if v and v == math.floor(v) and v >= 0 and v <= 100000 then return v end
    return 0
end

local alertAt = {}
B.On("S", function(f, sender)
    local guid, name, lvl, cls, map, guild = f[2], B.CleanName(f[3]), tonumber(f[4]), f[5], mapID(f[6]), f[7]
    if not (B.IsGUID(guid) and name and lvl and lvl >= 0 and lvl <= 80) then return end
    if cls ~= "" and not ns.CLASSES[cls] then return end
    local info = map and map > 0 and C_Map.GetMapInfo(map)
    local s = ns.db().seen
    local e = s[guid]
    local fresh = not e
    if not e then
        e = { first = time(), last = time(), n = 0, how = "shared" }
        s[guid] = e
        if ns.TrimSeen then ns.TrimSeen() end   -- shared sightings count toward the same cap
    end
    if e.how == "shared" then   -- never overwrite what you saw yourself with hearsay
        e.name, e.class = name, cls ~= "" and cls or e.class
        if lvl > 0 then e.level = lvl end
        e.guild = B.CleanName(guild) or e.guild
        e.faction = e.faction or ((UnitFactionGroup("player") == "Horde") and "Alliance" or "Horde")
        e.last, e.map, e.where, e.zone = time(), map, info and info.name or e.where, info and info.name or e.zone
        local ax, ay = tonumber(f[8]), tonumber(f[9])
        if ax and ay and ax >= 0 and ax <= 20 and ay >= 0 and ay <= 20 then e.ax, e.ay = math.floor(ax), math.floor(ay) end
    end
    ns.Habit(e, info and info.name, time())
    ns.TrackHit(guid, sender, info and info.name)
    e.sharedBy, e.sharedAt, e.sharedWhere = sender, time(), info and info.name or "?"
    local m = ns.char().marked[guid]
    if m then
        m.lastSeen, m.lastWhere = time(), (info and info.name or m.lastWhere)
        if not alertAt[guid] or time() - alertAt[guid] > 300 then
            alertAt[guid] = time()
            ns.say(("|cffff5555%s|r (Marked) seen by %s in %s."):format(m.name, sender, info and info.name or "?"))
        end
    end
    changed(fresh and "seen" or "seen2")
end)

----------------------------------------------------------------------
-- Writs
----------------------------------------------------------------------
local function writLine(kind, w)
    return B.Pack(kind, w.id, w.author, w.tguid, w.tname, w.tlvl or 0, w.tcls or "", w.size, w.cap, w.posted, w.kills or 1)
end

local function parseWrit(f, sender, relay)
    local w = {
        id = f[2], author = B.CleanName(f[3]), tguid = f[4], tname = B.CleanName(f[5]), tlvl = tonumber(f[6]),
        tcls = f[7], size = f[8], cap = tonumber(f[9]), posted = tonumber(f[10]), kills = tonumber(f[11]),
    }
    if not (w.author and w.tname and B.IsGUID(w.tguid) and SIZE_MULT[w.size] and w.cap and w.posted) then return end
    if w.id ~= w.author .. "#" .. w.posted then return end
    if w.tcls ~= "" and not ns.CLASSES[w.tcls] then return end
    if w.cap > ns.Cap(w.size, 80) then return end
    if w.posted > time() + 600 or time() - w.posted > OPEN_DAYS * 86400 then return end
    if not relay and sender ~= w.author then return end
    return w
end

local function store(w, sender, relay)
    local all = ns.Writs()
    local have = all[w.id]
    if have then
        if not relay and not have.confirmed then have.confirmed = true; changed("writ") end
        return have
    end
    w.confirmed = not relay
    w.heardFrom = sender
    w.hunters = {}
    all[w.id] = w
    changed("writ")
    return w
end

B.On("W", function(f, sender) local w = parseWrit(f, sender, false); if w then store(w, sender, false) end end)
B.On("w", function(f, sender) local w = parseWrit(f, sender, true); if w then store(w, sender, true) end end)

B.On("X", function(f, sender)
    local w = ns.Writs()[f[2]]
    if w and w.author == sender and not w.withdrawn then w.withdrawn = time(); changed("writ") end
end)

B.On("A", function(f, sender)
    local w = ns.Writs()[f[2]]
    if not w or sender == w.author or ns.Status(w) ~= "open" then return end
    w.hunters = w.hunters or {}
    if not w.hunters[sender] then w.hunters[sender] = time(); changed("writ") end
end)

local NO_CLAIM_ZONES = {
    ["Warsong Gulch"] = true, ["Arathi Basin"] = true, ["Alterac Valley"] = true,
    ["Orgrimmar"] = true, ["Undercity"] = true, ["Thunder Bluff"] = true,
    ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true,
}
ns.NO_CLAIM_ZONES = NO_CLAIM_ZONES

-- a kill in the open world (the user, 11-11: "bg stuff really shouldnt be counted"). The reader tags each
-- kill from the combat log's zone line: map 0/1 = the two continents = "world"; "bg" and "instance"
-- (dungeons, delves) don't count. Kills from before the tag: battleground names don't count.
function ns.IsWorldKill(k)
    if k.where and k.where ~= "" then return k.where == "world" end
    local z = k.zone or ""
    return not (z == "Warsong Gulch" or z == "Arathi Basin" or z == "Alterac Valley")
end

local function validClaim(w, hunter, killT, victim, zone)
    if not w or ns.Status(w) ~= "open" or hunter == w.author then return false end
    if victim ~= w.tguid or not killT or killT < w.posted then return false end
    if zone and NO_CLAIM_ZONES[zone] then return false end
    return true
end
ns.ValidClaim = validClaim

B.On("C", function(f, sender)
    local w = ns.Writs()[f[2]]
    local killT, victim, zone = tonumber(f[3]), f[4], f[5] ~= "" and f[5] or nil
    if not validClaim(w, sender, killT, victim, zone) then return end
    w.hunters = w.hunters or {}
    w.claim = { hunter = sender, t = killT, victim = victim, zone = zone, firsthand = true, accepted = w.hunters[sender] ~= nil }
    changed("claim")
    if w.author == me() then
        ns.say(("|cffffd200%s|r claims your writ on |cffff5555%s|r (killed %s, from their combat log). They'll pick the tribute next."):format(
            sender, w.tname, date("%H:%M", math.floor(killT))))
        PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
    end
end)

B.On("T", function(f, sender)
    local w = ns.Writs()[f[2]]
    if not (w and w.claim and w.claim.hunter == sender) or w.paid or w.recv then return end
    local pick = ns.ParsePick and ns.ParsePick(f[3], w.cap)
    if not pick then return end
    w.pick = pick
    changed("pick")
    if w.author == me() then
        ns.say(("%s picked the tribute for your writ on %s: %s. Open VoidBounty > Mine for the shopping list."):format(
            sender, w.tname, ns.PickText(pick)))
    end
end)

B.On("P", function(f, sender)
    local w = ns.Writs()[f[2]]
    if w and w.author == sender and w.claim and not w.paid then w.paid = time(); changed("paid") end
end)
B.On("R", function(f, sender)
    local w = ns.Writs()[f[2]]
    if w and w.claim and w.claim.hunter == sender and not w.recv then w.recv = time(); changed("paid") end
end)

-- catch-up: answer with the open / claimed writs we know (a few, paced by the transport)
local answeredAt = {}
B.On("Q", function(_, sender)
    if answeredAt[sender] and time() - answeredAt[sender] < 600 then return end
    answeredAt[sender] = time()
    local n = 0
    for _, w in pairs(ns.Writs()) do
        local st = ns.Status(w)
        if (st == "open" or st == "claimed") and n < 15 then
            n = n + 1
            B.Send(writLine(w.author == me() and "W" or "w", w), sender)
        end
    end
end)

-- once the network is up: ask two players for the board, and re-announce our own open writs
function ns.OnNetReady()
    B.Send(B.Pack("Q"))
    for _, w in pairs(ns.Writs()) do
        if w.author == me() and ns.Status(w) == "open" then B.Send(writLine("W", w)) end
    end
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------
function ns.OpenWritsBy(author)
    local n = 0
    for _, w in pairs(ns.Writs()) do
        if w.author == author and ns.Status(w) == "open" then n = n + 1 end
    end
    return n
end

-- can I post on this Marked entry? returns ok, why
function ns.CanPost(key, m)
    if not B.IsGUID(key) then return false, "Not seen yet: VoidBounty needs to see them once (nameplate, target or mouseover)." end
    if (m.kills or 0) < 1 then return false, "Only on a player who killed you (blood debt)." end
    if ns.Burned(me()) then return false, "You're Burned: pay your overdue tribute first." end
    for _, w in pairs(ns.Writs()) do
        if w.author == me() and w.tguid == key and ns.Status(w) == "open" then return false, "You already have an open writ on them." end
    end
    if ns.OpenWritsBy(me()) >= MAX_OPEN_PER_POSTER then return false, ("At most %d open writs at a time."):format(MAX_OPEN_PER_POSTER) end
    return true
end

function ns.Post(key, size)
    local m = ns.char().marked[key]
    local ok, why = ns.CanPost(key, m or {})
    if not ok then ns.say(why) return end
    local now = time()
    local e = ns.db().seen[key] or m
    local w = {
        id = me() .. "#" .. now, author = me(), tguid = key, tname = m.name, tlvl = e.level or m.level or 0,
        tcls = e.class or m.class or "", size = size, cap = ns.Cap(size, UnitLevel("player")), posted = now,
        kills = m.kills or 1, confirmed = true, hunters = {},
    }
    ns.Writs()[w.id] = w
    local sent = B.Send(writLine("W", w))
    ns.say(("writ posted on |cffff5555%s|r, tribute %s (up to %s)%s."):format(w.tname, size == "S" and "small" or size == "M" and "medium" or "large",
        ns.Money(w.cap), sent and "" or " (no other VoidBounty players online right now: it goes out when they are)"))
    changed("writ")
end

function ns.Withdraw(id)
    local w = ns.Writs()[id]
    if not (w and w.author == me()) or w.claim then return end
    w.withdrawn = time()
    B.Send(B.Pack("X", id))
    changed("writ")
end

function ns.Accept(id)
    local w = ns.Writs()[id]
    if not w or w.author == me() or ns.Status(w) ~= "open" then return end
    w.hunters = w.hunters or {}
    w.hunters[me()] = time()
    B.Send(B.Pack("A", id))
    B.Send(B.Pack("A", id), w.author)
    ns.say(("you took the writ on |cffff5555%s|r. Kill them outside cities and battlegrounds; your combat log is the proof."):format(w.tname))
    changed("writ")
end

-- a kill from my combat log (KillProof.lua) on an accepted writ's target
function ns.ClaimFromLog(k)
    local mine = 0
    for id, w in pairs(ns.Writs()) do
        if w.hunters and w.hunters[me()] and ns.IsWorldKill(k) and validClaim(w, me(), k.t, k.victim, k.zone)
            and k.t >= (w.hunters[me()] - 60) then
            w.claim = { hunter = me(), t = k.t, victim = k.victim, zone = k.zone, firsthand = true, accepted = true }
            local msg = B.Pack("C", id, ("%.3f"):format(k.t), k.victim, k.zone or "")
            B.Send(msg)
            B.Send(msg, w.author)
            mine = mine + 1
            ns.say(("|cff55ff55claimed|r the writ on %s (your combat log: killed %s). Pick your tribute in VoidBounty > Mine."):format(
                w.tname, date("%H:%M", math.floor(k.t))))
        end
    end
    if mine > 0 then changed("claim") end
end

function ns.SendPick(id, pick)
    local w = ns.Writs()[id]
    if not (w and w.claim and w.claim.hunter == me()) then return end
    w.pick = pick
    local msg = B.Pack("T", id, ns.PickString(pick))
    B.Send(msg, w.author)
    B.Send(msg)
    changed("pick")
end

function ns.MarkPaid(id, asPoster)
    local w = ns.Writs()[id]
    if not w then return end
    if asPoster then w.paid = time(); B.Send(B.Pack("P", id)); B.Send(B.Pack("P", id), w.claim and w.claim.hunter)
    else w.recv = time(); B.Send(B.Pack("R", id)); B.Send(B.Pack("R", id), w.author) end
    changed("paid")
end

----------------------------------------------------------------------
-- Notoriety (the user, 2026-11-10: on by default, with a switch): when an enemy player kills a
-- VoidBounty player, that player's game tells its side "killed by X" (D). Each side then knows
-- how many of its players X killed this week and where. Only the KILLER is named; the victim is
-- just the sender (never stored by name: only own-faction counts and times).
--   D guid name level class mapID
----------------------------------------------------------------------
local NOTO_KEEP, NOTO_PLAYERS = 60, 400
-- one report per victim per 20 s (a death is reported once). In memory only: the victim's
-- name is never saved (Codex 11-11: it was, in n.keys).
local dedupe, dedupeN = {}, 0
-- at most NOTO_PLAYERS killers (the oldest last kill goes first), and no victim names from older
-- versions (n.keys). Runs at login over everything, and on each new killer.
function ns.NotoTrim(keep)
    local noto = ns.db().noto
    if not noto then return end
    local list = {}
    for g, x in pairs(noto) do
        x.keys = nil
        local k = x.kills or {}
        list[#list + 1] = { g = g, t = k[#k] and k[#k].t or 0 }
    end
    if #list <= NOTO_PLAYERS then return end
    table.sort(list, function(a, b) return a.t < b.t end)
    local drop = #list - NOTO_PLAYERS
    for _, x in ipairs(list) do
        if drop <= 0 then break end
        if x.g ~= keep then noto[x.g] = nil; drop = drop - 1 end
    end
end
do
    local tf = CreateFrame("Frame")
    tf:RegisterEvent("PLAYER_LOGIN")
    tf:SetScript("OnEvent", function() ns.NotoTrim() end)
end
local function notoAdd(guid, name, cls, lvl, map, t, from)
    local key = guid .. "|" .. (from or "?") .. "@" .. math.floor(t / 20)
    if dedupe[key] then return end
    dedupe[key], dedupeN = true, dedupeN + 1
    if dedupeN > 2000 then dedupe, dedupeN = { [key] = true }, 1 end
    local d = ns.db()
    d.noto = d.noto or {}
    local n = d.noto[guid]
    if not n then
        n = { kills = {} }
        d.noto[guid] = n
        ns.NotoTrim(guid)
    end
    n.name, n.class = name or n.name, cls ~= "" and cls or n.class
    if lvl and lvl > 0 then n.level = lvl end
    table.insert(n.kills, { t = t, map = map })
    while #n.kills > NOTO_KEEP do table.remove(n.kills, 1) end
end

-- Core.lua: you were just killed by an enemy we know
function ns.OnDeathBy(guid, e)
    local map = C_Map.GetBestMapForUnit("player") or 0
    notoAdd(guid, e and e.name, e and e.class or "", e and e.level, map, time(), "me")
    if ns.char().shareDeaths ~= false and not ns.InBattle() and e and e.name then
        B.Send(B.Pack("D", guid, e.name, e.level or 0, e.class or "", map))
    end
    changed("noto")
end

B.On("D", function(f, sender)
    local guid, name, lvl, cls, map = f[2], B.CleanName(f[3]), tonumber(f[4]), f[5], mapID(f[6])
    if not (B.IsGUID(guid) and name and lvl and lvl >= 0 and lvl <= 80) then return end
    if cls ~= "" and not ns.CLASSES[cls] then return end
    notoAdd(guid, name, cls, lvl, map, time(), sender)
    changed("noto")
end)

local TIERS = { { 11, "Dread", "ff3333" }, { 6, "Feared", "ff7733" }, { 3, "Dangerous", "ffbb33" }, { 1, "Known", "cccc88" } }
-- kills on our side in the last 7 days, a tier name, its colour, and kills per zone
function ns.Notoriety(guid)
    local n = ns.db().noto and ns.db().noto[guid]
    if not n then return 0 end
    local now, c, zones = time(), 0, {}
    for _, k in ipairs(n.kills) do
        if now - k.t <= 7 * 86400 then
            c = c + 1
            local info = k.map and k.map > 0 and C_Map.GetMapInfo(k.map)
            local z = info and info.name or "?"
            zones[z] = (zones[z] or 0) + 1
        end
    end
    for _, t in ipairs(TIERS) do
        if c >= t[1] then return c, t[2], t[3], zones end
    end
    return c, nil, nil, zones
end

----------------------------------------------------------------------
-- Posters: the board groups writs by target. A poster = every open / claimed writ on one
-- player, the rewards added up.
----------------------------------------------------------------------
function ns.Posters()
    local by, me_ = {}, me()
    for _, w in pairs(ns.Writs()) do
        local st = ns.Status(w)
        if st == "open" or st == "claimed" or st == "overdue" then
            local p = by[w.tguid]
            if not p then
                p = { guid = w.tguid, name = w.tname, class = w.tcls, level = w.tlvl, writs = {}, cap = 0, open = 0,
                      hunters = {}, posters = {}, newest = 0 }
                by[w.tguid] = p
            end
            table.insert(p.writs, w)
            if st == "open" then p.open = p.open + 1; p.cap = p.cap + w.cap end
            p.posters[w.author] = w.size
            for h in pairs(w.hunters or {}) do p.hunters[h] = true end
            if w.claim then p.claimedBy = w.claim.hunter end
            if ns.Burned(w.author) then p.burned = (p.burned or 0) + 1 end
            p.newest = math.max(p.newest, w.posted)
            if w.author == me_ then p.mine = true end
        end
    end
    local out = {}
    for _, p in pairs(by) do
        local e = ns.db().seen[p.guid]
        if e then
            p.class = (e.class and e.class ~= "") and e.class or p.class
            p.level = e.level or p.level
            p.guild, p.race, p.last, p.where = e.guild, e.race, e.last, e.where
        end
        p.noto = ns.Notoriety(p.guid)
        p.status = p.open > 0 and "open" or "claimed"
        out[#out + 1] = p
    end
    return out
end

-- enemy players seen per zone in the last `secs` (yours + shared)
function ns.ZoneDanger(secs)
    local now, z = time(), {}
    for _, e in pairs(ns.db().seen) do
        if e.last and now - e.last <= (secs or 900) then
            local k = e.zone or e.where or "?"
            local t = z[k]
            if not t then t = { zone = k, n = 0, lvlMin = 99, lvlMax = 0 }; z[k] = t end
            t.n = t.n + 1
            if e.level then t.lvlMin, t.lvlMax = math.min(t.lvlMin, e.level), math.max(t.lvlMax, e.level) end
        end
    end
    local out = {}
    for _, t in pairs(z) do out[#out + 1] = t end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out
end

-- your record and the network's top hunters (from the ledger this client has seen)
function ns.Hall()
    local me_ = me()
    local r = { posted = 0, claimed = 0, settled = 0, paidOut = 0, burnedMe = ns.Burned(me_), hunters = {} }
    for _, w in pairs(ns.Writs()) do
        if w.author == me_ then r.posted = r.posted + 1; if w.paid or w.recv then r.paidOut = r.paidOut + 1 end end
        if w.claim then
            local h = r.hunters[w.claim.hunter] or { name = w.claim.hunter, claims = 0, settled = 0 }
            r.hunters[w.claim.hunter] = h
            h.claims = h.claims + 1
            if w.paid or w.recv then h.settled = h.settled + 1 end
            if w.claim.hunter == me_ then r.claimed = r.claimed + 1; if w.paid or w.recv then r.settled = r.settled + 1 end end
        end
    end
    local top = {}
    for _, h in pairs(r.hunters) do top[#top + 1] = h end
    table.sort(top, function(a, b) return a.settled ~= b.settled and a.settled > b.settled or a.claims > b.claims end)
    r.top = top
    local kills, myGUID = 0, UnitGUID("player")
    for _, k in ipairs(ns.Kills and ns.Kills() or {}) do if k.killer == myGUID and ns.IsWorldKill(k) then kills = kills + 1 end end
    r.kills = kills
    local deaths = 0
    for _, m in pairs(ns.char().marked) do deaths = deaths + (m.kills or 0) end
    r.deaths = deaths
    local most = {}
    for guid, n in pairs(ns.db().noto or {}) do
        local c, tier = ns.Notoriety(guid)
        if c > 0 then most[#most + 1] = { guid = guid, name = n.name, class = n.class, level = n.level, kills = c, tier = tier } end
    end
    table.sort(most, function(a, b) return a.kills > b.kills end)
    r.most = most
    return r
end
