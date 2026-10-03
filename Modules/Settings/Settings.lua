local _, ns = ...

-- Settings per character or for the whole account, as in Embolsao and Completao ("Character specific
-- preferences"). The SWITCHABLE keys are read from and written to the active store: the character's
-- (AggreaoCharDB) or the account's shared one (AggreaoDB.shared). The rest of ns.char always belongs to the
-- character. The rest of the addon uses ns.char without knowing which one is behind it, and reads a key
-- that was never set as its default (DEFAULTS), so a checkbox can store a plain true / false.
ns.DEFAULTS = {
    enabled = true,        -- show the aggro window
    locked = false,        -- window can't be dragged
    hideOutOfCombat = false, -- hide the window when you are not in combat
    rows = 5,              -- players listed
    scale = 1,
    opacity = 0.7,         -- window background
    showRoles = true,      -- tank / healer / dps icon
    pets = true,           -- list pets too (they can hold aggro)
    otherMobs = false,     -- under the list, one line per other mob in combat: who has its aggro
    alertSound = true,     -- sound when you are close to taking the aggro
    alertFlash = true,     -- red window border when you are close to taking the aggro
    alertThreshold = 80,   -- % of the tank's threat from which "close" starts
    alertSoundKey = "raid",
}

local SWITCHABLE = {
    quiet = true, minimap = true, window = true,
    enabled = true, locked = true, hideOutOfCombat = true, rows = true, scale = true, opacity = true, showRoles = true, pets = true,
    otherMobs = true,
    alertSound = true, alertFlash = true, alertThreshold = true, alertSoundKey = true,
}

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy(v) end
    return copy
end

local function activeStore()
    return AggreaoCharDB.perCharacter and AggreaoCharDB or AggreaoDB.shared
end

-- On load (ADDON_LOADED): prepares the saved variables and ns.db / ns.char.
function ns.InitSettings()
    AggreaoDB = AggreaoDB or {}
    AggreaoCharDB = AggreaoCharDB or {}
    ns.db = AggreaoDB
    -- version the welcome window's "Don't show this again" was ticked for; account-wide
    AggreaoDB.welcomeDismissedVersion = AggreaoDB.welcomeDismissedVersion or ""
    -- the first time, the shared settings come from the character that first uses them
    if not AggreaoDB.shared then
        AggreaoDB.shared = {}
        for key in pairs(SWITCHABLE) do AggreaoDB.shared[key] = deepCopy(AggreaoCharDB[key]) end
    end
    -- per character by default; a new one starts with a copy of the shared ones
    if AggreaoCharDB.perCharacter == nil then
        for key in pairs(SWITCHABLE) do
            if AggreaoCharDB[key] == nil then AggreaoCharDB[key] = deepCopy(AggreaoDB.shared[key]) end
        end
        AggreaoCharDB.perCharacter = true
    end
    ns.char = setmetatable({}, {
        __index = function(_, key)
            local value
            if SWITCHABLE[key] then value = activeStore()[key] else value = AggreaoCharDB[key] end
            if value == nil then return ns.DEFAULTS[key] end
            return value
        end,
        __newindex = function(_, key, value)
            if SWITCHABLE[key] then activeStore()[key] = value else AggreaoCharDB[key] = value end
        end,
    })
end

function ns.IsPerCharacter()
    return AggreaoCharDB.perCharacter and true or false
end

-- Switching to per character copies the shared settings, so the change isn't noticed; switching back to
-- shared leaves the character's copy saved, unused. Then whatever is in the new store is applied.
function ns.SetPerCharacter(enabled)
    enabled = enabled and true or false
    if enabled == ns.IsPerCharacter() then return end
    if enabled then
        for key in pairs(SWITCHABLE) do AggreaoCharDB[key] = deepCopy(AggreaoDB.shared[key]) end
    end
    AggreaoCharDB.perCharacter = enabled
    if ns.Minimap_Init then ns.Minimap_Init() end
    if ns.Meter_ApplySettings then ns.Meter_ApplySettings() end
end
