local AddonName, Addon = ...
Addon.DB = Addon.DB or {}

-- TreenAHDB schema
-- TreenAHDB = {
--     settings = { ... }, -- global addon settings
--     marketData = {
--         ["Realm - Faction"] = {
--             items = { ... },
--             nameIndex = { ... },
--         },
--     },
--     characterData = {
--         ["Realm - Character"] = {
--             trackedLists = { ... },
--         },
--     },
-- }

function Addon.DB.GetCurrentMarketKey()
    local realmName = GetRealmName and GetRealmName() or "UnknownRealm"
    local factionName = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"

    return tostring(realmName) .. " - " .. tostring(factionName)
end

function Addon.DB.GetMarketRoot(marketKey)
    TreenAHDB = TreenAHDB or {}
    TreenAHDB.marketData = TreenAHDB.marketData or {}

    local key = marketKey or Addon.DB.GetCurrentMarketKey()
    TreenAHDB.marketData[key] = TreenAHDB.marketData[key] or {
        items = {},
        nameIndex = {},
    }

    TreenAHDB.marketData[key].items = TreenAHDB.marketData[key].items or {}
    TreenAHDB.marketData[key].nameIndex = TreenAHDB.marketData[key].nameIndex or {}

    return TreenAHDB.marketData[key]
end

function Addon.DB.GetCurrentCharacterKey()
    local realmName = GetRealmName and GetRealmName() or "UnknownRealm"
    local playerName = UnitName and UnitName("player") or "UnknownCharacter"

    return tostring(realmName) .. " - " .. tostring(playerName)
end

function Addon.DB.GetCharacterRoot(characterKey)
    TreenAHDB = TreenAHDB or {}
    TreenAHDB.characterData = TreenAHDB.characterData or {}

    local key = characterKey or Addon.DB.GetCurrentCharacterKey()
    TreenAHDB.characterData[key] = TreenAHDB.characterData[key] or {
        trackedLists = {},
    }

    TreenAHDB.characterData[key].trackedLists = TreenAHDB.characterData[key].trackedLists or {}

    return TreenAHDB.characterData[key]
end

function Addon.DB.InitDB()
    TreenAHDB = TreenAHDB or {}
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.marketData = TreenAHDB.marketData or {}
    TreenAHDB.characterData = TreenAHDB.characterData or {}

    local marketRoot = Addon.DB.GetMarketRoot()
    marketRoot.items = marketRoot.items or {}
    marketRoot.nameIndex = marketRoot.nameIndex or {}

    local characterRoot = Addon.DB.GetCharacterRoot()
    characterRoot.trackedLists = characterRoot.trackedLists or {}

    if TreenAHDB.settings.autoShowMainPanel == nil then
        TreenAHDB.settings.autoShowMainPanel = true
    end

    if TreenAHDB.settings.autoScanEnabled == nil then
        TreenAHDB.settings.autoScanEnabled = true
    end

    if TreenAHDB.settings.autoReplyEnabled == nil then
        TreenAHDB.settings.autoReplyEnabled = true
    end

    if TreenAHDB.settings.debugMode == nil then
        TreenAHDB.settings.debugMode = false
    end

    if TreenAHDB.settings.autoReplyWhisper == nil then
        TreenAHDB.settings.autoReplyWhisper = true
    end

    if TreenAHDB.settings.autoReplyGuild == nil then
        TreenAHDB.settings.autoReplyGuild = false
    end

    if TreenAHDB.settings.autoReplyParty == nil then
        TreenAHDB.settings.autoReplyParty = false
    end

    if TreenAHDB.settings.autoReplyRaid == nil then
        TreenAHDB.settings.autoReplyRaid = false
    end

    if TreenAHDB.settings.autoReplySay == nil then
        TreenAHDB.settings.autoReplySay = false
    end

    if TreenAHDB.settings.showBrowsePriceColumn == nil then
        TreenAHDB.settings.showBrowsePriceColumn = true
    end

    if TreenAHDB.settings.autoTrackRequests == nil then
        TreenAHDB.settings.autoTrackRequests = true
    end

    if TreenAHDB.settings.unreasonablePriceMultiplier == nil then
        TreenAHDB.settings.unreasonablePriceMultiplier = 5
    end

    if TreenAHDB.settings.displayAverageWindowDays == nil then
        TreenAHDB.settings.displayAverageWindowDays = 14
    end

    if TreenAHDB.settings.showTooltipPriceData == nil then
        TreenAHDB.settings.showTooltipPriceData = true
    end

    if TreenAHDB.settings.showTooltipHeader == nil then
        TreenAHDB.settings.showTooltipHeader = true
    end

    if TreenAHDB.settings.showTooltipAveragePrice == nil then
        TreenAHDB.settings.showTooltipAveragePrice = true
    end

    if TreenAHDB.settings.showTooltipLastSeenPrice == nil then
        TreenAHDB.settings.showTooltipLastSeenPrice = true
    end

    if TreenAHDB.settings.showTooltipDelta == nil then
        TreenAHDB.settings.showTooltipDelta = true
    end
