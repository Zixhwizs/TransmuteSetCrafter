-- Transmute Set Crafter — UI setup and refresh

local TSC = TransmuteSetCrafter
local ADDON_NAME = TSC.name

local SET_ENTRY   = 1
local PIECE_ENTRY = 2
local QUEUE_ENTRY = 3
local COST_ENTRY  = 4

local INV_ROW_HEIGHT   = 30
local QUEUE_ROW_HEIGHT = 30

-- ── Enchantment options by trait category ─────────────────
-- Curated lists of common enchantment glyphs. Displayed in the queue as a
-- planning note only; the reconstruction API doesn't apply enchantments.

local ENCHANTMENTS_WEAPON = {
    "Absorb Health",
    "Absorb Magicka",
    "Absorb Stamina",
    "Crushing",
    "Decrease Health",
    "Flame",
    "Foulness (Disease)",
    "Frost",
    "Hardening",
    "Poison",
    "Prismatic Onslaught",
    "Shock",
    "Weakening",
}

local ENCHANTMENTS_ARMOR = {
    "Health",
    "Magicka",
    "Prismatic Defense",
    "Stamina",
}

local ENCHANTMENTS_JEWELRY = {
    "Bashing",
    "Decrease Physical Harm",
    "Decrease Spell Harm",
    "Disease Resist",
    "Flame Resist",
    "Frost Resist",
    "Healing Done",
    "Health Recovery",
    "Magicka Recovery",
    "Poison Resist",
    "Potion Boost",
    "Potion Speed",
    "Prismatic Recovery",
    "Reduce Feat Cost",
    "Reduce Magicka Cost",
    "Reduce Spell Cost",
    "Shielding",
    "Shock Resist",
    "Spell Damage",
    "Stamina Recovery",
    "Weapon Damage",
}

local function GetEnchantmentsForCategory(category)
    if     category == ITEM_TRAIT_TYPE_CATEGORY_WEAPON  then return ENCHANTMENTS_WEAPON
    elseif category == ITEM_TRAIT_TYPE_CATEGORY_ARMOR   then return ENCHANTMENTS_ARMOR
    elseif category == ITEM_TRAIT_TYPE_CATEGORY_JEWELRY then return ENCHANTMENTS_JEWELRY
    end
    return {}
end

-- ── Queue column layout ───────────────────────────────────
-- Column widths flex with the queue list width. Proportions sum to 1.

local QUEUE_LEFT_PAD   = 4
local QUEUE_RIGHT_PAD  = 4
local QUEUE_BUTTON_PAD = 68   -- Edit (36) + gap (4) + Close (24) + 4px right margin
local QUEUE_COL_GAP    = 4
local QUEUE_HEADER_GAP = 22   -- vertical gap from header baseline to list top
local QUEUE_SCROLLBAR  = 18   -- scrollbar reserved on the right of the list

local QUEUE_COL_PROP = {
    setName = 0.28,
    type    = 0.28,  -- includes weight suffix for armor, e.g. "Chest (H)"
    trait   = 0.20,
    enchant = 0.24,
}

local QUEUE_COL_MIN = {
    setName = 90,
    type    = 110,   -- room for "Greatsword" or "Shoulders (M)"
    trait   = 70,
    enchant = 70,
}

local function ComputeQueueColumnLayout(rowWidth)
    local usable = rowWidth - QUEUE_LEFT_PAD - QUEUE_RIGHT_PAD - QUEUE_BUTTON_PAD - (QUEUE_COL_GAP * 3)
    if usable < 50 then usable = 50 end

    local wSet     = math.max(QUEUE_COL_MIN.setName, math.floor(usable * QUEUE_COL_PROP.setName))
    local wType    = math.max(QUEUE_COL_MIN.type,    math.floor(usable * QUEUE_COL_PROP.type))
    local wTrait   = math.max(QUEUE_COL_MIN.trait,   math.floor(usable * QUEUE_COL_PROP.trait))
    local wEnchant = math.max(QUEUE_COL_MIN.enchant, usable - wSet - wType - wTrait)

    local x = QUEUE_LEFT_PAD
    local layout = {}
    layout.setName = { x = x, w = wSet };  x = x + wSet  + QUEUE_COL_GAP
    layout.type    = { x = x, w = wType }; x = x + wType + QUEUE_COL_GAP
    layout.trait   = { x = x, w = wTrait };x = x + wTrait + QUEUE_COL_GAP
    layout.enchant = { x = x, w = wEnchant }
    return layout
end

local function PlaceQueueCol(child, parent, x, w, offY)
    if not child then return end
    child:ClearAnchors()
    child:SetAnchor(TOPLEFT, parent, TOPLEFT, x, offY or 0)
    child:SetWidth(w)
end

function TSC.UpdateQueueColumnHeaders()
    local qList = TransmuteSetCrafterWindowQueueList
    if not qList then return end
    local listW = qList:GetWidth()
    if not listW or listW < 50 then return end
    local rowWidth = listW - QUEUE_SCROLLBAR
    local layout   = ComputeQueueColumnLayout(rowWidth)

    PlaceQueueCol(TransmuteSetCrafterWindowQueueColSet,     qList, layout.setName.x, layout.setName.w, -QUEUE_HEADER_GAP)
    PlaceQueueCol(TransmuteSetCrafterWindowQueueColType,    qList, layout.type.x,    layout.type.w,    -QUEUE_HEADER_GAP)
    PlaceQueueCol(TransmuteSetCrafterWindowQueueColTrait,   qList, layout.trait.x,   layout.trait.w,   -QUEUE_HEADER_GAP)
    PlaceQueueCol(TransmuteSetCrafterWindowQueueColEnchant, qList, layout.enchant.x, layout.enchant.w, -QUEUE_HEADER_GAP)
