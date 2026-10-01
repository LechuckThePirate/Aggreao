dofile("setupTests.lua")

describe("Settings", function()
    local ns, applied

    local function login(charDB, accountDB)
        _G.AggreaoDB, _G.AggreaoCharDB = accountDB, charDB
        ns = LoadAddon({ files = { "Modules/Settings/Settings.lua" } })
        applied = 0
        ns.Minimap_Init = function() ns.char.minimap = ns.char.minimap or { angle = 225 } end
        ns.Meter_ApplySettings = function() applied = applied + 1 end
        ns.InitSettings()
        return ns
    end

    before_each(function() WowMock.Reset() end)

    it("creates the saved variables on the first login, per character", function()
        login(nil, nil)
        assert.is_not_nil(AggreaoDB)
        assert.is_not_nil(AggreaoCharDB)
        assert.are.equal(AggreaoDB, ns.db)
        assert.is_true(ns.IsPerCharacter())
    end)

    it("keeps what was already saved", function()
        local account, char = { welcomed = true }, { quiet = true }
        login(char, account)
        assert.is_true(ns.db.welcomed)
        assert.is_true(ns.char.quiet)
    end)

    it("a setting never touched reads as its default; false is kept", function()
        login({}, {})
        assert.are.equal(5, ns.char.rows)
        assert.is_true(ns.char.showRoles)
        ns.char.showRoles = false
        assert.is_false(ns.char.showRoles)
        assert.are.equal(80, ns.char.alertThreshold)
    end)

    it("the shared settings start with the first character's", function()
        local account = {}
        login({ rows = 8 }, account)
        assert.are.equal(8, account.shared.rows)
    end)

    it("per character, changes don't touch the shared ones", function()
        local char, account = { rows = 8 }, {}
        login(char, account)
        ns.char.rows = 3
        assert.are.equal(3, char.rows)
        assert.are.equal(8, account.shared.rows)
    end)

    it("switching to shared reads and writes the shared ones; the character's copy stays", function()
        local char, account = { rows = 3 }, {}
        login(char, account)
        account.shared.rows = 9
        ns.SetPerCharacter(false)
        assert.is_false(ns.IsPerCharacter())
        assert.are.equal(9, ns.char.rows)
        ns.char.rows = 7
        assert.are.equal(7, account.shared.rows)
        assert.are.equal(3, char.rows)
    end)

    it("switching back to per character copies the shared ones, and re-applies the settings", function()
        local char, account = {}, {}
        login(char, account)
        ns.SetPerCharacter(false)
        ns.char.rows = 6
        local before = applied
        ns.SetPerCharacter(true)
        assert.are.equal(6, char.rows)
        assert.are.equal(before + 1, applied)
        ns.SetPerCharacter(true) -- nothing changes
        assert.are.equal(before + 1, applied)
    end)

    it("keys outside the switchable ones always belong to the character", function()
        local char, account = {}, {}
        login(char, account)
        ns.SetPerCharacter(false)
        ns.char.somethingElse = 1
        assert.are.equal(1, char.somethingElse)
        assert.is_nil(account.shared.somethingElse)
    end)
end)
