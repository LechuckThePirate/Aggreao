local _, ns = ...
local L = ns.L

-- "You are about to take the aggro" alert: a sound (and a red window border, see Meter) once your threat
-- reaches ns.char.alertThreshold % of what it takes to pull the mob (100 % = you pull it). It sounds once
-- per approach: it re-arms when you drop REARM_MARGIN points below the threshold, when you get the aggro or
-- when the target changes, and never twice within MIN_GAP seconds.
local REARM_MARGIN, MIN_GAP = 10, 2

-- SoundKit ids: they exist in every client. `name` is what Preferences lists.
ns.ALERT_SOUNDS = {
    { key = "raid", name = L["Raid warning"], id = 8959 },
    { key = "ready", name = L["Ready check"], id = 8960 },
    { key = "alarm", name = L["Alarm clock"], id = 12867 },
    { key = "ping", name = L["Map ping"], id = 3175 },
}

local armed, lastPlayed = true, nil

function ns.Alert_SoundName(key)
    for _, s in ipairs(ns.ALERT_SOUNDS) do
        if s.key == key then return s.name end
    end
    return ns.ALERT_SOUNDS[1].name
end

-- Plays an alert sound (the chosen one by default); Preferences' test button uses it too.
function ns.Alert_Play(key)
    key = key or ns.char.alertSoundKey
    local id = ns.ALERT_SOUNDS[1].id
    for _, s in ipairs(ns.ALERT_SOUNDS) do
        if s.key == key then id = s.id end
    end
    if PlaySound then PlaySound(id, "Master") end
end

function ns.Alert_Reset()
    armed = true
end

-- Looks at the threat list; returns true while the player is close to taking the aggro.
function ns.Alert_Check(list)
    local me
    for _, e in ipairs(list) do
        if e.isMe then me = e break end
    end
    local threshold = ns.char.alertThreshold
    -- a tank not holding it is trying to get it: nothing to warn about
    local near = me ~= nil and not me.tanking and me.role ~= "TANK" and me.pct >= threshold
    if near then
        local now = GetTime()
        if armed and ns.char.alertSound and (not lastPlayed or now - lastPlayed >= MIN_GAP) then
            ns.Alert_Play()
            lastPlayed = now
        end
        armed = false
    elseif me == nil or me.tanking or me.pct < threshold - REARM_MARGIN then
        armed = true
    end
    return near
end