end

-- ── Internal state ─────────────────────────────────────────

local browsingMode      = "sets"
local selectedSet       = nil   -- ZO_ItemSetCollectionData while in piece mode
local selectedPieces    = {}    -- { [pieceId] = pieceData, ... } — multi-selection
local lastSelectedPiece = nil   -- most recently selected piece; drives trait dropdown
local selectedTrait         = nil
local selectedQuality       = nil
local selectedEnchant       = ""    -- enchantment glyph name (planning note)
local selectedEnchantQuality = ITEM_FUNCTIONAL_QUALITY_LEGENDARY
local searchText            = ""
local traitComboBox         = nil
local qualityComboBox       = nil
local enchantComboBox       = nil
local enchantQualityComboBox = nil
local editingQueueIndex     = nil  -- when set, AddToQueue button updates this index instead of adding
local lastUsedCategory      = nil  -- trait category of the most recent selection; lets trait/enchant choices persist across Add

-- ── Build set list ─────────────────────────────────────────

local function BuildSetList()
    local setMap   = {}
    local lowerSrc = string.lower(searchText)

    for _, pieceData in ITEM_SET_COLLECTIONS_DATA_MANAGER:ItemSetCollectionPieceIterator() do
        if pieceData:IsUnlocked() then
            local setData = pieceData:GetItemSetCollectionData()
            local setId   = setData:GetId()
            local entry   = setMap[setId]
            if not entry then
                entry = { setData = setData, count = 0 }
                setMap[setId] = entry
            end
            entry.count = entry.count + 1
        end
    end

    local sets = {}
    for _, entry in pairs(setMap) do
        local passesSearch = searchText == "" or
            string.find(string.lower(entry.setData:GetRawName()), lowerSrc, 1, true)
        if passesSearch then
            table.insert(sets, entry)
        end
    end

    table.sort(sets, function(a, b)
        return a.setData:GetRawName() < b.setData:GetRawName()
    end)
    return sets
end

-- ── Build piece list for selected set ─────────────────────

local function BuildPieceList()
    local targetSetId = selectedSet:GetId()
    local pieces = {}
    for _, pieceData in ITEM_SET_COLLECTIONS_DATA_MANAGER:ItemSetCollectionPieceIterator() do
        if pieceData:GetItemSetCollectionData():GetId() == targetSetId then
            table.insert(pieces, pieceData)
        end
    end
    table.sort(pieces, function(a, b)
        return (a:GetRawName() or "") < (b:GetRawName() or "")
    end)
    return pieces
end

-- ── Clear piece selection ──────────────────────────────────

local function ClearPieceSelection()
    selectedPieces         = {}
    lastSelectedPiece      = nil
    selectedTrait          = nil
    selectedQuality        = nil
    selectedEnchant        = ""
    selectedEnchantQuality = ITEM_FUNCTIONAL_QUALITY_LEGENDARY
    editingQueueIndex      = nil
    lastUsedCategory       = nil
    if traitComboBox          then traitComboBox:ClearItems()          end
    if qualityComboBox        then qualityComboBox:ClearItems()        end
    if enchantComboBox        then enchantComboBox:ClearItems()        end
    if enchantQualityComboBox then enchantQualityComboBox:ClearItems() end
end

-- "Soft" clear after Add to Queue: drop the piece selection (and any edit-mode
-- lock), but KEEP the trait / quality / enchant / enchant-quality choices and
-- their populated dropdowns so the user can queue another same-category piece
-- without re-picking everything.
local function ClearSelectedPiecesKeepDropdowns()
    if lastSelectedPiece then
        lastUsedCategory = lastSelectedPiece.traitCategory
    end
    selectedPieces    = {}
    lastSelectedPiece = nil
    editingQueueIndex = nil
end

-- ── Count selected pieces ──────────────────────────────────

local function SelectedPieceCount()
    local n = 0
    for _ in pairs(selectedPieces) do n = n + 1 end
    return n
end

-- ── Navigation state ───────────────────────────────────────

function TSC.UpdateNavigationState()
    local inPieceMode = browsingMode == "pieces"

    TransmuteSetCrafterWindowSearchBG:SetHidden(inPieceMode)
    TransmuteSetCrafterWindowSearchBox:SetHidden(inPieceMode)

    if inPieceMode and selectedSet then
        TransmuteSetCrafterWindowInventoryHeader:SetText(
            GetString(SI_TSC_BACK_PREFIX) .. selectedSet:GetFormattedName())
        TransmuteSetCrafterWindowInventoryHeader:SetColor(0.46, 0.74, 0.76, 1)
    else
        TransmuteSetCrafterWindowInventoryHeader:SetText(GetString(SI_TSC_INVENTORY_HEADER))
        TransmuteSetCrafterWindowInventoryHeader:SetColor(1, 1, 1, 1)
    end
end

-- ── Setup ──────────────────────────────────────────────────

