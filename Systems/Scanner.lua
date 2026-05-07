local AddonName, Addon = ...
Addon.Scanner = Addon.Scanner or {}

local NUM_AUCTION_ITEMS_PER_PAGE = 50
local QUERY_ATTEMPT_WAIT_TIME = 0.1 -- seconds
local GET_ALL_SAFETY_THRESHOLD = 200 -- anything above this is definitely not a normal browse page
local PROCESS_RESULTS_DELAY = 0.35
local TRACKED_PAGE_MATCH_MAX_RETRIES = 12
local QUERY_READY_MAX_RETRIES = 300

Addon.scanSession = {
    active = false,
    mode = nil, -- "full", "item", "tracked", "getall"
    searchText = nil,
    currentPage = 0,
    pageCount = 0,
    numUpdates = 0,
    scanID = 0,
    trackedItemsSearchingIndex = 0,
    trackedItemsList = nil,
    trackedListKey = nil,
    trackedScanDisplayName = nil,
    trackedScanTarget = nil,
    trackedScanQueue = nil,
    trackedScanQueueIndex = 0,
    trackedPageMatchRetries = 0,
    pendingProcessToken = 0,
    queryWaitToken = 0,
    getAllPass = 0,
    getAllDebug = nil,
    processedAuctions = 0,
}

function Addon.Scanner.IsScanActive()
    return Addon.scanSession.active
end

function Addon.Scanner.IsExactMatchMode(mode)
    return mode == "item" or mode == "tracked"
end

function Addon.Scanner.IsSessionCurrent(scanId)
    return Addon.scanSession.active and Addon.scanSession.scanID == scanId
end

function Addon.Scanner.ResetScanSession()
    Addon.scanSession.active = false
    Addon.scanSession.mode = nil
    Addon.scanSession.searchText = nil
    Addon.scanSession.currentPage = 0
    Addon.scanSession.pageCount = 0
    Addon.scanSession.numUpdates = 0
    Addon.scanSession.scanID = (Addon.scanSession.scanID or 0) + 1
    Addon.scanSession.trackedItemsSearchingIndex = 0
    Addon.scanSession.trackedItemsList = nil
    Addon.scanSession.trackedListKey = nil
    Addon.scanSession.trackedScanDisplayName = nil
    Addon.scanSession.trackedScanTarget = nil
    Addon.scanSession.trackedScanQueue = nil
    Addon.scanSession.trackedScanQueueIndex = 0
    Addon.scanSession.trackedPageMatchRetries = 0
    Addon.scanSession.pendingProcessToken = 0
    Addon.scanSession.getAllPass = 0
    Addon.scanSession.getAllDebug = nil
    Addon.scanSession.processedAuctions = 0
    Addon.scanSession.queryWaitToken = 0
end

function Addon.Scanner.GetAuctionCounts()
    local batchCount, totalCount = GetNumAuctionItems("list")
    batchCount = batchCount or 0
    totalCount = totalCount or 0
    return batchCount, totalCount
end

function Addon.Scanner.IsLikelyGetAllResult()
    local batchCount, totalCount = Addon.Scanner.GetAuctionCounts()

    if batchCount <= 0 then
        return false
    end

    if batchCount > GET_ALL_SAFETY_THRESHOLD then
        return true
    end

    if totalCount > GET_ALL_SAFETY_THRESHOLD and batchCount == totalCount then
        return true
    end

    return false
end

function Addon.Scanner.CanAutoScanCurrentResults()
    if Addon.Scanner.IsScanActive() then
        return false
    end

    if Addon.Scanner.IsLikelyGetAllResult() then
        return false
    end

    return true
end

function Addon.Scanner.IsQueryWaitCurrent(scanId, queryWaitToken)
    return Addon.Scanner.IsSessionCurrent(scanId)
        and Addon.scanSession.queryWaitToken == queryWaitToken
end

function Addon.Scanner.CanStartQuery(mode)
    if not CanSendAuctionQuery then
        return false, "Auction query API is unavailable."
    end

    local canQuery, canQueryAll = CanSendAuctionQuery()

    if mode == "getall" then
        if not canQueryAll then
            return false, "Fast Full Scan is not ready yet. Try again shortly."
        end
    else
        if not canQuery then
            return false, "Auction query is not ready yet. Try again shortly."
        end
    end

    return true
end

function Addon.Scanner.GetAuctionData(index)
    local name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner =
        GetAuctionItemInfo("list", index)
    local itemLink = GetAuctionItemLink("list", index)
    local itemID = itemLink and Addon.Utils.GetItemIdFromLink(itemLink)
    local recordKey = itemID and Addon.DB.GetRecordKey and Addon.DB.GetRecordKey(itemID, name, itemLink) or itemID

    local pricePerUnit = (buyoutPrice and count and count > 0) and math.floor(buyoutPrice / count) or nil

    return {
        name = name,
        texture = texture,
        count = count,
        quality = quality,
        canUse = canUse,
        level = level,
        levelColHeader = levelColHeader,
        minBid = minBid,
        minIncrement = minIncrement,
        buyoutPrice = buyoutPrice,
        bidAmount = bidAmount,
        highBidder = highBidder,
        owner = owner,
        itemLink = itemLink,
        itemID = itemID,
        recordKey = recordKey,
        pricePerUnit = pricePerUnit,
    }
end

