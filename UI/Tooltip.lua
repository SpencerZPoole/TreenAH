local AddonName, Addon = ...
Addon.Tooltip = Addon.Tooltip or {}

function Addon.Tooltip.AddPriceToTooltip(tooltip)
    if not Addon.DB.IsTooltipPriceDataEnabled or not Addon.DB.IsTooltipPriceDataEnabled() then
        return
    end

    if not tooltip or not tooltip.GetItem then
        return
    end

    local _, itemLink = tooltip:GetItem()
    local itemKey = itemLink and Addon.DB.GetRecordedKeyFromLink and Addon.DB.GetRecordedKeyFromLink(itemLink) or nil
    if not itemKey then
        itemKey = Addon.Utils.GetItemIdFromTooltip(tooltip)
    end

    if not itemKey then
        return
    end

    local historicalAvgLow = Addon.DB.GetHistoricalAverageLowPrice(itemKey)
    local mostRecentLow = Addon.DB.GetItemMostRecentLow(itemKey)

    if not historicalAvgLow and not mostRecentLow then
        return
    end

    local showHeader = Addon.DB.IsTooltipHeaderEnabled and Addon.DB.IsTooltipHeaderEnabled()
    local showAverage = Addon.DB.IsTooltipAveragePriceEnabled and Addon.DB.IsTooltipAveragePriceEnabled()
    local showLastSeen = Addon.DB.IsTooltipLastSeenPriceEnabled and Addon.DB.IsTooltipLastSeenPriceEnabled()
    local showDelta = Addon.DB.IsTooltipDeltaEnabled and Addon.DB.IsTooltipDeltaEnabled()

    if not showHeader and not showAverage and not showLastSeen and not showDelta then
        return
    end

    local recentVsAvgPercent = nil
    if mostRecentLow and historicalAvgLow then
        recentVsAvgPercent = Addon.Utils.GetPercentDiffFromAverage(mostRecentLow, historicalAvgLow)
    end

    local deltaR, deltaG, deltaB = Addon.Utils.GetPercentColor(recentVsAvgPercent)
    local deltaLabel = Addon.PriceCheck.GetDeltaLabel(recentVsAvgPercent)

    tooltip:AddLine(" ")

    if showHeader then
        tooltip:AddLine(AddonName, 0.2, 1.0, 0.2)
    end

    if showAverage then
        tooltip:AddLine(
            string.format(
                "Average Price:   %s",
                historicalAvgLow and Addon.Utils.ConvertToCoinTextureString(math.floor(historicalAvgLow)) or "N/A"
            ),
            1.0, 0.82, 0.0
        )
    end

    if showLastSeen then
        tooltip:AddLine(
            string.format(
                "Last Seen Price:   %s",
                mostRecentLow and Addon.Utils.ConvertToCoinTextureString(mostRecentLow) or "N/A"
            ),
            1.0, 0.82, 0.0
        )
    end

    if showDelta then
        if recentVsAvgPercent then
            local tooltipText = string.format("Last Seen vs Avg:  %s", Addon.Utils.FormatPercentDiff(recentVsAvgPercent))
            if deltaLabel then
                tooltipText = tooltipText .. " " .. deltaLabel
            end
            tooltip:AddLine(tooltipText, deltaR, deltaG, deltaB)
        else
            tooltip:AddLine("Last Seen vs Avg:   N/A", 0.5, 0.5, 0.5)
        end
    end

    tooltip:Show()
end

-- Configurable list of tooltips to hook; users can modify this table as needed
Addon.TooltipsToHook = {
    GameTooltip,
    ItemRefTooltip,
    ShoppingTooltip1,
    ShoppingTooltip2,
}

function Addon.Tooltip.HookTooltips()
    for _, tooltip in ipairs(Addon.TooltipsToHook) do
        if tooltip and tooltip.HookScript then
            tooltip:HookScript("OnTooltipSetItem", function(tip)
                Addon.Tooltip.AddPriceToTooltip(tip)
            end)
        end
    end
end
