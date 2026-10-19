local _, ns = ...
local L = ns.L

-- The enemy list, like the enmity list of other games: one row per mob that is fighting you, with its health and
-- your own hold on it (a colored strip: green = you have it as a tank, red = it is loose or on you...), and
-- the mob's target. Clicking a row targets that mob, so a tank sees at once which one is slipping away and
-- can click it to take it back.
--
-- Clicking is a protected action: only a secure button can target a unit, and the game does not let an addon
-- change a secure button (what it targets, where it is, whether it is shown) once combat starts. So:
--  * each row has a secure button over it, bound to a unit token ("nameplate3"...), and it keeps that unit
--    for the whole combat. The game itself shows the button only while the unit exists, can be attacked and is alive
--    (a state driver), and the token always means whatever mob has it right now, so a click never lands on a
--    mob that is not the one in the row;
--  * the buttons hang from UIParent, not from the window: a frame a protected one depends on (its parent, the
--    frame it is anchored to) becomes protected too, and the window has to change in combat;
--  * outside combat the buttons are bound again every refresh to the mobs that are around, so the list is ready
--    when the pull starts. In combat the rows keep their tokens: mobs that join afterwards are listed only if
--    their token was already bound, and the order is the order of the tokens.
-- Everything that touches a button is done only outside combat; what is asked in combat waits for it to end.
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

local frame, message
local rows, buttons = {}, {}
local bound = {}    -- row -> the unit token its button has
local driven = {}   -- row -> what its state driver was last given, so it is not set again for nothing
local active = false     -- whether the list is on (changed only outside combat, with the buttons)
local activeRows = 0     -- how many rows are on (idem)
local layoutKey          -- where and how big the window and the buttons were last put
local petMode            -- whether the buttons were last set for a player with a pet

local function rowTop(i) return TOP + (i - 1) * ROW_H end

local function yes(value) return ns.Yes(value) end

-- Your role decides what a mob is telling you: a tank wants every mob on them; the others, none.
local function myRole()
    local classFile = ns.Plain(select(2, UnitClass("player")))
    return ns.Threat_Role("player", classFile)
end

-- Whether the list is wanted: always, never, or (the default) when you are a tank -- or the game doesn't say
-- what you are (older clients): better a list too many than none for a tank.
local function wanted()
    local mode = ns.char.enemyListMode
    if mode == "always" then return true end
    if mode == "never" then return false end
    local role = myRole()
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

-- Whether the list is on right now (it changes only outside combat, with the buttons).
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

local function windowHeight(count)
    return TOP + count * ROW_H + PAD
end

