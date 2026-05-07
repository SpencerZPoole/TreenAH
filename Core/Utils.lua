local AddonName, Addon = ...

Addon.Utils = Addon.Utils or {}

function Addon.Utils.TableCount(t)
    local count = 0
    for _ in pairs(t or {}) do count = count + 1 end
    return count
end

function Addon.Utils.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TreenAH:|r " .. tostring(msg))
end

function Addon.Utils.PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff3333TreenAH Error:|r " .. tostring(msg))
end

function Addon.Utils.GetCurrentDate()
    return date("%Y-%m-%d")
end

function Addon.Utils.ParseDateKey(dateKey)
    if not dateKey then
        return nil
    end

    local year, month, day = tostring(dateKey):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year or not month or not day then
        return nil
    end

    return {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
    }
end

function Addon.Utils.GetDateKeyAgeInDays(dateKey)
    local parsed = Addon.Utils.ParseDateKey(dateKey)
    if not parsed then
        return nil
    end

    local recordTime = time({
        year = parsed.year,
        month = parsed.month,
        day = parsed.day,
        hour = 12,
        min = 0,
        sec = 0,
    })

    local now = date("*t")
    local todayTime = time({
        year = now.year,
        month = now.month,
        day = now.day,
        hour = 12,
        min = 0,
        sec = 0,
    })

    if not recordTime or not todayTime then
        return nil
    end

    return math.floor((todayTime - recordTime) / 86400)
end

function Addon.Utils.GetCurrentHour()
    return tonumber(date("%H"))
end

function Addon.Utils.GetPercentColor(percentDiff)
    if not percentDiff then
        return 1.0, 1.0, 1.0
    end

    local MAX_ABS_PERCENT = 40

    if percentDiff == 0 then
        return 1.0, 0.82, 0.0
    end

    if math.abs(percentDiff) < 2 then
        return 1.0, 0.82, 0.0
    end

    local intensity = math.min(math.abs(percentDiff) / MAX_ABS_PERCENT, 1.0)

    if percentDiff < 0 then
        -- Blend from yellow -> green as price goes further below average
        local r = 1.0 - (0.8 * intensity)
        local g = 0.82 + (0.18 * intensity)
        local b = 0.0
        return r, g, b
    else
        -- Blend from yellow -> red as price goes further above average
        local r = 1.0
        local g = 0.82 - (0.57 * intensity)
        local b = 0.0
        return r, g, b
    end
end

function Addon.Utils.GetPercentDiffFromAverage(currentPerItem, historicalAvgLow)
    if not currentPerItem or currentPerItem <= 0 then
        return nil
    end

    if not historicalAvgLow or historicalAvgLow <= 0 then
        return nil
    end

    return ((currentPerItem - historicalAvgLow) / historicalAvgLow) * 100
end

function Addon.Utils.FormatPercentDiff(percentDiff)
    if not percentDiff then
        return "-"
    end

    return string.format("%+.0f%%", percentDiff)
end

function Addon.Utils.GetSortedKeysDescending(t)
    local keys = {}

    for k in pairs(t) do
        table.insert(keys, k)
    end

    table.sort(keys, function(a, b)
        return a > b
    end)

    return keys
end

function Addon.Utils.GetItemInfoByID(itemID)
    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = C_Item.GetItemInfo(itemID)
    return {
        name = itemName,
        link = itemLink,
        rarity = itemRarity,
        level = itemLevel,
        minLevel = itemMinLevel,
        type = itemType,
        subType = itemSubType,
        stackCount = itemStackCount,
        equipLoc = itemEquipLoc,
        texture = itemTexture,
    }
end

function Addon.Utils.GetItemIDByName(itemName)
    local normalizedName = Addon.Utils.NormalizeItemName(itemName)
    if not normalizedName then
        return nil
    end

    local itemNameResolved, itemLink = GetItemInfo(itemName)
    if itemLink then
        return Addon.Utils.GetItemIdFromLink(itemLink)
    end

    return nil
end

function Addon.Utils.GetItemDisplayNameByItemID(itemID, fallbackText)
    local resolvedItemID = tonumber(itemID)

    if not resolvedItemID and Addon.DB and Addon.DB.GetRecordBaseItemID then
        resolvedItemID = Addon.DB.GetRecordBaseItemID(itemID)
    end

    local itemInfo = resolvedItemID and Addon.Utils.GetItemInfoByID(resolvedItemID)
    if itemInfo and itemInfo.name then
        return itemInfo.name
    end

    return fallbackText or ("Item " .. tostring(resolvedItemID or itemID))
end

function Addon.Utils.NormalizeItemName(name)
    name = name and strtrim(name)
    return (name and name ~= "") and strlower(name) or nil
end

function Addon.Utils.ConvertToCoinTextureString(copper)
    if not copper or copper <= 0 then
        return "-"
    end

    return C_CurrencyInfo.GetCoinTextureString(copper)
end

function Addon.Utils.GetItemIdFromLink(itemLink)
    return itemLink and tonumber(itemLink:match("item:(%d+)"))
end

function Addon.Utils.GetItemSuffixIdFromLink(itemLink)
    if not itemLink then
        return nil
    end

    local itemString = itemLink:match("|H(item[%-%d:]+)|h") or itemLink:match("^(item[%-%d:]+)$")
    if not itemString then
        return nil
    end

    local fieldsText = itemString:match("^item:(.+)$")
    if not fieldsText then
        return nil
    end

    local fields = {}
    for field in string.gmatch(fieldsText, "([^:]+)") do
        fields[#fields + 1] = field
    end

    return tonumber(fields[7] or "")
end

function Addon.Utils.GetPlainItemNameFromLink(itemLink)
    if not itemLink then
        return nil
    end

    local bracketName = itemLink:match("%[(.+)%]")
    if bracketName and bracketName ~= "" then
        return bracketName
    end

    local itemName = GetItemInfo(itemLink)
    if itemName and itemName ~= "" then
        return itemName
    end

    return nil
end

function Addon.Utils.GetItemIdFromTooltip(tooltip)
    if not tooltip or not tooltip.GetItem then
        return nil
    end

    local _, itemLink = tooltip:GetItem()
    return Addon.Utils.GetItemIdFromLink(itemLink)
end

function Addon.Utils.FormatMoneyShort(copper)
    if not copper or copper <= 0 then
        return "-"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local remainingCopper = copper % 100

    if gold > 0 then
        return string.format("%dg %02ds", gold, silver)
    end

    return string.format("%ds %02dc", silver, remainingCopper)
end