function TSC.SetupUI()
    local win = TransmuteSetCrafterWindow

    -- Restore saved size then position (order matters: size before anchor)
    if TSC.savedVars.windowWidth and TSC.savedVars.windowHeight then
        win:SetDimensions(TSC.savedVars.windowWidth, TSC.savedVars.windowHeight)
    end
    if TSC.savedVars.xPos and TSC.savedVars.yPos then
        win:ClearAnchors()
        win:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT,
                      TSC.savedVars.xPos, TSC.savedVars.yPos)
    end

    -- Enable resize (bottom-right corner grip)
    win:SetResizeHandleSize(8)

    -- Cost window — restore saved size and position, enable resize.
    -- If no saved position, keep the XML default (docked to main window).
    local costWin = TransmuteSetCrafterCostWindow
    if costWin then
        if TSC.savedVars.costWindowWidth and TSC.savedVars.costWindowHeight then
            costWin:SetDimensions(TSC.savedVars.costWindowWidth, TSC.savedVars.costWindowHeight)
        end
        if TSC.savedVars.costXPos and TSC.savedVars.costYPos then
            costWin:ClearAnchors()
            costWin:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT,
                              TSC.savedVars.costXPos, TSC.savedVars.costYPos)
        end
        costWin:SetResizeHandleSize(8)
    end

    -- Quicksave window setup (deferred to its own module)
    if TSC.SetupQuicksavePanel then
        TSC.SetupQuicksavePanel()
    end

    TransmuteSetCrafterWindowTitle:SetText(GetString(SI_TSC_TITLE))
    TransmuteSetCrafterWindowQueueHeader:SetText(GetString(SI_TSC_QUEUE_HEADER))
    TransmuteSetCrafterWindowTraitLabel:SetText(GetString(SI_TSC_TARGET_TRAIT_LABEL))
    TransmuteSetCrafterWindowQualityLabel:SetText(GetString(SI_TSC_QUALITY_LABEL))

    TransmuteSetCrafterWindowQueueColSet:SetText("Set")
    TransmuteSetCrafterWindowQueueColType:SetText("Type")
    TransmuteSetCrafterWindowQueueColTrait:SetText("Trait")
    TransmuteSetCrafterWindowQueueColEnchant:SetText("Enchant")

    TransmuteSetCrafterWindowToggleCost:SetText("Materials")
    TransmuteSetCrafterWindowToggleQuicksaves:SetText("Quicksaves")

    TransmuteSetCrafterWindowClearQueueButton:SetText(GetString(SI_TSC_CLEAR_QUEUE))
    TransmuteSetCrafterWindowCancelEditButton:SetText("Cancel Edit")

    local searchBox = TransmuteSetCrafterWindowSearchBox
    searchBox:SetText("")
    searchBox:SetDefaultText(GetString(SI_TSC_SEARCH_PLACEHOLDER))

    local invList = TransmuteSetCrafterWindowInventoryList
    ZO_ScrollList_AddDataType(invList, SET_ENTRY, "TSC_SetRow",
                              INV_ROW_HEIGHT,
                              function(ctrl, data) TSC.SetupSetRow(ctrl, data) end)
    ZO_ScrollList_AddDataType(invList, PIECE_ENTRY, "TSC_InventoryRow",
                              INV_ROW_HEIGHT,
                              function(ctrl, data) TSC.SetupInventoryRow(ctrl, data) end)
    ZO_ScrollList_EnableHighlight(invList, "ZO_TallListHighlight")

    local qList = TransmuteSetCrafterWindowQueueList
    ZO_ScrollList_AddDataType(qList, QUEUE_ENTRY, "TSC_QueueRow",
                              QUEUE_ROW_HEIGHT,
                              function(ctrl, data) TSC.SetupQueueRow(ctrl, data) end)

    -- Cost panel scroll list
    local costList = TransmuteSetCrafterCostWindowList
    if costList then
        ZO_ScrollList_AddDataType(costList, COST_ENTRY, "TSC_CostRow", 22,
                                  function(ctrl, data) TSC.SetupCostRow(ctrl, data) end)
    end
    TransmuteSetCrafterCostWindowTitle:SetText("Materials")
    TransmuteSetCrafterCostWindowColName:SetText("Item")
    TransmuteSetCrafterCostWindowColNeeded:SetText("Need")
    TransmuteSetCrafterCostWindowColHave:SetText("Have")

    traitComboBox = ZO_ComboBox_ObjectFromContainer(TransmuteSetCrafterWindowTraitDropdown)
    traitComboBox:SetSortsItems(false)

    qualityComboBox = ZO_ComboBox_ObjectFromContainer(TransmuteSetCrafterWindowQualityDropdown)
    qualityComboBox:SetSortsItems(false)

    enchantComboBox = ZO_ComboBox_ObjectFromContainer(TransmuteSetCrafterWindowEnchantDropdown)
    enchantComboBox:SetSortsItems(false)

    enchantQualityComboBox = ZO_ComboBox_ObjectFromContainer(TransmuteSetCrafterWindowEnchantQualityDropdown)
    enchantQualityComboBox:SetSortsItems(false)

    TransmuteSetCrafterWindowEnchantLabel:SetText(GetString(SI_TSC_ENCHANTMENT_LABEL))

    TSC.UpdateNavigationState()
    TSC.UpdateQueueColumnHeaders()
    TSC.UpdateAddButton()
    TSC.UpdateTransmuteButton()
    TSC.UpdateCostDisplay()
end

-- ── Window open / close / toggle ───────────────────────────

function TSC.OpenWindow()
    browsingMode = "sets"
    selectedSet  = nil
    ClearPieceSelection()

    TransmuteSetCrafterWindow:SetHidden(false)
    TransmuteSetCrafterCostWindow:SetHidden(TSC.savedVars.costWindowHidden or false)
    TransmuteSetCrafterQuicksaveWindow:SetHidden(TSC.savedVars.quicksaveWindowHidden or false)
    TSC.UpdateQueueColumnHeaders()
    TSC.RefreshInventoryList()
    TSC.RefreshQueueList()
    TSC.UpdateCostDisplay()
    if TSC.RefreshQuicksavePanel then TSC.RefreshQuicksavePanel() end
