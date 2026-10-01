dofile("setupTests.lua")

describe("Welcome", function()
    local ns, welcome

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns, nil, { locked = true })
        welcome = _G.AggreaoWelcomeFrame
    end)

    it("shows once by itself, the first time (or after a version bump)", function()
        assert.is_not_nil(welcome)
        assert.is_true(welcome:IsShown())
    end)

    it("the issue tracker URL is there to copy", function()
        assert.are.equal("https://github.com/LechuckThePirate/Aggreao/issues", welcome.urlBox:GetText())
    end)

    it("mentions this is a beta, above the changelog", function()
        assert.matches("beta", welcome.body:GetText())
        local _, relTo = welcome.changelogLabel:GetPoint()
        assert.are.equal(welcome.urlBox, relTo)
    end)

    it("Don't show this again remembers the version, and clearing it forgets", function()
        local check = WowMock.Find(function(f) return f._kind == "CheckButton" and f._parent == welcome end)
        check:SetChecked(true); check:Click()
        assert.are.equal("0.0.0-test", AggreaoDB.welcomeDismissedVersion)
        check:SetChecked(false); check:Click()
        assert.are.equal("", AggreaoDB.welcomeDismissedVersion)
    end)

    it("does not show again once dismissed for this version, but does after a version bump", function()
        welcome:Hide()
        AggreaoDB.welcomeDismissedVersion = "0.0.0-test"
        local savedDB = AggreaoDB

        local ns2 = LoadAddon()
        StartAddon(ns2, savedDB, { locked = true })
        assert.is_false(_G.AggreaoWelcomeFrame:IsShown())

        savedDB.welcomeDismissedVersion = "0.0.0-old"
        local ns3 = LoadAddon()
        StartAddon(ns3, savedDB, { locked = true })
        assert.is_true(_G.AggreaoWelcomeFrame:IsShown())
    end)

    it("/aggreao changelog reopens it even if dismissed", function()
        welcome:Hide()
        AggreaoDB.welcomeDismissedVersion = "0.0.0-test"
        SlashCmdList.AGGREAO("changelog")
        assert.is_true(welcome:IsShown())
    end)
end)