function Addon.Scanner.IsAuctionNewLowThisHour(auctionData)
    local price = auctionData.pricePerUnit

    local recordKey = auctionData and (auctionData.recordKey or auctionData.itemID)

    if not recordKey or not price or price <= 0 then
        return false
    end

    if not Addon.DB.IsItemRecordedThisHour(recordKey) then
        return true
    end

    local currentLow = Addon.DB.GetItemLowThisHour(recordKey)
    return currentLow == nil or price < currentLow
end

function Addon.Scanner.IsReasonableAuctionPrice(auctionData)
    local recordKey = auctionData and (auctionData.recordKey or auctionData.itemID)
    if not auctionData or not recordKey or not auctionData.pricePerUnit then
        return false
    end

    local robustMedian, mad, recordedLowCount = Addon.DB.GetRobustPriceStats(recordKey)

    -- Do not apply outlier filtering until we have enough history to make it meaningful.
    if not robustMedian or robustMedian <= 0 or recordedLowCount < 5 then
        return true
    end

    local threshold = 5.0

    if Addon.DB and Addon.DB.GetUnreasonablePriceMultiplier then
        threshold = Addon.DB.GetUnreasonablePriceMultiplier()
    end

    -- If MAD is zero, the history is extremely tight or flat.
    -- Fall back to a simple median-based cap so we do not divide by zero.
    if not mad or mad <= 0 then
        return auctionData.pricePerUnit <= (robustMedian * threshold)
    end

    -- Modified z-score style check using MAD.
    -- Values much higher than the recent robust center get treated as outliers.
    local robustScore = 0.6745 * (auctionData.pricePerUnit - robustMedian) / mad

    return robustScore <= threshold
end

function Addon.Scanner.ShouldProcessAuction(auctionData, debugStats)
    if not auctionData or not auctionData.itemID then
        return false
    end

    if not auctionData.pricePerUnit or auctionData.pricePerUnit <= 0 then
        return false
    end

    if not Addon.Scanner.IsReasonableAuctionPrice(auctionData) then
        if debugStats then
            debugStats.unreasonablePrice = (debugStats.unreasonablePrice or 0) + 1
        end
        return false
    end

    return true
end

function Addon.Scanner.ProcessAuctionForNewHourlyLow(auctionData)
    if not Addon.Scanner.ShouldProcessAuction(auctionData) then
        return false
    end

    if Addon.Scanner.IsAuctionNewLowThisHour(auctionData) then
        local recordKey = auctionData.recordKey or auctionData.itemID
        local historicalAvg = Addon.DB.GetHistoricalAverageLowPrice(recordKey)

        Addon.DB.UpdateItemLowThisHour(recordKey, auctionData.pricePerUnit, auctionData.name, auctionData.itemID)
        Addon.scanSession.numUpdates = Addon.scanSession.numUpdates + 1

        if Addon.UI and Addon.UI.SetLatestNewLowLine then
            Addon.UI.SetLatestNewLowLine(Addon.Scanner.BuildNewLowSummaryText(auctionData, historicalAvg))
        end

        return true
    end

    return false
end

function Addon.Scanner.BuildNewLowSummaryText(auctionData, historicalAvg)
    if not auctionData then
        return "New low recorded."
    end

    local itemText = auctionData.itemLink
        or Addon.Utils.GetItemDisplayNameByItemID(auctionData.itemID, auctionData.name or "Unknown Item")

    local priceText = Addon.Utils.FormatMoneyShort(auctionData.pricePerUnit)
    local avgText = historicalAvg and Addon.Utils.FormatMoneyShort(historicalAvg) or "n/a"
    local deltaText = "n/a"

    if historicalAvg then
        local deltaValue = Addon.Utils.GetPercentDiffFromAverage(auctionData.pricePerUnit, historicalAvg)
        local rawDeltaText = Addon.Utils.FormatPercentDiff(deltaValue)

        if deltaValue < 0 then
            deltaText = "|cff6aff6a" .. rawDeltaText .. "|r"
        elseif deltaValue > 0 then
            deltaText = "|cffff6666" .. rawDeltaText .. "|r"
        else
            deltaText = "|cffffcc66" .. rawDeltaText .. "|r"
        end
    end

    return string.format("%s at %s (avg %s, %s)", itemText, priceText, avgText, deltaText)
end

