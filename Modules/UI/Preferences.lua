local _, ns = ...
local L = ns.L

-- Preferences window (opened with the minimap button, right-click on the aggro window or /aggreao prefs).
-- Settings, in ns.char: per character or shared by the account, depending on the first checkbox.
local WIDTH, HEIGHT = 340, 692
local LABEL_W = WIDTH - 48 - 16 -- a checkbox's text: from after the box (x = 48) to the window's right margin
local prefs

local function makeSlider(parent, y, min, max, step, getValue, setValue, labelFor)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 24, y)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(280, 16)
    slider:SetPoint("TOPLEFT", 28, y - 24)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local bar = slider:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("LEFT", 0, 0)
    bar:SetPoint("RIGHT", 0, 0)
    bar:SetHeight(4)
    bar:SetColorTexture(1, 1, 1, 0.25)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(20, 20)

    local refreshing = false
    slider:SetScript("OnValueChanged", function(_, value)
        value = tonumber(("%.2f"):format(math.floor(value / step + 0.5) * step)) -- on the step grid
        label:SetText(labelFor(value))
        if not refreshing then setValue(value) end
    end)
    function slider.Refresh()
        refreshing = true
        local value = getValue()
        slider:SetValue(value)
        label:SetText(labelFor(value))
        refreshing = false
    end
    return slider
end

local function makeCheck(parent, y, text, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 20, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    -- a long text (or a longer translation) wraps to a second line instead of running out of the window
    label:SetWidth(LABEL_W)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(text)
    check:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end)
    function check.Refresh() check:SetChecked(getValue() and true or false) end
    return check
end

