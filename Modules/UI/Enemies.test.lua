dofile("setupTests.lua")

describe("Enemies", function()
    local ns, frame

    local function visibleRows()
        return WowMock.FindAll(function(f)
            return f._parent == frame and f._kind == "StatusBar" and f._shown
        end)
    end

    local function texts(row)
        local list = {}
        for _, f in ipairs(WowMock.frames) do
            if f._parent == row and f._kind == "FontString" then list[#list + 1] = f._text end
        end
        return list -- who, hp, name (the order they were created in)
    end

    local function names()
        local list = {}
        for i, row in ipairs(visibleRows()) do list[i] = texts(row)[3] end
        return list
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

    local function start(charDB, role)
        WowMock.group = { size = 3 }
        WowMock.AddUnit("player", "Me", "WARRIOR", role or "TANK")
        WowMock.AddUnit("party1", "Healer", "PRIEST", "HEALER")
        WowMock.AddUnit("party2", "Mage", "MAGE", "DAMAGER")
        WowMock.AddUnit("party3", "Tank2", "PALADIN", "TANK")
        StartAddon(ns, nil, charDB or { locked = true })
        frame = _G.AggreaoEnemiesFrame
    end

    local function strip(row)
        return WowMock.Find(function(f) return f._parent == row and f._kind == "Texture" and f._set.SetColorTexture
            and f._set.SetColorTexture[4] == 1 end)._set.SetColorTexture
    end

    before_each(function()
        dofile("test/WowApiMock.lua")
        WowMock.Reset()
        _G.AggreaoEnemiesFrame = nil
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

        it("the close button turns it off for good, in combat too", function()
            start({})
            enterCombat()
            frame.close:Click()
            assert.are.equal("never", ns.char.enemyListMode)
            assert.is_false(frame:IsShown())
        end)

        it("moves by its title bar, in combat too; locked it does not start a move", function()
            start({})
            enterCombat()
            local moved = false
            frame.StartMoving = function() moved = true end
            frame._scripts.OnDragStart(frame)
            assert.is_true(moved)
            ns.char.locked = true
            moved = false
            frame._scripts.OnDragStart(frame)
            assert.is_false(moved)
        end)

        it("dragging saves the top left corner, the point it is anchored by", function()
            start({})
            frame.GetLeft = function() return 40 end
            frame.GetTop = function() return 500 end
            frame._scripts.OnDragStop(frame)
            assert.are.same({ x = 40, y = 500 }, ns.char.enemyWindow)
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 500 }, frame._points[#frame._points])
        end)

        it("restores the saved position, scale and background opacity", function()
            start({ locked = true, scale = 1.2, opacity = 0.4, enemyWindow = { x = 100, y = 700 } })
            assert.are.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700 }, frame._points[#frame._points])
            assert.are.equal(1.2, frame:GetScale())
            assert.are.same({ 0, 0, 0, 0.4 }, frame._set.SetBackdropColor)
        end)

        it("has its own padlock, the aggro window's too: it unlocks both and shows the state", function()
            start({ locked = true })
            ns.Prefs_Toggle()
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
            frame.lock:Click()
            assert.is_false(ns.char.locked)
            assert.are.same({ "Interface\\Buttons\\LockButton-Unlocked-Up" }, frame.lock._set.SetNormalTexture)
            _G.AggreaoMeterFrame.lock:Click()
            assert.are.same({ "Interface\\Buttons\\LockButton-Locked-Up" }, frame.lock._set.SetNormalTexture)
        end)

        it("right-click opens the preferences", function()
            start()
            frame._scripts.OnMouseUp(frame, "RightButton")
            assert.is_true(ns.Prefs_IsShown())
        end)

        it("grows with the mobs, from its top left corner", function()
            start({ locked = true })
            enterCombat()
            local empty = frame:GetHeight()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.player)
            ns.Meter_Update()
            assert.are.equal(empty + 20, frame:GetHeight())
        end)
    end)

    describe("who gets it", function()
        it("by default a tank gets it", function()
            start({ locked = true }, "TANK")
            enterCombat()
            assert.is_true(frame:IsShown())
            assert.is_true(ns.Enemies_IsActive())
        end)

        it("by default a dps or a healer does not, and sees the other mobs in the aggro window instead", function()
            start({ locked = true }, "DAMAGER")
            enterCombat()
            assert.is_false(frame:IsShown())
            assert.is_false(ns.Enemies_IsActive())
            mob("nameplate1", "Wolf", WowMock.units.party1)
            ns.Meter_Update()
            assert.are.equal(1, #WowMock.FindAll(function(f)
                return f._parent == _G.AggreaoMeterFrame and f.mob ~= nil and f._shown
            end))
        end)

        it("by default it is shown when the game does not say what you are", function()
            WowMock.group = nil
            StartAddon(ns, nil, { locked = true }) -- alone: no role, and the class (mage) is no guess either
            _G.UnitClass = function() return nil, nil end
            ns.Meter_Update()
            assert.is_true(ns.Enemies_IsActive())
        end)

        it("'always' gives it to a dps too; 'never' takes it from a tank", function()
            start({ locked = true, enemyListMode = "always" }, "DAMAGER")
            assert.is_true(ns.Enemies_IsActive())
            ns.char.enemyListMode = "never"
            ns.Meter_Update()
            assert.is_false(ns.Enemies_IsActive())
        end)

        it("a role change takes effect at once", function()
            start({ locked = true }, "TANK")
            enterCombat()
            WowMock.units.player.role = "DAMAGER"
            ns.Meter_Update()
            assert.is_false(ns.Enemies_IsActive())
            assert.is_false(frame:IsShown())
        end)
    end)

    describe("rows", function()
        it("one per mob in combat: name, health and whom it attacks, with your threat on it", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.party1, 25)
            mob("nameplate2", "Boar", WowMock.units.player, 80)
            WowMock.threat["player@nameplate1"] = { false, 1, 64, 50, 500 }
            enterCombat()
            local rows = visibleRows()
            assert.are.equal(2, #rows)
            -- the one on the healer first: the tank has to take it back
            assert.are.same({ "Wolf", "25%" }, { texts(rows[1])[3], texts(rows[1])[2] })
            assert.matches("Healer", texts(rows[1])[1])
            assert.matches("64%%", texts(rows[1])[1])
            assert.are.same({ "Boar", "80%", "YOU" }, { texts(rows[2])[3], texts(rows[2])[2], texts(rows[2])[1] })
        end)

        it("the health bar is given the health as it is", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player, 30)
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
            WowMock.AddUnit("party4", SECRET, SECRET, SECRET)
            mob("nameplate1", "Wolf", WowMock.units.party4)
            enterCombat()
            local row = visibleRows()[1]
            assert.are.equal(SECRET, texts(row)[1])
            assert.are.same({ 1, 1, 1 }, WowMock.Find(function(f) return f._parent == row and f._set.SetTextColor and f._text == SECRET end)
                ._set.SetTextColor)
            _G.issecretvalue = nil
        end)

        it("the row of your current target is marked", function()
            start()
            mob("nameplate1", "Boar", WowMock.units.player)
            mob("nameplate2", "Wolf", WowMock.units.player)
            WowMock.units.target = WowMock.units.nameplate2
            enterCombat()
            local rows = visibleRows()
            local function selected(row)
                return WowMock.Find(function(f) return f._parent == row and f._kind == "Texture" and f._set.SetColorTexture
                    and f._set.SetColorTexture[4] == 0.18 end)
            end
            assert.is_false(selected(rows[1]):IsShown()) -- Boar
            assert.is_true(selected(rows[2]):IsShown()) -- Wolf
        end)

        it("a mob that is not fighting, or is dead, has no row; the rest follow it", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.player)
            mob("nameplate3", "Bat", WowMock.units.player)
            enterCombat()
            assert.are.equal(3, #visibleRows())
            WowMock.units.nameplate2.inCombat = false
            WowMock.units.nameplate3.dead = true
            ns.Meter_Update()
            assert.are.same({ "Wolf" }, names())
        end)

        it("a mob seen under two tokens (focus and a nameplate) is listed once", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            WowMock.units.focus = WowMock.units.nameplate1
            enterCombat()
            assert.are.equal(1, #visibleRows())
        end)

        it("only as many rows as asked for, the ones that need you first", function()
            start({ locked = true, enemyRows = 3 })
            for i = 1, 5 do mob("nameplate" .. i, "M" .. i, WowMock.units.player) end
            mob("nameplate6", "Loose", WowMock.units.party2)
            enterCombat()
            assert.are.equal(3, #visibleRows())
            assert.are.equal("Loose", names()[1])
        end)

        it("a tank: the mobs on a healer or a dps first, then on another tank, then on the tank; by name otherwise", function()
            start()
            mob("nameplate1", "Mine", WowMock.units.player)
            mob("nameplate2", "OnTank", WowMock.units.party3)
            mob("nameplate3", "OnHealer", WowMock.units.party1)
            mob("nameplate4", "OnMage", WowMock.units.party2)
            enterCombat()
            assert.are.same({ "OnHealer", "OnMage", "OnTank", "Mine" }, names())
        end)

        it("a dps: the mobs on them first", function()
            start({ locked = true, enemyListMode = "always" }, "DAMAGER")
            mob("nameplate1", "OnHealer", WowMock.units.party1)
            mob("nameplate2", "Mine", WowMock.units.player)
            enterCombat()
            assert.are.same({ "Mine", "OnHealer" }, names())
        end)

        it("the strip says your hold: green a tank that has it, red when it is on a healer; the other way for a dps", function()
            start()
            mob("nameplate1", "Wolf", WowMock.units.player)
            mob("nameplate2", "Boar", WowMock.units.party1)
            enterCombat()
            local rows = visibleRows()
            assert.are.same({ 1, 0.15, 0.15, 1 }, strip(rows[1])) -- Boar, on the healer
            assert.are.same({ 0.2, 0.8, 0.2, 1 }, strip(rows[2])) -- Wolf, on me
            WowMock.units.player.role = "DAMAGER"
            ns.char.enemyListMode = "always"
            ns.Meter_Update()
            rows = visibleRows()
            assert.are.same({ 1, 0.15, 0.15, 1 }, strip(rows[1])) -- dps, on me
            assert.are.same({ 0.2, 0.8, 0.2, 1 }, strip(rows[2])) -- dps, on somebody else
        end)

        it("another tank holding it is yellow; a mob nobody attacks is loose", function()
            start()
            mob("nameplate1", "Held", WowMock.units.party3)
            mob("nameplate2", "Free", nil)
            enterCombat()
            local byName = {}
            for _, row in ipairs(visibleRows()) do byName[texts(row)[3]] = strip(row) end
            assert.are.same({ 1, 0.85, 0.2, 1 }, byName.Held)
            assert.are.same({ 1, 0.15, 0.15, 1 }, byName.Free)
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

    describe("marks on the nameplates", function()
        local function plate(token)
            local p = WowMock.NewFrame("Frame", nil, UIParent)
            WowMock.plates[token] = p
            return p
        end

        local function markOf(p)
            return WowMock.Find(function(f) return f._parent == p and f.text ~= nil end)
        end

        it("a tank gets a red mark on the nameplate of each mob that is not on them, and none on the others", function()
            start()
            local loose, held = plate("nameplate1"), plate("nameplate2")
            mob("nameplate1", "Boar", WowMock.units.party1)
            mob("nameplate2", "Wolf", WowMock.units.player)
            enterCombat()
            assert.is_true(markOf(loose):IsShown())
            assert.are.equal("!", markOf(loose).text._text)
            assert.is_nil(markOf(held))
        end)

        it("also for the mobs that did not fit in the list", function()
            start({ locked = true, enemyRows = 3 })
            local plates = {}
            for i = 1, 6 do
                plates[i] = plate("nameplate" .. i)
                mob("nameplate" .. i, "M" .. i, WowMock.units.party1)
            end
            enterCombat()
            assert.are.equal(3, #visibleRows())
            assert.is_true(markOf(plates[6]):IsShown())
        end)

        it("the mark goes when the mob is on the tank again, and when the combat ends", function()
            start()
            local p = plate("nameplate1")
            mob("nameplate1", "Boar", WowMock.units.party1)
            enterCombat()
            assert.is_true(markOf(p):IsShown())
            WowMock.units.nameplate1target = WowMock.units.player
            ns.Meter_Update()
            assert.is_false(markOf(p):IsShown())
            WowMock.units.nameplate1target = WowMock.units.party1
            ns.Meter_Update()
            assert.is_true(markOf(p):IsShown())
            WowMock.inCombat = false
            FireEvent("PLAYER_REGEN_ENABLED")
            ns.Meter_Update()
            assert.is_false(markOf(p):IsShown())
        end)

        it("off in the settings, or not a tank: no marks", function()
            start({ locked = true, enemyMarks = false })
            local p = plate("nameplate1")
            mob("nameplate1", "Boar", WowMock.units.party1)
            enterCombat()
            assert.is_nil(markOf(p))
            ns.char.enemyMarks = true
            WowMock.units.player.role = "DAMAGER"
            ns.char.enemyListMode = "always"
            ns.Meter_Update()
            assert.is_nil(markOf(p))
        end)

        it("a mob without a nameplate, or a client without the nameplate API, is no problem", function()
            start()
            mob("nameplate1", "Boar", WowMock.units.party1)
            assert.has_no.errors(function() enterCombat() end)
            _G.C_NamePlate = nil
            assert.has_no.errors(function() ns.Meter_Update() end)
        end)
    end)
end)