function Addon.Scanner.RunWhenQueryReady(callback, scanId, requireGetAll, queryWaitToken, attempt)
    if not Addon.Scanner.IsQueryWaitCurrent(scanId, queryWaitToken) then
        return
    end

    if not CanSendAuctionQuery then
        return
    end

    attempt = (attempt or 0) + 1

    local canQuery, canQueryAll = CanSendAuctionQuery()
    local isReady = requireGetAll and canQueryAll or canQuery

    if isReady then
        if Addon.Scanner.IsQueryWaitCurrent(scanId, queryWaitToken) then
            callback()
        end
        return
    end

    if attempt >= QUERY_READY_MAX_RETRIES then
        local mode = Addon.scanSession.mode
        local processedAuctions = Addon.scanSession.processedAuctions or 0
        local newLows = Addon.scanSession.numUpdates or 0

        if mode == "tracked" then
            local skippedItem = tostring(Addon.scanSession.searchText or "?")
            local listName = tostring(Addon.scanSession.trackedScanDisplayName or "Tracked Items")

            if Addon.UI and Addon.UI.AddScanEventLine then
                Addon.UI.AddScanEventLine(string.format(
                    "Skipped '%s' after waiting too long for query readiness.",
                    skippedItem
                ))
            end

            Addon.Utils.PrintError(string.format(
                "Tracked scan waited too long for Blizzard query readiness on '%s' in list '%s'. Skipping to the next item.",
                skippedItem,
                listName
            ))

            Addon.Scanner.AdvanceToNextTrackedItem()
            return
        end

        if Addon.UI and Addon.UI.UpdateScanSummaryLines then
            Addon.UI.UpdateScanSummaryLines({
                Addon.Scanner.GetModeSummaryLine(),
                "Status: Auction query timed out before Blizzard marked it ready",
                string.format("Processed auctions: %d", processedAuctions),
                string.format("Updates this scan: %d", newLows),
            })
        end

        if Addon.UI and Addon.UI.FinishScanSummary then
            Addon.UI.FinishScanSummary(Addon.Scanner.GetModeDisplayName(mode) .. " stopped because the auction query never became ready.")
        end

        Addon.Scanner.ResetScanSession()
        Addon.Utils.PrintError("Auction query never became ready. Scan stopped to avoid an infinite retry loop.")
        return
    end

    C_Timer.After(QUERY_ATTEMPT_WAIT_TIME, function()
        Addon.Scanner.RunWhenQueryReady(callback, scanId, requireGetAll, queryWaitToken, attempt)
    end)
end

function Addon.Scanner.SendCurrentScanQuery(scanId)
    if not Addon.Scanner.IsSessionCurrent(scanId) then
        return
    end

    local mode = Addon.scanSession.mode
    local requireGetAll = (mode == "getall")

    Addon.scanSession.queryWaitToken = (Addon.scanSession.queryWaitToken or 0) + 1
    local queryWaitToken = Addon.scanSession.queryWaitToken

    Addon.Scanner.RunWhenQueryReady(function()
        if not Addon.Scanner.IsQueryWaitCurrent(scanId, queryWaitToken) then
            return
        end

        if mode == "getall" then
            QueryAuctionItems("", nil, nil, 0, nil, 0, true, false)
            return
        end

        local exactMatch = Addon.Scanner.IsExactMatchMode(mode)
        QueryAuctionItems(
            Addon.scanSession.searchText,
            nil,
            nil,
            Addon.scanSession.currentPage,
            nil,
            0,
            false,
            exactMatch
        )
    end, scanId, requireGetAll, queryWaitToken)
end

function Addon.Scanner.ScanCurrentPage()
    local batchCount = GetNumAuctionItems("list") or 0
    Addon.scanSession.processedAuctions = (Addon.scanSession.processedAuctions or 0) + batchCount

    for i = 1, batchCount do
        local auctionData = Addon.Scanner.GetAuctionData(i)
        Addon.Scanner.ProcessAuctionForNewHourlyLow(auctionData)
    end
end

function Addon.Scanner.ScanAllResultsOnce()
    local batchCount = GetNumAuctionItems("list") or 0
    Addon.scanSession.getAllPass = (Addon.scanSession.getAllPass or 0) + 1
    Addon.scanSession.processedAuctions = batchCount

    Addon.Scanner.ResetGetAllDebugStats()

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        if Addon.UI.SetScanProgressText then
            Addon.UI.SetScanProgressText("Snapshot")
        end

        Addon.UI.UpdateScanSummaryLines({
            Addon.Scanner.GetModeSummaryLine(),
            "Status: Processing full auction snapshot...",
            string.format("Processed auctions: %d", batchCount),
            string.format("Updates this scan: %d", Addon.scanSession.numUpdates or 0),
        })
    else
        Addon.UI.RenderSummary(string.format(
            "%s\nStatus: Processing full auction snapshot...\nProcessed auctions: %d\nUpdates this scan: %d",
            Addon.Scanner.GetModeSummaryLine(),
            batchCount,
            Addon.scanSession.numUpdates or 0
        ))
    end

    local stats = Addon.scanSession.getAllDebug

    for i = 1, batchCount do
        local auctionData = Addon.Scanner.GetAuctionData(i)

        Addon.Scanner.DebugCountGetAllAuction(auctionData)

        if Addon.Scanner.ShouldProcessAuction(auctionData, stats) then
            local wasNewLow = Addon.Scanner.IsAuctionNewLowThisHour(auctionData)
            local recorded = Addon.Scanner.ProcessAuctionForNewHourlyLow(auctionData)

            if stats then
                stats.rowsProcessed = (stats.rowsProcessed or 0) + 1

                if wasNewLow and recorded then
                    stats.newLowsRecorded = (stats.newLowsRecorded or 0) + 1
                end
            end
        end
    end

    Addon.Scanner.PrintGetAllDebugSummary()
end

function Addon.Scanner.GetModeDisplayName(mode)
    mode = mode or Addon.scanSession.mode

    if mode == "item" then
        return "Single Item Scan"
    elseif mode == "tracked" then
        local target = Addon.scanSession.trackedScanTarget

        if target == "__all__" then
            return "List Scan (All Lists)"
        elseif target == "__all_no_requests__" then
            return "List Scan (All Except Requests)"
        end

        return "List Scan"
    elseif mode == "getall" then
        return "Fast Full Scan"
    elseif mode == "full" then
        return "Slow Full Scan"
    end

    return "Scan"