end

local function CopyHourRecord(hourData)
    local copied = {}

    for key, value in pairs(hourData or {}) do
        copied[key] = value
    end

    return copied
end

local function CopyDayData(dayData)
    local copiedDay = { hours = {} }

    for hour, hourData in pairs((dayData and dayData.hours) or {}) do
        copiedDay.hours[hour] = CopyHourRecord(hourData)
    end

    return copiedDay
end

local function AddKeyToOrderIfMissing(order, key)
    if not key then
        return
    end

    for _, existingKey in ipairs(order or {}) do
        if existingKey == key then
            return
        end
    end

    table.insert(order, key)
end

local function ResolveSelectedTrackedListKey(targetRoot, legacyRoot)
    if not targetRoot or not targetRoot.lists then
        return
    end

    local currentSelectedKey = targetRoot.selectedKey
    if currentSelectedKey and targetRoot.lists[currentSelectedKey] then
        return
    end

    local legacySelectedKey = legacyRoot and legacyRoot.selectedKey
    if legacySelectedKey and targetRoot.lists[legacySelectedKey] then
        targetRoot.selectedKey = legacySelectedKey
        return
    end

    if targetRoot.lists["default"] then
        targetRoot.selectedKey = "default"
        return
    end

    for _, key in ipairs(targetRoot.order or {}) do
        if targetRoot.lists[key] and key ~= "requests" then
            targetRoot.selectedKey = key
            return
        end
    end

    if targetRoot.lists["requests"] then
        targetRoot.selectedKey = "requests"
    end
end

local function MergeLegacyItemData(targetItemData, legacyItemData)
    local didImportData = false

    if not targetItemData.name and legacyItemData and legacyItemData.name then
        targetItemData.name = legacyItemData.name
        didImportData = true
    end

    targetItemData.days = targetItemData.days or {}

    for day, legacyDayData in pairs((legacyItemData and legacyItemData.days) or {}) do
        if not targetItemData.days[day] then
            targetItemData.days[day] = CopyDayData(legacyDayData)
            didImportData = true
        else
            local targetDayData = targetItemData.days[day]
            targetDayData.hours = targetDayData.hours or {}

            for hour, legacyHourData in pairs((legacyDayData and legacyDayData.hours) or {}) do
                local targetHourData = targetDayData.hours[hour]

                if not targetHourData then
                    targetDayData.hours[hour] = CopyHourRecord(legacyHourData)
                    didImportData = true
                elseif not targetHourData.seenAt and legacyHourData and legacyHourData.seenAt then
                    targetHourData.seenAt = legacyHourData.seenAt
                    didImportData = true
                end
            end
        end
    end

    return didImportData
end

local VARIANT_ITEM_KEY_PREFIX = "variant:"

local function SortRecordedKeysStable(a, b)
    local baseA = Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(a) or tonumber(a) or 0
    local baseB = Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(b) or tonumber(b) or 0

    if baseA == baseB then
        return tostring(a) < tostring(b)
    end

    return baseA < baseB
end

local function ResolveStoredItemEntry(recordKey)
    local marketRoot = Addon.DB.GetMarketRoot()
    local items = marketRoot and marketRoot.items or nil
    if not items or recordKey == nil then
        return nil, nil
    end

    if items[recordKey] ~= nil then
        return items[recordKey], recordKey
    end

    local numericKey = tonumber(recordKey)
    if numericKey ~= nil and items[numericKey] ~= nil then
        return items[numericKey], numericKey
    end

    local stringKey = tostring(recordKey)
    if items[stringKey] ~= nil then
        return items[stringKey], stringKey
    end

    return nil, nil
end

function Addon.DB.IsVariantItemName(itemID, itemName)
    local normalizedItemName = Addon.Utils.NormalizeItemName(itemName)
    if not itemID or not normalizedItemName then
        return false
    end

    local itemInfo = Addon.Utils.GetItemInfoByID(itemID)
    local normalizedBaseName = Addon.Utils.NormalizeItemName(itemInfo and itemInfo.name)

    return normalizedBaseName ~= nil and normalizedBaseName ~= normalizedItemName
end

