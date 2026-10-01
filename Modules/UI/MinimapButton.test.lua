dofile("setupTests.lua")

describe("MinimapButton", function()
    local ns, button

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns, nil, { locked = true })
        button = _G.AggreaoMinimapButton
    end)

    it("is created on entering, visible and at its default angle", function()
        assert.is_not_nil(button)
        assert.is_true(button:IsShown())
        assert.are.equal(225, ns.char.minimap.angle)
    end)

    it("a click opens and closes the preferences", function()
        button:Click()
        assert.is_true(_G.AggreaoPreferencesFrame:IsShown())
        button:Click()
        assert.is_false(_G.AggreaoPreferencesFrame:IsShown())
    end)

    it("dragging it changes its angle around the minimap", function()
        WowMock.cursor = { 200, 100 } -- right of the center (100, 100)
        button._scripts.OnDragStart(button)
        button._scripts.OnUpdate(button)
        button._scripts.OnDragStop(button)
        assert.near(0, ns.char.minimap.angle, 0.001)
    end)

    it("/aggreao minimap hides and shows it again, and it is remembered", function()
        SlashCmdList.AGGREAO("minimap")
        assert.is_false(button:IsShown())
        assert.is_true(ns.char.minimap.hide)
        assert.matches("hidden", WowMock.printed[#WowMock.printed])
        SlashCmdList.AGGREAO("minimap")
        assert.is_true(button:IsShown())
    end)
end)