end

function Addon.Scanner.GetModeSummaryLine()
    return "Mode: " .. Addon.Scanner.GetModeDisplayName()
end

function Addon.Scanner.GetCompletionChatMessage(mode, processedAuctions, newLows)
    local modeName = Addon.Scanner.GetModeDisplayName(mode)

    return string.format(
        "%s complete. Processed %d auctions. %d update(s) recorded.",
        modeName,
        processedAuctions or 0,
        newLows or 0
    )
end

function Addon.Scanner.GetStoppedChatMessage(mode, processedAuctions, newLows)
    local modeName = Addon.Scanner.GetModeDisplayName(mode)

    return string.format(
        "%s stopped. Processed %d auctions before stopping. %d update(s) were recorded.",
        modeName,
        processedAuctions or 0,
        newLows or 0
    )
end

function Addon.Scanner.GetScanLabel()
    local modeName = Addon.Scanner.GetModeDisplayName()

    if Addon.scanSession.mode == "item" then
        return string.format(
            "%s for '%s'",
            modeName,
            tostring(Addon.scanSession.searchText or "")
        )
    end

    return modeName
end

function Addon.Scanner.StartScan()
    local canStart, reason = Addon.Scanner.CanStartQuery(Addon.scanSession.mode)
    if not canStart then
        Addon.Utils.PrintError(reason or "Cannot start scan right now.")
        return
    end
    Addon.Utils.Print("Starting " .. Addon.Scanner.GetScanLabel() .. "...")
    Addon.scanSession.active = true
    Addon.scanSession.scanID = Addon.scanSession.scanID + 1
    Addon.scanSession.processedAuctions = 0

    local title = "TreenAH Scan Report"
    local lines = {}

    if Addon.scanSession.mode == "item" then
        lines = {
            Addon.Scanner.GetModeSummaryLine(),
            "Target: " .. tostring(Addon.scanSession.searchText or "-"),
            "Status: Sending auction query...",
            "Updates this scan: 0",
        }
    elseif Addon.scanSession.mode == "tracked" then
        lines = {
            Addon.Scanner.GetModeSummaryLine(),
            Addon.Scanner.GetTrackedListSummaryLine(),
            "Status: Sending first query...",
            "Updates this scan: 0",
        }
    elseif Addon.scanSession.mode == "getall" then
        lines = {
            Addon.Scanner.GetModeSummaryLine(),
            "Status: Requesting full auction snapshot...",
            "Processed auctions: 0",
            "Updates this scan: 0",
        }
    else
        lines = {
            Addon.Scanner.GetModeSummaryLine(),
            "Status: Sending auction query...",
            "Processed auctions: 0",
            "Updates this scan: 0",
        }
    end

    if Addon.UI and Addon.UI.BeginScanSummary then
        Addon.UI.BeginScanSummary(title, lines)
    end

    local thisScanId = Addon.scanSession.scanID
    Addon.Scanner.SendCurrentScanQuery(thisScanId)
end

function Addon.Scanner.StartFullScan()
    Addon.Scanner.ResetScanSession()
    Addon.scanSession.searchText = ""
    Addon.scanSession.mode = "full"
    Addon.Scanner.StartScan()
end

function Addon.Scanner.StartGetAllScan()
    if not CanSendAuctionQuery then
        Addon.Utils.PrintError("CanSendAuctionQuery is unavailable.")
        return
    end

    local _, canQueryAll = CanSendAuctionQuery()
    if not canQueryAll then
        Addon.Utils.PrintError("Fast Full Scan is not ready yet. Blizzard only allows it periodically.")
        return
    end

    Addon.Scanner.ResetScanSession()
    Addon.scanSession.searchText = ""
    Addon.scanSession.mode = "getall"
    Addon.scanSession.getAllPass = 0
    Addon.Scanner.StartScan()
end

function Addon.Scanner.StartItemScan(itemName)
    Addon.Scanner.ResetScanSession()
    Addon.scanSession.searchText = itemName
    Addon.scanSession.mode = "item"
    Addon.Scanner.StartScan()
end

function Addon.Scanner.PrintTrackedItemProgress()
    if Addon.scanSession.mode ~= "tracked" then
        return
    end
    local debugMode = Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled()

    local trackedList = Addon.scanSession.trackedItemsList or {}
    local currentIndex = Addon.scanSession.trackedItemsSearchingIndex or 0
    local currentName = Addon.scanSession.searchText or trackedList[currentIndex] or "?"
    local listName = Addon.scanSession.trackedScanDisplayName or "Tracked Items"

    if debugMode then
        Addon.Utils.Print(string.format(
            "Scanning list %s item %d/%d: %s",
            tostring(listName or "-"),
            currentIndex or 0,
            #trackedList or 0,
            tostring(currentName or "-")
        ))
    end
end

function Addon.Scanner.StartTrackedItemsScan(scanTarget)
    local queue = Addon.Scanner.BuildTrackedScanQueue(scanTarget)

    if #queue == 0 then
        Addon.Utils.PrintError("No tracked items to scan for that target.")
        return
    end

    Addon.Scanner.ResetScanSession()
    Addon.scanSession.mode = "tracked"
    Addon.scanSession.trackedScanQueue = queue
    Addon.scanSession.trackedScanTarget = scanTarget or "__selected__"

    if not Addon.Scanner.LoadTrackedScanQueueEntry(1) then
        Addon.Utils.PrintError("Could not start tracked scan.")
        Addon.Scanner.ResetScanSession()
        return
    end

    Addon.Scanner.PrintTrackedItemProgress()
    Addon.Scanner.StartScan()
