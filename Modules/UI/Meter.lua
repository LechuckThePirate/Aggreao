local ADDON, ns = ...
local L = ns.L

-- The aggro window: small, movable, lists who has the aggro of your target and how close the others are,
-- in order. Under the title bar (title, padlock to lock its position, close button) a line with the mob's
-- name (or what is going on: not in combat...), then each row: role icon, name, bar in the class color (full =
-- pulls the aggro) and the percentage.
local WIDTH, ROW_H, HEADER_H, PAD = 190, 16, 14, 4
local TITLE_H, LOCK_SIZE = 18, 14 -- the title bar and the padlock in it
local TOP = 3 + TITLE_H + 2 -- where the mob's name line starts
local SECTION_H, LINE_H = 13, 14 -- the "Other mobs" label, and each line under it
local OTHER_MOBS_MAX = 4 -- lines in that section
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES" -- in every client
local ROLE_COORDS = { -- left, right, top, bottom
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local PET_TEXTURE = "Interface\\AddOns\\" .. ADDON .. "\\Icons\\Pet.png" -- a paw print, for pets
-- the tank icon of the roles texture, as an inline picture for a line's text (pixels in the 64x64 texture)
local TANK_INLINE = "|T" .. ROLE_TEXTURE .. ":12:12:0:0:64:64:0:19:22:41|t "
local PET_INLINE = "|T" .. PET_TEXTURE .. ":10|t "
local BAR_TEXTURE ="Interface\\TargetingFrame\\UI-StatusBar"
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
}
local NORMAL_BORDER, ALERT_BORDER = { 0.3, 0.3, 0.3, 1 }, { 1, 0.1, 0.1, 1 }
local UPDATE_EVERY = 0.25
local UPDATE_EVENTS = {
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_PET", "PLAYER_ROLES_ASSIGNED",
}

local frame, header
local rows = {}
local lines = {} -- one per other mob
local driver

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function colorCode(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- A line of the "Other mobs" section: the mob's name, and on the right whom it is attacking (class color,
-- a paw for a pet) with your own threat on it; red when it is attacking you.
local function createLine(i, firstY)
    local line = CreateFrame("Frame", nil, frame)
    line:SetSize(WIDTH - 2 * PAD, LINE_H)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(firstY + (i - 1) * LINE_H))
    line.bg = line:CreateTexture(nil, "BACKGROUND")
    line.bg:SetAllPoints()
    line.bg:SetColorTexture(1, 0.1, 0.1, 0.25)
    line.who = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.who:SetPoint("RIGHT", -2, 0)
    line.who:SetJustifyH("RIGHT")
    line.who:SetWordWrap(false)
    line.mob = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line.mob:SetPoint("LEFT", 2, 0)
    line.mob:SetPoint("RIGHT", line.who, "LEFT", -4, 0)
    line.mob:SetJustifyH("LEFT")
    line.mob:SetWordWrap(false)
    return line
end

local function createRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetSize(WIDTH - 2 * PAD, ROW_H - 1)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + HEADER_H + (i - 1) * ROW_H))
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

-- The padlock's picture says whether the window is locked (only touched when that changes).
local function updateLock()
    if not (frame and frame.lock) then return end
    local locked = ns.char.locked and true or false
    if frame.lockedShown == locked then return end
    frame.lockedShown = locked
    local texture = locked and "Interface\\Buttons\\LockButton-Locked-Up"
        or "Interface\\Buttons\\LockButton-Unlocked-Up"
    frame.lock:SetNormalTexture(texture)
    frame.lock:SetPushedTexture(texture)
end

-- In combat the window is click-through (the mouse goes to the game behind it, so you can't click it by
-- mistake); out of combat it takes the mouse again (drag, padlock, close button, right-click).
local function applyMouse(inCombat)
    local enabled = not inCombat
    if frame.mouseEnabled == enabled then return end
    frame.mouseEnabled = enabled
    frame:EnableMouse(enabled)
    frame.close:EnableMouse(enabled)
    frame.lock:EnableMouse(enabled)
end

-- Position, scale and opacity from the settings.
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

function ns.Meter_SetLocked(locked)
    ns.char.locked = locked
    ns.Meter_Update()
    if ns.Prefs_Refresh then ns.Prefs_Refresh() end
end

function ns.Meter_ResetPosition()
    ns.char.window = nil
    ns.Meter_ApplySettings()
end