function Addon.DB.GetRecordKey(itemID, itemName, itemLink)
    if not itemID then
        return nil
    end

    local numericItemID = tonumber(itemID)
    local suffixID = itemLink and Addon.Utils.GetItemSuffixIdFromLink and Addon.Utils.GetItemSuffixIdFromLink(itemLink) or nil

    if numericItemID and suffixID and suffixID ~= 0 then
        local normalizedName = Addon.Utils.NormalizeItemName(itemName)
        if normalizedName then
            return string.format("%s%d:%s", VARIANT_ITEM_KEY_PREFIX, numericItemID, normalizedName)
        end
    end

    if numericItemID and Addon.DB.IsVariantItemName(numericItemID, itemName) then
        local normalizedName = Addon.Utils.NormalizeItemName(itemName)
        if normalizedName then
            return string.format("%s%d:%s", VARIANT_ITEM_KEY_PREFIX, numericItemID, normalizedName)
        end
    end

    return numericItemID or itemID
end

function Addon.DB.GetRecordBaseItemID(recordKey)
    local numericKey = tonumber(recordKey)
    if numericKey ~= nil then
        return numericKey
    end

    local stringKey = tostring(recordKey or "")
    local encodedItemID = stringKey:match("^" .. VARIANT_ITEM_KEY_PREFIX .. "(%-?%d+):")
    return encodedItemID and tonumber(encodedItemID) or nil
end

function Addon.DB.GetRecordDisplayName(recordKey, fallbackText)
    local itemData = Addon.DB.GetItemData(recordKey)
    if itemData and itemData.name and itemData.name ~= "" then
        return itemData.name
    end

    local baseItemID = Addon.DB.GetRecordBaseItemID(recordKey)
    if baseItemID then
        return Addon.Utils.GetItemDisplayNameByItemID(baseItemID, fallbackText)
    end

    return fallbackText or ("Item " .. tostring(recordKey))
end

function Addon.DB.GetRecordLabel(recordKey, itemData)
    local displayName = (itemData and itemData.name) or Addon.DB.GetRecordDisplayName(recordKey)
    local baseItemID = (itemData and itemData.baseItemID) or Addon.DB.GetRecordBaseItemID(recordKey)

    if baseItemID then
        return string.format("%s [%d]", tostring(displayName or "Item"), baseItemID)
    end

    return string.format("%s [%s]", tostring(displayName or "Item"), tostring(recordKey))
end

