local _, ns = ...
local L = ns.L

-- The enemy list, like the enmity list of other games: one row per mob that is fighting you, with its health and
-- your own hold on it (a colored strip: green = you have it as a tank, red = it is loose or on you...), and the
-- mob's target. The one slipping away comes first, so a tank sees at once what to take back. For a tank, the loose
-- mobs also get a red mark on their nameplate: the game does not let an addon target a mob from a list (a protected
-- action that the nameplate units cannot be given to), so what the list does is show which nameplate to click.
local WIDTH, ROW_H, PAD = 210, 20, 4
local TITLE_H = 18
local TOP = 3 + TITLE_H + 2 -- where the rows start
local MAX_ROWS = 10
local STRIP_W, WHO_W, HP_W = 4, 78, 30
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
}
local BORDER = { 0.3, 0.3, 0.3, 1 }
local HEALTH_COLOR = { 0.7, 0.15, 0.15, 0.9 }
-- your hold on a mob
local HELD, LOOSE, UNKNOWN, WARNING = { 0.2, 0.8, 0.2 }, { 1, 0.15, 0.15 }, { 1, 0.5, 0.1 }, { 1, 0.6, 0.1 }
local OTHER_TANK = { 1, 0.85, 0.2 }
local MOB_SEARCH = 40 -- mobs looked at before the first ones are kept

local frame, message
local rows = {}
local marks = {}       -- nameplate -> its mark
local markedNow = {}   -- nameplates marked in the last redraw
local active = false   -- whether the list is on right now

local function rowTop(i) return TOP + (i - 1) * ROW_H end

local function yes(value) return ns.Yes(value) end

-- Your role decides what a mob is telling you: a tank wants every mob on them; the others, none.
local function myRole()
    local classFile = ns.Plain(select(2, UnitClass("player")))
    return ns.Threat_Role("player", classFile)
end

-- Whether the list is wanted: always, never, or (the default) when you are a tank -- or the game doesn't say
-- what you are (older clients): better a list too many than none for a tank.
local function wanted(role)
    local mode = ns.char.enemyListMode
    if mode == "always" then return true end
    if mode == "never" then return false end
    return role == nil or role == "TANK"
end

-- The choices of the preference, in order.
function ns.Enemies_Modes()
    return {
        { key = "tank", name = L["Only as tank"] },
        { key = "always", name = L["Always"] },
        { key = "never", name = L["Never"] },
    }
end

function ns.Enemies_ModeName(key)
    for _, mode in ipairs(ns.Enemies_Modes()) do
        if mode.key == key then return mode.name end
    end
    return key
end

-- Whether the list is on right now.
function ns.Enemies_IsActive() return active end

-- Color of the strip: your hold on the mob.
local function holdColor(entry, role)
    if role == "TANK" then
        if entry.isMe then return HELD end
        if entry.whoSecret then return UNKNOWN end
        if entry.role == "TANK" or entry.isPet then return OTHER_TANK end -- somebody else holds it for you
        return LOOSE -- on a healer or a dps, or on nobody
    end
    if entry.isMe then return LOOSE end
    if (entry.pct or 0) >= ns.char.alertThreshold then return WARNING end
    return HELD
end

-- What needs you first: for a tank the mobs that are not on them (on a healer or a dps before on another tank),
-- for the rest the ones that are on them. In a fixed order otherwise, so the rows don't jump.
local function byUrgency(role)
    return function(a, b)
        if role == "TANK" then
            if a.isMe ~= b.isMe then return b.isMe end
            local aCovered, bCovered = a.role == "TANK" or a.isPet, b.role == "TANK" or b.isPet
            if aCovered ~= bCovered then return bCovered end
        elseif a.isMe ~= b.isMe then
            return a.isMe
        end
        if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        return a.unit < b.unit
    end
end

