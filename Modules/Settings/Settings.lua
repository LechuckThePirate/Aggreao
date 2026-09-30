local _, ns = ...

-- Saved variables: AggreaoDB is shared by the whole account, AggreaoCharDB belongs to the character.
-- The rest of the addon reads ns.db / ns.char without knowing where they live.

-- On load (ADDON_LOADED): prepares the saved variables and ns.db / ns.char.
function ns.InitSettings()
    AggreaoDB = AggreaoDB or {}
    AggreaoCharDB = AggreaoCharDB or {}
    ns.db = AggreaoDB
    ns.char = AggreaoCharDB
end