end

function Addon.Scanner.DoesCurrentPageMatchTrackedSearch()
    if Addon.scanSession.mode ~= "tracked" then
        return true
    end

    local expectedName = Addon.Utils.NormalizeItemName(Addon.scanSession.searchText)
    if not expectedName then
        return false
    end

    local batchCount = GetNumAuctionItems("list") or 0
    if batchCount == 0 then
        return true
    end

    local firstAuction = Addon.Scanner.GetAuctionData(1)
    local firstName = firstAuction and firstAuction.name and Addon.Utils.NormalizeItemName(firstAuction.name) or nil

    return firstName == expectedName
end

function Addon.Scanner.WaitForTrackedPageMatch()
    if not Addon.Scanner.IsScanActive() then
        return
    end

    local thisScanId = Addon.scanSession.scanID
    local expectedText = Addon.scanSession.searchText

    Addon.scanSession.trackedPageMatchRetries = (Addon.scanSession.trackedPageMatchRetries or 0) + 1
    local retries = Addon.scanSession.trackedPageMatchRetries

    if retries > TRACKED_PAGE_MATCH_MAX_RETRIES then
        local skippedItem = tostring(expectedText or "?")
        local listName = tostring(Addon.scanSession.trackedScanDisplayName or "Tracked Items")

        if Addon.UI and Addon.UI.AddScanEventLine then
            Addon.UI.AddScanEventLine(string.format(
                "Skipped '%s' after %d page-match retries.",
                skippedItem,
                TRACKED_PAGE_MATCH_MAX_RETRIES
            ))
        end

        Addon.Utils.PrintError(string.format(
            "Tracked scan could not confirm results for '%s' in list '%s'. Skipping to the next item.",
            skippedItem,
            listName
        ))

        Addon.Scanner.AdvanceToNextTrackedItem()
        return
    end

    C_Timer.After(0.2, function()
        if not Addon.Scanner.IsSessionCurrent(thisScanId) then
            return
        end

        if Addon.scanSession.searchText ~= expectedText then
            return
        end

        Addon.Scanner.ScheduleProcessCurrentResults()
    end)
end

function Addon.Scanner.GetScanPercentText()
    local mode = Addon.scanSession.mode

    if mode == "item" or mode == "full" then
        local pageCount = math.max(1, tonumber(Addon.scanSession.pageCount) or 1)
        local currentPage = math.min(pageCount, (tonumber(Addon.scanSession.currentPage) or 0) + 1)
        local percent = math.floor(((currentPage / pageCount) * 100) + 0.5)

        if percent < 0 then percent = 0 end
        if percent > 100 then percent = 100 end

        return string.format("(%d%%)", percent)
    end

    if mode == "tracked" then
        local queue = Addon.scanSession.trackedScanQueue or {}
        local totalItems = 0

        for _, entry in ipairs(queue) do
            totalItems = totalItems + #(entry.items or {})
        end

        if totalItems <= 0 then
            return "(0%)"
        end

        local completedItems = 0

        for queueIndex = 1, (Addon.scanSession.trackedScanQueueIndex or 1) - 1 do
            local entry = queue[queueIndex]
            completedItems = completedItems + #(entry and entry.items or {})
        end

        local currentItemIndex = Addon.scanSession.trackedItemsSearchingIndex or 1
        completedItems = completedItems + math.max(0, currentItemIndex - 1)

        local pageCount = math.max(1, tonumber(Addon.scanSession.pageCount) or 1)
        local currentPage = math.min(pageCount, (tonumber(Addon.scanSession.currentPage) or 0) + 1)
        local currentItemFraction = currentPage / pageCount

        local overallProgress = completedItems + currentItemFraction
        local percent = math.floor(((overallProgress / totalItems) * 100) + 0.5)

        if percent < 0 then percent = 0 end
        if percent > 100 then percent = 100 end

        return string.format("(%d%%)", percent)
    end

    return nil
end

function Addon.Scanner.GetTrackedListSummaryLine()
    local listName = tostring(Addon.scanSession.trackedScanDisplayName or "LIST_NAME")
    local queue = Addon.scanSession.trackedScanQueue or {}
    local queueIndex = tonumber(Addon.scanSession.trackedScanQueueIndex) or 1
    local totalLists = #queue

    if totalLists > 1 then
        if queueIndex < 1 then queueIndex = 1 end
        if queueIndex > totalLists then queueIndex = totalLists end
        return string.format("List: %s (%d/%d)", listName, queueIndex, totalLists)
    end

    return "List: " .. listName
end

