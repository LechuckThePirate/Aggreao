dofile("setupTests.lua")

describe("Enemies", function()
    local ns, frame

    local function visibleRows()
        return WowMock.FindAll(function(f)
            return f._parent == frame and f._kind == "StatusBar" and f._shown
        end)
    end

    local function buttons()
        local list = {}
        for i = 1, 10 do list[i] = _G["AggreaoEnemyButton" .. i] end
        return list
    end

    local function texts(row)
        local list = {}
        for _, f in ipairs(WowMock.frames) do
            if f._parent == row and f._kind == "FontString" then list[#list + 1] = f._text end
        end
        return list -- who, hp, name (the order they were created in)
    end

    local function mob(token, name, attackedBy, health)
        WowMock.AddUnit(token, name, "WARRIOR", nil, { hostile = true, npc = true, inCombat = true,
            health = health or 50, healthMax = 100 })
        WowMock.units[token .. "target"] = attackedBy
    end

    local function enterCombat()
        WowMock.inCombat = true
        FireEvent("PLAYER_REGEN_DISABLED")
        ns.Meter_Update()
    end

    local function start(charDB)
        WowMock.group = { size = 3 }
        WowMock.AddUnit("player", "Me", "WARRIOR", "TANK")
        WowMock.AddUnit("party1", "Healer", "PRIEST", "HEALER")
        WowMock.AddUnit("party2", "Mage", "MAGE", "DAMAGER")
        StartAddon(ns, nil, charDB or { locked = true })
        frame = _G.AggreaoEnemiesFrame
    end

    before_each(function()
        dofile("test/WowApiMock.lua")
        WowMock.Reset()
        _G.AggreaoEnemiesFrame = nil
        for i = 1, 10 do _G["AggreaoEnemyButton" .. i] = nil end -- (the mock keeps named frames in _G)
        ns = LoadAddon()
    end)

    describe("the window", function()
        it("is hidden out of combat, and shows while the preferences are open so it can be placed", function()
            start()
            assert.is_false(frame:IsShown())
            ns.Prefs_Toggle()
            assert.is_true(frame:IsShown())
            assert.is_not_nil(WowMock.Find(function(f)
                return f._parent == frame and f._kind == "FontString" and f._text == "Not in combat"
            end))
            ns.Prefs_Toggle()
            assert.is_false(frame:IsShown())
        end)

        it("shows in combat, saying so when nothing is fighting you", function()
            start()
            enterCombat()
            assert.is_true(frame:IsShown())
            assert.is_not_nil(WowMock.FindByText("No enemies"))
        end)

        it("off in the settings: never shown", function()
            start({ locked = true, enemyListMode = "never" })
            enterCombat()
            assert.is_false(frame:IsShown())
        end)

        describe("who gets it", function()
            local function playerIs(role, class)
                WowMock.group = { size = 3 }
                WowMock.AddUnit("player", "Me", class or "WARRIOR", role)
                WowMock.AddUnit("party1", "Healer", "PRIEST", "HEALER")
            end

            it("by default a tank gets it", function()
                playerIs("TANK")
                StartAddon(ns, nil, { locked = true })
                enterCombat()
                assert.is_true(_G.AggreaoEnemiesFrame:IsShown())
                assert.is_true(ns.Enemies_IsActive())
            end)

            it("by default a dps or a healer does not, and sees the other mobs in the aggro window instead", function()
                playerIs("DAMAGER")
                StartAddon(ns, nil, { locked = true })
                enterCombat()
                assert.is_false(_G.AggreaoEnemiesFrame:IsShown())
                assert.is_false(ns.Enemies_IsActive())
                for _, button in ipairs(buttons()) do
                    assert.are.equal("hide", WowMock.drivers[button].visibility)
                end
                mob("nameplate1", "Wolf", WowMock.units.party1)
                ns.Meter_Update()
                assert.are.equal(1, #WowMock.FindAll(function(f)
                    return f._parent == _G.AggreaoMeterFrame and f.mob ~= nil and f._shown
                end))
            end)

            it("by default it is shown when the game does not say what you are", function()
                WowMock.group = nil
                StartAddon(ns, nil, { locked = true }) -- alone, no role: the game gives none
                _G.UnitGroupRolesAssigned = function() return "NONE" end
                WowMock.class = { "Warrior", "WARRIOR", 1 }
                ns.Meter_Update()
                assert.is_true(ns.Enemies_IsActive())
            end)

            it("'always' gives it to a dps too; 'never' takes it from a tank", function()
                playerIs("DAMAGER")
                StartAddon(ns, nil, { locked = true, enemyListMode = "always" })
                assert.is_true(ns.Enemies_IsActive())
                ns.char.enemyListMode = "never"
                ns.Meter_Update()
                assert.is_false(ns.Enemies_IsActive())
            end)

            it("a role change in the middle of a fight takes effect when it ends", function()
                playerIs("TANK")
                StartAddon(ns, nil, { locked = true })
                enterCombat()
                WowMock.units.player.role = "DAMAGER"
                assert.has_no.errors(function() ns.Meter_Update() end)
                assert.is_true(ns.Enemies_IsActive())
                WowMock.inCombat = false
                FireEvent("PLAYER_REGEN_ENABLED")
                ns.Meter_Update()
                assert.is_false(ns.Enemies_IsActive())
            end)
        end)

        it("the close button turns it off for good", function()
            start({})
            ns.Prefs_Toggle()
            frame.close:Click()
            assert.are.equal("never", ns.char.enemyListMode)
            assert.is_false(frame:IsShown())
        end)

        it("takes the mouse in combat too (it is the window you click then); only moving it waits", function()
            start({})
            assert.is_true(frame:IsMouseEnabled())
            enterCombat()
            assert.is_true(frame:IsMouseEnabled())
            local moved = false
            frame.StartMoving = function() moved = true end
            frame._scripts.OnDragStart(frame)
            assert.is_false(moved)
            assert.matches("can't be moved in combat", WowMock.printed[#WowMock.printed])
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            frame._scripts.OnDragStart(frame)
            assert.is_true(moved)
        end)

        it("dragging saves the top left corner; locked, it does not start a move", function()
            start({})
            frame._points = {}
            frame.GetLeft = function() return 40 end
            frame.GetTop = function() return 500 end
            frame._scripts.OnDragStop(frame)
            assert.are.same({ x = 40, y = 500 }, ns.char.enemyWindow)
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 500 }, frame._points[#frame._points])
            local moved = false
            frame.StartMoving = function() moved = true end
            ns.char.locked = true
            frame._scripts.OnDragStart(frame)
            assert.is_false(moved)
            ns.char.locked = false
            frame._scripts.OnDragStart(frame)
            assert.is_true(moved)
        end)

        it("has its own padlock, the aggro window's too: it unlocks both and shows the state", function()
            start({ locked = true })
            ns.Prefs_Toggle()
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
            frame.lock:Click()
            assert.is_false(ns.char.locked)
            assert.are.same({ "Interface\\Buttons\\LockButton-Unlocked-Up" }, frame.lock._set.SetNormalTexture)
            local moved = false
            frame.StartMoving = function() moved = true end
            frame._scripts.OnDragStart(frame)
            assert.is_true(moved)
            -- the padlock of the aggro window changes the picture here too
            _G.AggreaoMeterFrame.lock:Click()
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
        end)

        it("/aggreao enemies reports each button, /aggreao debug reports each click, /aggreao where the frame under the mouse", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            WowMock.printed = {}
            SlashCmdList.AGGREAO("enemies")
            local report = table.concat(WowMock.printed, "\n")
            assert.matches("enemy list: active=true rows=3", report)
            assert.matches("1: unit=nameplate1 type1=target", report)
            assert.matches("window: shown=true", report)
            SlashCmdList.AGGREAO("debug")
            WowMock.printed = {}
            buttons()[1]._hooks.PreClick[1](buttons()[1], "LeftButton")
            assert.matches("click LeftButton on AggreaoEnemyButton1: type1=target unit=nameplate1", WowMock.printed[1])
            WowMock.printed = {}
            _G.GetMouseFoci = function() return { frame } end
            SlashCmdList.AGGREAO("where")
            _G.GetMouseFoci = nil
            assert.matches("under the mouse: AggreaoEnemiesFrame", WowMock.printed[#WowMock.printed])
        end)

        it("/aggreao test binds the first button to a mob with the plain target action, always shown; again turns it off", function()
            start({ locked = true })
            SlashCmdList.AGGREAO("test")
            assert.matches("no hostile mob", WowMock.printed[#WowMock.printed])
            WowMock.AddUnit("nameplate3", "Wolf", "WARRIOR", nil, { hostile = true, npc = true })
            SlashCmdList.AGGREAO("test")
            local b = buttons()[1]
            assert.are.equal("target", b:GetAttribute("type1"))
            assert.are.equal("nameplate3", b:GetAttribute("unit"))
            assert.are.equal("show", WowMock.drivers[b].visibility)
            assert.is_true(b.test:IsShown())
            ns.Meter_Update() -- the refresh leaves it as it is
            assert.are.equal("nameplate3", b:GetAttribute("unit"))
            assert.are.equal("show", WowMock.drivers[b].visibility)
            SlashCmdList.AGGREAO("test")
            assert.is_false(b.test:IsShown())
            assert.are.equal("nameplate3", b:GetAttribute("unit")) -- (it is also what the list binds to)
            assert.are_not.equal("show", WowMock.drivers[b].visibility)
        end)

        it("/aggreao test does nothing in combat", function()
            start({ locked = true })
            WowMock.AddUnit("nameplate3", "Wolf", "WARRIOR", nil, { hostile = true, npc = true })
            enterCombat()
            assert.has_no.errors(function() SlashCmdList.AGGREAO("test") end)
            assert.matches("not in combat", WowMock.printed[#WowMock.printed])
        end)

        it("in combat the padlock works, and the close button turns it off when the combat ends", function()
            start({})
            enterCombat()
            frame.lock:Click()
            assert.is_true(ns.char.locked)
            assert.has_no.errors(function() frame.close:Click() end)
            assert.matches("closes when the combat ends", WowMock.printed[#WowMock.printed])
            assert.is_true(frame:IsShown()) -- the buttons stay until then, so does the window
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.is_false(frame:IsShown())
        end)

        it("right-click opens the preferences", function()
            start()
            frame._scripts.OnMouseUp(frame, "RightButton")
            assert.is_true(ns.Prefs_IsShown())
        end)

        it("the same size in combat whatever the number of mobs: its height only follows the rows asked for", function()
            start({ locked = true, enemyRows = 4 })
            enterCombat()
            local height = frame:GetHeight()
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            assert.are.equal(height, frame:GetHeight())
        end)
    end)

    describe("rows", function()
        it("one per mob in combat: name, health and whom it attacks, with your threat on it", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.party1, 25)
            mob("nameplate2", "Boar", WowMock.units.player, 80)
            WowMock.threat["player@nameplate1"] = { false, 1, 64, 50, 500 }
            ns.Meter_Update() -- out of combat: the buttons get their mobs
            enterCombat()
            local rows = visibleRows()
            assert.are.equal(2, #rows)
            assert.are.same({ "Wolf", "25%" }, { texts(rows[1])[3], texts(rows[1])[2] })
            assert.matches("Healer", texts(rows[1])[1])
            assert.matches("64%%", texts(rows[1])[1])
            assert.are.same({ "Boar", "80%", "YOU" }, { texts(rows[2])[3], texts(rows[2])[2], texts(rows[2])[1] })
        end)

        it("the health bar is given the health as it is, even a hidden one", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player, 30)
            ns.Meter_Update()
            enterCombat()
            assert.are.same({ 0, 100 }, visibleRows()[1]._set.SetMinMaxValues)
            assert.are.same({ 30 }, visibleRows()[1]._set.SetValue)
        end)

        it("health numbers hidden from addons: the bar gets them, the text stays empty, nothing is compared", function()
            local SECRET = { "secret" }
            _G.issecretvalue = function(v) return v == SECRET end
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            WowMock.units.nameplate1.health, WowMock.units.nameplate1.healthMax = SECRET, SECRET
            ns.Meter_Update()
            enterCombat()
            local row = visibleRows()[1]
            assert.are.same({ SECRET }, row._set.SetValue)
            assert.are.equal("", texts(row)[2])
            _G.issecretvalue = nil
        end)

        it("an attacker whose name is hidden is handed over as it is: no color, no threat added", function()
            local SECRET = "\0secret"
            _G.issecretvalue = function(v) return v == SECRET end
            start()
            WowMock.AddUnit("party3", SECRET, SECRET, SECRET)
            mob("nameplate1", "Wolf", WowMock.units.party3)
            ns.Meter_Update()
            enterCombat()
            local row = visibleRows()[1]
            assert.are.equal(SECRET, texts(row)[1])
            assert.are.same({ 1, 1, 1 }, row.who and row.who._set.SetTextColor or { 1, 1, 1 })
            _G.issecretvalue = nil
        end)

        it("the row of your current target is marked", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.player)
            WowMock.units.target = WowMock.units.nameplate2
            ns.Meter_Update()
            enterCombat()
            local rows = visibleRows()
            local function selected(row)
                return WowMock.Find(function(f) return f._parent == row and f._kind == "Texture" and f._set.SetColorTexture
                    and f._set.SetColorTexture[4] == 0.18 end)
            end
            assert.is_false(selected(rows[1]):IsShown())
            assert.is_true(selected(rows[2]):IsShown())
        end)

        it("a mob that is not fighting, or is dead, has no row", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.player)
            mob("nameplate3", "Bat", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            WowMock.units.nameplate2.inCombat = false
            WowMock.units.nameplate3.dead = true
            ns.Meter_Update()
            assert.are.equal(1, #visibleRows())
        end)

        it("a mob seen under two tokens (focus and a nameplate) is listed once", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            WowMock.units.focus = WowMock.units.nameplate1
            ns.Meter_Update()
            enterCombat()
            assert.are.equal(1, #visibleRows())
        end)

        it("only as many rows as asked for", function()
            start({ locked = true, enemyRows = 3 })
            for i = 1, 5 do mob("nameplate" .. i, "M" .. i, WowMock.units.player) end
            ns.Meter_Update()
            enterCombat()
            assert.are.equal(3, #visibleRows())
        end)

        it("the strip says your hold: green a tank that has it, red when it is on a healer; the other way for a dps", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.party1)
            ns.Meter_Update()
            enterCombat()
            local function strip(row)
                return WowMock.Find(function(f) return f._parent == row and f._kind == "Texture" and f._set.SetColorTexture
                    and f._set.SetColorTexture[4] == 1 end)._set.SetColorTexture
            end
            local rows = visibleRows()
            assert.are.same({ 0.2, 0.8, 0.2, 1 }, strip(rows[1])) -- tank, on me
            assert.are.same({ 1, 0.15, 0.15, 1 }, strip(rows[2])) -- tank, on the healer
            WowMock.units.player.role = "DAMAGER"
            ns.Meter_Update()
            assert.are.same({ 1, 0.15, 0.15, 1 }, strip(rows[1])) -- dps, on me
            assert.are.same({ 0.2, 0.8, 0.2, 1 }, strip(rows[2])) -- dps, on somebody else
        end)

        it("the aggro window no longer repeats them under its own list", function()
            start({ locked = true })
            WowMock.inCombat = true
            WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            assert.are.equal(0, #WowMock.FindAll(function(f) return f._parent == _G.AggreaoMeterFrame and f.mob ~= nil and f._shown end))
        end)
    end)

    describe("click to target", function()
        it("there is a secure button for every row, over it, that targets with a left click", function()
            start()
            for i, button in ipairs(buttons()) do
                assert.is_not_nil(button, i)
                assert.are.equal("SecureActionButtonTemplate", button._template)
                assert.are.equal("target", button:GetAttribute("type1"))
                assert.are.equal(UIParent, button._parent)
            end
        end)

        it("outside combat each is bound to a mob that is around, the ones fighting first", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate5", "Wolf", WowMock.units.player)
            WowMock.units.nameplate1 = { name = "Rat", hostile = true } -- not fighting
            ns.Meter_Update()
            local b = buttons()
            assert.are.equal("nameplate5", b[1]:GetAttribute("unit"))
            assert.are.equal("nameplate1", b[2]:GetAttribute("unit"))
            -- the next free nameplate token, so a mob that shows up later has a row
            assert.are.equal("nameplate2", b[3]:GetAttribute("unit"))
        end)

        it("the game shows each button only while its mob can be attacked, is alive and you are in combat", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate5", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            assert.are.equal("[@nameplate5,harm,nodead,combat] show; hide", WowMock.drivers[buttons()[1]].visibility)
        end)

        it("buttons beyond the rows asked for are hidden for good", function()
            start({ locked = true, enemyRows = 3 })
            ns.Meter_Update()
            assert.are.equal("hide", WowMock.drivers[buttons()[4]].visibility)
            assert.are.equal("hide", WowMock.drivers[buttons()[10]].visibility)
        end)

        it("with the list off, every button is hidden", function()
            start({ locked = true, enemyListMode = "never" })
            for _, button in ipairs(buttons()) do
                assert.are.equal("hide", WowMock.drivers[button].visibility)
            end
        end)

        it("the buttons sit over the rows, from the window's top left corner, at the window's scale", function()
            start({ locked = true, scale = 1.2, enemyWindow = { x = 100, y = 700 } })
            local b = buttons()
            assert.are.equal(1.2, b[1]:GetScale())
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 104, 700 - 23 }, b[1]._points[#b[1]._points])
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 104, 700 - 23 - 20 }, b[2]._points[#b[2]._points])
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700 }, frame._points[#frame._points])
        end)

        it("moving the window moves the buttons with it", function()
            start({})
            frame.GetLeft = function() return 300 end
            frame.GetTop = function() return 400 end
            frame._scripts.OnDragStop(frame)
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 304, 400 - 23 }, buttons()[1]._points[#buttons()[1]._points])
        end)

        it("hangs from the screen, not from the window: nothing the window needs in combat is protected", function()
            start()
            assert.is_nil(frame._restricted)
            assert.is_nil(frame.close._restricted)
            for _, f in ipairs(WowMock.frames) do
                if f._parent == frame then assert.is_nil(f._restricted) end
            end
        end)

        it("in combat the rows keep their mobs and show whatever mob the token is on now", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            -- the game hands nameplate1 to another mob
            mob("nameplate1", "Boar", WowMock.units.party1)
            ns.Meter_Update()
            assert.are.equal("nameplate1", buttons()[1]:GetAttribute("unit"))
            assert.are.equal("Boar", texts(visibleRows()[1])[3])
        end)

        it("nothing protected is touched in combat: redraws, a new mob, dying mobs, settings changed", function()
            start({ locked = true })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            assert.has_no.errors(function()
                mob("nameplate2", "Boar", WowMock.units.party1)
                ns.Meter_Update()
                WowMock.units.nameplate1.dead = true
                ns.Meter_Update()
                ns.char.scale = 1.3
                ns.char.enemyRows = 8
                ns.char.enemyListMode = "never"
                ns.Meter_ApplySettings()
                FireEvent("PLAYER_TARGET_CHANGED")
            end)
        end)

        it("what is asked in combat (scale, rows, turning it off) is done when the combat ends", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            ns.char.scale = 1.3
            ns.char.enemyRows = 5
            ns.Meter_ApplySettings()
            assert.are.equal(1, buttons()[1]:GetScale())
            assert.are.equal("hide", WowMock.drivers[buttons()[5]].visibility)
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.are.equal(1.3, buttons()[1]:GetScale())
            assert.are.equal(1.3, frame:GetScale())
            assert.are_not.equal("hide", WowMock.drivers[buttons()[5]].visibility)
        end)

        it("started in combat (a /reload in the middle of it): nothing protected is touched; the buttons come after", function()
            WowMock.inCombat = true
            start({ locked = true })
            assert.is_nil(_G.AggreaoEnemyButton1)
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.is_not_nil(_G.AggreaoEnemyButton1)
        end)

        it("with a pet a click also sends it at that mob; without one it only targets", function()
            WowMock.AddUnit("pet", "Porky", "HUNTER", "NONE", { pet = true })
            start({ locked = true, enemyRows = 3 })
            mob("nameplate5", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            local b = buttons()[1]
            assert.are.equal("macro", b:GetAttribute("type1"))
            assert.are.equal("/target nameplate5\n/petattack", b:GetAttribute("macrotext1"))
            WowMock.units.pet = nil -- the pet is dismissed
            ns.Meter_Update()
            assert.are.equal("target", b:GetAttribute("type1"))
            assert.is_nil(b:GetAttribute("macrotext1"))
        end)

        it("a pet called in the middle of a fight changes nothing until it ends", function()
            start({ locked = true, enemyRows = 3 })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            enterCombat()
            WowMock.AddUnit("pet", "Porky", "HUNTER", "NONE", { pet = true })
            assert.has_no.errors(function() ns.Meter_Update() end)
            assert.are.equal("target", buttons()[1]:GetAttribute("type1"))
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.are.equal("macro", buttons()[1]:GetAttribute("type1"))
        end)

        it("the tooltip names the mob and says what a click does", function()
            start({ locked = true })
            mob("nameplate1", "Wolf", WowMock.units.player)
            ns.Meter_Update()
            local lines = {}
            GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
            buttons()[1]._scripts.OnEnter(buttons()[1])
            assert.are.same({ "Click: target this enemy" }, lines)
        end)
    end)
end)
