----------------------------------------------------------------------
-- VoidBounty: the nearby alert. One small box near the top of the screen:
--   * a Marked player nearby: a red line each ("MARKED Max Package, Warrior 36 (Ashes),
--     killed you 2x"), with a sound the moment they show up;
--   * other enemies: one quiet line ("3 Alliance nearby: Warrior 36, Mage 34, Druid 30").
-- It fades once nobody has been seen for a while. Shift-drag moves it (saved per character).
----------------------------------------------------------------------
local ADDON, ns = ...
if (select(4, GetBuildInfo()) or 0) >= 100000 then return end

local MAX_MARKED = 3

local function classColor(cls)
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    return c and c:GenerateHexColor() or "ffffffff"
end
ns.ClassColor = classColor

local function className(cls)
    if not cls then return "" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or (cls:sub(1, 1) .. cls:sub(2):lower())
end
ns.ClassName = className

function ns.Who(e)   -- "Warrior 36" in class colour
    return ("|c%s%s %s|r"):format(classColor(e.class), className(e.class), e.level and tostring(e.level) or "??")
end

-- one screen pixel in UI units (borders: never a fixed 1, feedback-pixel-perfect-borders)
local function px()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

-- the red flashing box (the user, 11-11: "can we have it blink in a red flashing box"): it flashes for a
-- few seconds when an enemy player shows up, and the whole time a player who killed you is near
local FLASH_NEW = 6
local flashUntil = 0

local box
local function build()
    local f = CreateFrame("Frame", "VoidBountyAlert", UIParent, "BackdropTemplate")
    f:SetSize(420, 20)
    -- a dark background (the names stay readable) and a red border on its own layer: only the border
    -- flashes (the user, 11-11: "i want a red border, the whole box red kind of interfers with names")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    f:SetBackdropColor(0.04, 0.02, 0.02, 0.8)
    f.edge = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.edge:SetAllPoints()
    f.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 * px() })
    f.edge:SetBackdropBorderColor(1, 0.1, 0.1, 1)
    f.pulse = f.edge:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local a = f.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.1)
    a:SetDuration(0.35)
    a:SetSmoothing("IN_OUT")
    f.pulse:SetScript("OnStop", function() f.edge:SetAlpha(1) end)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    local p = ns.char().alertPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -150) end
    f:SetMovable(true)
    f:EnableMouse(false)
    f.lines = {}
    for i = 1, MAX_MARKED + 1 do
        local fs = f:CreateFontString(nil, "OVERLAY", i <= MAX_MARKED and "GameFontNormalLarge" or "GameFontHighlight")
        fs:SetPoint("TOP", f, "TOP", 0, -8 - (i - 1) * 22)
        fs:SetShadowOffset(1, -1)
        fs:SetWidth(600)
        fs:SetWordWrap(false)
        f.lines[i] = fs
    end
    -- Shift-drag to move: the box takes the mouse only while Shift is held
    f:SetScript("OnUpdate", function(self)
        local want = IsShiftKeyDown() and self:IsShown()
        if want ~= self:IsMouseEnabled() then self:EnableMouse(want) end
    end)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        ns.char().alertPos = { pt, rel, x, y }
    end)
    f:Hide()
    return f
end

local function render()
    local c = ns.char()
    if not c.alerts or ns.InBattle() then if box then box:Hide() end return end
    local near = ns.Nearby()
    local marked, other = {}, {}
    for _, n in ipairs(near) do
        if ns.IsMarked(n.guid) then marked[#marked + 1] = n else other[#other + 1] = n end
    end
    if #marked == 0 and (#other == 0 or not c.quiet) then if box then box:Hide() end return end
    box = box or build()
    local i = 0
    for k = 1, math.min(#marked, MAX_MARKED) do
        local n = marked[k]
        local m = c.marked[n.guid]
        i = i + 1
        local kills = (m and (m.kills or 0) > 0) and (" · killed you %d×"):format(m.kills) or " · marked"
        box.lines[i]:SetText(("|cffff3333MARKED|r %s, %s%s|cffff9999%s|r"):format(n.e.name, ns.Who(n.e),
            n.e.guild and (" <" .. n.e.guild .. ">") or "", kills))
        box.lines[i]:Show()
    end
    if #other > 0 and c.quiet then
        local parts = {}
        for k = 1, math.min(#other, 4) do parts[#parts + 1] = ns.Who(other[k].e) end
        if #other > 4 then parts[#parts + 1] = "+" .. (#other - 4) end
        local fac = other[1].e.faction or "Enemy"
        i = i + 1
        box.lines[i]:SetText(("|cffcccccc%d %s nearby:|r %s"):format(#other, fac, table.concat(parts, ", ")))
        box.lines[i]:Show()
    end
    for k = i + 1, #box.lines do box.lines[k]:Hide() end
    local w = 0
    for k = 1, i do w = math.max(w, box.lines[k]:GetStringWidth() or 0) end
    box:SetSize(math.min(640, w + 32), math.max(20, i * 22) + 12)
    -- flash: a player who killed you is near, or someone just showed up; else a steady red box
    local flash = c.flash ~= false and (#marked > 0 or GetTime() < flashUntil)
    if flash and not box.pulse:IsPlaying() then box.pulse:Play()
    elseif not flash and box.pulse:IsPlaying() then box.pulse:Stop() end
    box:Show()
end
ns.FlashAlert = function(secs) flashUntil = math.max(flashUntil, GetTime() + (secs or FLASH_NEW)) end
ns.RenderAlert = render

ns.OnChange(function(what, guid, isNew)
    if what == "near" and isNew then flashUntil = GetTime() + FLASH_NEW end
    if what == "near" and isNew and ns.IsMarked(guid) and not ns.InBattle() and not guid:find("^Player%-0%-") then
        local e = ns.db().seen[guid]
        ns.Log("marked", ("%s showed up (alerts %s, sound %s)"):format(e and e.name or "?", tostring(ns.char().alerts), tostring(ns.char().sound)))
    end
    if what == "near" and isNew and ns.IsMarked(guid) and ns.char().sound and ns.char().alerts and not ns.InBattle() then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
    render()
end)
C_Timer.NewTicker(1, render)   -- people drop off after ns.NEAR_FOR seconds; the flash stops on time