function Addon.Scanner.RenderStandardPageSummary(totalAuctions)
    Addon.scanSession.pageCount = math.max(1, math.ceil(totalAuctions / NUM_AUCTION_ITEMS_PER_PAGE))

    local lines = {
        Addon.Scanner.GetModeSummaryLine(),
    }

    if Addon.scanSession.mode == "item" then
        table.insert(lines, "Target: " .. tostring(Addon.scanSession.searchText or "-"))
    elseif Addon.scanSession.mode == "tracked" then
        table.insert(lines, Addon.Scanner.GetTrackedListSummaryLine())
        table.insert(lines, string.format(
            "Current Item: %s (%d/%d)",
            tostring(Addon.scanSession.searchText or "-"),
            Addon.scanSession.trackedItemsSearchingIndex or 0,
            #(Addon.scanSession.trackedItemsList or {})
        ))
    end

    local statusText = "Status: Processing results"

    if Addon.scanSession.mode == "tracked" then
        statusText = "Status: Processing list item results"
    elseif Addon.scanSession.mode == "item" then
        statusText = "Status: Processing item results"
    elseif Addon.scanSession.mode == "full" then
        statusText = "Status: Processing full scan results"
    end

    table.insert(lines, statusText)
    table.insert(lines, "Updates this scan: " .. tostring(Addon.scanSession.numUpdates or 0))

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        if Addon.UI.SetScanProgressText then
            Addon.UI.SetScanProgressText(Addon.Scanner.GetScanPercentText() or "")
        end

        if Addon.UI.SetScanPageText then
            Addon.UI.SetScanPageText(string.format(
                "Item Page %d/%d",
                Addon.scanSession.currentPage + 1,
                Addon.scanSession.pageCount
            ))
        end

        Addon.UI.UpdateScanSummaryLines(lines)
    else
        Addon.UI.RenderSummary(string.format(
            "%s\n%s\nUpdates this scan: %d",
            Addon.Scanner.GetModeSummaryLine(),
            statusText,
            Addon.scanSession.numUpdates or 0
        ))
    end
end

function Addon.Scanner.GetFinalStatusLine(mode, outcome)
    local modeName = Addon.Scanner.GetModeDisplayName(mode)

    if outcome == "stopped" then
        return "Status: " .. modeName .. " stopped"
    elseif outcome == "complete" then
        return "Status: " .. modeName .. " finished"
    end

    return "Status: Idle"
end

function Addon.Scanner.HandleGetAllResults()
    Addon.Scanner.ScanAllResultsOnce()

    local processedAuctions = Addon.scanSession.processedAuctions or 0
    local newLows = Addon.scanSession.numUpdates or 0

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        Addon.UI.UpdateScanSummaryLines({
            Addon.Scanner.GetModeSummaryLine(),
            Addon.Scanner.GetFinalStatusLine("getall", "complete"),
            string.format("Processed auctions: %d", processedAuctions),
            string.format("Updates this scan: %d", newLows),
        })
    end

    if Addon.UI and Addon.UI.FinishScanSummary then
        Addon.UI.FinishScanSummary(Addon.Scanner.GetModeDisplayName("getall") .. " complete.")
    end

    Addon.Scanner.ResetScanSession()
    Addon.Utils.Print(Addon.Scanner.GetCompletionChatMessage("getall", processedAuctions, newLows))
    Addon.Utils.Print("Game freezing during Fast Full Scan is normal. Please wait patiently for it to complete.")
end

function Addon.Scanner.AdvanceToNextPage()
    Addon.scanSession.currentPage = Addon.scanSession.currentPage + 1
    local thisScanId = Addon.scanSession.scanID
    Addon.Scanner.SendCurrentScanQuery(thisScanId)
end

function Addon.Scanner.AdvanceToNextTrackedItem()
    local trackedList = Addon.scanSession.trackedItemsList or {}
    local nextItemIndexToScan = (Addon.scanSession.trackedItemsSearchingIndex or 0) + 1

    if trackedList[nextItemIndexToScan] then
        Addon.scanSession.trackedItemsSearchingIndex = nextItemIndexToScan
        Addon.scanSession.searchText = trackedList[nextItemIndexToScan]
        Addon.scanSession.currentPage = 0
        Addon.scanSession.pageCount = 0
        Addon.scanSession.trackedPageMatchRetries = 0

        Addon.Scanner.PrintTrackedItemProgress()

        local thisScanId = Addon.scanSession.scanID
        C_Timer.After(0.3, function()
            if Addon.Scanner.IsSessionCurrent(thisScanId) then
                Addon.Scanner.SendCurrentScanQuery(thisScanId)
            end
        end)
        return
    end

    local nextQueueIndex = (Addon.scanSession.trackedScanQueueIndex or 0) + 1
    if Addon.Scanner.LoadTrackedScanQueueEntry(nextQueueIndex) then
        local debugMode = Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print("Continuing list scan with list: " .. tostring(Addon.scanSession.trackedScanDisplayName))
        end
        Addon.Scanner.PrintTrackedItemProgress()

        local thisScanId = Addon.scanSession.scanID
        C_Timer.After(0.3, function()
            if Addon.Scanner.IsSessionCurrent(thisScanId) then
                Addon.Scanner.SendCurrentScanQuery(thisScanId)
            end
        end)
        return
    end

    local mode = Addon.scanSession.mode
    local totalUpdates = Addon.scanSession.numUpdates or 0
    local processedAuctions = Addon.scanSession.processedAuctions or 0
    local lines = {
        Addon.Scanner.GetModeSummaryLine(),
        Addon.Scanner.GetTrackedListSummaryLine(),
        Addon.Scanner.GetFinalStatusLine(mode, "complete"),
        string.format("Processed auctions: %d", processedAuctions),
        string.format("Updates this scan: %d", totalUpdates),
    }

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        Addon.UI.UpdateScanSummaryLines(lines)
    end

    if Addon.UI and Addon.UI.FinishScanSummary then
        Addon.UI.FinishScanSummary(Addon.Scanner.GetModeDisplayName(mode) .. " complete.")
    end

    Addon.Scanner.ResetScanSession()
    Addon.Utils.Print(Addon.Scanner.GetCompletionChatMessage(mode, processedAuctions, totalUpdates))
