dofile("setupTests.lua")

describe("Alert", function()
    local ns

    local function me(pct, extra)
        local e = { isMe = true, pct = pct, tanking = false, role = "DAMAGER" }
        for k, v in pairs(extra or {}) do e[k] = v end
        return { { name = "Tank", tanking = true, pct = 100 }, e }
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Settings/Settings.lua", "Modules/Alert/Alert.lua" } })
        _G.AggreaoDB, _G.AggreaoCharDB = {}, {}
        ns.InitSettings()
    end)

    it("below the threshold: no sound, not near", function()
        assert.is_false(ns.Alert_Check(me(79)))
        assert.are.equal(0, #WowMock.sounds)
    end)

    it("from the threshold up (80 % by default): near, and it sounds once", function()
        assert.is_true(ns.Alert_Check(me(80)))
        assert.are.equal(1, #WowMock.sounds)
        assert.is_true(ns.Alert_Check(me(95)))
        assert.are.equal(1, #WowMock.sounds)
    end)

    it("plays the chosen sound on the Master channel", function()
        ns.char.alertSoundKey = "alarm"
        ns.Alert_Check(me(90))
        assert.are.same({ 12867, "Master" }, WowMock.sounds[1])
    end)

    it("sounds again after dropping well below the threshold (and the minimum gap)", function()
        ns.Alert_Check(me(90))
        ns.Alert_Check(me(75)) -- under the threshold but within the margin: still disarmed
        WowMock.time = 10
        ns.Alert_Check(me(90))
        assert.are.equal(1, #WowMock.sounds)
        ns.Alert_Check(me(60)) -- 10 points below: armed again
        ns.Alert_Check(me(90))
        assert.are.equal(2, #WowMock.sounds)
    end)

    it("doesn't sound twice within the minimum gap", function()
        ns.Alert_Check(me(90))
        ns.Alert_Check(me(10))
        WowMock.time = 1
        ns.Alert_Check(me(90))
        assert.are.equal(1, #WowMock.sounds)
        WowMock.time = 3
        ns.Alert_Check(me(10))
        ns.Alert_Check(me(90))
        assert.are.equal(2, #WowMock.sounds)
    end)

    it("a target change (Alert_Reset) re-arms it", function()
        ns.Alert_Check(me(90))
        ns.Alert_Reset()
        WowMock.time = 5
        ns.Alert_Check(me(90))
        assert.are.equal(2, #WowMock.sounds)
    end)

    it("with the sound off it is still near, but silent", function()
        ns.char.alertSound = false
        assert.is_true(ns.Alert_Check(me(90)))
        assert.are.equal(0, #WowMock.sounds)
    end)

    it("the threshold is a setting", function()
        ns.char.alertThreshold = 50
        assert.is_true(ns.Alert_Check(me(55)))
    end)

    it("nothing to warn when you already have the aggro, or are not in the list", function()
        assert.is_false(ns.Alert_Check(me(100, { tanking = true })))
        assert.is_false(ns.Alert_Check({ { name = "Tank", tanking = true, pct = 100 } }))
        assert.are.equal(0, #WowMock.sounds)
    end)

    it("a tank who doesn't hold it is trying to get it: no alert", function()
        assert.is_false(ns.Alert_Check(me(90, { role = "TANK" })))
        assert.are.equal(0, #WowMock.sounds)
    end)

    it("Alert_Play without a key plays the saved one; an unknown key plays the first", function()
        ns.Alert_Play()
        assert.are.equal(8959, WowMock.sounds[1][1])
        ns.Alert_Play("nonsense")
        assert.are.equal(8959, WowMock.sounds[2][1])
        assert.are.equal("Ready check", ns.Alert_SoundName("ready"))
        assert.are.equal("Raid warning", ns.Alert_SoundName("nonsense"))
    end)
    describe("taking the aggro from someone else", function()
        it("sounds when you take it in one jump, without passing through the warning zone", function()
            ns.Alert_Check(me(40))
            assert.are.equal(0, #WowMock.sounds)
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(1, #WowMock.sounds)
        end)

        it("does not sound a second time if it had already warned you in this approach", function()
            ns.Alert_Check(me(85))
            assert.are.equal(1, #WowMock.sounds)
            WowMock.time = 10
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(1, #WowMock.sounds)
        end)

        it("does not sound when you held the aggro from the start (you pulled it)", function()
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(0, #WowMock.sounds)
        end)

        it("sounds when your pet holds it and then you do, even if you were not in the list", function()
            ns.Alert_Check({ { name = "Pet", tanking = true, pct = 100 } }) -- you have no threat yet
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(1, #WowMock.sounds)
        end)

        it("a tank taking it is not an alert", function()
            ns.Alert_Check(me(40, { role = "TANK" }))
            ns.Alert_Check(me(100, { tanking = true, role = "TANK" }))
            assert.are.equal(0, #WowMock.sounds)
        end)

        it("with the sound off it does not sound", function()
            ns.char.alertSound = false
            ns.Alert_Check(me(40))
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(0, #WowMock.sounds)
        end)

        it("a new target starts clean", function()
            ns.Alert_Check(me(100, { tanking = true }))
            ns.Alert_Reset()
            ns.Alert_Check(me(40))
            WowMock.time = 10
            ns.Alert_Check(me(100, { tanking = true }))
            assert.are.equal(1, #WowMock.sounds)
        end)
    end)

    describe("the pet takes the aggro back", function()
        it("does not sound while you are still high, as if you were about to pull", function()
            ns.Alert_Check(me(40))
            ns.Alert_Check(me(100, { tanking = true })) -- you took it: it sounded
            assert.are.equal(1, #WowMock.sounds)
            WowMock.time = 10
            ns.Alert_Check(me(95)) -- the pet growls: you are at 95 % and no longer hold it
            ns.Alert_Check(me(92))
            assert.are.equal(1, #WowMock.sounds)
        end)

        it("it warns again once your threat has dropped well below the threshold and climbs back", function()
            ns.Alert_Check(me(40))
            ns.Alert_Check(me(100, { tanking = true }))
            WowMock.time = 10
            ns.Alert_Check(me(95))
            ns.Alert_Check(me(50)) -- far below: re-armed
            WowMock.time = 20
            ns.Alert_Check(me(85))
            assert.are.equal(2, #WowMock.sounds)
        end)
    end)
end)