local function makeButton(parent, y, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(292, 24)
    button:SetPoint("TOPLEFT", 24, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function percent(value) return math.floor(value * 100 + 0.5) end

local function create()
    prefs = CreateFrame("Frame", "AggreaoPreferencesFrame", UIParent, "BackdropTemplate")
    prefs:SetSize(WIDTH, HEIGHT)
    prefs:SetPoint("CENTER")
    prefs:SetFrameStrata("DIALOG")
    prefs:SetClampedToScreen(true)
    prefs:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    prefs:SetBackdropColor(0, 0, 0, 0.9)
    prefs:SetMovable(true)
    prefs:EnableMouse(true)
    prefs:RegisterForDrag("LeftButton")
    prefs:SetScript("OnDragStart", prefs.StartMoving)
    prefs:SetScript("OnDragStop", prefs.StopMovingOrSizing)
    tinsert(UISpecialFrames, "AggreaoPreferencesFrame")

    local okClose, close = pcall(CreateFrame, "Button", nil, prefs, "UIPanelCloseButtonDefaultAnchors")
    if not okClose or not close then
        close = CreateFrame("Button", nil, prefs, "UIPanelCloseButton")
    end
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = prefs:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText(L["Aggreao!! Preferences"])

    local widgets = {}
    local note = prefs:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", 0, 16)
    local function refreshAll()
        for _, widget in ipairs(widgets) do widget.Refresh() end
        note:SetText(ns.IsPerCharacter() and L["Settings are saved for this character only."]
            or L["Settings are shared by all your characters."])
    end
    -- a setting changed: store it and redraw the window
    local function set(key)
        return function(value)
            ns.char[key] = value
            ns.Meter_Update()
        end
    end
    local function get(key) return function() return ns.char[key] end end
    local function applied(key)
        return function(value)
            ns.char[key] = value
            ns.Meter_ApplySettings()
        end
    end

    -- As in Embolsao: decides where everything below is kept (Modules/Settings, ns.SetPerCharacter).
    widgets[#widgets + 1] = makeCheck(prefs, -48, L["Character specific preferences"],
        function() return ns.IsPerCharacter() end,
        function(value)
            ns.SetPerCharacter(value)
            refreshAll()
        end)

    -- the window
    widgets[#widgets + 1] = makeCheck(prefs, -76, L["Show the aggro window"], get("enabled"), set("enabled"))
    widgets[#widgets + 1] = makeCheck(prefs, -104, L["Lock the window position"], get("locked"), set("locked"))
    widgets[#widgets + 1] = makeCheck(prefs, -132, L["Show role icons (tank, healer, dps)"], get("showRoles"), set("showRoles"))
    widgets[#widgets + 1] = makeCheck(prefs, -160, L["Include pets"], get("pets"), set("pets"))
    widgets[#widgets + 1] = makeCheck(prefs, -188, L["Hide when not in combat"], get("hideOutOfCombat"), set("hideOutOfCombat"))
    widgets[#widgets + 1] = makeSlider(prefs, -222, 3, 10, 1, get("rows"), set("rows"),
        function(value) return L["Players listed: %d"]:format(value) end)
    widgets[#widgets + 1] = makeSlider(prefs, -274, 0.5, 1.5, 0.05, get("scale"), applied("scale"),
        function(value) return L["Scale: %d%%"]:format(percent(value)) end)
    widgets[#widgets + 1] = makeSlider(prefs, -326, 0, 1, 0.05, get("opacity"), applied("opacity"),
        function(value) return L["Background opacity: %d%%"]:format(percent(value)) end)

    -- the alert
    widgets[#widgets + 1] = makeCheck(prefs, -378, L["Play a sound when you are close to taking the aggro"],
        get("alertSound"), set("alertSound"))
    widgets[#widgets + 1] = makeCheck(prefs, -422, L["Red border when you are close to taking the aggro"],
        get("alertFlash"), set("alertFlash"))
    widgets[#widgets + 1] = makeSlider(prefs, -466, 50, 100, 5, get("alertThreshold"), set("alertThreshold"),
        function(value) return L["Alert from %d%% of the aggro"]:format(value) end)

    local soundButton = makeButton(prefs, -518, "", function(self)
        local options = {}
        for _, s in ipairs(ns.ALERT_SOUNDS) do options[#options + 1] = { name = s.name, key = s.key } end
        ns.PopupMenu(self, options, function(opt)
            ns.char.alertSoundKey = opt.key
            ns.Alert_Play(opt.key) -- you hear what you picked
            refreshAll()
        end, 292)
    end)
    soundButton.Refresh = function()
        soundButton:SetText(L["Sound: %s"]:format(ns.Alert_SoundName(ns.char.alertSoundKey)))
    end
    widgets[#widgets + 1] = soundButton
    makeButton(prefs, -546, L["Test the sound"], function() ns.Alert_Play() end)

    -- the rest
    widgets[#widgets + 1] = makeCheck(prefs, -578, L["Show the minimap button"],
        function() return ns.Minimap_IsShown() end,
        function(value) ns.Minimap_SetShown(value) end)
    widgets[#widgets + 1] = makeCheck(prefs, -606, L["Show chat messages at startup"],
        function() return not ns.char.quiet end,
        function(value) ns.char.quiet = (not value) or nil end)

    local resetButton = makeButton(prefs, -634, L["Reset window position"], function() ns.Meter_ResetPosition() end)
    resetButton:SetWidth(142)
    local newButton = makeButton(prefs, -634, L["What's new"], function() ns.Welcome_Show() end)
    newButton:SetWidth(142)
    newButton:SetPoint("TOPLEFT", 174, -634)

    -- the aggro window stays visible while this one is open, even when it hides out of combat
    prefs:SetScript("OnShow", function()
        refreshAll()
        ns.Meter_Update()
    end)
    prefs:SetScript("OnHide", ns.Meter_Update)
    prefs:Hide() -- frames are born shown: hidden until the first Prefs_Toggle (which would close it otherwise)
end

function ns.Prefs_IsShown()
    return prefs ~= nil and prefs:IsShown()
end

function ns.Prefs_Toggle()
    if not prefs then create() end
    prefs:SetShown(not prefs:IsShown())
end
