dofile("setupTests.lua")

describe("Meter", function()
    local ns, frame

    local function visibleRows()
        return WowMock.FindAll(function(f)
            return f._parent == frame and f._kind == "StatusBar" and f._shown
        end)
    end

    local function rowTexts(row)
        local texts = {}
        for _, f in ipairs(WowMock.frames) do
            if f._parent == row and f._kind == "FontString" then texts[#texts + 1] = f._text end
        end
        return texts -- the percentage was created before the name
    end

    -- the line under the title bar: the mob's name, or what is going on when there is no list
    local function messageText() return frame.header._text end

    local function setup()
        WowMock.group = { size = 3 }
        WowMock.AddUnit("player", "Me", "MAGE", "DAMAGER")
        WowMock.AddUnit("party1", "Tank", "WARRIOR", "TANK")
        WowMock.AddUnit("party2", "Healer", "PRIEST", "HEALER")
    end

    local function target()
        WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
        WowMock.threat.player = { false, 1, 85, 70, 5000 }
        WowMock.threat.party1 = { true, 3, 100, 100, 6000 }
        WowMock.threat.party2 = { false, 0, 20, 15, 1000 }
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    local function start(charDB)
        setup()
        StartAddon(ns, nil, charDB or { locked = true })
        frame = _G.AggreaoMeterFrame
    end

    it("is created on entering; with nothing going on it says so, with no made-up players", function()
        start()
        assert.is_not_nil(frame)
        assert.is_true(frame:IsShown())
        assert.are.equal(0, #visibleRows())
        assert.are.equal("Not in combat", messageText())
    end)

    it("in combat it says what is missing: a target, or aggro data", function()
        start()
        WowMock.inCombat = true
        FireEvent("PLAYER_REGEN_DISABLED")
        ns.Meter_Update()
        assert.are.equal("No target", messageText())
        WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
        ns.Meter_Update()
        assert.are.equal("No aggro data", messageText())
    end)

    it("with a list, that line is the mob's name", function()
        start()
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal("Boss", messageText())
    end)

    describe("title bar", function()
        it("has the addon's name as title, a padlock and a close button", function()
            start()
            assert.are.equal("Aggreao!!", frame.barText._text)
            assert.is_not_nil(frame.lock)
            assert.is_not_nil(frame.close)
        end)

        it("the padlock locks and unlocks, changing its picture and the setting", function()
            start({})
            assert.are.same({ "Interface\\Buttons\\LockButton-Unlocked-Up" }, frame.lock._set.SetNormalTexture)
            frame.lock:Click()
            assert.is_true(ns.char.locked)
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
            frame.lock:Click()
            assert.is_false(ns.char.locked)
            assert.are.same({ "Interface\\Buttons\\LockButton-Unlocked-Up" }, frame.lock._set.SetNormalTexture)
        end)

        it("/aggreao lock changes the padlock too", function()
            start({})
            SlashCmdList.AGGREAO("lock")
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
        end)

        it("the padlock keeps the preferences checkbox in sync", function()
            start({})
            ns.Prefs_Toggle()
            local lockCheck = WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == _G.AggreaoPreferencesFrame end)[3]
            assert.is_false(lockCheck:GetChecked())
            frame.lock:Click()
            assert.is_true(lockCheck:GetChecked())
        end)

        it("the close button hides the window for good, and says how to bring it back", function()
            start({})
            frame.close:Click()
            assert.is_false(ns.char.enabled)
            assert.is_false(frame:IsShown())
            assert.matches("toggle", WowMock.printed[#WowMock.printed])
            SlashCmdList.AGGREAO("toggle")
            assert.is_true(frame:IsShown())
        end)
    end)

    describe("click-through in combat", function()
        it("out of combat the window, the padlock and the close button take the mouse", function()
            start()
            assert.is_true(frame:IsMouseEnabled())
            assert.is_true(frame.lock:IsMouseEnabled())
            assert.is_true(frame.close:IsMouseEnabled())
        end)

        it("in combat none of them does, so clicks go through to the game", function()
            start()
            WowMock.inCombat = true
            FireEvent("PLAYER_REGEN_DISABLED")
            ns.Meter_Update()
            assert.is_false(frame:IsMouseEnabled())
            assert.is_false(frame.lock:IsMouseEnabled())
            assert.is_false(frame.close:IsMouseEnabled())
        end)

        it("leaving combat gives the mouse back", function()
            start()
            WowMock.inCombat = true
            ns.Meter_Update()
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.is_true(frame:IsMouseEnabled())
            assert.is_true(frame.lock:IsMouseEnabled())
        end)
    end)

    describe("hide when not in combat", function()
        it("off (default): out of combat the window stays, with its message", function()
            start()
            assert.is_true(frame:IsShown())
        end)

        it("on and locked: hidden out of combat, shown in combat", function()
            start({ locked = true, hideOutOfCombat = true })
            assert.is_false(frame:IsShown())
            WowMock.inCombat = true
            target()
            FireEvent("PLAYER_TARGET_CHANGED")
            assert.is_true(frame:IsShown())
            WowMock.inCombat = false
            ns.Meter_Update()
            assert.is_false(frame:IsShown())
        end)

        it("on, locked or not: hidden out of combat", function()
            start({ hideOutOfCombat = true }) -- unlocked, the default
            assert.is_false(frame:IsShown())
        end)

        it("while the preferences are open it stays, so it can be placed; closing them hides it again", function()
            start({ hideOutOfCombat = true })
            ns.Prefs_Toggle()
            assert.is_true(frame:IsShown())
            assert.are.equal("Not in combat", messageText())
            ns.Prefs_Toggle()
            assert.is_false(frame:IsShown())
        end)

        it("leaving combat hides it on the next refresh", function()
            start({ locked = true, hideOutOfCombat = true })
            WowMock.inCombat = true
            target()
            FireEvent("PLAYER_TARGET_CHANGED")
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            local driver = WowMock.Find(function(f) return f._events and f._events.PLAYER_REGEN_ENABLED end)
            driver._scripts.OnUpdate(driver, 0.2)
            assert.is_false(frame:IsShown())
        end)
    end)

    it("targeting a hostile mob lists its threat, the tank first", function()
        start()
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.is_true(frame:IsShown())
        local rows = visibleRows()
        assert.are.equal(3, #rows)
        assert.are.same({ "100%", "Tank" }, rowTexts(rows[1]))
        assert.are.same({ "85%", "Me" }, rowTexts(rows[2]))
        assert.are.same({ "20%", "Healer" }, rowTexts(rows[3]))
    end)

    it("rows use the class color and the bar's fill follows the percentage (capped at 100)", function()
        start()
        target()
        WowMock.threat.player = { false, 1, 130, 130, 9000 }
        FireEvent("PLAYER_TARGET_CHANGED")
        local rows = visibleRows()
        assert.are.same({ 0.78, 0.61, 0.43, 0.9 }, rows[1]._set.SetStatusBarColor)
        assert.are.same({ 100 }, rows[2]._set.SetValue) -- 130 % pulls the aggro: full bar
        assert.are.same({ 20 }, rows[3]._set.SetValue)
    end)

    it("role icons: the icon of each role, hidden when unknown or turned off", function()
        start()
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        local rows = visibleRows()
        local function icon(row)
            return WowMock.Find(function(f) return f._parent == row and f._kind == "Texture" and f._set.SetTexCoord end)
        end
        assert.is_true(icon(rows[1]):IsShown())
        assert.are.equal(0, icon(rows[1])._set.SetTexCoord[1]) -- tank
        assert.are.near(20 / 64, icon(rows[3])._set.SetTexCoord[1], 0.0001) -- healer
        ns.char.showRoles = false
        ns.Meter_Update()
        assert.is_false(icon(rows[1]):IsShown())
    end)

    it("shows only as many rows as asked, keeping the player's own", function()
        start()
        target()
        ns.char.rows = 3
        WowMock.AddUnit("party3", "P3", "MAGE", "DAMAGER")
        WowMock.AddUnit("party4", "P4", "MAGE", "DAMAGER")
        WowMock.group = { size = 5 }
        WowMock.threat.party3 = { false, 0, 60, 50, 3000 }
        WowMock.threat.party4 = { false, 0, 50, 40, 2000 }
        WowMock.threat.player = { false, 0, 10, 10, 100 }
        FireEvent("PLAYER_TARGET_CHANGED")
        local rows = visibleRows()
        assert.are.equal(3, #rows)
        assert.are.same({ "10%", "Me" }, rowTexts(rows[3]))
    end)

    it("the list goes away when the target is not hostile, dead, or gone", function()
        start()
        WowMock.inCombat = true
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(3, #visibleRows())
        WowMock.units.target.dead = true
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #visibleRows())
        assert.are.equal("No target", messageText())
        WowMock.units.target.dead = false
        WowMock.units.target.hostile = false
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #visibleRows())
        WowMock.units.target = nil
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #visibleRows())
    end)

    it("a target nobody has threat on has no rows", function()
        start()
        WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #visibleRows())
        assert.are.equal("Not in combat", messageText())
    end)

    it("'Show the aggro window' off hides it for good", function()
        start({ locked = true, enabled = false })
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.is_false(frame:IsShown())
    end)

    it("threat events redraw on the next tick, not each", function()
        start()
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        WowMock.threat.player = { false, 1, 95, 90, 5900 }
        FireEvent("UNIT_THREAT_LIST_UPDATE")
        assert.are.same({ "85%", "Me" }, rowTexts(visibleRows()[2])) -- not yet
        local driver = WowMock.Find(function(f) return f._events and f._events.UNIT_THREAT_LIST_UPDATE end)
        driver._scripts.OnUpdate(driver, 0.01)
        assert.are.same({ "85%", "Me" }, rowTexts(visibleRows()[2]))
        driver._scripts.OnUpdate(driver, 0.2)
        assert.are.same({ "95%", "Me" }, rowTexts(visibleRows()[2]))
    end)

    it("without events it still refreshes every quarter second", function()
        start()
        target()
        FireEvent("PLAYER_TARGET_CHANGED")
        WowMock.threat.player = { false, 1, 70, 60, 5000 }
        local driver = WowMock.Find(function(f) return f._events and f._events.PLAYER_TARGET_CHANGED end)
        driver._scripts.OnUpdate(driver, 0.3)
        assert.are.same({ "70%", "Me" }, rowTexts(visibleRows()[2]))
    end)

    it("the border turns red close to taking the aggro, and back", function()
        start()
        target()
        WowMock.threat.player = { false, 1, 90, 80, 5800 }
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.same({ 1, 0.1, 0.1, 1 }, frame._set.SetBackdropBorderColor)
        WowMock.threat.player = { false, 1, 30, 30, 500 }
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.same({ 0.3, 0.3, 0.3, 1 }, frame._set.SetBackdropBorderColor)
        ns.char.alertFlash = false
        WowMock.threat.player = { false, 1, 90, 80, 5800 }
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.same({ 0.3, 0.3, 0.3, 1 }, frame._set.SetBackdropBorderColor)
    end)

    it("the sound plays when the target is first targeted already close to the aggro", function()
        start()
        target()
        WowMock.threat.player = { false, 1, 90, 80, 5800 }
        FireEvent("PLAYER_TARGET_CHANGED")
        assert.are.equal(1, #WowMock.sounds)
    end)

    describe("position and settings", function()
        it("dragging saves where it was left; reset forgets it", function()
            start({})
            frame._points = { { "TOPLEFT", UIParent, "TOPLEFT", 40, -60 } }
            frame._scripts.OnDragStop(frame)
            assert.are.same({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -60 }, ns.char.window)
            ns.Meter_ResetPosition()
            assert.is_nil(ns.char.window)
        end)

        it("restores the saved position, scale and background opacity", function()
            start({ window = { point = "TOP", relPoint = "TOP", x = 5, y = -7 }, scale = 1.2, opacity = 0.4 })
            local point = frame:GetPoint(1)
            assert.are.equal("TOP", point)
            assert.are.equal(1.2, frame:GetScale())
            assert.are.same({ 0, 0, 0, 0.4 }, frame._set.SetBackdropColor)
        end)

        it("locked, dragging doesn't start a move; unlocked it does", function()
            start({ locked = true })
            local moved = false
            frame.StartMoving = function() moved = true end
            frame._scripts.OnDragStart(frame)
            assert.is_false(moved)
            ns.char.locked = false
            frame._scripts.OnDragStart(frame)
            assert.is_true(moved)
        end)

        it("right-click opens the preferences", function()
            start()
            frame._scripts.OnMouseUp(frame, "LeftButton")
            assert.is_false(ns.Prefs_IsShown())
            frame._scripts.OnMouseUp(frame, "RightButton")
            assert.is_true(_G.AggreaoPreferencesFrame:IsShown())
        end)

        it("/aggreao toggle, lock, unlock, reset", function()
            start({})
            SlashCmdList.AGGREAO("toggle")
            assert.is_false(frame:IsShown())
            SlashCmdList.AGGREAO("toggle")
            assert.is_true(frame:IsShown())
            SlashCmdList.AGGREAO("lock")
            assert.is_true(ns.char.locked)
            SlashCmdList.AGGREAO("unlock")
            assert.is_false(ns.char.locked)
            ns.char.window = { point = "TOP", relPoint = "TOP", x = 1, y = 1 }
            SlashCmdList.AGGREAO("reset")
            assert.is_nil(ns.char.window)
        end)
    end)
end)
