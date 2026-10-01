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

-- Role of a unit: the one assigned in the group (Retail, TBC) or chosen as spec (the player on Retail);
-- otherwise guessed only for classes that can't do anything else. nil = unknown (no icon).
function ns.Threat_Role(unit, classFile)
    if UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned(unit)
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
    if GetSpecialization and GetSpecializationRole and UnitIsUnit(unit, "player") then
        local spec = GetSpecialization()
        local role = spec and GetSpecializationRole(spec)
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    end
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
    local _, classFile = UnitClass(classUnit)
    return {
        unit = unit,
        name = UnitName(unit) or "?",
        class = classFile,
        isPet = owner ~= nil,
        isMe = (not owner) and UnitIsUnit(unit, "player") or false,
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
            if UnitExists(u.unit) then
                local isTanking, _, scaled, raw, value = UnitDetailedThreatSituation(u.unit, mob)
                if readable(scaled) or readable(raw) or readable(value) then
                    local tanking = isTanking and true or false
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
            if UnitExists(u.unit) and UnitIsUnit(mob .. "target", u.unit) then
                local found
                for _, e in ipairs(list) do
                    if UnitIsUnit(e.unit, u.unit) then found = e break end
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