end

function TSC.CloseWindow()
    TransmuteSetCrafterWindow:SetHidden(true)
    TransmuteSetCrafterCostWindow:SetHidden(true)
    TransmuteSetCrafterQuicksaveWindow:SetHidden(true)
end

-- ── Side-panel visibility toggles ─────────────────────────

function TSC.ToggleCostWindow()
    local win = TransmuteSetCrafterCostWindow
    if not win then return end
    local nowHidden = not win:IsHidden()
    win:SetHidden(nowHidden)
    TSC.savedVars.costWindowHidden = nowHidden
    if not nowHidden then
        TSC.RefreshCostPanel()
    end
end

function TSC.ToggleQuicksaveWindow()
    local win = TransmuteSetCrafterQuicksaveWindow
    if not win then return end
    local nowHidden = not win:IsHidden()
    win:SetHidden(nowHidden)
    TSC.savedVars.quicksaveWindowHidden = nowHidden
    if not nowHidden and TSC.RefreshQuicksavePanel then
        TSC.RefreshQuicksavePanel()
    end
end

function TSC.ToggleWindow()
    if TransmuteSetCrafterWindow:IsHidden() then
        TSC.OpenWindow()
    else
        TSC.CloseWindow()
    end
end

-- ── Inventory list ─────────────────────────────────────────

function TSC.RefreshInventoryList()
    local invList  = TransmuteSetCrafterWindowInventoryList
    ZO_ScrollList_Clear(invList)
    local dataList = ZO_ScrollList_GetDataList(invList)

    if browsingMode == "sets" then
        for _, entry in ipairs(BuildSetList()) do
            table.insert(dataList, ZO_ScrollList_CreateDataEntry(SET_ENTRY, {
                setData   = entry.setData,
                setName   = entry.setData:GetFormattedName(),
                numPieces = entry.count,
            }))
        end
    else
        for _, pieceData in ipairs(BuildPieceList()) do
            table.insert(dataList, ZO_ScrollList_CreateDataEntry(PIECE_ENTRY, {
                pieceId        = pieceData:GetId(),
                pieceName      = pieceData:GetFormattedName(),
                pieceIcon      = pieceData:GetIcon(),
                displayQuality = pieceData:GetDisplayQuality(),
                traitCategory  = pieceData:GetTraitCategory(),
            }))
        end
    end

    ZO_ScrollList_Commit(invList)
    TSC.UpdateNavigationState()
end

-- ── Set row ────────────────────────────────────────────────

function TSC.SetupSetRow(ctrl, data)
    ctrl.data = data
    ctrl:GetNamedChild("Name"):SetText(data.setName)
    ctrl:GetNamedChild("Chevron"):SetText("›")
    ctrl:GetNamedChild("Highlight"):SetAlpha(0)
end

function TSC.OnSetRowMouseEnter(ctrl)
    if ctrl.data then ctrl:GetNamedChild("Highlight"):SetAlpha(0.15) end
end

function TSC.OnSetRowMouseExit(ctrl)
    if ctrl.data then ctrl:GetNamedChild("Highlight"):SetAlpha(0) end
end

function TSC.OnSetRowClick(ctrl, button, upInside)
    if not upInside or not ctrl.data then return end
    if button ~= MOUSE_BUTTON_INDEX_LEFT then return end

    browsingMode = "pieces"
    selectedSet  = ctrl.data.setData
    ClearPieceSelection()
    TSC.RefreshInventoryList()
    TSC.UpdateAddButton()
    TSC.UpdateTransmuteButton()
end

-- ── Piece row ──────────────────────────────────────────────

-- A row is "disabled" when something is already selected and this piece's trait
-- category doesn't match it — mixing categories would invalidate the trait dropdown.
local function PieceIsDisabled(data)
    if not lastSelectedPiece then return false end
    if selectedPieces[data.pieceId] then return false end
    return data.traitCategory ~= lastSelectedPiece.traitCategory
end

function TSC.SetupInventoryRow(ctrl, data)
    ctrl.data = data

    local iconCtrl = ctrl:GetNamedChild("Icon")
    local nameLbl  = ctrl:GetNamedChild("Name")
    iconCtrl:SetTexture(data.pieceIcon)
    nameLbl:SetText(data.pieceName)

    if PieceIsDisabled(data) then
        nameLbl:SetColor(0.4, 0.4, 0.4, 1)
        iconCtrl:SetColor(1, 1, 1, 0.35)
    else
        nameLbl:SetColor(0.463, 0.737, 0.765, 1)  -- 76BCC3
        iconCtrl:SetColor(1, 1, 1, 1)
    end

    ctrl:GetNamedChild("Highlight"):SetAlpha(0)
    ctrl:GetNamedChild("SelectionBG"):SetAlpha(selectedPieces[data.pieceId] and 0.55 or 0)
end

function TSC.OnInventoryRowMouseEnter(ctrl)
    if not ctrl.data then return end
    if not PieceIsDisabled(ctrl.data) then
        ctrl:GetNamedChild("Highlight"):SetAlpha(0.2)
    end
end

function TSC.OnInventoryRowMouseExit(ctrl)
    if ctrl.data then
        ctrl:GetNamedChild("Highlight"):SetAlpha(0)
    end
end