function Addon.DB.GetRecordedKeysByBaseItemID(baseItemID)
    local numericBaseItemID = tonumber(baseItemID)
    if numericBaseItemID == nil then
        return {}
    end

    local matches = {}
    local marketRoot = Addon.DB.GetMarketRoot()

    for itemKey, itemData in pairs(marketRoot.items or {}) do
        local candidateBaseItemID = (itemData and itemData.baseItemID) or Addon.DB.GetRecordBaseItemID(itemKey)
        if candidateBaseItemID == numericBaseItemID then
            matches[#matches + 1] = itemKey
        end
    end

    table.sort(matches, SortRecordedKeysStable)
    return matches
end

function Addon.DB.GetRecordedKeyFromLink(itemLink)
    local itemID = Addon.Utils.GetItemIdFromLink(itemLink)
    if not itemID then
        return nil
    end

    local itemName = Addon.Utils.GetPlainItemNameFromLink(itemLink)
    local variantKey = Addon.DB.GetRecordKey(itemID, itemName, itemLink)

    if variantKey and Addon.DB.HasItem(variantKey) then
        return variantKey
    end

    if Addon.DB.HasItem(itemID) then
        return itemID
    end

    return nil
end

function Addon.DB.MigrateLegacyGlobalMarketData()
    if not TreenAHDB then
        return 0
    end

    local legacyItems = TreenAHDB.items
    local legacyNameIndex = TreenAHDB.nameIndex

    if not legacyItems and not legacyNameIndex then
        return 0
    end

    local marketRoot = Addon.DB.GetMarketRoot()
    local targetItems = marketRoot.items or {}
    local migratedCount = 0

    for itemID, legacyItemData in pairs(legacyItems or {}) do
        local targetItemData = targetItems[itemID]
        local itemChanged = false

        if not targetItemData then
            targetItemData = {}
            targetItems[itemID] = targetItemData
        end

        itemChanged = MergeLegacyItemData(targetItemData, legacyItemData)

        if itemChanged then
            Addon.DB.RefreshItemLastRecordedAt(itemID)
            migratedCount = migratedCount + 1
        end
    end

    marketRoot.items = targetItems
    Addon.DB.RebuildNameIndex()

    TreenAHDB.items = nil
    TreenAHDB.nameIndex = nil

    return migratedCount
end

function Addon.DB.MigrateLegacyTrackedListsToCurrentCharacter()
    if not TreenAHDB or not TreenAHDB.trackedLists then
        return 0
    end

    local legacyRoot = TreenAHDB.trackedLists
    local characterRoot = Addon.DB.GetCharacterRoot()
    characterRoot.trackedLists = characterRoot.trackedLists or {}

    local targetRoot = characterRoot.trackedLists
    targetRoot.lists = targetRoot.lists or {}
    targetRoot.order = targetRoot.order or {}
    targetRoot.selectedKey = targetRoot.selectedKey or "default"

    local mergedListsCount = 0
    local listsChanged = {}

    for key, legacyListData in pairs(legacyRoot.lists or {}) do
        local targetListData = targetRoot.lists[key]
        local listChanged = false

        if not targetListData then
            targetListData = {
                name = legacyListData.name or key,
                items = {},
            }
            targetRoot.lists[key] = targetListData
            listChanged = true
        end

        if (not targetListData.name or targetListData.name == "") and legacyListData.name and legacyListData.name ~= "" then
            targetListData.name = legacyListData.name
            listChanged = true
        end

        targetListData.items = targetListData.items or {}

        for itemKey, itemName in pairs(legacyListData.items or {}) do
            local storedName = itemName or itemKey
            local normalizedName = Addon.Utils.NormalizeItemName(storedName) or Addon.Utils.NormalizeItemName(itemKey)
            if normalizedName and targetListData.items[normalizedName] == nil then
                targetListData.items[normalizedName] = storedName
                listChanged = true
            end
        end

        if listChanged then
            listsChanged[key] = true
        end
    end

    for _, key in ipairs(legacyRoot.order or {}) do
        if targetRoot.lists[key] then
            AddKeyToOrderIfMissing(targetRoot.order, key)
        end
    end

    for key in pairs(legacyRoot.lists or {}) do
        if targetRoot.lists[key] then
            AddKeyToOrderIfMissing(targetRoot.order, key)
        end
    end

    ResolveSelectedTrackedListKey(targetRoot, legacyRoot)

    for _ in pairs(listsChanged) do
        mergedListsCount = mergedListsCount + 1
    end

    TreenAHDB.trackedLists = nil
    return mergedListsCount
end

function Addon.DB.ClearPriceHistory()
    local marketRoot = Addon.DB.GetMarketRoot()
    marketRoot.items = {}
    marketRoot.nameIndex = {}

    Addon.Utils.Print("Price history cleared for current server/faction.")
end

function Addon.DB.HasItem(itemID)
    local itemData = ResolveStoredItemEntry(itemID)
    return itemData ~= nil
end

function Addon.DB.GetHistoricalAverageLowPrice(itemID)
    if not Addon.DB.HasItem(itemID) then
        return nil
    end

    local displayWindowDays = Addon.DB.GetDisplayAverageWindowDays()
    local itemData = Addon.DB.GetItemData(itemID)
    local sortedDays = Addon.Utils.GetSortedKeysDescending(itemData.days or {})
    local weightedTotal = 0
    local totalWeight = 0

    for _, day in ipairs(sortedDays) do
        local ageInDays = Addon.Utils.GetDateKeyAgeInDays(day)

        if ageInDays ~= nil and ageInDays >= 0 and ageInDays < displayWindowDays then
            local dayData = itemData.days[day]
            local dayTotal = 0
            local dayCount = 0

            for _, hourData in pairs(dayData.hours or {}) do
                if hourData.low and hourData.low > 0 then
                    dayTotal = dayTotal + hourData.low
                    dayCount = dayCount + 1
                end
            end

            if dayCount > 0 then
                local dayAverage = dayTotal / dayCount
                local weight = 1.0 - (ageInDays * 0.05)

                if weight < 0.30 then
                    weight = 0.30
                end

                weightedTotal = weightedTotal + (dayAverage * weight)
                totalWeight = totalWeight + weight
            end
        end
    end

    if totalWeight > 0 then
        return weightedTotal / totalWeight
    end

    return Addon.DB.GetItemMostRecentLow(itemID)
end

function Addon.DB.IsItemRecordedThisHour(itemID)
    return Addon.DB.GetItemLowThisHour(itemID) ~= nil
end

function Addon.DB.GetItemLowThisHour(itemID)
    if not Addon.DB.HasItem(itemID) then
        return nil
    end

    local itemData = Addon.DB.GetItemData(itemID)
    local currentDate = Addon.Utils.GetCurrentDate()
    local currentHour = Addon.Utils.GetCurrentHour()

    local hourData = itemData.days
        and itemData.days[currentDate]
        and itemData.days[currentDate].hours
        and itemData.days[currentDate].hours[currentHour]

    return hourData and hourData.low or nil
end

function Addon.DB.UpdateItemLowThisHour(itemID, lowPrice, itemName, baseItemID)
    if not itemID or not lowPrice or lowPrice <= 0 then
        return
    end

    local marketRoot = Addon.DB.GetMarketRoot()
    local recordKey = itemID
    marketRoot.items[recordKey] = marketRoot.items[recordKey] or {}
    local itemData = marketRoot.items[recordKey]

    itemData.days = itemData.days or {}
    itemData.baseItemID = tonumber(baseItemID) or itemData.baseItemID or Addon.DB.GetRecordBaseItemID(recordKey)

    if itemName and itemName ~= "" then
        itemData.name = itemName
    elseif not itemData.name then
        local itemInfo = Addon.Utils.GetItemInfoByID(itemData.baseItemID or Addon.DB.GetRecordBaseItemID(recordKey))
        if itemInfo and itemInfo.name then
            itemData.name = itemInfo.name
        end
    end

    if itemData.name then
        Addon.DB.IndexItemName(recordKey, itemData.name)
    end

    local currentDate = Addon.Utils.GetCurrentDate()
    local currentHour = Addon.Utils.GetCurrentHour()
    local now = time()

    itemData.days[currentDate] = itemData.days[currentDate] or { hours = {} }
    itemData.days[currentDate].hours = itemData.days[currentDate].hours or {}
    itemData.days[currentDate].hours[currentHour] = itemData.days[currentDate].hours[currentHour] or {}

    itemData.days[currentDate].hours[currentHour].low = lowPrice
    itemData.days[currentDate].hours[currentHour].seenAt = now
    itemData.lastRecordedAt = now

    if Addon.DB.IsDebugModeEnabled() then
        Addon.Utils.Print(string.format(
            "New low for %s this hour: %s",
            itemData.name or ("Item " .. tostring(itemID)),
            Addon.Utils.ConvertToCoinTextureString(lowPrice)
        ))
    end
end

function Addon.DB.GetItemData(itemID)
    local itemData = ResolveStoredItemEntry(itemID)
    return itemData
end

function Addon.DB.GetRecordedItemIDsByName(itemName)
    local normalizedTarget = Addon.Utils.NormalizeItemName(itemName)
    if not normalizedTarget then
        return {}
    end

    local marketRoot = Addon.DB.GetMarketRoot()
    if not marketRoot or not marketRoot.items then
        return {}
    end

    local matchesByID = {}
    local cachedItemID = Addon.DB.GetItemIDByName(itemName)

    if cachedItemID and Addon.DB.HasItem(cachedItemID) then
        matchesByID[tostring(cachedItemID)] = cachedItemID
    end

    for itemID, itemData in pairs(marketRoot.items) do
        local candidateName = itemData and itemData.name

        if candidateName and Addon.Utils.NormalizeItemName(candidateName) == normalizedTarget then
            matchesByID[tostring(itemID)] = itemID
        end
    end

    local matches = {}
    for _, itemKey in pairs(matchesByID) do
        matches[#matches + 1] = itemKey
    end

    table.sort(matches, SortRecordedKeysStable)

    return matches
end

function Addon.DB.FindRecordedItemIDByName(itemName)
    local matches = Addon.DB.GetRecordedItemIDsByName(itemName)
    if matches[1] then
        local itemData = Addon.DB.GetItemData(matches[1])
        if itemData and itemData.name then
            Addon.DB.IndexItemName(matches[1], itemData.name)
        end
        return matches[1]
    end

    return nil
end

function Addon.DB.GetItemMostRecentLow(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        return nil
    end

    local sortedDays = Addon.Utils.GetSortedKeysDescending(itemData.days or {})
    for _, day in ipairs(sortedDays) do
        local dayData = itemData.days[day]
        local sortedHours = Addon.Utils.GetSortedKeysDescending(dayData.hours or {})

        for _, hour in ipairs(sortedHours) do
            local hourData = dayData.hours[hour]
            if hourData.low and hourData.low > 0 then
                return hourData.low
            end
        end
    end

    return nil
end

function Addon.DB.GetNameIndex()
    local marketRoot = Addon.DB.GetMarketRoot()
    marketRoot.nameIndex = marketRoot.nameIndex or {}
    return marketRoot.nameIndex
end

function Addon.DB.IndexItemName(itemID, itemName)
    local normalizedName = Addon.Utils.NormalizeItemName(itemName)
    if not normalizedName or not itemID then
        return
    end

    local nameIndex = Addon.DB.GetNameIndex()
    nameIndex[normalizedName] = itemID
end

function Addon.DB.GetItemIDByName(itemName)
    local normalizedName = Addon.Utils.NormalizeItemName(itemName)
    if not normalizedName then
        return nil
    end

    local nameIndex = Addon.DB.GetNameIndex()
    return nameIndex[normalizedName]
end

function Addon.DB.RebuildNameIndex()
    local nameIndex = Addon.DB.GetNameIndex()

    for k in pairs(nameIndex) do
        nameIndex[k] = nil
    end

    local marketRoot = Addon.DB.GetMarketRoot()
    for itemID, itemData in pairs(marketRoot.items or {}) do
        local itemName = itemData and itemData.name
        if itemName then
            local normalizedName = Addon.Utils.NormalizeItemName(itemName)
            if normalizedName then
                nameIndex[normalizedName] = itemID
            end
        end
    end
end

function Addon.DB.GetRecordedLowCount(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        return 0
    end

    local count = 0

    for _, dayData in pairs(itemData.days or {}) do
        for _, hourData in pairs(dayData.hours or {}) do
            if hourData.low and hourData.low > 0 then
                count = count + 1
            end
        end
    end

    return count
end

function Addon.DB.GetRecordedLowsList(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        return {}
    end

    local values = {}

    for _, dayData in pairs(itemData.days or {}) do
        for _, hourData in pairs(dayData.hours or {}) do
            if hourData.low and hourData.low > 0 then
                values[#values + 1] = hourData.low
            end
        end
    end

    table.sort(values)
    return values
end

function Addon.DB.GetMedianOfSortedValues(sortedValues)
    local count = sortedValues and #sortedValues or 0
    if count == 0 then
        return nil
    end

    local mid = math.floor(count / 2) + 1

    if (count % 2) == 1 then
        return sortedValues[mid]
    end

    local left = sortedValues[mid - 1]
    local right = sortedValues[mid]
    return (left + right) / 2
end

function Addon.DB.GetRobustPriceStats(itemID)
    local values = Addon.DB.GetRecordedLowsList(itemID)
    local count = #values

    if count == 0 then
        return nil, nil, 0
    end

    local median = Addon.DB.GetMedianOfSortedValues(values)
    if not median then
        return nil, nil, count
    end

    local deviations = {}

    for i = 1, count do
        deviations[i] = math.abs(values[i] - median)
    end

    table.sort(deviations)

    local mad = Addon.DB.GetMedianOfSortedValues(deviations)
    return median, mad, count
end

function Addon.DB.GetRecordedItemsList()
    local list = {}
    local marketRoot = Addon.DB.GetMarketRoot()

    for itemKey, itemData in pairs(marketRoot.items or {}) do
        local baseItemID = (itemData and itemData.baseItemID) or Addon.DB.GetRecordBaseItemID(itemKey)
        local displayName = (itemData and itemData.name) or Addon.DB.GetRecordDisplayName(itemKey)

        list[#list + 1] = {
            itemKey = itemKey,
            itemID = baseItemID,
            name = displayName or ("Item " .. tostring(baseItemID or itemKey)),
            lastRecordedAt = itemData and itemData.lastRecordedAt or nil,
        }
    end

    table.sort(list, function(a, b)
        local nameA = Addon.Utils.NormalizeItemName(a.name) or ""
        local nameB = Addon.Utils.NormalizeItemName(b.name) or ""

        if nameA == nameB then
            return SortRecordedKeysStable(a.itemKey or a.itemID, b.itemKey or b.itemID)
        end

        return nameA < nameB
    end)

    return list
end

function Addon.DB.GetRecordedDays(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData or not itemData.days then
        return {}
    end

    return Addon.Utils.GetSortedKeysDescending(itemData.days)
end

function Addon.DB.GetRecordedHours(itemID, day)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData or not itemData.days or not itemData.days[day] then
        return {}
    end

    local hours = itemData.days[day].hours or {}
    return Addon.Utils.GetSortedKeysDescending(hours)
end

function Addon.DB.GetHourRecord(itemID, day, hour)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData or not itemData.days then
        return nil
    end

    local dayData = itemData.days[day]
    if not dayData or not dayData.hours then
        return nil
    end

    return dayData.hours[hour]
end

function Addon.DB.GetHourRecordTimestamp(day, hour, hourData)
    if hourData and hourData.seenAt then
        return hourData.seenAt
    end

    local parsedDay = Addon.Utils.ParseDateKey(day)
    local numericHour = tonumber(hour)

    if not parsedDay or numericHour == nil then
        return nil
    end

    return time({
        year = parsedDay.year,
        month = parsedDay.month,
        day = parsedDay.day,
        hour = numericHour,
        min = 0,
        sec = 0,
    })
end

function Addon.DB.GetItemMostRecentRecordTimestamp(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        return nil
    end

    local sortedDays = Addon.Utils.GetSortedKeysDescending(itemData.days or {})
    for _, day in ipairs(sortedDays) do
        local dayData = itemData.days[day]
        local sortedHours = Addon.Utils.GetSortedKeysDescending(dayData.hours or {})

        for _, hour in ipairs(sortedHours) do
            local hourData = dayData.hours[hour]
            if hourData and hourData.low and hourData.low > 0 then
                return Addon.DB.GetHourRecordTimestamp(day, hour, hourData)
            end
        end
    end

    return nil
end

function Addon.DB.RefreshItemLastRecordedAt(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        return nil
    end

    local mostRecentTimestamp = Addon.DB.GetItemMostRecentRecordTimestamp(itemID)
    itemData.lastRecordedAt = mostRecentTimestamp

    return mostRecentTimestamp
end

function Addon.DB.DeleteHourRecord(itemID, day, hour)
    local itemData = Addon.DB.GetItemData(itemID)
    local _, storedKey = ResolveStoredItemEntry(itemID)
    if not itemData or not itemData.days then
        return false, "Item not found."
    end

    local dayData = itemData.days[day]
    if not dayData or not dayData.hours then
        return false, "Day record not found."
    end

    local hourData = dayData.hours[hour]
    if not hourData then
        return false, "Hour record not found."
    end

    dayData.hours[hour] = nil

    if next(dayData.hours) == nil then
        itemData.days[day] = nil
    end

    itemData.days = itemData.days or {}

    if next(itemData.days) == nil then
        local marketRoot = Addon.DB.GetMarketRoot()
        marketRoot.items[storedKey or itemID] = nil
        Addon.DB.RebuildNameIndex()
        return true, "Deleted hourly record. Item now has no remaining history."
    end

    Addon.DB.RefreshItemLastRecordedAt(itemID)

    return true, "Deleted hourly record."
end

function Addon.DB.DeleteDayRecord(itemID, day)
    local itemData = Addon.DB.GetItemData(itemID)
    local _, storedKey = ResolveStoredItemEntry(itemID)
    if not itemData or not itemData.days then
        return false, "Item not found."
    end

    local dayData = itemData.days[day]
    if not dayData then
        return false, "Day record not found."
    end

    itemData.days[day] = nil
    itemData.days = itemData.days or {}

    if next(itemData.days) == nil then
        local marketRoot = Addon.DB.GetMarketRoot()
        marketRoot.items[storedKey or itemID] = nil
        Addon.DB.RebuildNameIndex()
        return true, "Deleted day record. Item now has no remaining history."
    end

    Addon.DB.RefreshItemLastRecordedAt(itemID)

    return true, "Deleted day record."
end

function Addon.DB.DeleteItemRecord(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    local _, storedKey = ResolveStoredItemEntry(itemID)
    if not itemData then
        return false, "Item not found."
    end

    local marketRoot = Addon.DB.GetMarketRoot()
    marketRoot.items[storedKey or itemID] = nil
    Addon.DB.RebuildNameIndex()

    return true, "Deleted item record."
end

-- SETTINGS FUNCTIONS --
-- These functions manage user settings stored in the database, such as auto-reply and UI preferences.

function Addon.DB.IsAutoReplyEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.autoReplyEnabled == nil then
        return true
    end

    return TreenAHDB.settings.autoReplyEnabled
end

function Addon.DB.SetAutoReplyEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.autoReplyEnabled = enabled and true or false
end

function Addon.DB.IsBrowsePriceColumnEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showBrowsePriceColumn == nil then
        return true
    end

    return TreenAHDB.settings.showBrowsePriceColumn == true
end

function Addon.DB.SetBrowsePriceColumnEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showBrowsePriceColumn = enabled and true or false
end

function Addon.DB.IsAutoScanEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.autoScanEnabled == nil then
        return true
    end

    return TreenAHDB.settings.autoScanEnabled
end

function Addon.DB.SetAutoScanEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.autoScanEnabled = enabled and true or false
end

function Addon.DB.IsAutoTrackRequestsEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.autoTrackRequests == nil then
        return true
    end

    return TreenAHDB.settings.autoTrackRequests == true
end

function Addon.DB.SetAutoTrackRequestsEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.autoTrackRequests = enabled and true or false
end

function Addon.DB.IsAutoShowMainPanelEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return false
    end

    if TreenAHDB.settings.autoShowMainPanel == nil then
        return true
    end

    return TreenAHDB.settings.autoShowMainPanel == true
end

function Addon.DB.SetAutoShowMainPanelEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.autoShowMainPanel = enabled and true or false
end

function Addon.DB.IsAutoReplyChannelEnabled(channelKey)
    if not TreenAHDB or not TreenAHDB.settings then
        return false
    end

    if channelKey == "whisper" then
        return TreenAHDB.settings.autoReplyWhisper == true
    elseif channelKey == "guild" then
        return TreenAHDB.settings.autoReplyGuild == true
    elseif channelKey == "party" then
        return TreenAHDB.settings.autoReplyParty == true
    elseif channelKey == "raid" then
        return TreenAHDB.settings.autoReplyRaid == true
    elseif channelKey == "say" then
        return TreenAHDB.settings.autoReplySay == true
    end

    return false
end

function Addon.DB.SetAutoReplyChannelEnabled(channelKey, enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    enabled = enabled and true or false

    if channelKey == "whisper" then
        TreenAHDB.settings.autoReplyWhisper = enabled
    elseif channelKey == "guild" then
        TreenAHDB.settings.autoReplyGuild = enabled
    elseif channelKey == "party" then
        TreenAHDB.settings.autoReplyParty = enabled
    elseif channelKey == "raid" then
        TreenAHDB.settings.autoReplyRaid = enabled
    elseif channelKey == "say" then
        TreenAHDB.settings.autoReplySay = enabled
    end
end

function Addon.DB.IsDebugModeEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return false
    end

    if TreenAHDB.settings.debugMode == nil then
        return false
    end

    return TreenAHDB.settings.debugMode == true
end

function Addon.DB.SetDebugModeEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.debugMode = enabled and true or false
end

function Addon.DB.GetUnreasonablePriceMultiplier()
    if not TreenAHDB or not TreenAHDB.settings then
        return 5
    end

    local value = tonumber(TreenAHDB.settings.unreasonablePriceMultiplier)
    if not value or value <= 0 then
        return 5
    end

    return value
end

function Addon.DB.SetUnreasonablePriceMultiplier(value)
    TreenAHDB.settings = TreenAHDB.settings or {}

    local numericValue = tonumber(value)
    if not numericValue or numericValue <= 0 then
        return false, "Enter a number greater than 0."
    end

    -- Keep people from entering something insane.
    if numericValue < 1 then
        return false, "Multiplier must be at least 1."
    end

    if numericValue > 100 then
        return false, "Multiplier must be 100 or less."
    end

    TreenAHDB.settings.unreasonablePriceMultiplier = numericValue
    return true, numericValue
end

function Addon.DB.GetDisplayAverageWindowDays()
    if not TreenAHDB or not TreenAHDB.settings then
        return 14
    end

    local value = tonumber(TreenAHDB.settings.displayAverageWindowDays)
    if not value then
        return 14
    end

    value = math.floor(value)

    if value < 1 then
        return 14
    end

    return value
end

function Addon.DB.SetDisplayAverageWindowDays(value)
    TreenAHDB.settings = TreenAHDB.settings or {}

    local numericValue = tonumber(value)
    if not numericValue then
        return false, "Enter a number."
    end

    numericValue = math.floor(numericValue)

    if numericValue < 1 then
        return false, "Window must be at least 1 day."
    end

    if numericValue > 60 then
        return false, "Window must be 60 days or less."
    end

    TreenAHDB.settings.displayAverageWindowDays = numericValue
    return true, numericValue
end

function Addon.DB.IsTooltipPriceDataEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showTooltipPriceData == nil then
        return true
    end

    return TreenAHDB.settings.showTooltipPriceData == true
end

function Addon.DB.SetTooltipPriceDataEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showTooltipPriceData = enabled and true or false
end

function Addon.DB.IsTooltipHeaderEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showTooltipHeader == nil then
        return true
    end

    return TreenAHDB.settings.showTooltipHeader == true
end

function Addon.DB.SetTooltipHeaderEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showTooltipHeader = enabled and true or false
end

function Addon.DB.IsTooltipAveragePriceEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showTooltipAveragePrice == nil then
        return true
    end

    return TreenAHDB.settings.showTooltipAveragePrice == true
end

function Addon.DB.SetTooltipAveragePriceEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showTooltipAveragePrice = enabled and true or false
end

function Addon.DB.IsTooltipLastSeenPriceEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showTooltipLastSeenPrice == nil then
        return true
    end

    return TreenAHDB.settings.showTooltipLastSeenPrice == true
end

function Addon.DB.SetTooltipLastSeenPriceEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showTooltipLastSeenPrice = enabled and true or false
end

function Addon.DB.IsTooltipDeltaEnabled()
    if not TreenAHDB or not TreenAHDB.settings then
        return true
    end

    if TreenAHDB.settings.showTooltipDelta == nil then
        return true
    end

    return TreenAHDB.settings.showTooltipDelta == true
end

function Addon.DB.SetTooltipDeltaEnabled(enabled)
    TreenAHDB.settings = TreenAHDB.settings or {}
    TreenAHDB.settings.showTooltipDelta = enabled and true or false
end
