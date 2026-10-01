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
end)