function TSC.OnInventoryRowClick(ctrl, button, upInside)
    if not upInside or not ctrl.data then return end
    if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
    if PieceIsDisabled(ctrl.data) then return end

    -- Auto-cancel any ongoing edit when starting a new selection
    if editingQueueIndex then
        TSC.CancelEdit()
    end

    local pieceId = ctrl.data.pieceId

    if selectedPieces[pieceId] then
        -- Deselect this piece
        selectedPieces[pieceId] = nil

        if lastSelectedPiece and lastSelectedPiece.pieceId == pieceId then
            lastSelectedPiece = nil
            for _, data in pairs(selectedPieces) do
                lastSelectedPiece = data
                break
            end
            if lastSelectedPiece then
                -- Re-populate for the new lead piece, preserving the user's choices
                TSC.PopulateTraitDropdown(lastSelectedPiece, selectedTrait)
                TSC.PopulateEnchantDropdown(lastSelectedPiece,
                    (selectedEnchant ~= "" and selectedEnchant) or nil)
            end
            -- If everything is now deselected, leave dropdowns + selections intact
            -- so the next pick can reuse them (within the same category).
        end
    else
        -- Select this piece
        local newCategory      = ctrl.data.traitCategory
        local categoryChanged  = (lastUsedCategory ~= nil and lastUsedCategory ~= newCategory)
        local firstEverSession = (lastUsedCategory == nil)

        selectedPieces[pieceId] = ctrl.data
        lastSelectedPiece       = ctrl.data

        if categoryChanged then
            -- Category changed — previous trait + enchant choices are no longer valid
            selectedTrait   = nil
            selectedEnchant = ""
        end

        -- Repopulate trait + enchant for this piece (preserves selection where possible
        -- and refreshes "(not researched)" labels which can differ between pieces).
        TSC.PopulateTraitDropdown(ctrl.data, selectedTrait)
        TSC.PopulateEnchantDropdown(ctrl.data,
            (selectedEnchant ~= "" and selectedEnchant) or nil)

        -- Quality dropdowns aren't category-dependent — populate once per session
        if firstEverSession then
            TSC.PopulateQualityDropdown(selectedQuality)
            TSC.PopulateEnchantQualityDropdown(selectedEnchantQuality)
        end

        lastUsedCategory = newCategory
    end

    TSC.RefreshInventoryList()
    TSC.UpdateAddButton()
    TSC.UpdateTransmuteButton()
end

-- ── Inventory header (back to sets) ───────────────────────

function TSC.OnInventoryHeaderClick()
    if browsingMode == "pieces" then TSC.BackToSets() end
end

function TSC.OnInventoryHeaderMouseEnter(ctrl)
    if browsingMode == "pieces" then ctrl:SetColor(1, 1, 0.4, 1) end
end

function TSC.OnInventoryHeaderMouseExit(ctrl)
    if browsingMode == "pieces" then
        ctrl:SetColor(0.46, 0.74, 0.76, 1)
    else
        ctrl:SetColor(1, 1, 1, 1)
    end
end

function TSC.BackToSets()
    browsingMode = "sets"
    selectedSet  = nil
    ClearPieceSelection()
    TSC.RefreshInventoryList()
    TSC.UpdateAddButton()
    TSC.UpdateTransmuteButton()
end

-- ── Trait dropdown ─────────────────────────────────────────

function TSC.PopulateTraitDropdown(itemData, preselectTrait)
    if not traitComboBox then return end
    traitComboBox:ClearItems()
    selectedTrait = nil

    local prompt = traitComboBox:CreateItemEntry(
                       GetString(SI_TSC_SELECT_TRAIT_PROMPT), function() selectedTrait = nil end)
    traitComboBox:AddItem(prompt)
    traitComboBox:SelectFirstItem()

    local pieceId       = itemData.pieceId
    local pieceTraitCat = itemData.traitCategory
    local allTraits     = ZO_CraftingUtils_GetSmithingTraitItemInfo()

    local preselectEntry = nil
    for _, traitData in ipairs(allTraits) do
        local traitCat  = GetItemTraitTypeCategory(traitData.type)
        local isNoTrait = traitData.type == ITEM_TRAIT_TYPE_NONE
        if isNoTrait or pieceTraitCat == traitCat then
            local known = IsTraitKnownForItem(pieceId, traitData.type)
            local label = GetString("SI_ITEMTRAITTYPE", traitData.type)
            if not known and not isNoTrait then
                label = label .. GetString(SI_TSC_TRAIT_NOT_RESEARCHED)
            end
            local capturedTrait = traitData.type
            local entry = traitComboBox:CreateItemEntry(label, function()
                selectedTrait = capturedTrait
                TSC.UpdateTransmuteButton()
            end)
            traitComboBox:AddItem(entry)
            if preselectTrait and traitData.type == preselectTrait then
                preselectEntry = entry
            end
        end
    end

    if preselectEntry then
        traitComboBox:SelectItem(preselectEntry)
        selectedTrait = preselectTrait
    end
end

-- ── Quality dropdown ───────────────────────────────────────

function TSC.PopulateQualityDropdown(preselectQuality)
    if not qualityComboBox then return end
    qualityComboBox:ClearItems()
    local target = preselectQuality or ITEM_FUNCTIONAL_QUALITY_ARTIFACT
    selectedQuality = target

    local targetEntry = nil
    for quality = ITEM_FUNCTIONAL_QUALITY_NORMAL, ITEM_FUNCTIONAL_QUALITY_LEGENDARY do
        local label           = GetString("SI_ITEMQUALITY", quality)
        local capturedQuality = quality
        local entry = qualityComboBox:CreateItemEntry(label, function()
            selectedQuality = capturedQuality
            TSC.UpdateTransmuteButton()
        end)
        qualityComboBox:AddItem(entry)
        if quality == target then
            targetEntry = entry
        end
    end

    if targetEntry then
        qualityComboBox:SelectItem(targetEntry)
    end
