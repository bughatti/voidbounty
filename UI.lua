----------------------------------------------------------------------
-- VoidBounty: the big window (the user, 2026-11-10: "this is too basic, we need a bigger panel,
-- with wanted posters and all kinds of different things"; mockup approved: big size).
--
--   left menu   Board · Blood debts · My hunts · Ledger · Sightings · Hall of hunters · Settings
--               + a "danger here" line (enemy players seen in your zone, last 15 min)
--   Board       wanted posters (one per target, writs stacked), filters + sort, 6 a page;
--               a click opens the detail side: notoriety, hunting grounds, usual hours,
--               posters, hunters, Track / Add my bounty / Route to last seen
--   Blood debts who killed you: Writ / Track / Unmark; Mark my target
--   My hunts    writs you took (where the target was last seen, Pick tribute, Got it) and
--               the writs you posted (Withdraw, Shop)
--   Ledger      every writ you posted or took, with its outcome
--   Sightings   enemy players per zone (15 min) and the 30-minute feed (yours + your side's)
--   Hall        your record, top hunters, most wanted (notoriety)
--   Settings    the switches
-- Writ size picker and tribute picker are small dialogs on top.
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

local A = { 0, 0.78, 1 }                       -- Void cyan
local W, H = 900, 600   -- 600: two rows of posters + the page buttons under them
local NAV_W = 130
local CX = NAV_W + 20                           -- content left
local CW = W - CX - 10                          -- content width
local ROW_H = 20
local PARCH = { 0.91, 0.84, 0.66 }             -- poster parchment
local INK = { 0.23, 0.16, 0.07 }
local BLOOD = { 0.45, 0.08, 0.04 }
local SIZE_NAME = { S = "small", M = "medium", L = "large" }

local function me() return ns.Me or GetUnitName("player") end

local function ago(t)
    if not t then return "never" end
    local s = time() - t
    if s < 60 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end

local function tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(type(title) == "function" and title(self) or title, 1, 1, 1)
        local b = type(body) == "function" and body(self) or body
        if b then GameTooltip:AddLine(b, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 20)
    b:SetText(text)
    b:GetFontString():SetFontObject(GameFontHighlightSmall)
    return b
end

local function fs(parent, font, w, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if w then t:SetWidth(w) end
    t:SetJustifyH(justify or "LEFT")
    t:SetWordWrap(true)
    return t
end

local function box(parent, r, g, b, a, edge)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetBackdropColor(r, g, b, a)
    local e = edge or A
    f:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 0.5)
    return f
end

local function header(parent, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetTextColor(A[1], A[2], A[3])
    h:SetText(text)
    return h
end

local function classIcon(tex, cls)
    -- the client's own class icon atlas first (what Blizzard's UI uses), the old circles sheet as fallback
    local atlas = cls and ("classicon-" .. cls:lower())
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(atlas)
        return
    end
    local c = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if c then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Route to where a player was last seen (an area, never a live position)
local function routeTo(guid)
    local e = ns.db().seen[guid]
    if not (e and e.map) then ns.say("no sighting with a place yet.") return end
    local x, y = e.ax and e.ax / 20 or 0.5, e.ay and e.ay / 20 or 0.5
    if ns.Route then
        local ok, why = ns.Route:Go({ map = e.map, x = x, y = y, name = "Last seen: " .. (e.name or "?"), zone = e.where },
            { arrive = 60, say = ns.say })
        if not ok and why then ns.say(why) end
    end
end

local function toggleTrack(guid)
    local tr = ns.char().track
    tr[guid] = not tr[guid] or nil
    local e = ns.db().seen[guid] or {}
    ns.say(tr[guid] and ("tracking %s: you'll hear the moment anyone on your side sees them."):format(e.name or "?")
        or ("stopped tracking %s."):format(e.name or "?"))
end

----------------------------------------------------------------------
-- Generic list rows (Blood debts, My hunts, Ledger, Sightings, Hall)
----------------------------------------------------------------------
local function makeRow(parent, w)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(w, ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = fs(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 22, 0)
    r.text:SetWordWrap(false)
    r.btn = {}
    for i = 1, 3 do
        local b = button(r, "", 60, 18)
        if i == 1 then b:SetPoint("RIGHT", 0, 0) else b:SetPoint("RIGHT", r.btn[i - 1], "LEFT", -3, 0) end
        r.btn[i] = b
    end
    r:EnableMouse(true)
    r:Hide()
    return r
end

local Refresh   -- forward

-- item = { text, cls (icon), head = bool, tip = fn(tt), buttons = { { label, fn, tipText, w, enabled } } }
local function fillRow(r, item, i, w)
    r:Show()
    if item.head then
        r.bg:SetColorTexture(A[1], A[2], A[3], 0.10)
        r.text:SetFontObject(GameFontNormalSmall)
        r.text:SetTextColor(A[1], A[2], A[3])
        r.icon:Hide()
        r.text:SetPoint("LEFT", 6, 0)
    else
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
        r.text:SetFontObject(GameFontHighlightSmall)
        r.text:SetTextColor(1, 1, 1)
        if item.cls ~= nil then classIcon(r.icon, item.cls); r.icon:Show(); r.text:SetPoint("LEFT", 22, 0)
        else r.icon:Hide(); r.text:SetPoint("LEFT", 6, 0) end
    end
    r.text:SetText(item.text or "")
    local used = 0
    for k, b in ipairs(r.btn) do
        local spec = item.buttons and item.buttons[k]
        if spec then
            b:SetText(spec[1]); b:SetWidth(spec[4] or 60)
            b:SetScript("OnClick", function() spec[2](); Refresh() end)
            tip(b, spec[1], spec[3])
            b:SetEnabled(spec[5] ~= false)
            b:Show()
            used = used + (spec[4] or 60) + 3
        else
            b:Hide()
        end
    end
    r.text:SetWidth(w - 28 - used)
    if item.tip then
        r:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); item.tip(GameTooltip); GameTooltip:Show() end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil)
    end
end

-- a page that is a paged list of rows
local function listPage(parent, w, rows)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", CX, -44)
    p:SetSize(w, H - 54)
    p.rows = {}
    for i = 1, rows do
        local r = makeRow(p, w)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 1))
        p.rows[i] = r
    end
    p.page = 1
    p.prev = button(p, "<", 26, 18); p.prev:SetPoint("BOTTOMRIGHT", -34, 4)
    p.next = button(p, ">", 26, 18); p.next:SetPoint("BOTTOMRIGHT", -4, 4)
    p.pageText = fs(p, "GameFontDisableSmall"); p.pageText:SetPoint("RIGHT", p.prev, "LEFT", -6, 0)
    p.prev:SetScript("OnClick", function() p.page = p.page - 1; Refresh() end)
    p.next:SetScript("OnClick", function() p.page = p.page + 1; Refresh() end)
    function p:Show_(items)
        local per = #self.rows
        local pages = math.max(1, math.ceil(#items / per))
        self.page = math.max(1, math.min(self.page, pages))
        for i, r in ipairs(self.rows) do
            local it = items[(self.page - 1) * per + i]
            if it then fillRow(r, it, i, w) else r:Hide() end
        end
        self.prev:SetShown(pages > 1); self.next:SetShown(pages > 1); self.pageText:SetShown(pages > 1)
        self.prev:SetEnabled(self.page > 1); self.next:SetEnabled(self.page < pages)
        self.pageText:SetText(("page %d of %d"):format(self.page, pages))
    end
    p:Hide()
    return p
end

----------------------------------------------------------------------
-- Dialogs: writ size, tribute
----------------------------------------------------------------------
local function dialog(name, w, h)
    local f = box(UIParent, 0.04, 0.04, 0.07, 0.97)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = fs(f, "GameFontNormal"); f.title:SetPoint("TOPLEFT", 10, -8); f.title:SetTextColor(A[1], A[2], A[3])
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)
    _G[name] = f
    table.insert(UISpecialFrames, name)
    f:Hide()
    return f
end

local win
local sizer
local function chooseSize(key, m)
    if not sizer then
        sizer = dialog("VoidBountySize", 330, 130)
        sizer.title:SetText("Post a writ")
        sizer.info = fs(sizer, "GameFontHighlightSmall", 310); sizer.info:SetPoint("TOPLEFT", 10, -30)
        sizer.btns = {}
        for i, s in ipairs({ "S", "M", "L" }) do
            local b = button(sizer, "", 100, 22)
            b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 106, 10)
            b.size = s
            sizer.btns[i] = b
        end
    end
    sizer.info:SetText(("Writ on |cffff5555%s|r (killed you %d×). Pick the tribute size: the hunter chooses the goods (food, potions, ammo, reagents) up to this vendor value, and you hand them over in a trade. No gold ever changes hands."):format(m.name or "?", m.kills or 0))
    for _, b in ipairs(sizer.btns) do
        b:SetText(("%s · %s"):format(SIZE_NAME[b.size]:gsub("^%l", string.upper), ns.Money(ns.Cap(b.size, UnitLevel("player")))))
        b:SetScript("OnClick", function() ns.Post(key, b.size); sizer:Hide(); Refresh() end)
    end
    sizer:ClearAllPoints(); sizer:SetPoint("CENTER", win or UIParent, "CENTER")
    sizer:Show()
