local _, ns = ...
local L = ns.L

-- The aggro window: small, movable, lists who has the aggro of your target and how close the others are,
-- in order. Each row: role icon, name, bar in the class color (full = pulls the aggro) and the percentage.
local WIDTH, ROW_H, HEADER_H, PAD = 190, 16, 14, 4
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES" -- in every client
local ROLE_COORDS = { -- left, right, top, bottom
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
}
local NORMAL_BORDER, ALERT_BORDER = { 0.3, 0.3, 0.3, 1 }, { 1, 0.1, 0.1, 1 }
local UPDATE_EVERY = 0.25
local UPDATE_EVENTS = {
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_PET", "PLAYER_ROLES_ASSIGNED",
}

local frame, header, message
local rows = {}
local driver

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function createRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetSize(WIDTH - 2 * PAD, ROW_H - 1)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER_H + PAD + (i - 1) * ROW_H))
    row:SetStatusBarTexture(BAR_TEXTURE)
    row:SetMinMaxValues(0, 100)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.1)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT", 1, 0)
    row.icon:SetTexture(ROLE_TEXTURE)
    row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pct:SetPoint("RIGHT", -3, 0)
    row.pct:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.name:SetPoint("RIGHT", row.pct, "LEFT", -3, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

-- Position, scale, opacity and mouse behaviour from the settings.
function ns.Meter_ApplySettings()
    if not frame then return end
    local w = ns.char.window
    frame:ClearAllPoints()
    if w then
        frame:SetPoint(w.point, UIParent, w.relPoint, w.x, w.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    end
    frame:SetScale(ns.char.scale)
    frame:SetBackdropColor(0, 0, 0, ns.char.opacity)
    ns.Meter_Update()
end

function ns.Meter_ResetPosition()
    ns.char.window = nil
    ns.Meter_ApplySettings()
end

local function create()
    frame = CreateFrame("Frame", "AggreaoMeterFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEADER_H + 2 * PAD)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropBorderColor(unpack(NORMAL_BORDER))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.char.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.char.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.Prefs_Toggle() end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Aggreao!!")
        GameTooltip:AddLine(L["Drag: move"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Right-click: preferences"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", PAD + 2, -PAD)
    header:SetPoint("TOPRIGHT", -PAD - 2, -PAD)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)

    -- what the window says when there is no list to show (not in combat, no target...)
    message = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    message:SetPoint("TOPLEFT", PAD + 2, -(HEADER_H + PAD))
    message:SetPoint("TOPRIGHT", -PAD - 2, -(HEADER_H + PAD))
    message:SetHeight(ROW_H)
    message:SetJustifyH("CENTER")
end

-- Draws the list (see ns.Threat_Collect); `alert` turns the border red. With an empty list, `text` is
-- shown in its place.
function ns.Meter_Render(list, title, alert, text)
    if not frame then create() end
    header:SetText(title or "")
    local shown = ns.Threat_Top(list, ns.char.rows)
    message:SetText(#shown == 0 and text or "")
    for i, e in ipairs(shown) do
        local row = rows[i] or createRow(i)
        rows[i] = row
        local r, g, b = classColor(e.class)
        row:SetStatusBarColor(r, g, b, 0.9)
        row:SetValue(math.min(e.pct, 100))
        row.name:SetText(e.name)
        row.pct:SetText(("%d%%"):format(math.floor(e.pct + 0.5)))
        local coords = e.role and ns.char.showRoles and ROLE_COORDS[e.role]
        if coords then
            row.icon:SetTexCoord(unpack(coords))
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
        else
            row.icon:Hide()
            row.name:SetPoint("LEFT", row, "LEFT", 3, 0)
        end
        row:Show()
    end
    for i = #shown + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(HEADER_H + 2 * PAD + math.max(#shown, 1) * ROW_H)
    frame:SetBackdropBorderColor(unpack(alert and ns.char.alertFlash and ALERT_BORDER or NORMAL_BORDER))
end

-- Reads the target's threat and redraws (or hides) the window.
function ns.Meter_Update()
    if not frame then create() end
    local mob = "target"
    local validMob = UnitExists(mob) and UnitCanAttack("player", mob) and not UnitIsDead(mob)
    local inCombat = UnitAffectingCombat("player")
    local list, alert = {}, false
    if validMob then
        list = ns.Threat_Collect(mob, ns.char.pets)
        alert = ns.Alert_Check(list)
    else
        ns.Alert_Reset()
    end
    if not ns.char.enabled then
        frame:Hide()
    elseif ns.char.hideOutOfCombat and not inCombat and not ns.Prefs_IsShown() then
        frame:Hide() -- while the preferences are open it stays, to be placed
    elseif #list > 0 then
        ns.Meter_Render(list, UnitName(mob), alert)
        frame:Show()
    else
        local text = L["Not in combat"]
        if inCombat then text = validMob and L["No aggro data"] or L["No target"] end
        ns.Meter_Render({}, "Aggreao!!", false, text)
        frame:Show()
    end
end

function ns.Meter_Toggle()
    ns.char.enabled = not ns.char.enabled
    ns.Meter_Update()
    ns.Print(ns.char.enabled and L["Window shown."] or L["Window hidden."])
end

-- Creates the window and starts following the target's threat. Events mark the list as stale and the
-- redraw happens in the next OnUpdate tick (threat events can come by the dozen in a raid); a target change
-- redraws at once. The tick also covers clients that send few threat events.
function ns.Meter_Init()
    if driver then return end
    create()
    ns.Meter_ApplySettings()
    driver = CreateFrame("Frame")
    for _, event in ipairs(UPDATE_EVENTS) do pcall(driver.RegisterEvent, driver, event) end
    local elapsed, stale = 0, false
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            ns.Alert_Reset()
            ns.Meter_Update()
        else
            stale = true
        end
    end)
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= UPDATE_EVERY then
            elapsed, stale = 0, false
            ns.Meter_Update()
        elseif stale and elapsed >= 0.1 then
            elapsed, stale = 0, false
            ns.Meter_Update()
        end
    end)
end