end

-- ── Enchantment quality dropdown ──────────────────────────

function TSC.PopulateEnchantQualityDropdown(preselectQuality)
    if not enchantQualityComboBox then return end
    enchantQualityComboBox:ClearItems()
    local target = preselectQuality or ITEM_FUNCTIONAL_QUALITY_LEGENDARY
    selectedEnchantQuality = target

    local targetEntry = nil
    for quality = ITEM_FUNCTIONAL_QUALITY_NORMAL, ITEM_FUNCTIONAL_QUALITY_LEGENDARY do
        local label    = GetString("SI_ITEMQUALITY", quality)
        local captured = quality
        local entry    = enchantQualityComboBox:CreateItemEntry(label, function()
            selectedEnchantQuality = captured
        end)
        enchantQualityComboBox:AddItem(entry)
        if quality == target then
            targetEntry = entry
        end
    end

    if targetEntry then
        enchantQualityComboBox:SelectItem(targetEntry)
    end
end

-- ── Enchantment dropdown ──────────────────────────────────

function TSC.PopulateEnchantDropdown(itemData, preselectName)
    if not enchantComboBox then return end
    enchantComboBox:ClearItems()
    selectedEnchant = ""

    local noneEntry = enchantComboBox:CreateItemEntry("(none)", function()
        selectedEnchant = ""
    end)
    enchantComboBox:AddItem(noneEntry)
    enchantComboBox:SelectFirstItem()

    local preselectEntry = nil
    for _, name in ipairs(GetEnchantmentsForCategory(itemData.traitCategory)) do
        local captured = name
        local entry = enchantComboBox:CreateItemEntry(name, function()
            selectedEnchant = captured
        end)
        enchantComboBox:AddItem(entry)
        if preselectName and preselectName ~= "" and name == preselectName then
            preselectEntry = entry
        end
    end

    if preselectEntry then
        enchantComboBox:SelectItem(preselectEntry)
        selectedEnchant = preselectName
    end
end

-- ── Search ─────────────────────────────────────────────────

function TSC.OnSearchTextChanged(editBox)
    searchText = editBox:GetText() or ""
    if browsingMode == "sets" then
        TSC.RefreshInventoryList()
    end
end

-- ── Queue list ─────────────────────────────────────────────

function TSC.RefreshQueueList()
    local qList    = TransmuteSetCrafterWindowQueueList
    ZO_ScrollList_Clear(qList)
    local dataList = ZO_ScrollList_GetDataList(qList)

    for i, entry in ipairs(TSC.queue) do
        table.insert(dataList, ZO_ScrollList_CreateDataEntry(QUEUE_ENTRY, {
            queueIndex     = i,
            pieceId        = entry.pieceId,
            setName        = entry.setName,
            pieceType      = entry.pieceType   or "",
            traitName      = entry.traitName,
            quality        = entry.quality,
            qualityName    = entry.qualityName,
            enchantment    = entry.enchantment or "",
            enchantQuality = entry.enchantQuality or ITEM_FUNCTIONAL_QUALITY_LEGENDARY,
            status         = entry.status or "pending",
        }))
    end

    ZO_ScrollList_Commit(qList)
    TSC.UpdateTransmuteButton()
end

function TSC.OnQueueRowMouseEnter(ctrl)
    if not ctrl.data then return end
    ctrl:GetNamedChild("Highlight"):SetAlpha(0.2)
    if not ctrl.data.pieceId then return end
    local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(ctrl.data.pieceId)
    if pieceData then
        InitializeTooltip(ItemTooltip, ctrl, LEFT, -5, 0)
        ItemTooltip:SetItemSetCollectionPieceLink(pieceData:GetItemLink(), HIDE_TRAIT)
    end
end

function TSC.OnQueueRowMouseExit(ctrl)
    if ctrl.data then
        ctrl:GetNamedChild("Highlight"):SetAlpha(0)
        ClearTooltip(ItemTooltip)
    end
end

function TSC.SetupQueueRow(ctrl, data)
    ctrl.data = data
    local quality = data.quality or ITEM_FUNCTIONAL_QUALITY_ARTIFACT
    local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, quality)
    if not r then r, g, b = 1, 1, 1 end

    -- Match row width to current list width and reflow columns proportionally
    local qList = TransmuteSetCrafterWindowQueueList
    local listW = (qList and qList:GetWidth()) or 500
    local rowWidth = listW - QUEUE_SCROLLBAR
    if rowWidth < 200 then rowWidth = 488 end
    ctrl:SetWidth(rowWidth)

    local layout     = ComputeQueueColumnLayout(rowWidth)
    local setNameLbl = ctrl:GetNamedChild("SetName")
    local typeLbl    = ctrl:GetNamedChild("Type")
    local traitLbl   = ctrl:GetNamedChild("Trait")
    local enchantLbl = ctrl:GetNamedChild("Enchant")

    PlaceQueueCol(setNameLbl, ctrl, layout.setName.x, layout.setName.w)
    PlaceQueueCol(typeLbl,    ctrl, layout.type.x,    layout.type.w)
    PlaceQueueCol(traitLbl,   ctrl, layout.trait.x,   layout.trait.w)
    PlaceQueueCol(enchantLbl, ctrl, layout.enchant.x, layout.enchant.w)

    setNameLbl:SetText(data.setName or "")
    setNameLbl:SetColor(r, g, b, 1)
    typeLbl:SetText(data.pieceType or "")
    traitLbl:SetText(data.traitName or "")

    local enchantText = data.enchantment or ""
    if data.status == "needs_enchant" and enchantText ~= "" then
        enchantText = enchantText .. " (missing)"
    end
    enchantLbl:SetText(enchantText)
    if data.enchantment and data.enchantment ~= "" then
        local eq = data.enchantQuality or ITEM_FUNCTIONAL_QUALITY_LEGENDARY
        local er, eg, eb = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, eq)
        if not er then er, eg, eb = 0.463, 0.737, 0.765 end
        enchantLbl:SetColor(er, eg, eb, 1)
    else
        enchantLbl:SetColor(0.463, 0.737, 0.765, 1)  -- default cyan-blue when blank
    end

    ctrl:GetNamedChild("Highlight"):SetAlpha(0)
    ctrl:GetNamedChild("Edit"):SetText("Edit")
