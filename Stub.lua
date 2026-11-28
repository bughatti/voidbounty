----------------------------------------------------------------------
-- VoidBounty 0.5.0: VoidBounty is part of VoidHonor now (2026-11-27). This addon only keeps your saved VoidBounty
-- data (blood debts, sightings, tracked players, settings) so VoidHonor can take it over the first time both are
-- installed, and says where everything went. It runs nothing else: no alerts, no network.
--
-- VoidHonor (Bounty/Migrate.lua) sees VoidBountyStub and runs the world PvP code itself; when it has copied the
-- data it marks VoidBountyCharDB.movedToHonor (per character), and this stays quiet for that character.
----------------------------------------------------------------------
VoidBountyStub = true

local function honorLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("VoidHonor") or false
end

local function say(msg) print("|cff00c7ffVoidBounty|r: " .. msg) end

local MSG = "VoidBounty is now part of |cff00c7ffVoidHonor|r (WoW Forever PvP: your rank, weeklies, battlegrounds"
    .. " and world PvP). Install VoidHonor from CurseForge and keep VoidBounty for now: each character's blood debts,"
    .. " sightings and settings move over by themselves when that character logs in with both installed."

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- per character: blood debts are this character's (VoidHonor copies them when this character logs in with it)
    local moved = type(VoidBountyCharDB) == "table" and VoidBountyCharDB.movedToHonor
    if honorLoaded() or moved then return end
    -- once a day per character, a few seconds after logging in
    VoidBountyCharDB = VoidBountyCharDB or {}
    local today = date("%Y-%m-%d")
    if VoidBountyCharDB.toldHonor == today then return end
    VoidBountyCharDB.toldHonor = today
    C_Timer.After(10, function() say(MSG) end)
end)

SLASH_VOIDBOUNTY1, SLASH_VOIDBOUNTY2 = "/vbounty", "/voidbounty"
SlashCmdList.VOIDBOUNTY = function()
    if honorLoaded() then return end   -- VoidHonor's copy has /vbounty (it loads after this and takes it over)
    say(MSG)
end

-- the hub button's drawer: VoidBounty's icon says where it went
VoidHubLaunchers = VoidHubLaunchers or {}
VoidHubLaunchers.VoidBounty = VoidHubLaunchers.VoidBounty or { icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    onClick = function() if _G.VoidHub_Open and honorLoaded() then _G.VoidHub_Open("VoidHonor", "world") else say(MSG) end end }