local function createRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetSize(WIDTH - 2 * PAD, ROW_H - 1)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -rowTop(i))
    row:SetStatusBarTexture(BAR_TEXTURE)
    row:SetMinMaxValues(0, 1)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.1)
    row.sel = row:CreateTexture(nil, "ARTWORK") -- the row of your current target
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 1, 1, 0.18)
    row.strip = row:CreateTexture(nil, "OVERLAY")
    row.strip:SetPoint("TOPLEFT", 0, 0)
    row.strip:SetPoint("BOTTOMLEFT", 0, 0)
    row.strip:SetWidth(STRIP_W)
    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.who:SetPoint("RIGHT", -3, 0)
    row.who:SetWidth(WHO_W)
    row.who:SetJustifyH("RIGHT")
    row.who:SetWordWrap(false)
    row.hp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.hp:SetPoint("RIGHT", row.who, "LEFT", -4, 0)
    row.hp:SetWidth(HP_W)
    row.hp:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", STRIP_W + 3, 0)
    row.name:SetPoint("RIGHT", row.hp, "LEFT", -3, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

-- The padlock is the aggro window's too (one setting for both): its picture says whether they can be moved.
local function updateLock()
    local locked = ns.char.locked and true or false
    if frame.lockedShown == locked then return end
    frame.lockedShown = locked
    local texture = locked and "Interface\\Buttons\\LockButton-Locked-Up"
        or "Interface\\Buttons\\LockButton-Unlocked-Up"
    frame.lock:SetNormalTexture(texture)
    frame.lock:SetPushedTexture(texture)
end

local function windowOrigin()
    local w = ns.char.enemyWindow
    if w then return w.x, w.y end
    -- the first time: to the left of the center of the screen, in the window's own scale
    local scale = ns.char.scale
    return (UIParent:GetWidth() / 2 - 250 - WIDTH / 2) / scale, (UIParent:GetHeight() / 2 + 120) / scale
end

-- Where the window is and how it looks, from the settings (it is anchored by its top left corner, so it grows down).
local layoutKey
local function applyLayout()
    local scale = ns.char.scale
    local x, y = windowOrigin()
    local key = table.concat({ tostring(x), tostring(y), tostring(scale), tostring(ns.char.opacity) }, ":")
    if layoutKey == key then return end
    layoutKey = key
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    frame:SetBackdropColor(0, 0, 0, ns.char.opacity)
end

-- The red mark that goes on a loose mob's nameplate: where to click to take it back.
local function createMark(plate)
    local mark = CreateFrame("Frame", nil, plate)
    mark:SetSize(20, 24)
    mark:SetPoint("RIGHT", plate, "LEFT", 4, 0)
    mark:SetFrameLevel(plate:GetFrameLevel() + 10)
    mark.text = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mark.text:SetPoint("CENTER")
    mark.text:SetText("!")
    mark.text:SetTextColor(LOOSE[1], LOOSE[2], LOOSE[3])
    return mark
end

-- Marks the nameplates of `entries` (the loose mobs of a tank) and clears the ones marked before.
local function updateMarks(entries)
    for plate in pairs(markedNow) do
        if marks[plate] then marks[plate]:Hide() end
        markedNow[plate] = nil
    end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    for _, entry in ipairs(entries) do
        local plate = C_NamePlate.GetNamePlateForUnit(entry.unit)
        if plate then
            if not marks[plate] then
                local ok, mark = pcall(createMark, plate)
                marks[plate] = ok and mark or nil
            end
            if marks[plate] then
                marks[plate]:Show()
                markedNow[plate] = true
            end
        end
    end
end

function ns.Enemies_ApplySettings()
    if frame then ns.Enemies_Update() end
end

function ns.Enemies_ResetPosition()
    ns.char.enemyWindow = nil
    ns.Enemies_ApplySettings()
end

local function create()
    frame = CreateFrame("Frame", "AggreaoEnemiesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, TOP + ROW_H + PAD)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropBorderColor(unpack(BORDER))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.char.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- saved as the top left corner, the point the window is anchored by
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then ns.char.enemyWindow = { x = left, y = top } end
        ns.Enemies_Update()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.Prefs_Toggle() end
    end)

    frame.bar = frame:CreateTexture(nil, "BACKGROUND")
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("TOPRIGHT", -1, -1)
    frame.bar:SetHeight(TITLE_H)
    frame.bar:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    frame.barText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.barText:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
    frame.barText:SetText(L["Enemies"])

    local okClose, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not okClose or not close then close = CreateFrame("Button", nil, frame) end
    close:SetSize(TITLE_H + 6, TITLE_H + 6)
    close:SetPoint("TOPRIGHT", 3, 3)
    close:SetScript("OnClick", function() -- closes the list for good (the preferences bring it back)
        ns.char.enemyListMode = "never"
        ns.Enemies_Update()
        if ns.Prefs_Refresh then ns.Prefs_Refresh() end
        ns.Print(L["Enemy list closed. Show it again in the preferences."])
    end)
    frame.close = close

    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(14, 14)
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

    message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    message:SetPoint("TOPLEFT", PAD + 2, -TOP)
    message:SetPoint("TOPRIGHT", -PAD - 2, -TOP)
    message:SetHeight(ROW_H)
    message:SetJustifyH("LEFT")
    message:SetTextColor(0.5, 0.5, 0.5)
end

function ns.Enemies_Init()
    if frame then return end
    create()
    ns.Enemies_Update()
end

local function draw(row, entry, role)
    local color = holdColor(entry, role)
    row.strip:SetColorTexture(color[1], color[2], color[3], 1)
    row:SetStatusBarColor(unpack(HEALTH_COLOR))
    -- the health can be hidden from addons (a status bar can still be given it)
    row:SetMinMaxValues(0, entry.healthMax or 1)
    row:SetValue(entry.health or 0)
    row.name:SetText(entry.mob)
    row.hp:SetText(entry.healthPct and ("%d%%"):format(math.floor(entry.healthPct + 0.5)) or "")
    row.sel:SetShown(yes(UnitIsUnit(entry.unit, "target")))
    -- whom it attacks: YOU, or the name in the class color with your threat on the mob. A name hidden from addons is
    -- only handed over as it is (no color, no text added).
    local hidden = entry.whoSecret and not entry.isMe
    local who
    if entry.isMe then
        who = L["YOU"]
    else
        who = entry.who or "-"
    end
    if hidden then
        row.who:SetTextColor(1, 1, 1)
    elseif entry.isMe then
        row.who:SetTextColor(color[1], color[2], color[3])
    else
        row.who:SetTextColor(1, 0.82, 0)
        if entry.class then who = ns.ColorCode(ns.ClassColor(entry.class)) .. who .. "|r" end
        if entry.pct then who = who .. (" %d%%"):format(math.floor(entry.pct + 0.5)) end
    end
    row.who:SetText(who)
    row:Show()
end

-- Redraws the list. Called with every refresh of the aggro window.
function ns.Enemies_Update()
    if not frame then return end
    local role = myRole()
    active = wanted(role)
    applyLayout()
    updateLock()
    local inCombat = yes(UnitAffectingCombat("player"))
    -- out of combat it is only there to be placed, while the preferences are open
    if not (active and (inCombat or ns.Prefs_IsShown())) then
        frame:Hide()
        updateMarks({})
        return
    end
    local list = inCombat and ns.Threat_Mobs(MOB_SEARCH) or {}
    table.sort(list, byUrgency(role))
    local count = math.min(#list, math.min(ns.char.enemyRows, MAX_ROWS))
    local loose = {}
    for i = 1, count do
        local row = rows[i] or createRow(i)
        rows[i] = row
        draw(row, list[i], role)
    end
    for i = count + 1, #rows do rows[i]:Hide() end
    -- the nameplates of the mobs that are loose, all of them, listed or not
    if role == "TANK" and ns.char.enemyMarks then
        for _, entry in ipairs(list) do
            if holdColor(entry, role) == LOOSE then loose[#loose + 1] = entry end
        end
    end
    updateMarks(loose)
    if count == 0 then
        message:SetText(inCombat and L["No enemies"] or L["Not in combat"])
        message:Show()
    else
        message:Hide()
    end
    frame:SetHeight(TOP + math.max(count, 1) * ROW_H + PAD)
    frame:Show()
end