end

function Addon.Scanner.FinishStandardScan(totalAuctions)
    local mode = Addon.scanSession.mode
    local newLows = Addon.scanSession.numUpdates or 0
    local processedAuctions = Addon.scanSession.processedAuctions or 0
    local lines = {
        Addon.Scanner.GetModeSummaryLine(),
        Addon.Scanner.GetFinalStatusLine(mode, "complete"),
        string.format("Processed auctions: %d", processedAuctions),
        string.format("Updates this scan: %d", newLows),
    }
    local footer = Addon.Scanner.GetModeDisplayName(mode) .. " complete."

    if mode == "item" then
        table.insert(lines, 2, "Target: " .. tostring(Addon.scanSession.searchText or "-"))
    elseif mode == "tracked" then
        table.insert(lines, 2, Addon.Scanner.GetTrackedListSummaryLine())
    end

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        Addon.UI.UpdateScanSummaryLines(lines)
    end

    if Addon.UI and Addon.UI.FinishScanSummary then
        Addon.UI.FinishScanSummary(footer)
    end

    Addon.Scanner.ResetScanSession()
    Addon.Utils.Print(Addon.Scanner.GetCompletionChatMessage(mode, processedAuctions, newLows))
end

function Addon.Scanner.BuildStoppedSummaryLines()
    local mode = Addon.scanSession.mode
    local newLows = Addon.scanSession.numUpdates or 0
    local processedAuctions = Addon.scanSession.processedAuctions or 0
    local lines = {
        Addon.Scanner.GetModeSummaryLine(),
        Addon.Scanner.GetFinalStatusLine(mode, "stopped"),
        string.format("Processed auctions: %d", processedAuctions),
        string.format("Updates this scan: %d", newLows),
    }

    if mode == "item" then
        table.insert(lines, 2, "Target: " .. tostring(Addon.scanSession.searchText or "-"))
    elseif mode == "tracked" then
        table.insert(lines, 2, Addon.Scanner.GetTrackedListSummaryLine())

        if Addon.scanSession.searchText and Addon.scanSession.searchText ~= "" then
            table.insert(lines, 3, "Current Item: " .. tostring(Addon.scanSession.searchText))
        end
    end

    return lines
end

function Addon.Scanner.StopScan()
    if not Addon.Scanner.IsScanActive() then
        Addon.Utils.PrintError("No scan is currently in progress.")
        return
    end

    local mode = Addon.scanSession.mode
    local processedAuctions = Addon.scanSession.processedAuctions or 0
    local newLows = Addon.scanSession.numUpdates or 0
    local lines = Addon.Scanner.BuildStoppedSummaryLines()

    if Addon.UI and Addon.UI.UpdateScanSummaryLines then
        Addon.UI.UpdateScanSummaryLines(lines)
    end

    if Addon.UI and Addon.UI.FinishScanSummary then
        Addon.UI.FinishScanSummary(Addon.Scanner.GetModeDisplayName(mode) .. " stopped. Updates before stopping were recorded.")
    end

    Addon.Scanner.ResetScanSession()
    Addon.Utils.Print(Addon.Scanner.GetStoppedChatMessage(mode, processedAuctions, newLows))
end

function Addon.Scanner.HandleStandardPageResults()
    if Addon.scanSession.mode == "tracked" and not Addon.Scanner.DoesCurrentPageMatchTrackedSearch() then
        local waitText = "Waiting for tracked query results to finish loading for: " .. tostring(Addon.scanSession.searchText)
        local debugMode = Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print(waitText)
        end
        Addon.Scanner.WaitForTrackedPageMatch()
        return
    end

    if Addon.scanSession.mode == "tracked" then
        Addon.scanSession.trackedPageMatchRetries = 0
    end

    local _, totalAuctions = GetNumAuctionItems("list")
    totalAuctions = totalAuctions or 0

    Addon.Scanner.ScanCurrentPage()
    Addon.Scanner.RenderStandardPageSummary(totalAuctions)

    if Addon.scanSession.currentPage < (Addon.scanSession.pageCount - 1) then
        Addon.Scanner.AdvanceToNextPage()
        return
    end

    if Addon.scanSession.mode == "tracked" then
        Addon.Scanner.AdvanceToNextTrackedItem()
        return
    end

    Addon.Scanner.FinishStandardScan(totalAuctions)
end

function Addon.Scanner.ProcessNewPageDuringScan()
    if Addon.scanSession.mode == "getall" then
        Addon.Scanner.HandleGetAllResults()
        return
    end

    Addon.Scanner.HandleStandardPageResults()
end