local function create()
    frame = CreateFrame("Frame", "AggreaoMeterFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, TOP + HEADER_H + PAD)
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

    -- title bar: what the window is, the padlock and the close button
    frame.bar = frame:CreateTexture(nil, "BACKGROUND")
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("TOPRIGHT", -1, -1)
    frame.bar:SetHeight(TITLE_H)
    frame.bar:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    frame.barText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.barText:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
    frame.barText:SetText("Aggreao!!")

    local okClose, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not okClose or not close then close = CreateFrame("Button", nil, frame) end
    close:SetSize(TITLE_H + 6, TITLE_H + 6)
    close:SetPoint("TOPRIGHT", 3, 3)
    close:SetScript("OnClick", function() -- closes the window for good (Preferences or /aggreao toggle bring it back)
        ns.char.enabled = false
        ns.Meter_Update()
        if ns.Prefs_Refresh then ns.Prefs_Refresh() end
        ns.Print(L["Window closed. Show it again with /aggreao toggle or in the preferences."])
    end)
    frame.close = close

    -- padlock at the top left: locked, the window can't be moved
    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(LOCK_SIZE, LOCK_SIZE)
    lock:SetPoint("TOPLEFT", 5, -3)
    lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    lock:SetScript("OnClick", function() ns.Meter_SetLocked(not ns.char.locked) end)
    lock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.char.locked and L["Unlock position"] or L["Lock position"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", GameTooltip_Hide)
    frame.lock = lock

    -- the mob's name, or what is going on when there is no list to show (not in combat, no target...)
    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", PAD + 2, -TOP)
    header:SetPoint("TOPRIGHT", -PAD - 2, -TOP)
    header:SetHeight(HEADER_H)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    frame.header = header

    frame.othersHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.othersHeader:SetJustifyH("LEFT")
    frame.othersHeader:SetText(L["Other mobs"])
    frame.othersHeader:Hide()
end

-- Draws the list (see ns.Threat_Collect); `alert` turns the border red. With an empty list, `text` is
-- shown in the mob's name line (in grey), in place of the name.
function ns.Meter_Render(list, title, alert, text, others)
    if not frame then create() end
    local shown = ns.Threat_Top(list, ns.char.rows)
    if #shown == 0 then
        header:SetText(text or "")
        header:SetTextColor(0.5, 0.5, 0.5)
    else
        header:SetText(title or "")
        header:SetTextColor(1, 0.82, 0)
    end
    for i, e in ipairs(shown) do
        local row = rows[i] or createRow(i)
        rows[i] = row
        local r, g, b = classColor(e.class)
        row:SetStatusBarColor(r, g, b, 0.9)
        row:SetValue(math.min(e.pct, 100))
        row.name:SetText(e.name)
        row.pct:SetText(("%d%%"):format(math.floor(e.pct + 0.5)))
        -- the icon: a paw for a pet, the role's for a player (the row is reused, so set both every time)
        local coords = e.role and ns.char.showRoles and ROLE_COORDS[e.role]
        if e.isPet and ns.char.showRoles then
            row.icon:SetTexture(PET_TEXTURE)
            row.icon:SetTexCoord(0, 1, 0, 1)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
        elseif coords then
            row.icon:SetTexture(ROLE_TEXTURE)
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
    local bottom = TOP + HEADER_H + #shown * ROW_H
    others = others or {}
    if #others > 0 then
        frame.othersHeader:ClearAllPoints()
        frame.othersHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(bottom + 2))
        frame.othersHeader:Show()
        local firstY = bottom + SECTION_H
        for i, o in ipairs(others) do
            local line = lines[i] or createLine(i, firstY)
            lines[i] = line
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(firstY + (i - 1) * LINE_H))
            line.bg:SetShown(o.isMe)
            line.mob:SetText(o.mob)
            local who = o.who or "-"
            -- who holds the mob: a shield if it is a tank, a paw if it is a pet (alone, your pet is your tank)
            if ns.char.showRoles then
                if o.isPet then
                    who = PET_INLINE .. who
                elseif o.role == "TANK" then
                    who = TANK_INLINE .. who
                end
            end
            if o.isMe then
                who = colorCode(1, 0.3, 0.3) .. who .. "|r"
            elseif o.class then
                who = colorCode(classColor(o.class)) .. who .. "|r"
            end
            if o.pct and not o.isMe then who = who .. (" %d%%"):format(math.floor(o.pct + 0.5)) end
            line.who:SetText(who)
            line.who:SetWidth(math.min(110, math.ceil(line.who:GetStringWidth()) + 4))
            line:Show()
        end
        bottom = firstY + #others * LINE_H
    else
        frame.othersHeader:Hide()
    end
    for i = #others + 1, #lines do lines[i]:Hide() end
    frame:SetHeight(bottom + PAD)
    frame:SetBackdropBorderColor(unpack(alert and ns.char.alertFlash and ALERT_BORDER or NORMAL_BORDER))
end

-- Reads the target's threat and redraws (or hides) the window.
function ns.Meter_Update()
    if not frame then create() end
    local mob = "target"
    local validMob = UnitExists(mob) and UnitCanAttack("player", mob) and not UnitIsDead(mob)
    local inCombat = UnitAffectingCombat("player")
    updateLock()
    applyMouse(inCombat)
    local list, alert, others = {}, false, nil
    if validMob then
        list = ns.Threat_Collect(mob, ns.char.pets)
        alert = ns.Alert_Check(list)
    else
        ns.Alert_Reset()
    end
    if ns.char.otherMobs and inCombat then
        others = ns.Threat_Mobs(OTHER_MOBS_MAX, validMob and UnitGUID(mob) or nil)
    end
    if not ns.char.enabled then
        frame:Hide()
    elseif ns.char.hideOutOfCombat and not inCombat and not ns.Prefs_IsShown() then
        frame:Hide() -- while the preferences are open it stays, to be placed
    elseif #list > 0 then
        ns.Meter_Render(list, UnitName(mob), alert, nil, others)
        frame:Show()
    else
        local text = L["Not in combat"]
        if inCombat then text = validMob and L["No aggro data"] or L["No target"] end
        ns.Meter_Render({}, nil, false, text, others)
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
