local _, ns = ...

-- A scroll frame (UIPanelScrollFrameTemplate) whose bar is only there when there is something to scroll:
-- the template keeps the bar, its arrows and thumb showing (greyed out) even when the content fits, which
-- is noise next to a short list. `scrollBarHideable` is the template's own switch for that; it acts when the
-- scroll range changes, so it is also run once now and whenever the frame is shown.
function ns.HideableScroll(scroll)
    scroll.scrollBarHideable = true
    local function sync()
        if ScrollFrame_OnScrollRangeChanged then ScrollFrame_OnScrollRangeChanged(scroll) end
    end
    scroll:HookScript("OnShow", sync)
    sync()
    return scroll
end
