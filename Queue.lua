-- Transmute Set Crafter — Queue management and execution
--
-- A queue entry is:
--   { pieceId, pieceName, setName, pieceIcon,
--     traitType, traitName, quality, qualityName,
--     crystalCost, currencyType }

local TSC = TransmuteSetCrafter
local ADDON_NAME = TSC.name

-- ── Queue state ────────────────────────────────────────────

TSC.queue = TSC.queue or {}
local processingQueue = false
local processingIndex = nil

-- ── Helpers: derive display strings from pieceData ────────

local function GetPieceType(pieceData)
    local link       = pieceData:GetItemLink()
    local weaponType = GetItemLinkWeaponType(link)
    if weaponType ~= WEAPONTYPE_NONE then
        return GetString("SI_WEAPONTYPE", weaponType)
    end
    local equipType = GetItemLinkEquipType(link)
    if not equipType or equipType == EQUIP_TYPE_INVALID then
        return ""
    end
    local typeName  = GetString("SI_EQUIPTYPE", equipType)
    local armorType = GetItemLinkArmorType(link)
    if     armorType == ARMORTYPE_LIGHT  then return typeName .. " (L)"
    elseif armorType == ARMORTYPE_MEDIUM then return typeName .. " (M)"
    elseif armorType == ARMORTYPE_HEAVY  then return typeName .. " (H)"
    end
    return typeName
end

-- ── Public: Add a piece to the queue ──────────────────────

function TSC.AddToQueue(pieceId, traitType, quality, enchantment, enchantQuality)
    local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(pieceId)
    if not pieceData then return end

    local setData      = pieceData:GetItemSetCollectionData()
    local currencyType = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetReconstructionCurrencyOptionType(1)
                         or CURT_TRANSMUTE_CRYSTALS
    local crystalCost  = setData:GetReconstructionCurrencyOptionCost(currencyType)

    local entry = {
        pieceId        = pieceId,
        pieceName      = pieceData:GetFormattedName(),
        pieceType      = GetPieceType(pieceData),
        setName        = setData and setData:GetFormattedName() or "",
        pieceIcon      = pieceData:GetIcon(),
        traitType      = traitType,
        traitName      = GetString("SI_ITEMTRAITTYPE", traitType),
        quality        = quality,
        qualityName    = GetString("SI_ITEMQUALITY", quality),
        enchantment    = enchantment or "",
        enchantQuality = enchantQuality or ITEM_FUNCTIONAL_QUALITY_LEGENDARY,
        crystalCost    = crystalCost,
        currencyType   = currencyType,
        status         = "pending",  -- "pending" or "needs_enchant"
    }
    table.insert(TSC.queue, entry)
    TSC.savedVars.queue = TSC.queue

    TSC.RefreshQueueList()
    TSC.UpdateCostDisplay()
end

-- ── Public: Update existing queue entry in place ──────────

function TSC.UpdateQueueEntry(index, traitType, quality, enchantment, enchantQuality)
    local entry = TSC.queue[index]
    if not entry then return end

    entry.traitType      = traitType
    entry.traitName      = GetString("SI_ITEMTRAITTYPE", traitType)
    entry.quality        = quality
    entry.qualityName    = GetString("SI_ITEMQUALITY", quality)
    entry.enchantment    = enchantment or ""
    entry.enchantQuality = enchantQuality or ITEM_FUNCTIONAL_QUALITY_LEGENDARY

    TSC.savedVars.queue = TSC.queue
    TSC.RefreshQueueList()
    TSC.UpdateCostDisplay()
end

-- ── Public: Remove by queue index ──────────────────────────

function TSC.RemoveFromQueue(index)
    if TSC.queue[index] then
        table.remove(TSC.queue, index)
        TSC.savedVars.queue = TSC.queue
        TSC.RefreshQueueList()
        TSC.UpdateCostDisplay()
    end
end

-- ── Public: Remove via row control ─────────────────────────

function TSC.RemoveQueueRow(rowControl)
    if rowControl and rowControl.data then
        TSC.RemoveFromQueue(rowControl.data.queueIndex)
    end
end

-- ── Public: Clear entire queue ─────────────────────────────

function TSC.ClearQueue()
    TSC.queue = {}
    TSC.savedVars.queue = TSC.queue
    processingQueue = false
    processingIndex = nil
    TSC.RefreshQueueList()
    TSC.UpdateCostDisplay()
end

-- ── Public: Total crystal cost ─────────────────────────────

function TSC.GetTotalCrystalCost()
    local total = 0
    for _, entry in ipairs(TSC.queue) do
        if entry.status ~= "needs_enchant" then
            total = total + (entry.crystalCost or 0)
        end
    end
    return total
