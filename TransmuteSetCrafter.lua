-- Transmute Set Crafter
-- A queue-based transmutation assistant for the Transmutation Station.
-- Based on the design of Dolgubon's Lazy Set Crafter by Joseph Heinzle.
--
-- This file MUST load first (see manifest). It defines the namespace
-- and TSC.name so all subsequent modules can reference them at load time.

TransmuteSetCrafter = TransmuteSetCrafter or {}
local TSC = TransmuteSetCrafter

TSC.name    = "TransmuteSetCrafter"
TSC.version = 1

-- ── Saved variable defaults ────────────────────────────────

TSC.defaults = {
    queue          = {},
    xPos           = nil,
    yPos           = nil,
    windowWidth           = 900,
    windowHeight          = 540,
    costWindowWidth       = 300,
    costWindowHeight      = 540,
    costWindowHidden      = false,
    costXPos              = nil,  -- nil → docked to main window
    costYPos              = nil,
    quicksaveWindowWidth  = 280,
    quicksaveWindowHeight = 540,
    quicksaveWindowHidden = false,
    quicksaveXPos         = nil,  -- nil → docked to cost window
    quicksaveYPos         = nil,
    quicksaves            = {},
    openAtStation  = true,
    closeOnExit    = true,
}

-- ── Initialization ─────────────────────────────────────────

local function Initialize()
    TSC.savedVars = ZO_SavedVars:NewAccountWide(
        "TransmuteSetCrafterSavedVars", TSC.version, nil, TSC.defaults)

    TSC.InitializeSettings()
    TSC.SetupUI()
end

-- ── Addon loaded ───────────────────────────────────────────

local function OnAddonLoaded(_, addonName)
    if addonName ~= TSC.name then return end
    EVENT_MANAGER:UnregisterForEvent(TSC.name, EVENT_ADD_ON_LOADED)
    Initialize()
end

EVENT_MANAGER:RegisterForEvent(TSC.name, EVENT_ADD_ON_LOADED, OnAddonLoaded)

-- ── Player activated — deferred setup that needs live bags ─
-- Restore the persisted queue (bags are accessible now) and
-- register the retrait scene state callback (scenes are set up now).

local function OnPlayerActivated()
    EVENT_MANAGER:UnregisterForEvent(TSC.name .. "_Activate", EVENT_PLAYER_ACTIVATED)

    -- Restore queue from saved vars, dropping any items no longer in bags
    TSC.RestoreQueue()
    TSC.RefreshQueueList()
    TSC.UpdateCostDisplay()

    -- Watch the keyboard retrait scene so we can close when the player leaves.
    -- KEYBOARD_RETRAIT_ROOT_SCENE is a global set by the game's retrait station code.
    local scene = KEYBOARD_RETRAIT_ROOT_SCENE
                  or SCENE_MANAGER:GetScene("retrait_keyboard_root")
    if scene then
        scene:RegisterCallback("StateChange", function(_, newState)
            if newState == SCENE_HIDDEN and TSC.savedVars and TSC.savedVars.closeOnExit then
                TSC.CloseWindow()
            end
        end)
    end

    -- Escape key handler: when the in-game menu would open (escape pressed
    -- with no other UI on top), close our window stack first and cancel the
    -- menu opening so escape acts like "close TSC" rather than "open menu".
    local gameMenuScene = SCENE_MANAGER:GetScene("gameMenuInGame")
    if gameMenuScene then
        gameMenuScene:RegisterCallback("StateChange", function(_, newState)
            if newState ~= SCENE_SHOWING then return end
            local mainWin = TransmuteSetCrafterWindow
            if not mainWin or mainWin:IsHidden() then return end

            TSC.CloseWindow()
            -- Cancel the game menu that just started opening
            zo_callLater(function()
                if SCENE_MANAGER:IsShowing("gameMenuInGame") then
                    SCENE_MANAGER:Hide("gameMenuInGame")
                end
            end, 0)
        end)
    end
end

EVENT_MANAGER:RegisterForEvent(
    TSC.name .. "_Activate", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)

-- ── Retrait station open event ─────────────────────────────

EVENT_MANAGER:RegisterForEvent(
    TSC.name .. "_Open",
    EVENT_RETRAIT_STATION_INTERACT_START,
    function()
        if TSC.savedVars and TSC.savedVars.openAtStation then
            TSC.OpenWindow()
        end
    end
)

-- ── Slash commands ─────────────────────────────────────────

SLASH_COMMANDS["/tsc"]              = function() TSC.ToggleWindow() end
SLASH_COMMANDS["/transmutecrafter"] = function() TSC.ToggleWindow() end
