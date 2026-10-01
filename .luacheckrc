-- luacheck: Lua 5.1, the game's version. Runs in CI; locally:
--   luacheck Aggreao.lua Localization Modules test setupTests.lua
std = "lua51"
max_line_length = 160
codes = true

exclude_files = {
    "tools/",
    ".github/",
    "images/",
}

-- what the addon defines as globals
globals = {
    "AggreaoDB", "AggreaoCharDB",
    "SlashCmdList", "SLASH_AGGREAO1", "SLASH_AGGREAO2",
}

-- the game's API and frames it uses
read_globals = {
    "C_AddOns", "C_Timer", "CLOSE", "CreateFrame", "GameTooltip", "GameTooltip_Hide", "GetAddOnMetadata",
    "GetCursorPosition", "GetLocale", "GetNumGroupMembers", "GetSpecialization", "GetSpecializationRole", "GetTime",
    "InCombatLockdown", "IsInGroup", "IsInRaid", "Minimap", "PlaySound", "RAID_CLASS_COLORS",
    "ScrollFrame_OnScrollRangeChanged", "UIParent", "UISpecialFrames", "UnitCanAttack", "UnitClass",
    "UnitDetailedThreatSituation", "UnitExists", "UnitGroupRolesAssigned", "UnitIsDead", "UnitIsUnit", "UnitName",
    "hooksecurefunc", "issecretvalue", "strtrim", "tinsert", "wipe",
}

-- tests (busted): they define and change the simulated game's globals on purpose
files["**/*.test.lua"] = { std = "+busted", globals = { "_G" }, allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["setupTests.lua"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["test/"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122", "131", "212" } }
