-- Loading the addon in tests: the files in TOC order (like the game), each with ("Aggreao", ns).
-- LoadAddon() loads everything; LoadAddon({ files = {...} }) only those files (with Localization/Locale.lua
-- in front if missing). StartAddon(ns) simulates entering the game.

function TocFiles()
    local files = {}
    for line in io.lines("Aggreao.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^##") and line:match("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

function LoadAddon(opts)
    opts = opts or {}
    local ns = {}
    local files = opts.files
    if files then
        if files[1] ~= "Localization/Locale.lua" then
            local withLocale = { "Localization/Locale.lua" }
            for _, f in ipairs(files) do withLocale[#withLocale + 1] = f end
            files = withLocale
        end
    else
        files = TocFiles()
    end
    for _, f in ipairs(files) do
        local chunk = assert(loadfile(f))
        chunk("Aggreao", ns)
    end
    return ns
end

-- Every frame that registered the event and has an OnEvent receives it (as if the game fired it).
function FireEvent(event, ...)
    for _, f in ipairs(WowMock.frames) do
        local handler = f._scripts.OnEvent
        if handler and f._events and f._events[event] then handler(f, event, ...) end
    end
end

-- ADDON_LOADED + PLAYER_ENTERING_WORLD, with fresh saved variables (or the ones passed in).
function StartAddon(ns, db, charDB)
    AggreaoDB, AggreaoCharDB = db, charDB
    FireEvent("ADDON_LOADED", "Aggreao")
    FireEvent("PLAYER_ENTERING_WORLD")
    return ns
end
