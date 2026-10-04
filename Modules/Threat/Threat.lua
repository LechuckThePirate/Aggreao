local _, ns = ...

-- Threat list of a mob: who has its aggro and how close the others are. Works on every client:
--  * UnitDetailedThreatSituation(unit, mob) gives each unit's threat where the client has it (Retail, TBC,
--    Classic "Forever"; Classic Era as far as the client fills it in).
--  * Where it gives nothing (missing API, nothing returned, or "secret" values the addon can't read), the
--    mob's own target is listed as the one with the aggro, at 100 %, so the window still says who has it.

local ONE_ROLE = { MAGE = "DAMAGER", ROGUE = "DAMAGER", HUNTER = "DAMAGER", WARLOCK = "DAMAGER" }

local function readable(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- The newest clients (Retail 12.x and WoW Forever) hide ("secret") some values the game gives about units in combat -- the role, the class, the name
-- of an enemy's target... A secret can't be compared, joined to text, used as a table key or tested as a
-- condition (that is an error), only handed to the interface (SetText...). So everything that comes from a unit
-- goes through these before the addon does anything else with it:
--  * plain(v): v, or nil if it is secret;
--  * yes(v):   a game flag as a plain boolean (a secret one counts as false).
local function plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
local function yes(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value and true or false
end
ns.Plain, ns.Yes = plain, yes

-- Role of a unit: the one assigned in the group (Retail, TBC) or chosen as spec (the player on Retail);
-- otherwise guessed only for classes that can't do anything else. nil = unknown (no icon).
function ns.Threat_Role(unit, classFile)
    classFile = plain(classFile)
    if UnitGroupRolesAssigned then
        local role = plain(UnitGroupRolesAssigned(unit))
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
    if GetSpecialization and GetSpecializationRole and yes(UnitIsUnit(unit, "player")) then
        local spec = GetSpecialization()
        local role = spec and plain(GetSpecializationRole(spec))
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
    if classFile == nil then return nil end
    return ONE_ROLE[classFile]
end

-- Everybody who can hold aggro: the player, the group (party or raid) and, if asked, their pets.
-- { { unit = , owner = unit of the owner for a pet } }
function ns.Threat_Units(includePets)
    local list = {}
    local function add(unit, owner) list[#list + 1] = { unit = unit, owner = owner } end
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            add("raid" .. i)
            if includePets then add("raidpet" .. i, "raid" .. i) end
        end
    else
        add("player")
        if includePets then add("pet", "player") end
        if IsInGroup and IsInGroup() then
            for i = 1, GetNumGroupMembers() - 1 do
                add("party" .. i)
                if includePets then add("partypet" .. i, "party" .. i) end
            end
        end
    end
    return list
end

local function entryFor(unit, owner, isTanking, pct, value)
    local classUnit = owner or unit
    local classFile = plain(select(2, UnitClass(classUnit)))
    local name = plain(UnitName(unit))
    if type(name) ~= "string" then name = "?" end
    return {
        unit = unit,
        name = name,
        class = classFile,
        isPet = owner ~= nil,
        isMe = (not owner) and yes(UnitIsUnit(unit, "player")),
        role = (not owner) and ns.Threat_Role(unit, classFile) or nil,
        tanking = isTanking and true or false,
        pct = pct or 0,
        value = value or 0,
    }
end

-- Who has the aggro first, then the rest by threat (highest first).
local function byThreat(a, b)
    if a.tanking ~= b.tanking then return a.tanking end
    if a.value ~= b.value then return a.value > b.value end
    if a.pct ~= b.pct then return a.pct > b.pct end
    return a.name < b.name
end

-- list of entries { unit, name, class, isPet, isMe, role, tanking, pct (100 = pulls the aggro), value },
-- sorted by byThreat, for the mob unit (normally "target").
function ns.Threat_Collect(mob, includePets)
    local list, hasTank = {}, false
    local units = ns.Threat_Units(includePets)
    if UnitDetailedThreatSituation then
        for _, u in ipairs(units) do
            if yes(UnitExists(u.unit)) then
                local isTanking, _, scaled, raw, value = UnitDetailedThreatSituation(u.unit, mob)
                if readable(scaled) or readable(raw) or readable(value) then
                    local tanking = yes(isTanking)
                    local pct = readable(scaled) and scaled or (readable(raw) and raw) or 0
                    value = readable(value) and value or 0
                    if tanking or value > 0 or pct > 0 then
                        list[#list + 1] = entryFor(u.unit, u.owner, tanking, tanking and math.max(pct, 100) or pct, value)
                        hasTank = hasTank or tanking
                    end
                end
            end
        end
    end
    if not hasTank then
        -- nobody reported as tanking: the mob's target is, if it is one of ours
        for _, u in ipairs(units) do
            if yes(UnitExists(u.unit)) and yes(UnitIsUnit(mob .. "target", u.unit)) then
                local found
                for _, e in ipairs(list) do
                    if yes(UnitIsUnit(e.unit, u.unit)) then found = e break end
                end
                if found then
                    found.tanking, found.pct = true, math.max(found.pct, 100)
                else
                    list[#list + 1] = entryFor(u.unit, u.owner, true, 100, 0)
                end
                break
            end
        end
    end
    table.sort(list, byThreat)
    return list
end

-- Only the player's own entry for the mob (one API call): for the fast check of the "about to pull" alert, which
-- can't wait for the whole list. nil where the client doesn't give it (or hides it from addons).
function ns.Threat_Self(mob)
    if not UnitDetailedThreatSituation then return nil end
    local isTanking, _, scaled, raw = UnitDetailedThreatSituation("player", mob)
    local pct = readable(scaled) and scaled or (readable(raw) and raw) or nil
    local tanking = yes(isTanking)
    if not pct and not tanking then return nil end
    local classFile = plain(select(2, UnitClass("player")))
    return { isMe = true, tanking = tanking, pct = pct or 100, role = ns.Threat_Role("player", classFile) }
end

-- The first `max` entries; if the player is further down, their row replaces the last one so they
-- always see their own place.
function ns.Threat_Top(list, max)
    if #list <= max then return list end
    local top = {}
    for i = 1, max do top[i] = list[i] end
    for i = max + 1, #list do
        if list[i].isMe then top[max] = list[i] break end
    end
    return top
end

-- The other mobs you are fighting: one entry per hostile unit in combat that the game lets us reach
-- (enemy nameplates, focus, bosses), without your target if `skipTarget` (it is already listed in full).
-- It only asks who each mob is attacking (its target), plus your own threat on it where the client has it, so
-- it is cheap and works even where the full threat list isn't available.
-- { { mob = name, who = name of whom it attacks, whoSecret = true if that name is hidden from addons (it can
--     only be shown as it is: no color, no icon, no text added), class = , role = , isPet = , isMe = ,
--     pct = your % on it or nil } }, the ones attacking you first, then by your threat; at most `max`.
local MOB_TOKENS = { "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
for i = 1, 40 do MOB_TOKENS[#MOB_TOKENS + 1] = "nameplate" .. i end

function ns.Threat_Mobs(max, skipTarget)
    local list, accepted = {}, {}
    for _, unit in ipairs(MOB_TOKENS) do
        if yes(UnitExists(unit)) and yes(UnitCanAttack("player", unit)) and not yes(UnitIsDead(unit))
            and yes(UnitAffectingCombat(unit)) and not (skipTarget and yes(UnitIsUnit(unit, "target"))) then
            -- the same mob can be a nameplate and also the focus: counted once
            local duplicate = false
            for _, other in ipairs(accepted) do
                if yes(UnitIsUnit(unit, other)) then duplicate = true break end
            end
            if not duplicate then
                accepted[#accepted + 1] = unit
                local name = UnitName(unit)
                if type(name) ~= "string" then name = "?" end
                local entry = { mob = name, sortName = plain(name) or "", isMe = false, isPet = false }
                local target = unit .. "target"
                if yes(UnitExists(target)) then
                    local who = UnitName(target)
                    if type(who) == "string" then
                        entry.who = who
                        entry.whoSecret = (plain(who) == nil)
                    end
                    entry.isMe = yes(UnitIsUnit(target, "player"))
                    local isPlayer = yes(UnitIsPlayer(target))
                    entry.isPet = (not isPlayer) and yes(UnitPlayerControlled(target))
                    if isPlayer then
                        entry.class = plain(select(2, UnitClass(target)))
                        entry.role = ns.Threat_Role(target, entry.class) -- TANK marks the one holding the mob
                    end
                end
                if entry.isMe then
                    entry.pct = 100
                elseif UnitDetailedThreatSituation then
                    local _, _, scaled = UnitDetailedThreatSituation("player", unit)
                    if readable(scaled) then entry.pct = scaled end
                end
                list[#list + 1] = entry
            end
        end
    end
    table.sort(list, function(a, b)
        if a.isMe ~= b.isMe then return a.isMe end
        if (a.pct or 0) ~= (b.pct or 0) then return (a.pct or 0) > (b.pct or 0) end
        return a.sortName < b.sortName
    end)
    while #list > max do list[#list] = nil end
    return list
end
