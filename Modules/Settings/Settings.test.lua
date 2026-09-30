dofile("setupTests.lua")

describe("Settings", function()
    local ns

    local function login(charDB, accountDB)
        _G.AggreaoDB, _G.AggreaoCharDB = accountDB, charDB
        ns = LoadAddon({ files = { "Modules/Settings/Settings.lua" } })
        ns.InitSettings()
        return ns
    end

    before_each(function() WowMock.Reset() end)

    it("creates the saved variables on the first login", function()
        login(nil, nil)
        assert.are.same({}, AggreaoDB)
        assert.are.same({}, AggreaoCharDB)
        assert.are.equal(AggreaoDB, ns.db)
        assert.are.equal(AggreaoCharDB, ns.char)
    end)

    it("keeps what was already saved", function()
        local account, char = { welcomed = true }, { quiet = true }
        login(char, account)
        assert.is_true(ns.db.welcomed)
        assert.is_true(ns.char.quiet)
    end)
end)
