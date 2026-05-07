local _, Addon = ...
Addon.BrowseColumn = Addon.BrowseColumn or {}

Addon.BrowseColumn.retryScheduled = false
Addon.BrowseColumn.retryAttempts = 0
Addon.BrowseColumn.maxRetryAttempts = 5

function Addon.BrowseColumn.IsEnabled()
    return Addon.DB and Addon.DB.IsBrowsePriceColumnEnabled and Addon.DB.IsBrowsePriceColumnEnabled()
end

function Addon.BrowseColumn.ClearBrowseRowDisplay(row)
    if not row or not row.TreenAHAvgText then
        return
    end

    row.TreenAHAvgText:SetText("")
    row.TreenAHAvgText:SetTextColor(1.0, 1.0, 1.0)
end

function Addon.BrowseColumn.ShouldSkipForLargeResultSet()
    return Addon.Scanner and Addon.Scanner.IsLikelyGetAllResult and Addon.Scanner.IsLikelyGetAllResult()
end

function Addon.BrowseColumn.SetBrowseRowNeutral(row, text)
    if not row or not row.TreenAHAvgText then
        return
    end

    row.TreenAHAvgText:SetText(text or "-")
    row.TreenAHAvgText:SetTextColor(0.5, 0.5, 0.5)
end

function Addon.BrowseColumn.ScheduleRetry()
    if Addon.BrowseColumn.retryScheduled then
        return
    end

    if Addon.BrowseColumn.ShouldSkipForLargeResultSet() then
        Addon.BrowseColumn.retryAttempts = 0
        return
    end

    if (Addon.BrowseColumn.retryAttempts or 0) >= (Addon.BrowseColumn.maxRetryAttempts or 5) then
        return
    end

    Addon.BrowseColumn.retryScheduled = true
    Addon.BrowseColumn.retryAttempts = (Addon.BrowseColumn.retryAttempts or 0) + 1

    C_Timer.After(0.05, function()
        Addon.BrowseColumn.retryScheduled = false

        if Addon.BrowseColumn.ShouldSkipForLargeResultSet() then
            Addon.BrowseColumn.retryAttempts = 0
            return
        end

        Addon.BrowseColumn.UpdateBrowseColumn()
    end)
end

function Addon.BrowseColumn.CreateBrowseColumn()
    ---@diagnostic disable-next-line: undefined-global
    if not AuctionFrameBrowse.TreenAHAvgHeader then
        ---@diagnostic disable-next-line: undefined-global
        local header = AuctionFrameBrowse:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ---@diagnostic disable-next-line: undefined-global
        header:SetPoint("BOTTOMRIGHT", BrowseButton1, "TOPRIGHT", -150, 2)
        header:SetText("Avg / Δ%")
        ---@diagnostic disable-next-line: undefined-global
        AuctionFrameBrowse.TreenAHAvgHeader = header
    end

    for i = 1, NUM_BROWSE_TO_DISPLAY do
        local row = _G["BrowseButton" .. i]

        if row and not row.TreenAHAvgText then
            local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txt:SetWidth(95)
            txt:SetJustifyH("RIGHT")
            txt:SetPoint("RIGHT", row, "RIGHT", -150, 0)
            txt:SetText("")
            row.TreenAHAvgText = txt
        end
    end

    if not Addon.browseHooked then
        hooksecurefunc("AuctionFrameBrowse_Update", function()
            Addon.BrowseColumn.UpdateBrowseColumn()
        end)

        Addon.browseHooked = true
    end

    Addon.BrowseColumn.RefreshVisibility()
end

function Addon.BrowseColumn.UpdateBrowseColumn()
    if not Addon.BrowseColumn.IsEnabled() then
        Addon.BrowseColumn.retryAttempts = 0
        Addon.BrowseColumn.RefreshVisibility()
        return
    end

    Addon.BrowseColumn.RefreshVisibility()

    if Addon.BrowseColumn.ShouldSkipForLargeResultSet() then
        Addon.BrowseColumn.retryAttempts = 0
        for i = 1, NUM_BROWSE_TO_DISPLAY do
            local row = _G["BrowseButton" .. i]
            if row and row.TreenAHAvgText then
                Addon.BrowseColumn.SetBrowseRowNeutral(row, "GetAll")
            end
        end
        return
    end

    local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    local numDisplayed = GetNumAuctionItems("list") or 0
    local needsRetry = false

    for i = 1, NUM_BROWSE_TO_DISPLAY do
        local row = _G["BrowseButton" .. i]

        if row and row.TreenAHAvgText then
            Addon.BrowseColumn.ClearBrowseRowDisplay(row)

            if row:IsShown() then
                local dataIndex = offset + i

                if dataIndex <= numDisplayed then
                    local auctionInfo = Addon.Scanner.GetAuctionData(dataIndex)

                    if not auctionInfo
                        or not auctionInfo.itemID
                        or not auctionInfo.count
                        or auctionInfo.count <= 0
                        or not auctionInfo.buyoutPrice
                        or auctionInfo.buyoutPrice <= 0 then

                        needsRetry = true
                        Addon.BrowseColumn.SetBrowseRowNeutral(row, "...")
                    else
                        local recordKey = auctionInfo.recordKey or auctionInfo.itemID
                        local historicalAvgLow = Addon.DB.GetHistoricalAverageLowPrice(recordKey)
                        local unitPrice = math.floor(auctionInfo.buyoutPrice / auctionInfo.count)
                        local percentDiff = Addon.Utils.GetPercentDiffFromAverage(unitPrice, historicalAvgLow)

                        if not historicalAvgLow or not percentDiff then
                            Addon.BrowseColumn.SetBrowseRowNeutral(row, "-")
                        else
                            row.TreenAHAvgText:SetText(
                                Addon.Utils.FormatMoneyShort(historicalAvgLow)
                                    .. "\n"
                                    .. Addon.Utils.FormatPercentDiff(percentDiff)
                            )
                            row.TreenAHAvgText:SetTextColor(Addon.Utils.GetPercentColor(percentDiff))
                        end
                    end
                end
            end
        end
    end

    if needsRetry then
        Addon.BrowseColumn.ScheduleRetry()
    else
        Addon.BrowseColumn.retryAttempts = 0
    end
end

function Addon.BrowseColumn.RefreshVisibility()
    local enabled = Addon.BrowseColumn.IsEnabled()

    ---@diagnostic disable-next-line: undefined-global
    if AuctionFrameBrowse and AuctionFrameBrowse.TreenAHAvgHeader then
        if enabled then
            ---@diagnostic disable-next-line: undefined-global
            AuctionFrameBrowse.TreenAHAvgHeader:Show()
        else
            ---@diagnostic disable-next-line: undefined-global
            AuctionFrameBrowse.TreenAHAvgHeader:Hide()
        end
    end

    for i = 1, NUM_BROWSE_TO_DISPLAY do
        local row = _G["BrowseButton" .. i]
        if row and row.TreenAHAvgText then
            if enabled then
                row.TreenAHAvgText:Show()
            else
                row.TreenAHAvgText:SetText("")
                row.TreenAHAvgText:Hide()
            end
        end
    end
end