end

-- ── Add button state ───────────────────────────────────────

function TSC.UpdateAddButton()
    local label
    if editingQueueIndex then
        label = "Update Entry"
    else
        local count = SelectedPieceCount()
        if count > 1 then
            label = zo_strformat(SI_TSC_ADD_COUNT_TO_QUEUE, count)
        else
            label = GetString(SI_TSC_ADD_TO_QUEUE)
        end
    end
    TransmuteSetCrafterWindowAddToQueueButton:SetText(label)
    TransmuteSetCrafterWindowCancelEditButton:SetHidden(editingQueueIndex == nil)
end

-- ── "Add Selected to Queue" / "Update Entry" ──────────────

function TSC.AddSelectedToQueue()
    -- Edit mode: update the existing entry instead of adding a new one
    if editingQueueIndex then
        if not selectedTrait then
            d("[TSC] No target trait selected.")
            return
        end
        if not selectedQuality then
            d("[TSC] No quality selected.")
            return
        end
        TSC.UpdateQueueEntry(editingQueueIndex, selectedTrait, selectedQuality,
                             selectedEnchant, selectedEnchantQuality)
        ClearPieceSelection()
        TSC.UpdateAddButton()
        TSC.UpdateTransmuteButton()
        return
    end

    -- Normal mode: add selected pieces to queue
    if not next(selectedPieces) then
        d("[TSC] No pieces selected.")
        return
    end
    if not selectedTrait then
        d("[TSC] No target trait selected.")
        return
    end
    if not selectedQuality then
        d("[TSC] No quality selected.")
        return
    end
    for pieceId in pairs(selectedPieces) do
        TSC.AddToQueue(pieceId, selectedTrait, selectedQuality, selectedEnchant, selectedEnchantQuality)
    end
    ClearSelectedPiecesKeepDropdowns()
    TSC.RefreshInventoryList()
    TSC.UpdateAddButton()
    TSC.UpdateTransmuteButton()
end

-- ── Cancel Edit ────────────────────────────────────────────

function TSC.CancelEdit()
    if not editingQueueIndex then return end
    ClearPieceSelection()      -- resets editingQueueIndex and all dropdowns
    TSC.UpdateAddButton()      -- restores "Add to Queue" label, hides Cancel button
    TSC.RefreshInventoryList() -- restore normal row appearance
end

-- ── Edit Queue Row ─────────────────────────────────────────

function TSC.EditQueueRow(ctrl)
    if not ctrl or not ctrl.data or not ctrl.data.queueIndex then return end
    local queueIndex = ctrl.data.queueIndex
    local entry      = TSC.queue[queueIndex]
    if not entry then return end

    local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(entry.pieceId)
    if not pieceData then
        d("[TSC] Item set piece no longer available — cannot edit.")
        return
    end

    -- Reset any current piece selection before entering edit mode
    ClearPieceSelection()
    editingQueueIndex = queueIndex

    -- Repopulate dropdowns with the row's current values preselected
    local itemData = {
        pieceId       = entry.pieceId,
        traitCategory = pieceData:GetTraitCategory(),
    }
    TSC.PopulateTraitDropdown(itemData, entry.traitType)
    TSC.PopulateEnchantDropdown(itemData, entry.enchantment)
    TSC.PopulateQualityDropdown(entry.quality)
    TSC.PopulateEnchantQualityDropdown(entry.enchantQuality)

    TSC.UpdateAddButton()
    TSC.RefreshInventoryList()  -- inventory rows reflect lack of selection
end

-- ── Cost display ───────────────────────────────────────────

-- ── Materials lookup helpers ─────────────────────────────
-- Quality-tier improvement counts assuming max improvement skill (typical end
-- game). Index 1=white→green, 2=green→blue, 3=blue→purple, 4=purple→gold.

local IMPROVEMENT_COUNTS = { 2, 3, 4, 8 }

local function GetItemNameById(itemId)
    if not itemId then return nil end
    local link = string.format("|H1:item:%d:30:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", itemId)
    local name = GetItemLinkName(link)
    if not name or name == "" then return nil end
    return name
end

-- Sum the player's stock of an item across backpack, bank, subscriber bank, and craft bag.
local function CountItemAvailable(itemId)
    if not itemId or itemId == 0 then return 0 end
    local link = string.format("|H1:item:%d:30:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", itemId)
    local bag, bank, craft = GetItemLinkStacks(link)
    return (bag or 0) + (bank or 0) + (craft or 0)
end