end

function TSC.GetPendingCount()
    local n = 0
    for _, entry in ipairs(TSC.queue) do
        if entry.status ~= "needs_enchant" then
            n = n + 1
        end
    end
    return n
end

-- ── Public: Execute queue ──────────────────────────────────

function TSC.ExecuteQueue()
    if not ZO_RETRAIT_STATION_MANAGER or
       not ZO_RETRAIT_STATION_MANAGER:IsReconstructFragmentShowing() then
        d(GetString(SI_TSC_NOT_AT_STATION))
        return
    end

    if TSC.GetPendingCount() == 0 then
        d(GetString(SI_TSC_EMPTY_QUEUE))
        return
    end

    local cost         = TSC.GetTotalCrystalCost()
    local currencyType = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetReconstructionCurrencyOptionType(1)
                         or CURT_TRANSMUTE_CRYSTALS
    local location     = GetCurrencyPlayerStoredLocation(currencyType)
    local available    = GetCurrencyAmount(currencyType, location)
    if cost > available then
        d(zo_strformat(SI_TSC_INSUFFICIENT_CRYSTALS, cost, available))
        return
    end

    processingQueue = true
    processingIndex = 1
    TSC.ProcessNextQueueEntry()
end

-- ── Internal: Process one entry ────────────────────────────

function TSC.ProcessNextQueueEntry()
    if not processingQueue then return end

    -- Walk forward, skipping already-reconstructed (needs_enchant) entries,
    -- pruning any whose source piece has gone missing, and stop at the first
    -- pending entry to request a reconstruction.
    while processingIndex <= #TSC.queue do
        local entry = TSC.queue[processingIndex]
        if entry and entry.status ~= "needs_enchant" then
            local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(entry.pieceId)
            if not pieceData then
                d(zo_strformat(SI_TSC_ITEM_NOT_FOUND, entry.pieceName))
                table.remove(TSC.queue, processingIndex)
                TSC.savedVars.queue = TSC.queue
                TSC.RefreshQueueList()
                TSC.UpdateCostDisplay()
                -- index now points at what was the next entry; loop continues
            else
                RequestItemReconstruction(entry.pieceId, entry.traitType, entry.quality, entry.currencyType)
                return  -- wait for OnReconstructResponse
            end
        else
            processingIndex = processingIndex + 1
        end
    end

    -- No more pending entries
    processingQueue = false
    processingIndex = nil
    d("[TSC] All reconstructions complete.")
    TSC.UpdateTransmuteButton()
end

-- ── Event: Reconstruct response ────────────────────────────

local function OnReconstructResponse(_, result)
    if not processingQueue then return end

    if result == RECONSTRUCT_RESPONSE_SUCCESS then
        local entry = TSC.queue[processingIndex]
        if entry and entry.enchantment and entry.enchantment ~= "" then
            -- Reconstruction done; entry stays in queue until glyph is applied
            entry.status = "needs_enchant"
            processingIndex = processingIndex + 1
        else
            -- No enchant planned, entry is fully complete
            table.remove(TSC.queue, processingIndex)
            -- processingIndex now points at the next entry due to the shift
        end
        TSC.savedVars.queue = TSC.queue
        TSC.RefreshQueueList()
        TSC.UpdateCostDisplay()
        TSC.UpdateTransmuteButton()
        zo_callLater(function() TSC.ProcessNextQueueEntry() end, 200)
    else
        local errStr = GetString("SI_RECONSTRUCTRESPONSE", result)
        d(zo_strformat(SI_TSC_TRANSMUTE_FAILED, errStr))
        processingQueue = false
        processingIndex = nil
    end
end

EVENT_MANAGER:RegisterForEvent(
    ADDON_NAME .. "_Queue",
    EVENT_RECONSTRUCT_RESPONSE,
    OnReconstructResponse
)

-- ── Restore queue from saved vars ──────────────────────────

function TSC.RestoreQueue()
    TSC.queue = TSC.savedVars.queue or {}
    local cleaned = {}
    for _, entry in ipairs(TSC.queue) do
        local pieceData = ITEM_SET_COLLECTIONS_DATA_MANAGER:GetItemSetCollectionPieceData(entry.pieceId)
        if pieceData then
            entry.pieceName   = pieceData:GetFormattedName()
            entry.pieceType   = GetPieceType(pieceData)
            entry.pieceWeight = nil  -- field removed; clear stale saved value
            entry.status      = entry.status or "pending"
            table.insert(cleaned, entry)
        end
    end
    TSC.queue = cleaned
    TSC.savedVars.queue = TSC.queue
end
