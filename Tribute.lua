----------------------------------------------------------------------
-- VoidBounty: tribute (stage 2). The user, 2026-11-10: rewards are basic NPC goods, never gold
-- (Forever bans for gold moving between strangers): "options for a hunter to select their reward
-- ... only selecting what that person can get ... basic npc stuff that is not limited".
--
--   catalog   TributeData.lua (tools/cmd/vb-tribute): vendor-only, unlimited, plain gold
--   the pick  the hunter picks items for THEIR level and faction, total <= the writ's cap
--   shopping  the poster gets the list; one click puts it in VoidGPS's errands (vendor routes)
--   payment   face to face in the trade window; both clients read the trade, and a completed
--             trade that covers the pick settles the writ (P from the poster, R from the hunter)
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local MAX_LINES = 6

local function myFac() return UnitFactionGroup("player") == "Alliance" and "A" or "H" end

-- items a player of this level and faction can be paid in: their level or a bit under, vendor-buyable
function ns.TributeChoices(level)
    local out, fac = {}, myFac()
    for id, t in pairs(ns.TRIBUTE or {}) do
        local name, cat, req, price, stack, facs = t[1], t[2], t[3], t[4], t[5], t[6]
        local useful = req <= level and (cat == "supplies" or cat == "reagent" or req >= level - 20 or req == 0)
        if facs:find(fac, 1, true) and useful then
            out[#out + 1] = { id = id, name = name, cat = cat, req = req, price = price, stack = stack }
        end
    end
    local ORDER = { food = 1, potion = 2, bandage = 3, ammo = 4, reagent = 5, supplies = 6 }
    table.sort(out, function(a, b)
        if a.cat ~= b.cat then return (ORDER[a.cat] or 9) < (ORDER[b.cat] or 9) end
        if a.req ~= b.req then return a.req > b.req end
        return a.name < b.name
    end)
    return out
end

function ns.PickCost(pick)
    local c = 0
    for _, p in ipairs(pick) do
        local t = ns.TRIBUTE[p.id]
        c = c + (t and t[4] or 0) * p.n
    end
    return c
end

function ns.PickString(pick)
    local t = {}
    for _, p in ipairs(pick) do t[#t + 1] = p.id .. ":" .. p.n end
    return table.concat(t, ",")
end

function ns.PickText(pick)
    local t = {}
    for _, p in ipairs(pick) do
        local d = ns.TRIBUTE[p.id]
        t[#t + 1] = ("%d× %s"):format(p.n, d and d[1] or ("item " .. p.id))
    end
    return table.concat(t, ", ")
end

-- from a T message: only catalog items, sane counts, at most MAX_LINES lines, total within the cap
function ns.ParsePick(s, cap)
    if type(s) ~= "string" or s == "" then return nil end
    local pick = {}
    for id, n in s:gmatch("(%d+):(%d+)") do
        id, n = tonumber(id), tonumber(n)
        if not ns.TRIBUTE[id] or n < 1 or n > 1000 then return nil end
        pick[#pick + 1] = { id = id, n = n }
        if #pick > MAX_LINES then return nil end
    end
    if #pick == 0 or ns.PickCost(pick) > cap then return nil end
    return pick
end

-- the poster's shopping list into VoidGPS errands (have qty more than you hold now)
function ns.ToErrands(w)
    local E = _G.VoidGPS and _G.VoidGPS.Errands
    if not E then ns.say("VoidGPS isn't loaded: buy " .. ns.PickText(w.pick or {}) .. " at any vendor.") return end
    for _, p in ipairs(w.pick or {}) do E:Add(p.id, p.n, "VoidBounty tribute for " .. (w.claim and w.claim.hunter or "?")) end
    if E.Toggle and E.Count and E:Count() > 0 then pcall(E.Toggle, E, true) end
    ns.say("tribute added to VoidGPS errands: the box routes you to the nearest vendor for each.")
end

----------------------------------------------------------------------
-- The trade check
----------------------------------------------------------------------
local trade   -- { partner, give = {[id]=n}, get = {[id]=n} } while a trade window is open

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

local function snapshot()
    if not trade then return end
    trade.give, trade.get = {}, {}
    for i = 1, 6 do
        local id = itemID(GetTradePlayerItemLink and GetTradePlayerItemLink(i))
        if id then
            local _, _, n = GetTradePlayerItemInfo(i)
            trade.give[id] = (trade.give[id] or 0) + (n or 1)
        end
        id = itemID(GetTradeTargetItemLink and GetTradeTargetItemLink(i))
        if id then
            local _, _, n = GetTradeTargetItemInfo(i)
            trade.get[id] = (trade.get[id] or 0) + (n or 1)
        end
    end
end

local function covers(have, pick)
    for _, p in ipairs(pick or {}) do
        if (have[p.id] or 0) < p.n then return false end
    end
    return pick and #pick > 0
end

local function settle()
    if not trade then return end
    local me = ns.Me or GetUnitName("player")
    for id, w in pairs(ns.Writs()) do
        if w.claim and w.pick and not (w.paid or w.recv) then
            if w.author == me and trade.partner == w.claim.hunter and covers(trade.give, w.pick) then
                ns.MarkPaid(id, true)
                ns.say(("tribute paid to %s: the writ on %s is settled."):format(w.claim.hunter, w.tname))
            elseif w.claim.hunter == me and trade.partner == w.author and covers(trade.get, w.pick) then
                ns.MarkPaid(id, false)
                ns.say(("tribute received from %s: the writ on %s is settled."):format(w.author, w.tname))
            end
        end
    end
end

local tf = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
                     "TRADE_CLOSED", "UI_INFO_MESSAGE" }) do pcall(tf.RegisterEvent, tf, e) end
tf:SetScript("OnEvent", function(_, ev, a1, a2)
    if ev == "TRADE_SHOW" then
        local n, sur = UnitName("NPC")
        local partner = n and (sur and sur ~= "" and (n .. " " .. sur) or n)
        if (not partner or partner == "") and TradeFrameRecipientNameText then partner = TradeFrameRecipientNameText:GetText() end
        trade = { partner = partner, give = {}, get = {} }
    elseif ev == "UI_INFO_MESSAGE" then
        -- (messageType, message): the trade went through
        if trade and (a2 == ERR_TRADE_COMPLETE or a1 == ERR_TRADE_COMPLETE) then settle(); trade = nil end
    elseif ev == "TRADE_CLOSED" then
        -- TRADE_CLOSED fires before the "Trade complete" message: keep the snapshot a moment
        local t = trade
        C_Timer.After(2, function() if trade == t then trade = nil end end)
    elseif trade then
        snapshot()
    end
end)
