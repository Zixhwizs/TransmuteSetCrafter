-- Transmute Set Crafter — Quicksaves
--
-- Named snapshots of the current queue. Each quicksave stores a deep copy of
-- the queue's entries. Clicking a row re-adds those entries to the current
-- queue (via TSC.AddToQueue, so derived fields like crystalCost are refreshed
-- to current game state). Saves persist to account-wide savedVars.

local TSC = TransmuteSetCrafter
local ADDON_NAME = TSC.name

local QUICKSAVE_ENTRY      = 1
local QUICKSAVE_ROW_HEIGHT = 26

local nameEditBox = nil

-- ── Helpers ───────────────────────────────────────────────

local function CopyEntry(entry)
    local copy = {}
    for k, v in pairs(entry) do
        copy[k] = v  -- shallow copy: all queue-entry values are primitives
    end
    return copy
end

local function CopyQueue(q)
    local copy = {}
    for _, entry in ipairs(q) do
        table.insert(copy, CopyEntry(entry))
    end
    return copy
end

local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetSaves()
    if not TSC.savedVars.quicksaves then
        TSC.savedVars.quicksaves = {}
    end
    return TSC.savedVars.quicksaves
end

-- ── Public: create / load / delete ────────────────────────

function TSC.CreateQuicksave(name)
    if not name or name == "" then
        d("[TSC] Quicksave needs a name.")
        return
    end
    if #TSC.queue == 0 then
        d("[TSC] Queue is empty — nothing to save.")
        return
    end
    local saves = GetSaves()
    table.insert(saves, { name = name, queue = CopyQueue(TSC.queue) })
    TSC.savedVars.quicksaves = saves
    TSC.RefreshQuicksavePanel()
    d(zo_strformat("[TSC] Saved quicksave '<<1>>' with <<2>> item(s).", name, #TSC.queue))
end

function TSC.LoadQuicksave(index)
    local saves = GetSaves()
    local save  = saves[index]
    if not save then return end

    local added = 0
    for _, entry in ipairs(save.queue) do
        TSC.AddToQueue(
            entry.pieceId,
            entry.traitType,
            entry.quality,
            entry.enchantment,
            entry.enchantQuality
        )
        added = added + 1
    end
    d(zo_strformat("[TSC] Loaded quicksave '<<1>>' (<<2>> item(s)).", save.name, added))
end

function TSC.DeleteQuicksave(index)
    local saves = GetSaves()
    if not saves[index] then return end
    local name = saves[index].name
    table.remove(saves, index)
    TSC.savedVars.quicksaves = saves
    TSC.RefreshQuicksavePanel()
    d(zo_strformat("[TSC] Deleted quicksave '<<1>>'.", name))
end

function TSC.CreateQuicksaveFromInput()
    if not nameEditBox then return end
    local name = Trim(nameEditBox:GetText())
    if name == "" then
        d("[TSC] Type a name first.")
        return
    end
    TSC.CreateQuicksave(name)
    nameEditBox:SetText("")
end

-- ── Row callbacks (wired from XML) ────────────────────────

function TSC.SetupQuicksaveRow(ctrl, data)
    ctrl.data = data
    local nameLbl = ctrl:GetNamedChild("Name")
    nameLbl:SetText(zo_strformat("<<1>>  (<<2>>)", data.name, data.count))

    -- Resize the row to track the scroll list width so Delete stays right-pinned
    local list = TransmuteSetCrafterQuicksaveWindowList
    if list then
        local w = list:GetWidth() - 18
        if w > 120 then ctrl:SetWidth(w) end
    end

    ctrl:GetNamedChild("Highlight"):SetAlpha(0)
end

function TSC.OnQuicksaveRowMouseEnter(ctrl)
    if ctrl.data then
        ctrl:GetNamedChild("Highlight"):SetAlpha(0.2)
    end
end

function TSC.OnQuicksaveRowMouseExit(ctrl)
    if ctrl.data then
        ctrl:GetNamedChild("Highlight"):SetAlpha(0)
    end
end

function TSC.OnQuicksaveRowClick(ctrl, button, upInside)
    if not upInside or not ctrl.data then return end
    if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
    TSC.LoadQuicksave(ctrl.data.index)
end

function TSC.DeleteQuicksaveRow(ctrl)
    if ctrl and ctrl.data then
        TSC.DeleteQuicksave(ctrl.data.index)
    end
end

-- ── Panel refresh ─────────────────────────────────────────

function TSC.RefreshQuicksavePanel()
    local list = TransmuteSetCrafterQuicksaveWindowList
    if not list then return end
    ZO_ScrollList_Clear(list)
    local dataList = ZO_ScrollList_GetDataList(list)

    for i, save in ipairs(GetSaves()) do
        table.insert(dataList, ZO_ScrollList_CreateDataEntry(QUICKSAVE_ENTRY, {
            index = i,
            name  = save.name,
            count = save.queue and #save.queue or 0,
        }))
    end
    ZO_ScrollList_Commit(list)
end

-- ── Setup, called by UI.lua SetupUI ───────────────────────

function TSC.SetupQuicksavePanel()
    local win = TransmuteSetCrafterQuicksaveWindow
    if not win then return end

    -- Restore saved dimensions and position, enable corner-grip resize.
    -- If no saved position, keep the XML default (docked to cost window).
    if TSC.savedVars.quicksaveWindowWidth and TSC.savedVars.quicksaveWindowHeight then
        win:SetDimensions(TSC.savedVars.quicksaveWindowWidth, TSC.savedVars.quicksaveWindowHeight)
    end
    if TSC.savedVars.quicksaveXPos and TSC.savedVars.quicksaveYPos then
        win:ClearAnchors()
        win:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT,
                      TSC.savedVars.quicksaveXPos, TSC.savedVars.quicksaveYPos)
    end
    win:SetResizeHandleSize(8)

    -- Wire scroll list data type
    local list = TransmuteSetCrafterQuicksaveWindowList
    if list then
        ZO_ScrollList_AddDataType(list, QUICKSAVE_ENTRY, "TSC_QuicksaveRow",
                                  QUICKSAVE_ROW_HEIGHT,
                                  function(ctrl, data) TSC.SetupQuicksaveRow(ctrl, data) end)
    end

    -- Labels and the name editbox
    TransmuteSetCrafterQuicksaveWindowTitle:SetText("Quicksaves")
    TransmuteSetCrafterQuicksaveWindowSaveButton:SetText("Save")

    nameEditBox = TransmuteSetCrafterQuicksaveWindowNameBox
    if nameEditBox then
        nameEditBox:SetDefaultText("Quicksave name...")
        -- Save on Enter
        nameEditBox:SetHandler("OnEnter", function()
            TSC.CreateQuicksaveFromInput()
        end)
    end

    TSC.RefreshQuicksavePanel()
end
