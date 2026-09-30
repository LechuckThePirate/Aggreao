dofile("setupTests.lua")

describe("Aggreao (startup)", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    it("loads every TOC file", function()
        assert.is_not_nil(ns.L)
        assert.are.equal("function", type(ns.InitSettings))
        assert.are.equal("function", type(ns.Print))
    end)

    it("on entering, sets up the saved variables and announces in chat", function()
        StartAddon(ns)
        assert.is_not_nil(AggreaoDB)
        assert.is_not_nil(AggreaoCharDB)
        assert.matches("initializing", WowMock.printed[1])
        assert.matches("initialization complete", WowMock.printed[2])
    end)

    it("with messages turned off, writes nothing to chat", function()
        StartAddon(ns, nil, { quiet = true })
        assert.are.equal(0, #WowMock.printed)
    end)

    it("ignores other addons' ADDON_LOADED", function()
        _G.AggreaoDB, _G.AggreaoCharDB = nil, nil
        FireEvent("ADDON_LOADED", "SomethingElse")
        assert.is_nil(AggreaoDB)
        assert.are.equal(0, #WowMock.printed)
    end)

    it("registers /aggreao and /agg", function()
        assert.are.equal("/aggreao", SLASH_AGGREAO1)
        assert.are.equal("/agg", SLASH_AGGREAO2)
        assert.are.equal("function", type(SlashCmdList.AGGREAO))
    end)

    it("/aggreao version prints the TOC version, anything else the usage", function()
        SlashCmdList.AGGREAO("version")
        assert.matches("v0%.0%.0%-test", WowMock.printed[1])
        SlashCmdList.AGGREAO("nonsense")
        assert.matches("Usage", WowMock.printed[2])
    end)
end)