local function GetImprovementMaterialId(craftType, tier)
    local link = GetSmithingImprovementItemLink(craftType, tier, LINK_STYLE_DEFAULT)
    if not link or link == "" then return nil end
    local id = GetItemLinkItemId(link)
    if id == 0 then return nil end
    return id
end

-- Public: returns { {name, needed, have, sortKey}, ... } describing every
-- material needed for the queue, including transmute crystals, glyph runes
-- (via LLC), and item-upgrade materials (via GetSmithingImprovementItemLink).
function TSC.GetCostBreakdown()
    local rows = {}

    -- Transmute crystals
    local crystalCost  = TSC.GetTotalCrystalCost()
    local currencyType = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetReconstructionCurrencyOptionType(1)
                         or CURT_TRANSMUTE_CRYSTALS
    local location     = GetCurrencyPlayerStoredLocation(currencyType)
    local crystalAvail = GetCurrencyAmount(currencyType, location)
    table.insert(rows, {
        name    = "Transmute Crystals",
        needed  = crystalCost,
        have    = crystalAvail,
        sortKey = "0_crystals",
    })

    -- Glyph runes (only if LLC is available)
    if TSC.GetGlyphRuneCounts then
        local runeCounts = TSC.GetGlyphRuneCounts()
        for itemId, needed in pairs(runeCounts) do
            local name = GetItemNameById(itemId) or ("Rune " .. itemId)
            table.insert(rows, {
                name    = name,
                needed  = needed,
                have    = CountItemAvailable(itemId),
                sortKey = "1_" .. name,
            })
        end
    end

    -- Improvement (upgrade) materials per item using ESO's canonical itemIds
    local matCounts = {}
    for _, entry in ipairs(TSC.queue) do
        local quality = entry.quality
        if quality and quality > ITEM_FUNCTIONAL_QUALITY_NORMAL then
            local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(entry.pieceId)
            if pieceData then
                local craftType = GetItemLinkCraftingSkillType(pieceData:GetItemLink())
                for tier = 1, quality - 1 do
                    local matId = GetImprovementMaterialId(craftType, tier)
                    if matId then
                        matCounts[matId] = (matCounts[matId] or 0) + IMPROVEMENT_COUNTS[tier]
                    end
                end
            end
        end
    end
    for itemId, needed in pairs(matCounts) do
        local name = GetItemNameById(itemId) or ("Material " .. itemId)
        table.insert(rows, {
            name    = name,
            needed  = needed,
            have    = CountItemAvailable(itemId),
            sortKey = "2_" .. name,
        })
    end

    table.sort(rows, function(a, b) return a.sortKey < b.sortKey end)
    return rows
end

function TSC.SetupCostRow(ctrl, data)
    ctrl.data = data

    -- Track the list width so the row's right-anchored Have/Needed columns
    -- end up at the right edge of the visible area and Name stretches to fill.
    local list = TransmuteSetCrafterCostWindowList
    if list then
        local rowWidth = list:GetWidth() - 18  -- scrollbar
        if rowWidth > 200 then
            ctrl:SetWidth(rowWidth)
        end
    end

    local nameLbl   = ctrl:GetNamedChild("Name")
    local neededLbl = ctrl:GetNamedChild("Needed")
    local haveLbl   = ctrl:GetNamedChild("Have")
    nameLbl:SetText(data.name)
    neededLbl:SetText(tostring(data.needed))
    haveLbl:SetText(tostring(data.have))

    local r, g, b
    if data.have >= data.needed then
        r, g, b = 0.55, 0.95, 0.55  -- enough — light green
    else
        r, g, b = 1.0, 0.45, 0.45   -- short — light red
    end
    nameLbl:SetColor(r, g, b, 1)
    neededLbl:SetColor(r, g, b, 1)
    haveLbl:SetColor(r, g, b, 1)
end

function TSC.RefreshCostPanel()
    local list = TransmuteSetCrafterCostWindowList
    if not list then return end
    ZO_ScrollList_Clear(list)
    local dataList = ZO_ScrollList_GetDataList(list)
    for _, row in ipairs(TSC.GetCostBreakdown()) do
        table.insert(dataList, ZO_ScrollList_CreateDataEntry(COST_ENTRY, row))
    end
    ZO_ScrollList_Commit(list)
end

function TSC.UpdateCostDisplay()
    local cost         = TSC.GetTotalCrystalCost()
    local currencyType = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetReconstructionCurrencyOptionType(1)
                         or CURT_TRANSMUTE_CRYSTALS
    local location     = GetCurrencyPlayerStoredLocation(currencyType)
    local available    = GetCurrencyAmount(currencyType, location)
    TransmuteSetCrafterWindowCostLabel:SetText(zo_strformat(SI_TSC_CRYSTALS_COST, cost, available))
    TSC.RefreshCostPanel()
end

-- ── Transmute / Clear buttons ──────────────────────────────

function TSC.UpdateTransmuteButton()
    local pending = TSC.GetPendingCount()
    TransmuteSetCrafterWindowTransmuteButton:SetText(
        zo_strformat(SI_TSC_TRANSMUTE_ALL, pending))
    TransmuteSetCrafterWindowTransmuteButton:SetEnabled(pending > 0)
end

-- ── Dirty event ────────────────────────────────────────────

local function OnCollectionsUpdated()
    if not TransmuteSetCrafterWindow:IsHidden() then
        TSC.RefreshInventoryList()
    end
end

EVENT_MANAGER:RegisterForEvent(
    ADDON_NAME .. "_UI", EVENT_ITEM_SET_COLLECTIONS_UPDATED, OnCollectionsUpdated)