end
ns.ChooseSize = chooseSize

local pk
local PK_ROWS = 14
local function picker(w)
    if not pk then
        pk = dialog("VoidBountyPicker", 400, 30 + PK_ROWS * 20 + 74)
        pk.rows = {}
        for i = 1, PK_ROWS do
            local r = CreateFrame("Frame", nil, pk)
            r:SetSize(380, 20)
            r:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 20)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 0, 0)
            r.text = fs(r, "GameFontHighlightSmall", 250); r.text:SetPoint("LEFT", 20, 0); r.text:SetWordWrap(false)
            r.plus = button(r, "+", 22, 18); r.plus:SetPoint("RIGHT", 0, 0)
            r.n = fs(r, "GameFontHighlightSmall", 32, "CENTER"); r.n:SetPoint("RIGHT", r.plus, "LEFT", -2, 0)
            r.minus = button(r, "-", 22, 18); r.minus:SetPoint("RIGHT", r.n, "LEFT", -2, 0)
            pk.rows[i] = r
        end
        pk.total = fs(pk, "GameFontHighlightSmall", 380); pk.total:SetPoint("BOTTOMLEFT", 10, 40)
        pk.prev = button(pk, "<", 26); pk.prev:SetPoint("BOTTOMLEFT", 10, 10)
        pk.next = button(pk, ">", 26); pk.next:SetPoint("LEFT", pk.prev, "RIGHT", 4, 0)
        pk.send = button(pk, "Send pick", 100, 22); pk.send:SetPoint("BOTTOMRIGHT", -10, 10)
    end
    local choices = ns.TributeChoices(UnitLevel("player"))
    local counts, page = {}, 1
    for _, p in ipairs(w.pick or {}) do counts[p.id] = p.n end
    local CAT = { food = "Food & drink", potion = "Potion", bandage = "Bandage", ammo = "Ammo", reagent = "Reagent", supplies = "Supplies" }
    local function pickList()
        local out = {}
        for _, c in ipairs(choices) do if (counts[c.id] or 0) > 0 then out[#out + 1] = { id = c.id, n = counts[c.id] } end end
        return out
    end
    local function render()
        local pick = pickList()
        local pages = math.max(1, math.ceil(#choices / PK_ROWS))
        page = math.max(1, math.min(page, pages))
        for i, r in ipairs(pk.rows) do
            local c = choices[(page - 1) * PK_ROWS + i]
            if c then
                local step = (c.cat == "ammo") and 100 or (c.cat == "food" or c.cat == "potion" or c.cat == "bandage") and 5 or 1
                r.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.id) or 134400)
                r.text:SetText(("%s |cff888888%s%s · %s|r"):format(c.name, CAT[c.cat] or c.cat, c.req > 0 and (" " .. c.req) or "", ns.Money(c.price)))
                r.n:SetText(tostring(counts[c.id] or 0))
                r.plus:SetScript("OnClick", function()
                    counts[c.id] = (counts[c.id] or 0) + step
                    if ns.PickCost(pickList()) > w.cap or #pickList() > 6 then counts[c.id] = counts[c.id] - step; if counts[c.id] <= 0 then counts[c.id] = nil end end
                    render()
                end)
                r.minus:SetScript("OnClick", function()
                    counts[c.id] = math.max(0, (counts[c.id] or 0) - step)
                    if counts[c.id] == 0 then counts[c.id] = nil end
                    render()
                end)
                r:Show()
            else
                r:Hide()
            end
        end
        pk.total:SetText(("Picked %s of %s · page %d/%d%s"):format(ns.Money(ns.PickCost(pick)), ns.Money(w.cap), page, pages,
            #pick > 0 and ("\n" .. ns.PickText(pick)) or ""))
        pk.send:SetEnabled(#pick > 0)
        pk.prev:SetEnabled(page > 1); pk.next:SetEnabled(page < pages)
    end
    pk.title:SetText("Your tribute for " .. w.tname)
    pk.prev:SetScript("OnClick", function() page = page - 1; render() end)
    pk.next:SetScript("OnClick", function() page = page + 1; render() end)
    pk.send:SetScript("OnClick", function()
        ns.SendPick(w.id, pickList())
        ns.say(("tribute picked: %s. %s gets the shopping list; meet them and trade."):format(ns.PickText(pickList()), w.author))
        pk:Hide(); Refresh()
    end)
    pk:ClearAllPoints(); pk:SetPoint("CENTER", win or UIParent, "CENTER", 60, 0)
    pk:Show()
    render()
end

----------------------------------------------------------------------
-- Board: posters + detail
----------------------------------------------------------------------
local POSTER_W, POSTER_H = 176, 236
local DETAIL_W = CW - 3 * (POSTER_W + 8) - 6
local board = { sel = nil, page = 1, sort = "reward", zone = false, lvl = false, recent = false }

local SORTS = { { "reward", "Biggest reward" }, { "newest", "Newest" }, { "noto", "Most dangerous" }, { "seen", "Seen latest" } }

local function makePoster(parent)
    local p = CreateFrame("Button", nil, parent, "BackdropTemplate")
    p:SetSize(POSTER_W, POSTER_H)
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    p:SetBackdropColor(PARCH[1], PARCH[2], PARCH[3], 1)
    p:SetBackdropBorderColor(0.48, 0.35, 0.16, 1)
    p.wanted = p:CreateFontString(nil, "OVERLAY")
    p.wanted:SetFont("Fonts\\MORPHEUS.TTF", 20, "")
    p.wanted:SetTextColor(BLOOD[1], BLOOD[2], BLOOD[3])
    p.wanted:SetPoint("TOP", 0, -6)
    p.wanted:SetText("WANTED")
    p.ring = p:CreateTexture(nil, "ARTWORK")
    p.ring:SetSize(48, 48)
    p.ring:SetPoint("TOP", 0, -32)
    p.portrait = p:CreateTexture(nil, "OVERLAY")
    p.portrait:SetSize(44, 44)
    p.portrait:SetPoint("CENTER", p.ring, "CENTER")
    p.ring:SetColorTexture(0.35, 0.23, 0.07, 1)
    local function line(y, font, size)
        local t = p:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
        if size then t:SetFont(STANDARD_TEXT_FONT, size, "") end
        t:SetTextColor(INK[1], INK[2], INK[3])
        t:SetPoint("TOP", 0, y)
        t:SetWidth(POSTER_W - 12)
        t:SetWordWrap(false)
        return t
    end
    p.name = line(-84, nil, 13)
    p.sub = line(-100, nil, 10)
    p.guild = line(-113, nil, 10)
    p.noto = line(-128, nil, 10)
    p.reward = box(p, 0.85, 0.75, 0.54, 1, { 0.48, 0.35, 0.16, 0.8 })
    p.reward:SetSize(POSTER_W - 16, 34)
    p.reward:SetPoint("TOP", 0, -143)
    p.rewardText = p.reward:CreateFontString(nil, "OVERLAY")
    p.rewardText:SetFont(STANDARD_TEXT_FONT, 10, "")
    p.rewardText:SetTextColor(INK[1], INK[2], INK[3])
    p.rewardText:SetPoint("CENTER")
    p.rewardText:SetWidth(POSTER_W - 20)
    p.seen = line(-181, nil, 10)
    p.seen:SetWordWrap(true)            -- "Last seen 49m ago" / the zone: two short lines, never cut off
    p.seen:SetTextColor(BLOOD[1], BLOOD[2], BLOOD[3])
    p.act = CreateFrame("Button", nil, p, "BackdropTemplate")
    p.act:SetSize(POSTER_W - 16, 22)
    p.act:SetPoint("BOTTOM", 0, 8)
    p.act:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    p.act.text = p.act:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.act.text:SetPoint("CENTER")
    p.act:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    p.act:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.15)
    -- the stamp sits beside the portrait, never over the name (first test, 11-11)
    p.stamp = p:CreateFontString(nil, "OVERLAY")
    p.stamp:SetFont(STANDARD_TEXT_FONT, 12, "")
    p.stamp:SetPoint("LEFT", p.ring, "RIGHT", 3, 0)
    p.stamp:SetJustifyH("CENTER")
    p.stamp:SetShadowColor(1, 1, 1, 0.4)
    p.stamp:SetShadowOffset(1, -1)
    pcall(p.stamp.SetRotation, p.stamp, math.rad(-14))
    p.selected = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.selected:SetPoint("TOPLEFT", -3, 3); p.selected:SetPoint("BOTTOMRIGHT", 3, -3)
    p.selected:SetColorTexture(A[1], A[2], A[3], 0.8)
    p:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    p:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    p:Hide()
    return p
end

local function fillPoster(p, ps)
    p.data = ps
    classIcon(p.portrait, ps.class ~= "" and ps.class or nil)
    p.name:SetText(ps.name or "?")
    p.sub:SetText(("%s %s%s"):format(ns.ClassName(ps.class ~= "" and ps.class or nil), ps.level and ps.level > 0 and ps.level or "??", ps.race and (" · " .. ps.race) or ""))
    p.guild:SetText(ps.guild and ("<" .. ps.guild .. ">") or " ")
    local c, tier = ns.Notoriety(ps.guid)
    p.noto:SetText(c > 0 and ("%s · |cff8a1a0a%d|r of us killed"):format(tier or "Known", c) or "No kills reported yet")
    local n = #ps.writs
    local reward
    if ps.open > 0 then
        local first = n > 1 and ("Reward from %d writs"):format(n) or ("Reward: %s writ"):format(SIZE_NAME[ps.writs[1].size] or "?")
        reward = ("%s\n|cff8a1a0a≈ %s|r in goods"):format(first, ns.Money(ps.cap))
    else
        reward = "Claimed by\n" .. (ps.claimedBy or "?")
    end
    p.rewardText:SetText(reward)
    local zone = ps.where and ps.where:match("([^,]+)$")
    p.seen:SetText(ps.last and ("Last seen %s\n%s"):format(ago(ps.last), zone or "") or "Not seen lately")
    local mineTaken = false
    for _, w in ipairs(ps.writs) do if w.hunters and w.hunters[me()] then mineTaken = true end end
    local stamp, sr, sg, sb
    if ps.status ~= "open" then stamp, sr, sg, sb = "CLAIMED", 0.63, 0.09, 0.09
    elseif ps.burned and ps.burned >= n then stamp, sr, sg, sb = "BURNED", 0.12, 0.1, 0.08
    elseif ps.mine then stamp, sr, sg, sb = "YOUR\nWRIT", 0.08, 0.27, 0.55 end
    p.stamp:SetText(stamp or "")
    if stamp then p.stamp:SetTextColor(sr, sg, sb, 0.9) end
    local label, enabled, r, g, b = "Take the writ", true, BLOOD[1], BLOOD[2], BLOOD[3]
    if ps.status ~= "open" then label, enabled, r, g, b = "Claimed", false, 0.45, 0.4, 0.3
    elseif ps.mine and n == 1 then label, enabled, r, g, b = "Your writ", false, 0.12, 0.3, 0.5
    elseif mineTaken then label, enabled, r, g, b = "You're hunting", false, 0.15, 0.4, 0.15
    elseif ps.burned and ps.burned >= n then label, enabled, r, g, b = "Poster burned", false, 0.3, 0.3, 0.3 end
    p.act:SetBackdropColor(r, g, b, 1)
    p.act.text:SetText(label)
    p.act.text:SetTextColor(0.96, 0.9, 0.77)
    p.act:SetEnabled(enabled)
    p.act:SetScript("OnClick", function()
        for _, w in ipairs(ps.writs) do
            if ns.Status(w) == "open" and w.author ~= me() and not ns.Burned(w.author) then ns.Accept(w.id) end
        end
        Refresh()
    end)
    tip(p.act, label, enabled and "Takes every open writ on this player. Your killing blow, after taking it, outside cities and battlegrounds; your combat log is the proof." or nil)
    p.selected:SetShown(board.sel == ps.guid)
    p:SetScript("OnClick", function() board.sel = ps.guid; Refresh() end)
    p:Show()
end

local function bar(n, max)
    local w = math.max(1, math.floor(6 * n / math.max(1, max)))   -- 6 wide: the zone name fits on the same line
    -- "||" is one drawn "|" ("|" alone starts an escape code: a lone one ate the colours, 11-11)
    return ("|cffff7755%s|r|cff555555%s|r %d"):format(("||"):rep(w), ("||"):rep(6 - w), n)
end

local function hoursText(hours)
    if not hours then return "not enough sightings yet" end
    local list = {}
    for h, n in pairs(hours) do list[#list + 1] = { h = h, n = n } end
    if #list == 0 then return "not enough sightings yet" end
    table.sort(list, function(a, b) return a.n > b.n end)
    local t = {}
    for i = 1, math.min(3, #list) do t[#t + 1] = ("%02d:00"):format(list[i].h) end
    return "mostly around " .. table.concat(t, ", ")
end

local function buildBoard(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetPoint("TOPLEFT", CX, -44)
    b:SetSize(CW, H - 54)
    -- filters
    b.zone = button(b, "", 110, 20); b.zone:SetPoint("TOPLEFT", 0, 0)
    b.lvl = button(b, "", 110, 20); b.lvl:SetPoint("LEFT", b.zone, "RIGHT", 4, 0)
    b.recent = button(b, "", 110, 20); b.recent:SetPoint("LEFT", b.lvl, "RIGHT", 4, 0)
    b.sort = button(b, "", 140, 20); b.sort:SetPoint("LEFT", b.recent, "RIGHT", 4, 0)
    b.zone:SetScript("OnClick", function() board.zone = not board.zone; board.page = 1; Refresh() end)
    b.lvl:SetScript("OnClick", function() board.lvl = not board.lvl; board.page = 1; Refresh() end)
    b.recent:SetScript("OnClick", function() board.recent = not board.recent; board.page = 1; Refresh() end)
    b.sort:SetScript("OnClick", function()
        for i, s in ipairs(SORTS) do if s[1] == board.sort then board.sort = SORTS[i % #SORTS + 1][1]; break end end
        Refresh()
    end)
    tip(b.zone, "Zone", "All zones, or only posters for players last seen in your zone.")
    tip(b.lvl, "Level", "All levels, or only targets within 5 levels of you.")
    tip(b.recent, "Seen", "Any time, or only targets seen in the last hour.")
    tip(b.sort, "Sort")
    b.posters = {}
    for i = 1, 6 do
        local p = makePoster(b)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        p:SetPoint("TOPLEFT", col * (POSTER_W + 8), -28 - row * (POSTER_H + 8))
        b.posters[i] = p
    end
    b.empty = fs(b, "GameFontDisable", 3 * (POSTER_W + 8) - 20, "CENTER")
    b.empty:SetPoint("TOP", -DETAIL_W / 2, -160)
    b.empty:SetText("No wanted posters yet.\n\nPost one from Blood debts on a player who killed you,\nor wait for other VoidBounty players on your side to post theirs.")
    b.prev = button(b, "<", 26, 18); b.prev:SetPoint("BOTTOMLEFT", 3 * (POSTER_W + 8) / 2 - 70, 0)
    b.pageText = fs(b, "GameFontDisableSmall", 80, "CENTER"); b.pageText:SetPoint("LEFT", b.prev, "RIGHT", 4, 0)
    b.next = button(b, ">", 26, 18); b.next:SetPoint("LEFT", b.pageText, "RIGHT", 4, 0)
    b.prev:SetScript("OnClick", function() board.page = board.page - 1; Refresh() end)
    b.next:SetScript("OnClick", function() board.page = board.page + 1; Refresh() end)
    -- detail side
    local d = box(b, 0.06, 0.06, 0.1, 0.9)
    d:SetPoint("TOPRIGHT", 0, -28)
    d:SetSize(DETAIL_W, H - 54 - 28)
    b.d = d
    d.icon = d:CreateTexture(nil, "ARTWORK"); d.icon:SetSize(36, 36); d.icon:SetPoint("TOPLEFT", 8, -8)
    d.name = fs(d, "GameFontNormal", DETAIL_W - 56); d.name:SetPoint("TOPLEFT", 50, -8); d.name:SetTextColor(1, 0.4, 0.35)
    d.name:SetWordWrap(false)   -- a long name wrapped over the class line (11-11)
    d.sub = fs(d, "GameFontHighlightSmall", DETAIL_W - 56); d.sub:SetPoint("TOPLEFT", 50, -28)
    d.body = fs(d, "GameFontHighlightSmall", DETAIL_W - 16); d.body:SetPoint("TOPLEFT", 8, -52)
    d.track = button(d, "Track", DETAIL_W - 16, 22); d.track:SetPoint("BOTTOMLEFT", 8, 60)
    d.add = button(d, "Add my bounty", DETAIL_W - 16, 22); d.add:SetPoint("BOTTOMLEFT", 8, 34)
    d.route = button(d, "Route to last seen", DETAIL_W - 16, 22); d.route:SetPoint("BOTTOMLEFT", 8, 8)
    d.none = fs(d, "GameFontDisableSmall", DETAIL_W - 16, "CENTER"); d.none:SetPoint("CENTER")
    d.none:SetText("Click a poster for the details: notoriety, hunting grounds, usual hours, who posted it.")
    b:Hide()
    return b
end

local function showBoard(b)
    for _, k in ipairs({ { b.zone, board.zone and "Zone: here" or "Zone: all" }, { b.lvl, board.lvl and "Level: near me" or "Level: all" },
                         { b.recent, board.recent and "Seen: last hour" or "Seen: any time" } }) do k[1]:SetText(k[2]) end
    for _, s in ipairs(SORTS) do if s[1] == board.sort then b.sort:SetText("Sort: " .. s[2]:lower()) end end
    local list, here, myLvl = {}, GetZoneText and GetZoneText() or "", UnitLevel("player")
    for _, ps in ipairs(ns.Posters()) do
        local ok = true
        if board.zone and not ((ps.where or ""):find(here, 1, true)) then ok = false end
        if board.lvl and ps.level and ps.level > 0 and math.abs(ps.level - myLvl) > 5 then ok = false end
        if board.recent and not (ps.last and time() - ps.last <= 3600) then ok = false end
        if ok then list[#list + 1] = ps end
    end
    local key = {
        reward = function(p) return p.cap end, newest = function(p) return p.newest end,
        noto = function(p) return p.noto end, seen = function(p) return p.last or 0 end,
    }
    local kf = key[board.sort]
    table.sort(list, function(a, c)
        if (a.status == "open") ~= (c.status == "open") then return a.status == "open" end
        return kf(a) > kf(c)
    end)
    local pages = math.max(1, math.ceil(#list / 6))
    board.page = math.max(1, math.min(board.page, pages))
    for i, p in ipairs(b.posters) do
        local ps = list[(board.page - 1) * 6 + i]
        if ps then fillPoster(p, ps) else p:Hide() end
    end
    b.empty:SetShown(#list == 0)
    b.prev:SetShown(pages > 1); b.next:SetShown(pages > 1); b.pageText:SetShown(pages > 1)
    b.prev:SetEnabled(board.page > 1); b.next:SetEnabled(board.page < pages)
    b.pageText:SetText(("page %d of %d"):format(board.page, pages))

    -- detail
    local d, sel = b.d, nil
    for _, ps in ipairs(list) do if ps.guid == board.sel then sel = ps end end
    if not sel and board.sel then for _, ps in ipairs(ns.Posters()) do if ps.guid == board.sel then sel = ps end end end
    local show = sel ~= nil
    for _, f in ipairs({ d.icon, d.name, d.sub, d.body, d.track, d.add, d.route }) do f:SetShown(show) end
    d.none:SetShown(not show)
    if not show then return end
    local e = ns.db().seen[sel.guid] or {}
    classIcon(d.icon, sel.class ~= "" and sel.class or nil)
    d.name:SetText(sel.name)
    d.sub:SetText(("%s %s · server %s%s"):format(ns.ClassName(sel.class ~= "" and sel.class or nil), sel.level or "??", ns.Server(sel.guid) or "?",
        sel.guild and ("\n<" .. sel.guild .. ">") or ""))
    local c, tier, color, nz = ns.Notoriety(sel.guid)
    local lines = {}
    lines[#lines + 1] = c > 0 and ("|cff%sNotoriety: %s|r (%d kills on our side, 7 days)"):format(color or "cccc88", tier or "Known", c)
        or "|cff888888Notoriety: no kills reported yet|r"
    -- hunting grounds: where they're seen + where they killed
    local grounds, max = {}, 1
    for z, n in pairs(e.zones or {}) do grounds[z] = (grounds[z] or 0) + n end
    for z, n in pairs(nz or {}) do grounds[z] = (grounds[z] or 0) + n * 2 end
    local gl = {}
    for z, n in pairs(grounds) do gl[#gl + 1] = { z = z, n = n }; max = math.max(max, n) end
    table.sort(gl, function(a, z) return a.n > z.n end)
    lines[#lines + 1] = "\n|cff00c7ffHunting grounds|r"
    if #gl == 0 then lines[#lines + 1] = "|cff888888not enough sightings yet|r" end
    for i = 1, math.min(4, #gl) do lines[#lines + 1] = ("%s  %s"):format(bar(gl[i].n, max), gl[i].z) end
    lines[#lines + 1] = "\n|cff00c7ffUsually online|r\n" .. hoursText(e.hours)
    lines[#lines + 1] = "\n|cff00c7ffPosters|r"
    for author, size in pairs(sel.posters) do
        lines[#lines + 1] = ("%s · %s%s"):format(author, SIZE_NAME[size] or "?", ns.Burned(author) and " |cffff3333(Burned)|r" or "")
    end
    local hunters = 0
    for _ in pairs(sel.hunters) do hunters = hunters + 1 end
    lines[#lines + 1] = ("\n|cff00c7ffHunters on it:|r %d"):format(hunters)
    lines[#lines + 1] = ("|cff00c7ffLast seen:|r %s%s"):format(ago(sel.last), sel.where and (" · " .. sel.where) or "")
    if e.sharedBy then lines[#lines + 1] = ("|cff888888reported by %s|r"):format(e.sharedBy) end
    d.body:SetText(table.concat(lines, "\n"))
    local tracked = ns.char().track[sel.guid]
    d.track:SetText(tracked and "Stop tracking" or "Track")
    d.track:SetScript("OnClick", function() toggleTrack(sel.guid); Refresh() end)
    tip(d.track, "Track", "An alert (sound and chat) the moment you or anyone on your side sees them.")
    local m = ns.char().marked[sel.guid]
    local can, why = false, "Only a player who killed you can get your writ (blood debt)."
    if m then can, why = ns.CanPost(sel.guid, m) end
    d.add:SetEnabled(can)
    d.add:SetScript("OnClick", function() chooseSize(sel.guid, m) end)
    tip(d.add, "Add my bounty", can and "Stack your own writ on this poster: a bigger reward for whoever gets them." or why)
    d.route:SetEnabled(e.map ~= nil)
    d.route:SetScript("OnClick", function() routeTo(sel.guid) end)
    tip(d.route, "Route to last seen", "A waypoint to the area they were last seen in (across continents if needed). Never a live position.")
end

----------------------------------------------------------------------
-- The list pages
----------------------------------------------------------------------
local function isGUID(s) return ns.Bus.IsGUID(s) end

local function debtsItems()
    local c, seen, items = ns.char(), ns.db().seen, {}
    local marks = {}
    for key, m in pairs(c.marked) do marks[#marks + 1] = { key = key, m = m } end
    table.sort(marks, function(a, b)
        if (a.m.kills or 0) ~= (b.m.kills or 0) then return (a.m.kills or 0) > (b.m.kills or 0) end
        return (a.m.lastSeen or a.m.first or 0) > (b.m.lastSeen or b.m.first or 0)
    end)
    items[#items + 1] = { head = true, text = ("Blood debts: %d player%s who killed you or you marked"):format(#marks, #marks == 1 and "" or "s") }
    if #marks == 0 then items[#items + 1] = { text = ns.WRITS and "|cff888888Nobody yet. Whoever kills you lands here, with how often and where. Then you can post a writ on them.|r"
        or "|cff888888Nobody yet. Whoever kills you lands here, with how often and where, and the warning goes red when they come back.|r" } end
    for _, x in ipairs(marks) do
        local key, m = x.key, x.m
        local e = seen[key] or m
        local near = ns.near[key] and (GetTime() - ns.near[key] <= ns.NEAR_FOR)
        local cN, tier = ns.Notoriety(key)
        local can, why = ns.CanPost(key, m)
        local tracked = c.track[key]
        items[#items + 1] = {
            cls = e.class or "",
            text = ("%s%s|r  %s%s  %s  |cff999999%s%s|r%s"):format(near and "|cff55ff55" or "|cffffffff", m.name or "?", ns.Who(e),
                e.guild and (" <" .. e.guild .. ">") or "",
                (m.kills or 0) > 0 and ("|cffff7777killed you %d×|r"):format(m.kills) or "|cffff7777marked|r",
                near and "nearby now" or ("seen " .. ago(m.lastSeen)), m.killWhere and (" · last kill in " .. m.killWhere) or "",
                cN > 0 and ("  |cffff9944%s (%d)|r"):format(tier or "Known", cN) or ""),
            buttons = {
                { "Unmark", function() ns.Unmark(key) end, "Off your list. They come back if they kill you again.", 56 },
                { tracked and "Untrack" or "Track", function() if isGUID(key) then toggleTrack(key) end end, "Alert when anyone on your side sees them.", 58, isGUID(key) },
                ns.WRITS and { "Writ", function() chooseSize(key, m) end, can and "Post a writ: other VoidBounty players hunt them for a tribute you pay in vendor goods." or why, 48, can } or nil,
            } }
    end
    return items
end

local function writLine(w)
    local e = ns.db().seen[w.tguid] or {}
    return ("|cffff5555%s|r %s · %s (≤%s)"):format(w.tname, ns.Who({ class = w.tcls ~= "" and w.tcls or e.class, level = e.level or (w.tlvl > 0 and w.tlvl or nil) }),
        SIZE_NAME[w.size] or "?", ns.Money(w.cap))
end

local function huntsItems()
    local items, took, posted = {}, {}, {}
    for _, w in pairs(ns.Writs()) do
        local st = ns.Status(w)
        if st ~= "withdrawn" and st ~= "expired" and not (st == "paid" and time() - (w.paid or w.recv or 0) > 86400) then
            if w.author == me() then posted[#posted + 1] = w
            elseif (w.hunters and w.hunters[me()]) or (w.claim and w.claim.hunter == me()) then took[#took + 1] = w end
        end
    end
    local function newest(a, b) return a.posted > b.posted end
    table.sort(took, newest); table.sort(posted, newest)
    if ns.Burned(me()) then items[#items + 1] = { text = "|cffff3333You're Burned: a claimed writ of yours is past its deadline unpaid. Pay it to clear it.|r" } end
    items[#items + 1] = { head = true, text = "Writs you took" }
    if #took == 0 then items[#items + 1] = { text = "|cff888888None yet. Take one from the Board.|r" } end
    for _, w in ipairs(took) do
        local st, e = ns.Status(w), ns.db().seen[w.tguid] or {}
        local mineClaim = w.claim and w.claim.hunter == me()
        local status, btns
        if st == "open" then
            status = ("hunting · last seen %s%s"):format(ago(e.last), e.where and (" · " .. e.where) or "")
            btns = { { "Route", function() routeTo(w.tguid) end, "Waypoint to where they were last seen.", 52, e.map ~= nil },
                     { ns.char().track[w.tguid] and "Untrack" or "Track", function() toggleTrack(w.tguid) end, "Alert when anyone on your side sees them.", 58 } }
        elseif not mineClaim then status = "|cff999999claimed by " .. (w.claim and w.claim.hunter or "?") .. "|r"
        elseif st == "paid" then status = "|cff55ff55tribute received|r"
        elseif not w.pick then
            status = "|cffffd200you got them!|r pick your tribute"
            btns = { { "Pick tribute", function() picker(w) end, "Choose your goods, up to " .. ns.Money(w.cap) .. ".", 80 } }
        else
            status = ("|cffffd200waiting for %s:|r %s"):format(w.author, ns.PickText(w.pick))
            btns = { { "Got it", function() ns.MarkPaid(w.id, false) end, "You received it (the trade window does this by itself).", 52 },
                     { "Repick", function() picker(w) end, "Change your pick.", 52 } }
        end
        items[#items + 1] = { cls = w.tcls, text = writLine(w) .. "  " .. status, buttons = btns }
    end
    items[#items + 1] = { head = true, text = "Writs you posted" }
    if #posted == 0 then items[#items + 1] = { text = "|cff888888None. Post one from Blood debts.|r" } end
    for _, w in ipairs(posted) do
        local st = ns.Status(w)
        local n = 0
        for _ in pairs(w.hunters or {}) do n = n + 1 end
        local status, btns
        if st == "open" then
            status = ("open · %d hunter%s · posted %s"):format(n, n == 1 and "" or "s", ago(w.posted))
            btns = { { "Withdraw", function() ns.Withdraw(w.id) end, "Take it down (only before it's claimed).", 62 } }
        elseif st == "paid" then status = "|cff55ff55settled|r"
        else
            local left = ns.PAY_DAYS * 86400 - (time() - w.claim.t)
            status = (st == "overdue" and "|cffff3333overdue|r " or "|cffffd200claimed|r ") .. ("by %s"):format(w.claim.hunter)
                .. (w.pick and (" · owe: " .. ns.PickText(w.pick)) or " · picking tribute")
                .. (left > 0 and (" · %dh left"):format(math.floor(left / 3600)) or "")
            if w.pick then btns = { { "Shop", function() ns.ToErrands(w) end, "Puts the tribute on VoidGPS's errand list (routes to the nearest vendor). Then trade it to " .. w.claim.hunter .. ".", 48 } } end
        end
        items[#items + 1] = { cls = w.tcls, text = writLine(w) .. "  " .. status, buttons = btns }
    end
    return items
end

local function ledgerItems()
    local items, list = {}, {}
    for _, w in pairs(ns.Writs()) do
        if w.author == me() or (w.hunters and w.hunters[me()]) or (w.claim and w.claim.hunter == me()) then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.posted > b.posted end)
    items[#items + 1] = { head = true, text = "Ledger: every writ you posted or took" }
    if #list == 0 then items[#items + 1] = { text = "|cff888888Empty so far.|r" } end
    local LABEL = { open = "open", claimed = "|cffffd200claimed|r", overdue = "|cffff3333overdue|r", paid = "|cff55ff55settled|r",
                    expired = "|cff888888expired|r", withdrawn = "|cff888888withdrawn|r" }
    for _, w in ipairs(list) do
        local role = w.author == me() and "posted" or "took"
        items[#items + 1] = { cls = w.tcls,
            text = ("%s  |cff999999%s %s|r  %s%s%s"):format(writLine(w), role, date("%m-%d", w.posted), LABEL[ns.Status(w)] or "?",
                w.claim and (" · by " .. w.claim.hunter .. " " .. date("%m-%d %H:%M", math.floor(w.claim.t))) or "",
                w.pick and (" · " .. ns.PickText(w.pick)) or "") }
    end
    return items
end

local function sightingsItems()
    local items = {}
    local danger = ns.ZoneDanger(900)
    items[#items + 1] = { head = true, text = "Enemy players per zone, last 15 minutes (yours + your side's)" }
    if #danger == 0 then items[#items + 1] = { text = "|cff888888Quiet: nobody seen.|r" } end
    local enemy = UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde"
    for i = 1, math.min(5, #danger) do
        local z = danger[i]
        local lv = z.lvlMax > 0 and (z.lvlMin == z.lvlMax and ("· level %d"):format(z.lvlMin) or ("· levels %d-%d"):format(z.lvlMin, z.lvlMax)) or ""
        items[#items + 1] = { text = ("%s  |cffff7755%d|r %s %s"):format(z.zone, z.n, enemy, lv) }
    end
    items[#items + 1] = { head = true, text = "Feed: last 30 minutes" }
    local list = {}
    for g, e in pairs(ns.db().seen) do
        if e.last and time() - e.last <= 1800 then list[#list + 1] = { g = g, e = e } end
    end
    table.sort(list, function(a, b) return a.e.last > b.e.last end)
    if #list == 0 then items[#items + 1] = { text = "|cff888888Nothing in the last 30 minutes.|r" } end
    for _, x in ipairs(list) do
        local e, g = x.e, x.g
        local near = ns.near[g] and (GetTime() - ns.near[g] <= ns.NEAR_FOR)
        local cN, tier = ns.Notoriety(g)
        items[#items + 1] = { cls = e.class or "",
            text = ("%s%s|r  %s%s  |cff999999%s · %s%s|r%s%s"):format(near and "|cff55ff55" or "|cffdddddd", e.name, ns.Who(e),
                e.guild and (" <" .. e.guild .. ">") or "", near and "nearby" or ago(e.last), e.where or "",
                e.how == "shared" and (" · via " .. (e.sharedBy or "?")) or "",
                ns.IsMarked(g) and "  |cffff5555marked|r" or "", cN > 0 and ("  |cffff9944%s|r"):format(tier or "") or ""),
            buttons = { { ns.char().track[g] and "Untrack" or "Track", function() toggleTrack(g) end, "Alert when anyone on your side sees them.", 58 } } }
    end
    return items
end

local function standing(r)
    if r.burnedMe then return "|cffff3333Burned|r" end
    local s = r.settled
    if s >= 10 then return "|cffff9944Executioner|r" elseif s >= 3 then return "|cffffd27aHunter|r"
    elseif s >= 1 then return "|cffffd27aCollector|r" end
    return "|cffccccccNewcomer|r"
end
ns.Standing = function() return standing(ns.Hall()) end

local function hallItems()
    local r, items = ns.Hall(), {}
    if not ns.WRITS then
        -- writs coming soon: no standing or kills yet (kills are proven with them), just the threat list
        items[#items + 1] = { head = true, text = "Most wanted: who's killing our side (last 7 days)" }
        if #r.most == 0 then items[#items + 1] = { text = "|cff888888No kills reported yet. Every VoidBounty player's death on your side adds to this.|r" } end
        for i = 1, math.min(20, #r.most) do
            local x = r.most[i]
            items[#items + 1] = { cls = x.class or "", text = ("%d. |cffff5555%s|r %s  ·  |cffff9944%s|r, %d kill%s"):format(i, x.name or "?",
                ns.Who({ class = x.class, level = x.level }), x.tier or "Known", x.kills, x.kills == 1 and "" or "s"),
                buttons = { { ns.char().track[x.guid] and "Untrack" or "Track", function() toggleTrack(x.guid) end, "Alert when anyone on your side sees them.", 58 } } }
        end
        items[#items + 1] = { head = true, text = "You" }
        items[#items + 1] = { text = ns.KILLS and ("Players killed (combat log): |cff55ff55%d|r   ·   Deaths to enemy players: |cffff7777%d|r"):format(r.kills, r.deaths)
            or ("Deaths to enemy players: |cffff7777%d|r"):format(r.deaths) }
        if ns.KILLS then
            local list = {}
            for _, k in ipairs(ns.Kills()) do if k.killer == UnitGUID("player") then list[#list + 1] = k end end
            table.sort(list, function(a, b) return a.t > b.t end)
            items[#items + 1] = { head = true, text = "Your kills (from your combat log)" }
            if #list == 0 then items[#items + 1] = { text = "|cff888888None yet. A kill shows here after a /reload.|r" } end
            for i = 1, math.min(10, #list) do
                local k = list[i]
                items[#items + 1] = { text = ("|cffff5555%s|r  |cff999999%s · %s|r"):format(k.name or "?", date("%m-%d %H:%M", math.floor(k.t)), k.zone or "?") }
            end
        end
        return items
    end
    items[#items + 1] = { head = true, text = "Your record" }
    items[#items + 1] = { text = ("Standing: %s   ·   Players killed (combat log): |cff55ff55%d|r   ·   Deaths to enemy players: |cffff7777%d|r   ·   K/D %.1f"):format(
        standing(r), r.kills, r.deaths, r.kills / math.max(1, r.deaths)) }
    items[#items + 1] = { text = ("Writs posted: %d (%d paid out)   ·   Writs claimed: %d (%d settled)"):format(r.posted, r.paidOut, r.claimed, r.settled) }
    items[#items + 1] = { head = true, text = "Top hunters (writs settled, from the ledger your game has seen)" }
    if #r.top == 0 then items[#items + 1] = { text = "|cff888888No claims yet. The full ladder comes with voidscout.io.|r" } end
    for i = 1, math.min(5, #r.top) do
        local h = r.top[i]
        items[#items + 1] = { text = ("%d. %s  ·  %d claimed, %d settled"):format(i, h.name, h.claims, h.settled) }
    end
    items[#items + 1] = { head = true, text = "Most wanted (kills on our side, last 7 days)" }
    if #r.most == 0 then items[#items + 1] = { text = "|cff888888No kills reported yet. Every VoidBounty player's death adds to this.|r" } end
    for i = 1, math.min(8, #r.most) do
        local x = r.most[i]
        items[#items + 1] = { cls = x.class or "", text = ("%d. |cffff5555%s|r %s  ·  |cffff9944%s|r, %d kill%s"):format(i, x.name or "?",
            ns.Who({ class = x.class, level = x.level }), x.tier or "Known", x.kills, x.kills == 1 and "" or "s"),
            buttons = { { ns.char().track[x.guid] and "Untrack" or "Track", function() toggleTrack(x.guid) end, "Alert when anyone on your side sees them.", 58 } } }
    end
    return items
end

local function buildSettings(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetPoint("TOPLEFT", CX, -44)
    s:SetSize(CW, H - 54)
    local h = header(s, "Settings (this character)")
    h:SetPoint("TOPLEFT", 0, 0)
    s.checks = {}
    local OPTS = {
        { "alerts", "Nearby warning", "A small line near the top of the screen while enemy players are around (Shift-drag it to move it). Red for players who killed you." },
        { "sound", "Sound for Marked and Tracked players", "A warning sound when a player who killed you shows up, or a tracked player is spotted." },
        { "quiet", "Show unmarked enemies too", "One quiet line for other enemy players: \"3 Alliance nearby: ...\"." },
        ns.KILLS and { "autolog", "Auto combat log", "On while you're PvP-flagged in the world (it's how your kills are proven), off 5 minutes after. Never touches a log something else started.", true } or nil,
        { "shareSeen", "Share my sightings with my side", "Enemy players you see are sent to other VoidBounty players of your faction (name, level, class, zone and a rough area, never a live position)." },
        { "shareDeaths", "Share my deaths (notoriety)", "When an enemy player kills you, your side hears \"killed by X\". That builds Most wanted. Your own name isn't stored by anyone." },
    }
    do   -- drop the nil hole (autolog when writs are off)
        local packed = {}
        for i = 1, 6 do if OPTS[i] then packed[#packed + 1] = OPTS[i] end end
        OPTS = packed
    end
    for i, o in ipairs(OPTS) do
        local c = CreateFrame("CheckButton", nil, s, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("TOPLEFT", 0, -22 - (i - 1) * 46)
        c.label = fs(c, "GameFontHighlight"); c.label:SetPoint("LEFT", c, "RIGHT", 2, 6); c.label:SetText(o[2])
        c.desc = fs(c, "GameFontDisableSmall", CW - 40); c.desc:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -2); c.desc:SetText(o[3])
        c:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            ns.char()[o[1]] = on
            if o[1] == "autolog" and on then ns.LogState() end
            ns.RenderAlert()
        end)
        c.key, c.defaultOn = o[1], o[4]
        s.checks[i] = c
    end
    s.test = button(s, "Test the warning", 140, 22)
    s.test:SetPoint("TOPLEFT", 0, -22 - #OPTS * 46 - 8)
    s.test:SetScript("OnClick", function() ns.Test(); C_Timer.After(25, function() ns.Unmark("Player-0-TEST0001"); ns.db().seen["Player-0-TEST0001"] = nil; ns.RenderAlert(); Refresh() end) end)
    tip(s.test, "Test the warning", "A made-up Marked enemy \"Test Dummy\" near you for 25 seconds.")
    s.mark = button(s, "Mark my target", 140, 22)
    s.mark:SetPoint("LEFT", s.test, "RIGHT", 8, 0)
    s.mark:SetScript("OnClick", function() ns.MarkTarget(); Refresh() end)
    tip(s.mark, "Mark my target", ns.WRITS and "Puts the enemy player you have targeted on your Blood debts list. A writ needs them to have killed you."
        or "Puts the enemy player you have targeted on your Blood debts list: the warning goes red when they're near.")
    s.about = fs(s, "GameFontDisableSmall", CW - 10)
    s.about:SetPoint("TOPLEFT", s.test, "BOTTOMLEFT", 0, -16)
    s.about:SetText(ns.WRITS and "How it works: writs are paid in basic vendor goods, never gold (Blizzard bans for gold between strangers). A writ can only be posted on a player who killed you. A claim is proven by the hunter's own combat log file (the VoidScout program reads it; /reload to see it in game). Not paying a claimed writ within 3 days makes you Burned until you pay."
        or "How it works: enemy players are seen from nameplates, your target and your mouse, in the open world (battlegrounds hide who players are). Whoever kills you goes on Blood debts by itself. Other VoidBounty players of your side share what they see, so a player you track can be spotted by anyone. Bounties are coming soon.")
    s:Hide()
    return s
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local NAV_FULL = { { "board", "Board" }, { "debts", "Blood debts" }, { "hunts", "My hunts" }, { "ledger", "Ledger" },
                   { "sightings", "Sightings" }, { "hall", "Hall of hunters" }, { "settings", "Settings" } }
-- writs "coming soon" (Core.lua ns.WRITS): what works without them, and one page that says what's next
local NAV_SOON = { { "sightings", "Sightings" }, { "debts", "Blood debts" }, { "hall", "Most wanted" },
                   { "soon", "Bounties (soon)" }, { "settings", "Settings" } }
local NAV = NAV_FULL
local current = "board"
local pages = {}

local function buildSoon(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetPoint("TOPLEFT", CX, -44)
    s:SetSize(CW, H - 54)
    local h = header(s, "Bounties: coming soon")
    h:SetPoint("TOPLEFT", 0, 0)
    local t = fs(s, "GameFontHighlight", CW - 20)
    t:SetPoint("TOPLEFT", 0, -28)
    t:SetSpacing(4)
    t:SetText("Being tested now, and switched on in an update once it's solid:\n\n"
        .. "|cffffd27aWanted posters|r  A writ on a player who killed you, shown to every VoidBounty player of your side.\n\n"
        .. "|cffffd27aHunting|r  Take a writ, get the killing blow outside cities and battlegrounds. Your own combat log is the proof.\n\n"
        .. "|cffffd27aTribute|r  The reward is basic vendor goods the poster buys and trades to you (food, potions, ammo, reagents). Never gold.\n\n"
        .. "|cffffd27aStanding|r  Settle your writs to climb: Collector, Hunter, Executioner. Leave one unpaid and you're Burned.\n\n"
        .. "|cff999999Everything else works today: the nearby warning, Blood debts, Sightings, tracking and Most wanted. "
        .. "The players who kill you now will still be on your list when bounties arrive.|r")
    s:Hide()
    return s
end

local function build()
    local f = box(UIParent, 0.03, 0.03, 0.06, 0.96)
    f:SetSize(W, H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    local p = ns.char().bigPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        ns.char().bigPos = { pt, rel, x, y }
    end)
    _G.VoidBountyFrame = f
    table.insert(UISpecialFrames, "VoidBountyFrame")
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont("Fonts\\MORPHEUS.TTF", 22, "")
    f.title:SetTextColor(A[1], A[2], A[3])
    f.title:SetPoint("TOPLEFT", 12, -8)
    f.title:SetText("VoidBounty")
    f.net = fs(f, "GameFontDisableSmall", 380); f.net:SetPoint("LEFT", f.title, "RIGHT", 10, -2)
    f.standing = fs(f, "GameFontHighlightSmall", 320, "RIGHT"); f.standing:SetPoint("TOPRIGHT", -34, -14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)
    local line = f:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(A[1], A[2], A[3], 0.3)
    line:SetPoint("TOPLEFT", 8, -36); line:SetPoint("TOPRIGHT", -8, -36); line:SetHeight(VoidPX())
    -- nav
    NAV = ns.WRITS and NAV_FULL or NAV_SOON
    current = NAV[1][1]
    f.nav = {}
    for i, n in ipairs(NAV) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(NAV_W, 26)
        b:SetPoint("TOPLEFT", 8, -44 - (i - 1) * 28)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.edge = b:CreateTexture(nil, "ARTWORK"); b.edge:SetPoint("TOPLEFT"); b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetWidth(2)
        b.edge:SetColorTexture(A[1], A[2], A[3], 1)
        b.text = fs(b, "GameFontHighlight", NAV_W - 12); b.text:SetPoint("LEFT", 10, 0); b.text:SetWordWrap(false)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8"); b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
        b.id, b.label = n[1], n[2]
        b:SetScript("OnClick", function() current = n[1]; Refresh() end)
        f.nav[i] = b
    end
    f.danger = fs(f, "GameFontDisableSmall", NAV_W - 4)
    f.danger:SetPoint("TOPLEFT", 10, -44 - #NAV * 28 - 12)
    pages.board = buildBoard(f)
    pages.debts = listPage(f, CW, 24)
    pages.hunts = listPage(f, CW, 24)
    pages.ledger = listPage(f, CW, 24)
    pages.sightings = listPage(f, CW, 24)
    pages.hall = listPage(f, CW, 24)
    pages.settings = buildSettings(f)
    pages.soon = buildSoon(f)
    f:SetScript("OnShow", function() Refresh() end)
    f:Hide()
    return f
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local f = win
    -- header
    local others = ns.NetOthers and ns.NetOthers()
    f.net:SetText(("%s network · %s other VoidBounty player%s online"):format(UnitFactionGroup("player") or "?",
        others and tostring(others) or "?", others == 1 and "" or "s"))
    local r = ns.Hall()
    if ns.WRITS then
        f.standing:SetText(("Your standing: %s · %d writ%s settled · %d players killed"):format(standing(r), r.settled, r.settled == 1 and "" or "s", r.kills))
    else
        f.standing:SetText("|cff999999Bounties: coming soon|r")
    end
    -- nav: counts
    local debts = 0
    for _ in pairs(ns.char().marked) do debts = debts + 1 end
    local hunts = 0
    for _, w in pairs(ns.Writs()) do
        if w.hunters and w.hunters[me()] and ns.Status(w) == "open" then hunts = hunts + 1 end
        if w.claim and w.claim.hunter == me() and not (w.paid or w.recv) then hunts = hunts + 1 end
        if w.author == me() and w.claim and not (w.paid or w.recv) then hunts = hunts + 1 end
    end
    local open = 0
    for _, ps in ipairs(ns.Posters()) do if ps.status == "open" then open = open + 1 end end
    local COUNT = { board = open, debts = debts, hunts = hunts }
    for _, b in ipairs(f.nav) do
        local sel = b.id == current
        b.bg:SetColorTexture(A[1], A[2], A[3], sel and 0.15 or 0)
        b.edge:SetShown(sel)
        local c = COUNT[b.id]
        b.text:SetText(b.label .. ((c and c > 0) and ("  |cff%s%d|r"):format(b.id == "debts" and "ff6b6b" or "ffd27a", c) or ""))
        b.text:SetTextColor(sel and 1 or 0.8, sel and 1 or 0.8, sel and 1 or 0.8)
    end
    -- danger here
    local here, n, lo, hi = GetZoneText and GetZoneText() or "", 0, 99, 0
    for _, z in ipairs(ns.ZoneDanger(900)) do
        if z.zone == here then n, lo, hi = z.n, z.lvlMin, z.lvlMax end
    end
    local level = n == 0 and "|cff55ff55quiet|r" or n < 3 and "|cffffd27asome|r" or n < 7 and "|cffff9944high|r" or "|cffff3333very high|r"
    f.danger:SetText(("Danger here: %s\n%d enemy player%s seen in %s, last 15 min%s"):format(level, n, n == 1 and "" or "s", here,
        hi > 0 and ("\n(levels %d-%d)"):format(lo, hi) or ""))
    -- pages
    for id, pg in pairs(pages) do pg:SetShown(id == current) end
    if current == "board" then showBoard(pages.board)
    elseif current == "debts" then pages.debts:Show_(debtsItems())
    elseif current == "hunts" then pages.hunts:Show_(huntsItems())
    elseif current == "ledger" then pages.ledger:Show_(ledgerItems())
    elseif current == "sightings" then pages.sightings:Show_(sightingsItems())
    elseif current == "hall" then pages.hall:Show_(hallItems())
    elseif current == "settings" then
        for _, c in ipairs(pages.settings.checks) do
            local v = ns.char()[c.key]
            if c.defaultOn then c:SetChecked(v ~= false) else c:SetChecked(v and true or false) end
        end
    end
end

local function toggle()
    win = win or build()
    win:SetShown(not win:IsShown())
end
ns.Toggle = toggle

function ns.Changed() if win and win:IsShown() then Refresh() end end
local lastTick = 0
ns.OnChange(function(what)
    if not (win and win:IsShown()) then return end
    if what == "tick" then
        if GetTime() - lastTick < 5 then return end
        lastTick = GetTime()
    end
    Refresh()
end)

SLASH_VOIDBOUNTY1 = "/vbounty"     -- NOT /vb: that's VoidBags' (it opened the bags in the first test, 11-10)
SLASH_VOIDBOUNTY2 = "/voidbounty"
SlashCmdList.VOIDBOUNTY = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "mark" then ns.MarkTarget()
    elseif msg == "net" then if ns.NetReport then ns.NetReport() end
    elseif msg == "test" then ns.Test(); ns.say("made-up Marked enemy \"Test Dummy\" nearby for 25 s (/vbounty untest removes it).")
    elseif msg == "writs" then   -- dev: writs on/off for this client (they're "coming soon" for players)
        local d = ns.realDB()
        d.devWrits = not d.devWrits or nil
        ns.say(("writs %s on this client after /reload."):format(d.devWrits and "|cff55ff55ON|r" or "|cffff7777OFF|r"))
    elseif msg == "demo" then
        if not ns.WRITS then ns.say("bounties are coming soon: the demo board shows them, so it waits for them too.") return end
        ns.DemoOn(); if not (win and win:IsShown()) then toggle() end
    elseif msg == "undemo" then ns.DemoOff()
    elseif msg == "untest" then
        ns.Unmark("Player-0-TEST0001"); ns.db().seen["Player-0-TEST0001"] = nil; ns.near["Player-0-TEST0001"] = nil; ns.RenderAlert()
    else toggle() end
    Refresh()
end

VoidHubLaunchers = VoidHubLaunchers or {}
VoidHubLaunchers.VoidBounty = { icon = "Interface\\Icons\\INV_Misc_Note_02", onClick = function() toggle() end }

VoidHubToggles = VoidHubToggles or {}
table.insert(VoidHubToggles, {
    id = "VoidBounty.alerts", group = "PvP", label = "Enemy nearby warning",
    tip = "VoidBounty: a small line near the top of the screen while enemy players are around; red for players who killed you.",
    get = function() return ns.char().alerts end,
    set = function(on) ns.char().alerts = on; ns.RenderAlert() end,
})
