dofile("setupTests.lua")

describe("Welcome", function()
    local ns, welcome

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns, nil, { locked = true })
        welcome = _G.AggreaoWelcomeFrame
    end)

    it("is opaque: the welcome window of another addon behind it does not show through", function()
        assert.matches("ChatFrameBackground", welcome._set.SetBackdrop[1].bgFile)
        assert.are.equal(1, welcome._set.SetBackdropColor[4])
    end)
    
    it("shows once by itself, the first time (or after a version bump)", function()
        assert.is_not_nil(welcome)
        assert.is_true(welcome:IsShown())
    end)

    it("the issue tracker URL is there to copy", function()
        assert.are.equal("https://github.com/LechuckThePirate/Aggreao/issues", welcome.urlBox:GetText())
    end)

    it("says where to report bugs and ideas, above the changelog", function()
        assert.matches("GitHub", welcome.body:GetText())
        assert.is_nil(welcome.body:GetText():find("beta"))
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

    describe("the other addons", function()
        local siblings = { "Embolsao", "Completao", "Aggreao", "Fabrikao" }

        it("have a link each, to copy, and not one to itself", function()
            local urls = {}
            for _, box in ipairs(welcome.siblingBoxes) do urls[#urls + 1] = box:GetText() end
            assert.are.equal(3, #urls)
            local all = table.concat(urls, " ")
            for _, name in ipairs(siblings) do
                if name == "Aggreao" then
                    assert.is_nil(all:find(name:lower(), 1, true))
                else
                    assert.is_truthy(all:find(name:lower(), 1, true) or all:find("1733457", 1, true), name)
                end
            end
        end)

        it("are CurseForge pages", function()
            for _, box in ipairs(welcome.siblingBoxes) do
                assert.matches("^https://www%.curseforge%.com/", box:GetText())
            end
        end)

        it("have a label above them, and the changelog stops above that", function()
            assert.matches("More addons by the same author", welcome.siblingsLabel:GetText())
        end)

        it("select their link when clicked, so it can be copied", function()
            local box = welcome.siblingBoxes[1]
            local highlighted = false
            box.HighlightText = function() highlighted = true end
            box._scripts.OnEditFocusGained(box)
            assert.is_true(highlighted)
        end)
    end)
end)