-- A secure button over each row. Tooltip: the mob, and what a click does.
local function createButton(i)
    local button = CreateFrame("Button", "AggreaoEnemyButton" .. i, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type1", "target")
    button:SetFrameStrata("HIGH")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local unit = self:GetAttribute("unit")
        if unit and not pcall(GameTooltip.SetUnit, GameTooltip, unit) then GameTooltip:SetText("Aggreao!!") end
        GameTooltip:AddLine(self:GetAttribute("type1") == "macro" and L["Click: target this enemy and send your pet"]
            or L["Click: target this enemy"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:HookScript("PreClick", function(self, mouseButton)
        if ns.debugClicks then
            ns.Print(("click %s on %s: type1=%s unit=%s"):format(tostring(mouseButton), self:GetName() or "?",
                tostring(self:GetAttribute("type1")), tostring(self:GetAttribute("unit"))))
        end
    end)
    return button
end

local function setDriver(i, conditions)
    if driven[i] == conditions then return end
    driven[i] = conditions
    RegisterStateDriver(buttons[i], "visibility", conditions)
end

-- The units around that can be attacked, the ones already fighting first: what the rows are bound to. Where there
-- are fewer than rows, the rest are bound to the next nameplate tokens, so a mob that shows up later has a row.
local function pickTokens(count)
    local picked, used = {}, {}
    local function take(unit)
        for _, other in ipairs(picked) do
            if yes(UnitIsUnit(unit, other)) then return end -- one mob, many tokens (focus, nameplate...)
        end
        picked[#picked + 1] = unit
        used[unit] = true
    end
    for pass = 1, 2 do
        for _, unit in ipairs(ns.Threat_MobTokens()) do
            if #picked >= count then break end
            if yes(UnitExists(unit)) and yes(UnitCanAttack("player", unit)) and not yes(UnitIsDead(unit))
                and (yes(UnitAffectingCombat(unit)) == (pass == 1)) then
                take(unit)
            end
        end
    end
    for _, unit in ipairs(ns.Threat_MobTokens()) do
        if #picked >= count then break end
        if not used[unit] and unit:find("^nameplate") then
            picked[#picked + 1] = unit
            used[unit] = true
        end
    end
    return picked
end

-- Outside combat only: puts the window and the buttons where the settings say, and binds the buttons.
local function settle()
    local scale = ns.char.scale
    local x, y = windowOrigin()
    local count = active and ns.char.enemyRows or 0
    local key = table.concat({ tostring(x), tostring(y), tostring(scale), tostring(ns.char.opacity), tostring(active),
        tostring(count) }, ":")
    if layoutKey ~= key then
        layoutKey = key
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        frame:SetBackdropColor(0, 0, 0, ns.char.opacity)
        for i = 1, MAX_ROWS do
            local button = buttons[i]
            button:SetScale(scale)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + PAD, y - rowTop(i))
            button:SetSize(WIDTH - 2 * PAD, ROW_H - 1)
        end
    end
    local tokens = active and pickTokens(count) or {}
    -- with a pet, a click also sends it at that mob (a hunter's pet then takes the one that is running at them)
    local pet = yes(UnitExists("pet"))
    for i = 1, MAX_ROWS do
        local token = tokens[i]
        if token ~= bound[i] or pet ~= petMode then
            bound[i] = token
            local button = buttons[i]
            if token then button:SetAttribute("unit", token) end
            if pet and token then
                button:SetAttribute("type1", "macro")
                -- (plain /target <unit>, then the pet attacks what is targeted: the forms every client understands)
                button:SetAttribute("macrotext1", ("/target %s\n/petattack"):format(token))
            else
                button:SetAttribute("type1", "target")
                button:SetAttribute("macrotext1", nil)
            end
        end
        setDriver(i, token and ("[@%s,harm,nodead,combat] show; hide"):format(token) or "hide")
    end
    petMode = pet
end

-- For when a click does nothing (/aggreao enemies): what each button is bound to and whether it is there.
function ns.Enemies_Debug()
    ns.Print(("enemy list: active=%s rows=%s lockdown=%s pet=%s mode=%s"):format(tostring(active), tostring(activeRows),
        tostring(InCombatLockdown()), tostring(petMode), tostring(ns.char.enemyListMode)))
    for i = 1, activeRows do
        local b = buttons[i]
        if b then
            ns.Print(("%d: unit=%s type1=%s shown=%s visible=%s mouse=%s size=%sx%s left=%s top=%s scale=%s driver=%s"):format(
                i, tostring(b:GetAttribute("unit")), tostring(b:GetAttribute("type1")), tostring(b:IsShown()),
                tostring(b:IsVisible()), tostring(b:IsMouseEnabled()), tostring(b:GetWidth()), tostring(b:GetHeight()),
                tostring(b:GetLeft()), tostring(b:GetTop()), tostring(b:GetScale()), tostring(driven[i])))
        end
    end
    -- what the game itself makes of each button's conditions, and what is really on each token
    for i = 1, activeRows do
        local token = bound[i]
        if token then
            local parsed = SecureCmdOptionParse and SecureCmdOptionParse(driven[i] or "") or "?"
            ns.Print(("%d: %s exists=%s attack=%s dead=%s inCombat=%s -> game says %s"):format(i, token,
                tostring(yes(UnitExists(token))), tostring(yes(UnitCanAttack("player", token))),
                tostring(yes(UnitIsDead(token))), tostring(yes(UnitAffectingCombat("player"))), tostring(parsed)))
        end
    end
    local around = {}
    for _, unit in ipairs(ns.Threat_MobTokens()) do
        if yes(UnitExists(unit)) then
            around[#around + 1] = ("%s=%s%s"):format(unit, tostring(ns.Plain(UnitName(unit))),
                yes(UnitCanAttack("player", unit)) and (yes(UnitAffectingCombat(unit)) and "(hostile,fighting)" or "(hostile)") or "")
        end
    end
    ns.Print("tokens in use: " .. (#around > 0 and table.concat(around, ", ") or "none"))
    if frame then
        ns.Print(("window: shown=%s mouse=%s left=%s top=%s scale=%s strata=%s"):format(tostring(frame:IsShown()),
            tostring(frame:IsMouseEnabled()), tostring(frame:GetLeft()), tostring(frame:GetTop()),
            tostring(frame:GetScale()), tostring(frame:GetFrameStrata())))
    end
end

-- /aggreao where: in 3 seconds, the frame under the mouse (point at the window or a row meanwhile).
function ns.Enemies_Where()
    ns.Print("pointing at what? 3 seconds...")
    C_Timer.After(3, function()
        local focus = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() or nil }
        if #focus == 0 then ns.Print("nothing under the mouse") end
        for _, f in ipairs(focus) do
            local parent = f.GetParent and f:GetParent()
            ns.Print(("under the mouse: %s (%s), parent %s"):format(tostring(f.GetName and f:GetName()),
                tostring(f.GetObjectType and f:GetObjectType()), tostring(parent and parent.GetName and parent:GetName())))
        end
    end)
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
    frame:SetSize(WIDTH, windowHeight(1))
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropBorderColor(unpack(BORDER))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    -- (unlike the aggro window it takes the mouse in combat too: it is the one you click then. Only moving it waits,
    -- because the buttons over the rows can't be moved in combat)
    frame:SetScript("OnDragStart", function(self)
        if ns.char.locked then return end
        if InCombatLockdown() then
            ns.Print(L["The enemy list can't be moved in combat. Open the preferences out of combat to place it."])
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- saved as the top left corner, the point the rows are counted from (the buttons are put there too)
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
        -- (in combat the buttons stay until it ends, and so does the window)
        ns.Print(InCombatLockdown() and L["The enemy list closes when the combat ends. Show it again in the preferences."]
            or L["Enemy list closed. Show it again in the preferences."])
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

local function draw(row, entry, role, token)
    local color = holdColor(entry, role)
    row.strip:SetColorTexture(color[1], color[2], color[3], 1)
    row:SetStatusBarColor(unpack(HEALTH_COLOR))
    -- the health can be hidden from addons (a status bar can still be given it)
    row:SetMinMaxValues(0, entry.healthMax or 1)
    row:SetValue(entry.health or 0)
    row.name:SetText(entry.mob)
    row.hp:SetText(entry.healthPct and ("%d%%"):format(math.floor(entry.healthPct + 0.5)) or "")
    row.sel:SetShown(yes(UnitIsUnit(token, "target")))
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
    local locked = InCombatLockdown()
    if not locked then
        for i = 1, MAX_ROWS do
            buttons[i] = buttons[i] or createButton(i)
        end
        active = wanted()
        activeRows = active and ns.char.enemyRows or 0
        settle()
    end
    local inCombat = yes(UnitAffectingCombat("player"))
    updateLock()
    -- out of combat it is only there to be placed, while the preferences are open
    local show = active and (inCombat or ns.Prefs_IsShown())
    if not show then
        frame:Hide()
        return
    end
    local role = myRole()
    local shown = 0
    local tokens = {}
    for i = 1, activeRows do
        local row = rows[i] or createRow(i)
        rows[i] = row
        local token = bound[i]
        local entry
        if inCombat and token and ns.Threat_IsEnemyInCombat(token) then
            entry = ns.Threat_Mob(token)
            for _, other in ipairs(tokens) do
                if yes(UnitIsUnit(token, other)) then entry = nil break end -- a mob under two tokens: once
            end
        end
        if entry then
            tokens[#tokens + 1] = token
            shown = shown + 1
            draw(row, entry, role, token)
        else
            row:Hide()
        end
    end
    for i = activeRows + 1, #rows do rows[i]:Hide() end
    if shown == 0 then
        message:SetText(inCombat and L["No enemies"] or L["Not in combat"])
        message:Show()
    else
        message:Hide()
    end
    frame:SetHeight(windowHeight(activeRows))
    frame:Show()
end
