dofile("setupTests.lua")

describe("Threat", function()
    local ns

    -- a three-player party facing a hostile target; threat = { isTanking, status, scaledPct, rawPct, value }
    local function party()
        WowMock.group = { size = 3 }
        WowMock.AddUnit("player", "Me", "MAGE", "DAMAGER")
        WowMock.AddUnit("party1", "Tank", "WARRIOR", "TANK")
        WowMock.AddUnit("party2", "Healer", "PRIEST", "HEALER")
        WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
    end

    before_each(function()
        dofile("test/WowApiMock.lua") -- some tests remove API functions: start from a complete game
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Threat/Threat.lua" } })
    end)

    describe("Threat_Units", function()
        it("solo: the player, and the pet if asked", function()
            local list = ns.Threat_Units(true)
            assert.are.equal("player", list[1].unit)
            assert.are.equal("pet", list[2].unit)
            assert.are.equal("player", list[2].owner)
            assert.are.equal(1, #ns.Threat_Units(false))
        end)

        it("in a party: the player and party1..n-1 (the count includes the player)", function()
            WowMock.group = { size = 3 }
            local units = {}
            for _, e in ipairs(ns.Threat_Units(false)) do units[#units + 1] = e.unit end
            assert.are.same({ "player", "party1", "party2" }, units)
        end)

        it("in a raid: raid1..n, with their pets", function()
            WowMock.group = { size = 2, raid = true }
            local units = {}
            for _, e in ipairs(ns.Threat_Units(true)) do units[#units + 1] = e.unit end
            assert.are.same({ "raid1", "raidpet1", "raid2", "raidpet2" }, units)
        end)
    end)

    describe("Threat_Role", function()
        it("uses the assigned role", function()
            WowMock.AddUnit("party1", "Tank", "WARRIOR", "TANK")
            assert.are.equal("TANK", ns.Threat_Role("party1", "WARRIOR"))
        end)

        it("without one, guesses only for classes that can't do anything else", function()
            WowMock.AddUnit("party1", "A", "MAGE", "NONE")
            WowMock.AddUnit("party2", "B", "PRIEST", "NONE")
            assert.are.equal("DAMAGER", ns.Threat_Role("party1", "MAGE"))
            assert.is_nil(ns.Threat_Role("party2", "PRIEST"))
        end)

        it("clients without role API: guesses by class", function()
            _G.UnitGroupRolesAssigned = nil
            assert.are.equal("DAMAGER", ns.Threat_Role("party1", "ROGUE"))
            assert.is_nil(ns.Threat_Role("party1", "WARRIOR"))
        end)

        it("the player's own spec role on clients that have it", function()
            WowMock.AddUnit("player", "Me", "PRIEST", "NONE")
            _G.GetSpecialization = function() return 2 end
            _G.GetSpecializationRole = function() return "HEALER" end
            assert.are.equal("HEALER", ns.Threat_Role("player", "PRIEST"))
            _G.GetSpecialization, _G.GetSpecializationRole = nil, nil
        end)
    end)

    describe("Threat_Collect", function()
        it("lists who has threat, the tank first and then by threat", function()
            party()
            WowMock.threat.player = { false, 1, 85, 70, 5000 }
            WowMock.threat.party1 = { true, 3, 100, 100, 6000 }
            WowMock.threat.party2 = { false, 0, 20, 15, 1000 }
            local list = ns.Threat_Collect("target", false)
            assert.are.equal(3, #list)
            assert.are.equal("Tank", list[1].name)
            assert.is_true(list[1].tanking)
            assert.are.equal("Me", list[2].name)
            assert.are.equal(85, list[2].pct)
            assert.is_true(list[2].isMe)
            assert.are.equal("Healer", list[3].name)
            assert.are.equal("TANK", list[1].role)
            assert.are.equal("WARRIOR", list[1].class)
        end)

        it("a taunted tank with less threat than the others is still first", function()
            party()
            WowMock.threat.player = { false, 1, 90, 90, 9000 }
            WowMock.threat.party1 = { true, 3, 100, 100, 100 }
            local list = ns.Threat_Collect("target", false)
            assert.are.equal("Tank", list[1].name)
            assert.are.equal("Me", list[2].name)
        end)

        it("leaves out units with no threat", function()
            party()
            WowMock.threat.party1 = { true, 3, 100, 100, 6000 }
            WowMock.threat.party2 = { false, 0, 0, 0, 0 }
            local list = ns.Threat_Collect("target", false)
            assert.are.equal(1, #list)
        end)

        it("pets are listed with the owner's class and no role", function()
            party()
            WowMock.AddUnit("pet", "Wolf", "HUNTER", "NONE")
            WowMock.group = nil
            WowMock.threat.pet = { true, 3, 100, 100, 100 }
            local list = ns.Threat_Collect("target", true)
            assert.are.equal("Wolf", list[1].name)
            assert.is_true(list[1].isPet)
            assert.is_false(list[1].isMe)
            assert.are.equal("MAGE", list[1].class) -- the owner's (the player's)
            assert.is_nil(list[1].role)
        end)

        it("in a raid, the player is recognized under their raid unit", function()
            WowMock.group = { size = 2, raid = true }
            local me = WowMock.AddUnit("raid1", "Me", "MAGE", "DAMAGER")
            WowMock.units.player = me
            WowMock.AddUnit("raid2", "Tank", "WARRIOR", "TANK")
            WowMock.threat.raid1 = { false, 1, 50, 40, 400 }
            WowMock.threat.raid2 = { true, 3, 100, 100, 800 }
            local list = ns.Threat_Collect("target", false)
            assert.is_false(list[1].isMe)
            assert.is_true(list[2].isMe)
        end)

        it("without the threat API, the mob's target is listed as the one with the aggro", function()
            party()
            _G.UnitDetailedThreatSituation = nil
            WowMock.units.targettarget = WowMock.units.party1
            local list = ns.Threat_Collect("target", false)
            assert.are.equal(1, #list)
            assert.are.equal("Tank", list[1].name)
            assert.is_true(list[1].tanking)
            assert.are.equal(100, list[1].pct)
        end)

        it("when the API says nothing, falls back to the mob's target too", function()
            party()
            WowMock.units.targettarget = WowMock.units.player
            local list = ns.Threat_Collect("target", false)
            assert.are.equal(1, #list)
            assert.is_true(list[1].isMe)
            assert.is_true(list[1].tanking)
        end)

        it("the mob's target already listed without tanking is marked as the tank, not duplicated", function()
            party()
            WowMock.threat.party2 = { false, 1, 60, 60, 600 }
            WowMock.units.targettarget = WowMock.units.party2
            local list = ns.Threat_Collect("target", false)
            assert.are.equal(1, #list)
            assert.is_true(list[1].tanking)
            assert.are.equal(100, list[1].pct)
        end)

        it("ignores secret values it can't read", function()
            party()
            _G.issecretvalue = function(v) return v == 777 end
            WowMock.threat.party1 = { true, 3, 777, 777, 777 }
            WowMock.threat.party2 = { false, 1, 30, 30, 300 }
            WowMock.units.targettarget = WowMock.units.party1
            local list = ns.Threat_Collect("target", false)
            assert.are.equal("Tank", list[1].name) -- from the mob's target
            assert.are.equal("Healer", list[2].name)
            _G.issecretvalue = nil
        end)

        it("no mob target and no threat: empty", function()
            party()
            assert.are.same({}, ns.Threat_Collect("target", false))
        end)
    end)

    describe("Threat_Self", function()
        it("only the player's entry: percentage, whether tanking, role", function()
            party()
            WowMock.threat.player = { false, 1, 85, 70, 5000 }
            local me = ns.Threat_Self("target")
            assert.is_true(me.isMe)
            assert.is_false(me.tanking)
            assert.are.equal(85, me.pct)
            assert.are.equal("DAMAGER", me.role)
        end)

        it("tanking is 100 % even if the client gives no percentage", function()
            party()
            WowMock.threat.player = { true, 3, nil, nil, 5000 }
            local me = ns.Threat_Self("target")
            assert.is_true(me.tanking)
            assert.are.equal(100, me.pct)
        end)

        it("nil with no threat data, with secret values, or without the API", function()
            party()
            assert.is_nil(ns.Threat_Self("target"))
            _G.issecretvalue = function() return true end
            WowMock.threat.player = { false, 1, 85, 70, 5000 }
            assert.is_nil(ns.Threat_Self("target"))
            _G.issecretvalue = nil
            _G.UnitDetailedThreatSituation = nil
            assert.is_nil(ns.Threat_Self("target"))
        end)
    end)

    describe("Threat_Top", function()
        local function entries(n, meAt)
            local list = {}
            for i = 1, n do list[i] = { name = "P" .. i, pct = 100 - i, isMe = (i == meAt) } end
            return list
        end

        it("returns the list itself if it fits", function()
            local list = entries(3)
            assert.are.equal(list, ns.Threat_Top(list, 5))
        end)

        it("cuts to the first rows", function()
            local top = ns.Threat_Top(entries(8), 5)
            assert.are.equal(5, #top)
            assert.are.equal("P5", top[5].name)
        end)

        it("the player's row replaces the last one when they are further down", function()
            local top = ns.Threat_Top(entries(8, 7), 5)
            assert.are.equal(5, #top)
            assert.are.equal("P4", top[4].name)
            assert.are.equal("P7", top[5].name)
        end)
    end)

    describe("Threat_Mobs", function()
        local function mob(token, name, guid, extra)
            local e = { hostile = true, npc = true, inCombat = true, guid = guid }
            for k, v in pairs(extra or {}) do e[k] = v end
            return WowMock.AddUnit(token, name, "WARRIOR", nil, e)
        end

        before_each(function()
            WowMock.group = { size = 3 }
            WowMock.AddUnit("player", "Me", "MAGE", "DAMAGER")
            WowMock.AddUnit("party1", "Tank", "WARRIOR", "TANK")
        end)

        it("lists the hostile mobs in combat that the game lets us reach", function()
            mob("nameplate1", "Wolf", "G1")
            mob("nameplate2", "Boar", "G2")
            mob("boss1", "King", "G3")
            local names = {}
            for _, e in ipairs(ns.Threat_Mobs(10)) do names[#names + 1] = e.mob end
            table.sort(names)
            assert.are.same({ "Boar", "King", "Wolf" }, names)
        end)

        it("leaves out mobs that are not in combat, dead, friendly, or your target", function()
            mob("nameplate1", "Idle", "G1", { inCombat = false })
            mob("nameplate2", "Dead", "G2", { dead = true })
            mob("nameplate3", "Friend", "G3", { hostile = false })
            WowMock.units.target = mob("nameplate4", "Target", "G4") -- your target is also a nameplate
            mob("nameplate5", "Other", "G5")
            local list = ns.Threat_Mobs(10, true)
            assert.are.equal(1, #list)
            assert.are.equal("Other", list[1].mob)
        end)

        it("counts a mob once even if it is a nameplate and also your focus", function()
            WowMock.units.focus = mob("nameplate1", "Wolf", "G1") -- the same unit under two tokens
            assert.are.equal(1, #ns.Threat_Mobs(10))
        end)

        it("says whom each mob is attacking, with the class for players", function()
            mob("nameplate1", "Wolf", "G1")
            WowMock.units.nameplate1target = WowMock.units.party1
            local e = ns.Threat_Mobs(10)[1]
            assert.are.equal("Tank", e.who)
            assert.are.equal("WARRIOR", e.class)
            assert.is_false(e.isMe)
            assert.is_false(e.isPet)
        end)

        it("tells the role of whom it attacks: a tank is a TANK, a pet has none", function()
            mob("nameplate1", "Wolf", "G1")
            WowMock.units.nameplate1target = WowMock.units.party1 -- the group's tank
            assert.are.equal("TANK", ns.Threat_Mobs(10)[1].role)
            WowMock.units.nameplate1target = WowMock.AddUnit("pet", "Porky", "HUNTER", "NONE", { pet = true })
            assert.is_nil(ns.Threat_Mobs(10)[1].role)
        end)

        it("a mob attacking your pet: the pet, with no class", function()
            mob("nameplate1", "Wolf", "G1")
            WowMock.units.nameplate1target = WowMock.AddUnit("pet", "Porky", "HUNTER", "NONE", { pet = true })
            local e = ns.Threat_Mobs(10)[1]
            assert.are.equal("Porky", e.who)
            assert.is_true(e.isPet)
            assert.is_nil(e.class)
        end)

        it("a mob with no target has nobody to show", function()
            mob("nameplate1", "Wolf", "G1")
            local e = ns.Threat_Mobs(10)[1]
            assert.is_nil(e.who)
            assert.is_false(e.isMe)
        end)

        it("your own threat on each mob, where the client has it; 100 % if it attacks you", function()
            mob("nameplate1", "Wolf", "G1")
            mob("nameplate2", "Boar", "G2")
            WowMock.units.nameplate1target = WowMock.units.party1
            WowMock.units.nameplate2target = WowMock.units.player
            WowMock.threat["player@nameplate1"] = { false, 1, 64, 50, 500 }
            local byName = {}
            for _, e in ipairs(ns.Threat_Mobs(10)) do byName[e.mob] = e end
            assert.are.equal(64, byName.Wolf.pct)
            assert.is_true(byName.Boar.isMe)
            assert.are.equal(100, byName.Boar.pct)
        end)

        it("without the threat API it still says whom they attack, with no percentage", function()
            mob("nameplate1", "Wolf", "G1")
            WowMock.units.nameplate1target = WowMock.units.party1
            _G.UnitDetailedThreatSituation = nil
            local e = ns.Threat_Mobs(10)[1]
            assert.are.equal("Tank", e.who)
            assert.is_nil(e.pct)
        end)

        it("the ones attacking you first, then by your threat, and at most max", function()
            mob("nameplate1", "A", "G1")
            mob("nameplate2", "B", "G2")
            mob("nameplate3", "C", "G3")
            mob("nameplate4", "D", "G4")
            WowMock.units.nameplate4target = WowMock.units.player
            WowMock.threat["player@nameplate1"] = { false, 1, 30, 30, 1 }
            WowMock.threat["player@nameplate2"] = { false, 1, 90, 90, 1 }
            local list = ns.Threat_Mobs(3)
            assert.are.equal(3, #list)
            assert.are.same({ "D", "B", "A" }, { list[1].mob, list[2].mob, list[3].mob })
        end)

        describe("hidden (secret) values of the newest clients (Retail, Forever)", function()
            local SECRET = "\0secret"
            before_each(function() _G.issecretvalue = function(v) return v == SECRET end end)
            after_each(function() _G.issecretvalue = nil end)

            it("a role and a class that are hidden give no role, instead of an error", function()
                WowMock.AddUnit("party2", SECRET, SECRET, SECRET)
                assert.is_nil(ns.Threat_Role("party2", SECRET))
            end)

            it("whom a mob attacks with a hidden name, class and role: the name is kept as it is, with no class or role", function()
                mob("nameplate1", "Wolf", "G1")
                WowMock.units.nameplate1target = WowMock.AddUnit("party2", SECRET, SECRET, SECRET)
                local e = ns.Threat_Mobs(10)[1]
                assert.are.equal(SECRET, e.who)
                assert.is_true(e.whoSecret)
                assert.is_nil(e.class)
                assert.is_nil(e.role)
            end)

            it("a hidden name of the mob itself is no problem for the sorting", function()
                mob("nameplate1", SECRET, "G1")
                mob("nameplate2", "Boar", "G2")
                mob("nameplate3", SECRET, "G3")
                local list = ns.Threat_Mobs(10)
                assert.are.equal(3, #list)
                assert.are.equal("Boar", list[3].mob) -- hidden names sort as "" (first); the order is only a tie-breaker
            end)

            it("a plain name is not marked as hidden", function()
                mob("nameplate1", "Wolf", "G1")
                WowMock.units.nameplate1target = WowMock.units.party1
                assert.is_false(ns.Threat_Mobs(10)[1].whoSecret)
            end)

            it("a group member with a hidden name and class is still listed, as ?", function()
                WowMock.units.party2 = nil
                WowMock.AddUnit("party2", SECRET, SECRET, SECRET)
                WowMock.group = { size = 3 }
                WowMock.AddUnit("target", "Boss", "WARRIOR", nil, { hostile = true })
                WowMock.threat.party2 = { true, 3, 100, 100, 6000 }
                local list = ns.Threat_Collect("target", false)
                assert.are.equal(1, #list)
                assert.are.equal("?", list[1].name)
                assert.is_nil(list[1].class)
                assert.is_nil(list[1].role)
            end)

            it("a hidden flag counts as false instead of breaking the condition", function()
                assert.is_false(ns.Yes(SECRET))
                assert.is_true(ns.Yes(true))
                assert.is_false(ns.Yes(nil))
                assert.is_nil(ns.Plain(SECRET))
                assert.are.equal("x", ns.Plain("x"))
            end)
        end)
    end)
end)
