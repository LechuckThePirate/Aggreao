local _, ns = ...
local L = ns.L

-- "You are about to take the aggro" alert: a sound (and a red window border, see Meter) once your threat
-- reaches ns.char.alertThreshold % of what it takes to pull the mob (100 % = you pull it). It sounds once
-- per approach, and never twice within MIN_GAP seconds:
--  * if your threat jumps over the warning zone between two updates of the game and you take the aggro from
--    someone else (your pet, say), it sounds then -- unless it had already warned you in this approach;
--  * it re-arms only when your threat drops REARM_MARGIN points below the threshold, or the target changes.
--    Holding the aggro doesn't re-arm it: when your pet takes it back your threat is still high, and that
--    must not sound as if you were about to pull.
local REARM_MARGIN, MIN_GAP = 10, 2

-- SoundKit ids: they exist in every client. `name` is what Preferences lists.
ns.ALERT_SOUNDS = {
    { key = "raid", name = L["Raid warning"], id = 8959 },
    { key = "ready", name = L["Ready check"], id = 8960 },
    { key = "alarm", name = L["Alarm clock"], id = 12867 },
    { key = "ping", name = L["Map ping"], id = 3175 },
}

local armed, lastPlayed = true, nil
local wasTanking -- whether you held the aggro in the last check: nil = unknown, false = someone else did

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
    armed, wasTanking = true, nil
end

local function sound()
    local now = GetTime()
    if ns.char.alertSound and (not lastPlayed or now - lastPlayed >= MIN_GAP) then
        ns.Alert_Play()
        lastPlayed = now
    end
end

-- Looks at the threat list; returns true while the player is close to taking the aggro.
function ns.Alert_Check(list)
    local me
    for _, e in ipairs(list) do
        if e.isMe then me = e break end
    end
    local threshold = ns.char.alertThreshold
    -- a tank not holding it is trying to get it: nothing to warn about
    local isTank = me ~= nil and me.role == "TANK"
    -- you took the aggro from someone else, and nothing warned you on the way: now
    local pulled = me ~= nil and me.tanking and wasTanking == false and armed and not isTank
    if me then
        wasTanking = me.tanking
    elseif #list > 0 then
        wasTanking = false -- someone else holds it, and you don't even have threat on it
    end
    local near = me ~= nil and not me.tanking and not isTank and me.pct >= threshold
    if near or pulled then
        if armed then sound() end
        armed = false
    elseif me and me.tanking then
        armed = false -- holding it: no warning when the other one takes it back with you still high
    elseif me == nil or me.pct < threshold - REARM_MARGIN then
        armed = true
    end
    return near
end
