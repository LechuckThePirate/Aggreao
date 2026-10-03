local _, ns = ...

-- Keys are the English text; on esES/esMX clients they are replaced by the Spanish one.
local es = {
    ["initializing..."] = "inicializando...",
    ["initialization complete"] = "inicialización completa",
    ["Usage: /aggreao | prefs | toggle | lock | minimap | reset | changelog | version"] =
        "Uso: /aggreao | prefs | toggle | lock | minimap | reset | changelog | version",

    -- aggro window
    ["Drag: move"] = "Arrastrar: mover",
    ["Right-click: preferences"] = "Clic derecho: preferencias",
    ["Not in combat"] = "Fuera de combate",
    ["No target"] = "Sin objetivo",
    ["No aggro data"] = "Sin datos de aggro",
    ["Lock position"] = "Bloquear posición",
    ["Unlock position"] = "Desbloquear posición",
    ["Window closed. Show it again with /aggreao toggle or in the preferences."] =
        "Ventana cerrada. Vuelve a mostrarla con /aggreao toggle o en las preferencias.",
    ["Window shown."] = "Ventana mostrada.",
    ["Window hidden."] = "Ventana oculta.",
    ["Window locked."] = "Ventana bloqueada.",
    ["Window unlocked."] = "Ventana desbloqueada.",
    ["Window position reset."] = "Posición de la ventana restablecida.",

    -- alert sounds
    ["Raid warning"] = "Aviso de banda",
    ["Ready check"] = "Comprobación de listos",
    ["Alarm clock"] = "Despertador",
    ["Map ping"] = "Señal en el mapa",

    -- minimap button
    ["Left-click: preferences"] = "Clic izquierdo: preferencias",
    ["Minimap button hidden."] = "Botón del minimapa oculto.",
    ["Minimap button shown."] = "Botón del minimapa mostrado.",

    -- preferences
    ["Aggreao!! Preferences"] = "Preferencias de Aggreao!!",
    ["Settings are saved for this character only."] = "Los ajustes se guardan solo para este personaje.",
    ["Settings are shared by all your characters."] = "Los ajustes son comunes a todos tus personajes.",
    ["Character specific preferences"] = "Preferencias por personaje",
    ["Show the aggro window"] = "Mostrar la ventana de aggro",
    ["Lock the window position"] = "Bloquear la posición de la ventana",
    ["Show role icons (tank, healer, dps)"] = "Mostrar iconos de rol (tanque, sanador, dps)",
    ["Include pets"] = "Incluir mascotas",
    ["Show other mobs in combat"] = "Mostrar otros mobs en combate",
    ["Other mobs"] = "Otros mobs",
    ["Needs the enemy nameplates on (V key)."] = "Necesita las placas de enemigos activadas (tecla V).",
    ["Needs the enemy nameplates on (V key). They are off now."] =
        "Necesita las placas de enemigos activadas (tecla V). Ahora están desactivadas.",
    ["Hide when not in combat"] = "Ocultar fuera de combate",
    ["Players listed: %d"] = "Jugadores en la lista: %d",
    ["Scale: %d%%"] = "Escala: %d%%",
    ["Background opacity: %d%%"] = "Opacidad del fondo: %d%%",
    ["Play a sound when you are close to taking the aggro"] = "Sonar cuando estés cerca de coger el aggro",
    ["Red border when you are close to taking the aggro"] = "Borde rojo cuando estés cerca de coger el aggro",
    ["Alert from %d%% of the aggro"] = "Avisar desde el %d%% del aggro",
    ["Sound: %s"] = "Sonido: %s",
    ["Test the sound"] = "Probar el sonido",
    ["Show the minimap button"] = "Mostrar el botón del minimapa",
    ["Show chat messages at startup"] = "Mostrar mensajes en el chat al iniciar",
    ["Reset window position"] = "Restablecer posición",
    ["What's new"] = "Novedades",

    -- welcome window
    ["Welcome to Aggreao!!"] = "Bienvenido a Aggreao!!",
    ["Found a bug or have an idea? Please report it on GitHub (click to select, then Ctrl+C):"] =
        "¿Has encontrado un error o tienes una idea? Cuéntalo en GitHub (clic para seleccionar y luego Ctrl+C):",
    ["Don't show this message again"] = "No volver a mostrar este mensaje",
    ["What's new in v%s:"] = "Novedades de la v%s:",
}

ns.L = setmetatable({}, { __index = function(_, k) return k end })

local locale = GetLocale()
if locale == "esES" or locale == "esMX" then
    for k, v in pairs(es) do ns.L[k] = v end
end
