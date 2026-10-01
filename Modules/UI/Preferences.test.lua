dofile("setupTests.lua")

describe("Preferences", function()
    local ns, prefs

    local function checks()
        return WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == prefs end)
    end
    local function sliders()
        return WowMock.FindAll(function(f) return f._kind == "Slider" and f._parent == prefs end)
    end
    local function changeSlider(slider, value)
        slider._scripts.OnValueChanged(slider, value)
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns, nil, { locked = true })
        ns.Prefs_Toggle()
        prefs = _G.AggreaoPreferencesFrame
    end)

    it("the first call opens it (no second call needed), the next closes it", function()
        assert.is_true(prefs:IsShown())
        ns.Prefs_Toggle()
        assert.is_false(prefs:IsShown())
    end)

    it("the checkboxes reflect and change the settings", function()
        -- order: per character, show window, lock, role icons, pets, sound, red border, minimap, chat messages
        local list = checks()
        assert.are.equal(9, #list)
        assert.is_true(list[1]:GetChecked())  -- per character
        assert.is_true(list[2]:GetChecked())  -- window shown (default)
        assert.is_true(list[3]:GetChecked())  -- locked (the test login)
        assert.is_true(list[4]:GetChecked())  -- role icons (default)
        list[3]:SetChecked(false); list[3]:Click()
        assert.is_false(ns.char.locked)
        list[4]:SetChecked(false); list[4]:Click()
        assert.is_false(ns.char.showRoles)
        list[5]:SetChecked(false); list[5]:Click()
        assert.is_false(ns.char.pets)
        list[6]:SetChecked(false); list[6]:Click()
        assert.is_false(ns.char.alertSound)
        list[7]:SetChecked(false); list[7]:Click()
        assert.is_false(ns.char.alertFlash)
        list[9]:SetChecked(false); list[9]:Click()
        assert.is_true(ns.char.quiet)
        list[8]:SetChecked(false); list[8]:Click()
        assert.is_true(ns.char.minimap.hide)
    end)

    it("the sliders show and change rows, scale, opacity and the alert threshold", function()
        local list = sliders()
        assert.are.equal(4, #list)
        changeSlider(list[1], 7)
        assert.are.equal(7, ns.char.rows)
        changeSlider(list[2], 1.2)
        assert.are.equal(1.2, ns.char.scale)
        assert.are.equal(1.2, _G.AggreaoMeterFrame:GetScale())
        changeSlider(list[3], 0.35)
        assert.are.equal(0.35, ns.char.opacity)
        changeSlider(list[4], 90)
        assert.are.equal(90, ns.char.alertThreshold)
    end)

    it("refreshing the sliders (opening it) doesn't write the settings", function()
        ns.char.rows = 4
        prefs:Hide()
        prefs:Show()
        assert.are.equal(4, ns.char.rows)
        assert.are.same({ 4 }, sliders()[1]._set.SetValue)
    end)

    it("the sound button shows the chosen sound, offers them all and plays the picked one", function()
        local button = WowMock.FindButton("Sound: Raid warning")
        assert.is_not_nil(button)
        button:Click()
        local options = WowMock.FindAll(function(f) return f.text and f._scripts.OnClick and f._shown and f._parent and f._parent.buttons end)
        assert.are.equal(#ns.ALERT_SOUNDS, #options)
        options[3]:Click()
        assert.are.equal("alarm", ns.char.alertSoundKey)
        assert.are.equal(12867, WowMock.sounds[#WowMock.sounds][1])
        assert.is_not_nil(WowMock.FindButton("Sound: Alarm clock"))
    end)

    it("the test button plays the chosen sound", function()
        ns.char.alertSoundKey = "ping"
        WowMock.FindButton("Test the sound"):Click()
        assert.are.equal(3175, WowMock.sounds[1][1])
    end)

    it("Reset window position forgets the saved position", function()
        ns.char.window = { point = "TOP", relPoint = "TOP", x = 1, y = 1 }
        WowMock.FindButton("Reset window position"):Click()
        assert.is_nil(ns.char.window)
    end)

    it("What's new opens the welcome window", function()
        WowMock.FindButton("What's new"):Click()
        assert.is_true(_G.AggreaoWelcomeFrame:IsShown())
    end)

    it("the first checkbox switches between per character and shared settings", function()
        local first = checks()[1]
        first:SetChecked(false); first:Click()
        assert.is_false(ns.IsPerCharacter())
        assert.matches("shared", WowMock.FindAll(function(f) return f._kind == "FontString" and f._parent == prefs and
            type(f._text) == "string" and f._text:find("shared") end)[1]._text)
    end)
end)