function Addon.Scanner.ScheduleProcessCurrentResults()
    if not Addon.Scanner.IsScanActive() then
        return
    end

    Addon.scanSession.pendingProcessToken = (Addon.scanSession.pendingProcessToken or 0) + 1
    local token = Addon.scanSession.pendingProcessToken
    local thisScanId = Addon.scanSession.scanID

    C_Timer.After(PROCESS_RESULTS_DELAY, function()
        if not Addon.Scanner.IsSessionCurrent(thisScanId) then
            return
        end

        if Addon.scanSession.pendingProcessToken ~= token then
            return
        end

        Addon.Scanner.ProcessNewPageDuringScan()
    end)
end

function Addon.Scanner.ResetGetAllDebugStats()
    Addon.scanSession.getAllDebug = {
        rowsSeen = 0,
        rowsProcessed = 0,
        nilName = 0,
        nilLink = 0,
        nilItemID = 0,
        nilBuyout = 0,
        invalidCount = 0,
        nilPricePerUnit = 0,
        unreasonablePrice = 0,
        newLowsRecorded = 0,
    }
end

function Addon.Scanner.DebugCountGetAllAuction(auctionData)
    local stats = Addon.scanSession.getAllDebug
    if not stats then
        return
    end

    stats.rowsSeen = stats.rowsSeen + 1

    if not auctionData.name then
        stats.nilName = stats.nilName + 1
    end

    if not auctionData.itemLink then
        stats.nilLink = stats.nilLink + 1
    end

    if not auctionData.itemID then
        stats.nilItemID = stats.nilItemID + 1
    end

    if not auctionData.buyoutPrice or auctionData.buyoutPrice <= 0 then
        stats.nilBuyout = stats.nilBuyout + 1
    end

    if not auctionData.count or auctionData.count <= 0 then
        stats.invalidCount = stats.invalidCount + 1
    end

    if not auctionData.pricePerUnit or auctionData.pricePerUnit <= 0 then
        stats.nilPricePerUnit = stats.nilPricePerUnit + 1
    end
end

function Addon.Scanner.PrintGetAllDebugSummary()
    if not Addon.DB.IsDebugModeEnabled or not Addon.DB.IsDebugModeEnabled() then
        return
    end

    local stats = Addon.scanSession.getAllDebug
    if not stats then
        return
    end

    Addon.Utils.Print(string.format(
        "GetAll debug -- Seen: %d, Processed: %d, New lows: %d, Nil link: %d, Nil itemID: %d, Nil buyout: %d, Invalid count: %d, Nil unit price: %d, Unreasonable price: %d",
        stats.rowsSeen or 0,
        stats.rowsProcessed or 0,
        stats.newLowsRecorded or 0,
        stats.nilLink or 0,
        stats.nilItemID or 0,
        stats.nilBuyout or 0,
        stats.invalidCount or 0,
        stats.nilPricePerUnit or 0,
        stats.unreasonablePrice or 0
    ))
end

function Addon.Scanner.HasGetAllMissingLinkData()
    local stats = Addon.scanSession.getAllDebug
    if not stats then
        return false
    end

    return (stats.nilLink or 0) > 0 or (stats.nilItemID or 0) > 0
end

function Addon.Scanner.BuildTrackedScanQueue(scanTarget)
    local queue = {}

    if scanTarget == "__all__" or scanTarget == "__all_no_requests__" then
        local seenItems = {}

        for _, listEntry in ipairs(Addon.TrackedItems.GetTrackedListEntries()) do
            -- Skip Requests list if using the filtered option
            if scanTarget ~= "__all_no_requests__" or not listEntry.isRequests then
                local itemList = Addon.TrackedItems.GetTrackedItemsList(listEntry.key)
                local uniqueItems = {}

                for _, itemName in ipairs(itemList) do
                    local dedupeKey = Addon.Utils.NormalizeItemName(itemName) or itemName

                    if dedupeKey and not seenItems[dedupeKey] then
                        seenItems[dedupeKey] = true
                        uniqueItems[#uniqueItems + 1] = itemName
                    end
                end

                if #uniqueItems > 0 then
                    queue[#queue + 1] = {
                        listKey = listEntry.key,
                        listName = listEntry.name,
                        items = uniqueItems,
                    }
                end
            end
        end

        return queue
    end

    local resolvedListKey = scanTarget
    if not resolvedListKey or resolvedListKey == "__selected__" then
        resolvedListKey = Addon.TrackedItems.GetSelectedListKey()
    end

    local listData = Addon.TrackedItems.GetTrackedListData(resolvedListKey)
    local itemList = Addon.TrackedItems.GetTrackedItemsList(resolvedListKey)

    if #itemList > 0 then
        queue[#queue + 1] = {
            listKey = resolvedListKey,
            listName = listData and listData.name or resolvedListKey,
            items = itemList,
        }
    end

    return queue
end

function Addon.Scanner.LoadTrackedScanQueueEntry(queueIndex)
    local queue = Addon.scanSession.trackedScanQueue or {}
    local entry = queue[queueIndex]

    if not entry or not entry.items or not entry.items[1] then
        return false
    end

    Addon.scanSession.trackedScanQueueIndex = queueIndex
    Addon.scanSession.trackedListKey = entry.listKey
    Addon.scanSession.trackedScanDisplayName = entry.listName
    Addon.scanSession.trackedItemsList = entry.items
    Addon.scanSession.trackedItemsSearchingIndex = 1
    Addon.scanSession.searchText = entry.items[1]
    Addon.scanSession.currentPage = 0
    Addon.scanSession.pageCount = 0
    Addon.scanSession.trackedPageMatchRetries = 0

    return true
end
