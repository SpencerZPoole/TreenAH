local AddonName, Addon = ...
Addon.DataBrowser = Addon.DataBrowser or {}

Addon.DataBrowser.selectedItemID = nil
Addon.DataBrowser.selectedDay = nil
Addon.DataBrowser.selectedHour = nil

Addon.DataBrowser.rowHeight = 18
Addon.DataBrowser.maxItemsPerPage = 150
Addon.DataBrowser.searchText = ""
Addon.DataBrowser.currentPage = 1
Addon.DataBrowser.pendingSearchToken = 0
Addon.DataBrowser.searchDebounceSeconds = 0.20

local function SafeText(text)
    return text or ""
end

local function SafeTrim(text)
    return text and strtrim(text) or ""
end

local function GetItemEntryKey(itemEntry)
    return itemEntry and (itemEntry.itemKey or itemEntry.itemID) or nil
end

local function FormatItemEntryLabel(itemEntry)
    local itemName = SafeText(itemEntry and itemEntry.name)
    local displayItemID = itemEntry and itemEntry.itemID or nil
    local recordKey = GetItemEntryKey(itemEntry)

    if displayItemID ~= nil then
        return string.format("%s [%d]", itemName, displayItemID)
    end

    return string.format("%s [%s]", itemName, tostring(recordKey or "?"))
end

function Addon.DataBrowser.FormatHourLabel(hour, record)
    local lowText = record and record.low and Addon.Utils.FormatMoneyShort(record.low) or "-"
    return string.format("%02d:00  %s", tonumber(hour) or 0, lowText)
end

function Addon.DataBrowser.FormatSeenAt(seenAt)
    if not seenAt then
        return "N/A"
    end

    return date("%Y-%m-%d %H:%M:%S", seenAt)
end

function Addon.DataBrowser.ClearSelectionBelowItem()
    Addon.DataBrowser.selectedDay = nil
    Addon.DataBrowser.selectedHour = nil
end

function Addon.DataBrowser.ClearSelectionBelowDay()
    Addon.DataBrowser.selectedHour = nil
end

function Addon.DataBrowser.GetSelectedRecord()
    local itemID = Addon.DataBrowser.selectedItemID
    local day = Addon.DataBrowser.selectedDay
    local hour = Addon.DataBrowser.selectedHour

    if not itemID or not day or hour == nil then
        return nil
    end

    return Addon.DB.GetHourRecord(itemID, day, hour)
end

function Addon.DataBrowser.GetNormalizedSearchText()
    return Addon.Utils.NormalizeItemName(Addon.DataBrowser.searchText or "")
end

function Addon.DataBrowser.ItemMatchesSearch(itemEntry, normalizedSearch, numericSearch)
    if not itemEntry then
        return false
    end

    if (not normalizedSearch or normalizedSearch == "") and not numericSearch then
        return true
    end

    if numericSearch and tonumber(itemEntry.itemID) == numericSearch then
        return true
    end

    local normalizedName = Addon.Utils.NormalizeItemName(itemEntry.name or "")
    if normalizedName and normalizedSearch and string.find(normalizedName, normalizedSearch, 1, true) then
        return true
    end

    return false
end

function Addon.DataBrowser.BuildFilteredItemsList()
    local allItems = Addon.DB.GetRecordedItemsList()
    local normalizedSearch = Addon.DataBrowser.GetNormalizedSearchText()
    local numericSearch = tonumber(SafeTrim(Addon.DataBrowser.searchText or ""))
    local filtered = {}

    for _, itemEntry in ipairs(allItems) do
        if Addon.DataBrowser.ItemMatchesSearch(itemEntry, normalizedSearch, numericSearch) then
            filtered[#filtered + 1] = itemEntry
        end
    end

    Addon.DataBrowser.allItemsCount = #allItems
    Addon.DataBrowser.filteredItemsTotal = #filtered
    Addon.DataBrowser.filteredItems = filtered

    local perPage = Addon.DataBrowser.maxItemsPerPage or 150
    local totalPages = math.max(1, math.ceil(#filtered / perPage))
    Addon.DataBrowser.totalPages = totalPages

    if Addon.DataBrowser.currentPage < 1 then
        Addon.DataBrowser.currentPage = 1
    end
    if Addon.DataBrowser.currentPage > totalPages then
        Addon.DataBrowser.currentPage = totalPages
    end

    local startIndex = ((Addon.DataBrowser.currentPage - 1) * perPage) + 1
    local endIndex = math.min(startIndex + perPage - 1, #filtered)

    local paged = {}
    for i = startIndex, endIndex do
        paged[#paged + 1] = filtered[i]
    end

    Addon.DataBrowser.itemsList = paged
    Addon.DataBrowser.pageStartIndex = (#filtered > 0) and startIndex or 0
    Addon.DataBrowser.pageEndIndex = (#filtered > 0) and endIndex or 0

    return paged
end

function Addon.DataBrowser.UpdateItemsSummaryText()
    if not Addon.DataBrowser.itemsSummaryText then
        return
    end

    local total = Addon.DataBrowser.allItemsCount or 0
    local filteredTotal = Addon.DataBrowser.filteredItemsTotal or 0
    local shown = Addon.DataBrowser.itemsList and #Addon.DataBrowser.itemsList or 0
    local searchText = SafeTrim(Addon.DataBrowser.searchText or "")
    local page = Addon.DataBrowser.currentPage or 1
    local totalPages = Addon.DataBrowser.totalPages or 1
    local startIndex = Addon.DataBrowser.pageStartIndex or 0
    local endIndex = Addon.DataBrowser.pageEndIndex or 0

    if shown == 0 then
        if searchText ~= "" then
            Addon.DataBrowser.itemsSummaryText:SetText(string.format(
                "0 matches (%d total items)",
                total
            ))
        else
            Addon.DataBrowser.itemsSummaryText:SetText("0 items")
        end
        return
    end

    if searchText ~= "" then
        Addon.DataBrowser.itemsSummaryText:SetText(string.format(
            "Showing %d-%d of %d matches (%d total items)  |  Page %d/%d",
            startIndex,
            endIndex,
            filteredTotal,
            total,
            page,
            totalPages
        ))
    else
        Addon.DataBrowser.itemsSummaryText:SetText(string.format(
            "Showing %d-%d of %d items  |  Page %d/%d",
            startIndex,
            endIndex,
            total,
            page,
            totalPages
        ))
    end
end

function Addon.DataBrowser.ValidateSelection()
    local itemID = Addon.DataBrowser.selectedItemID
    if itemID and not Addon.DB.GetItemData(itemID) then
        Addon.DataBrowser.selectedItemID = nil
        Addon.DataBrowser.selectedDay = nil
        Addon.DataBrowser.selectedHour = nil
        return
    end

    if itemID then
        local visibleSelected = false
        for _, itemEntry in ipairs(Addon.DataBrowser.filteredItems or {}) do
            if GetItemEntryKey(itemEntry) == itemID then
                visibleSelected = true
                break
            end
        end

        if not visibleSelected then
            Addon.DataBrowser.selectedItemID = nil
            Addon.DataBrowser.selectedDay = nil
            Addon.DataBrowser.selectedHour = nil
            return
        end
    end

    local day = Addon.DataBrowser.selectedDay
    if itemID and day then
        local days = Addon.DB.GetRecordedDays(itemID)
        local dayStillExists = false

        for _, existingDay in ipairs(days) do
            if existingDay == day then
                dayStillExists = true
                break
            end
        end

        if not dayStillExists then
            Addon.DataBrowser.selectedDay = nil
            Addon.DataBrowser.selectedHour = nil
            return
        end
    end

    local hour = Addon.DataBrowser.selectedHour
    if itemID and day and hour ~= nil then
        local hours = Addon.DB.GetRecordedHours(itemID, day)
        local hourStillExists = false

        for _, existingHour in ipairs(hours) do
            if existingHour == hour then
                hourStillExists = true
                break
            end
        end

        if not hourStillExists then
            Addon.DataBrowser.selectedHour = nil
        end
    end
end

function Addon.DataBrowser.SetSearchText(text)
    Addon.DataBrowser.searchText = SafeTrim(text or "")
    Addon.DataBrowser.currentPage = 1
    Addon.DataBrowser.RefreshAll()
end

function Addon.DataBrowser.QueueLiveSearch(text)
    Addon.DataBrowser.searchText = SafeTrim(text or "")
    Addon.DataBrowser.currentPage = 1

    Addon.DataBrowser.pendingSearchToken = (Addon.DataBrowser.pendingSearchToken or 0) + 1
    local token = Addon.DataBrowser.pendingSearchToken

    C_Timer.After(Addon.DataBrowser.searchDebounceSeconds or 0.20, function()
        if token ~= Addon.DataBrowser.pendingSearchToken then
            return
        end

        if Addon.DataBrowser.searchBox then
            local latestText = SafeTrim(Addon.DataBrowser.searchBox:GetText() or "")
            if latestText ~= Addon.DataBrowser.searchText then
                Addon.DataBrowser.searchText = latestText
                Addon.DataBrowser.currentPage = 1
            end
        end

        Addon.DataBrowser.RefreshAll()
    end)
end

function Addon.DataBrowser.ClearSearch()
    Addon.DataBrowser.pendingSearchToken = (Addon.DataBrowser.pendingSearchToken or 0) + 1
    Addon.DataBrowser.searchText = ""
    Addon.DataBrowser.currentPage = 1

    if Addon.DataBrowser.searchBox then
        Addon.DataBrowser.searchBox:SetText("")
    end

    Addon.DataBrowser.RefreshAll()
end

function Addon.DataBrowser.GoToPreviousPage()
    if (Addon.DataBrowser.currentPage or 1) <= 1 then
        return
    end

    Addon.DataBrowser.currentPage = Addon.DataBrowser.currentPage - 1
    Addon.DataBrowser.RefreshAll()
end

function Addon.DataBrowser.GoToNextPage()
    local totalPages = Addon.DataBrowser.totalPages or 1
    if (Addon.DataBrowser.currentPage or 1) >= totalPages then
        return
    end

    Addon.DataBrowser.currentPage = Addon.DataBrowser.currentPage + 1
    Addon.DataBrowser.RefreshAll()
end

function Addon.DataBrowser.UpdatePaginationButtons()
    if not Addon.DataBrowser.prevPageButton or not Addon.DataBrowser.nextPageButton then
        return
    end

    local currentPage = Addon.DataBrowser.currentPage or 1
    local totalPages = Addon.DataBrowser.totalPages or 1

    Addon.DataBrowser.prevPageButton:SetEnabled(currentPage > 1)
    Addon.DataBrowser.nextPageButton:SetEnabled(currentPage < totalPages)

    if Addon.DataBrowser.pageText then
        Addon.DataBrowser.pageText:SetText(string.format("Page %d / %d", currentPage, totalPages))
    end
end

function Addon.DataBrowser.EnsureFrame()
    if Addon.DataBrowser.frame then
        return
    end

    local frame = CreateFrame("Frame", "TreenAH_DataBrowserFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(930, 410)
    frame:SetPoint("CENTER")
    frame:SetToplevel(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -5)
    title:SetText("TreenAH Data Browser")

    Addon.DataBrowser.frame = frame

    local itemsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    itemsLabel:SetText("Items")

    local daysLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    daysLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 310, -34)
    daysLabel:SetText("Days")

    local hoursLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hoursLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 494, -34)
    hoursLabel:SetText("Hours")

    local detailsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 678, -34)
    detailsLabel:SetText("Details")

    local searchBox = CreateFrame("EditBox", "TreenAH_DataBrowserSearchBox", frame, "InputBoxTemplate")
    searchBox:SetSize(170, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end
        Addon.DataBrowser.QueueLiveSearch(self:GetText())
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Addon.DataBrowser.SetSearchText(self:GetText())
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        Addon.DataBrowser.SetSearchText(self:GetText())
    end)
    Addon.DataBrowser.searchBox = searchBox

    local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchButton:SetSize(64, 20)
    searchButton:SetPoint("LEFT", searchBox, "RIGHT", 3, 0)
    searchButton:SetText("Search")
    searchButton:SetScript("OnClick", function()
        Addon.DataBrowser.SetSearchText(Addon.DataBrowser.searchBox:GetText())
    end)
    Addon.DataBrowser.searchButton = searchButton

    local clearSearchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearSearchButton:SetSize(50, 20)
    clearSearchButton:SetPoint("LEFT", searchButton, "RIGHT", 3, 0)
    clearSearchButton:SetText("Clear")
    clearSearchButton:SetScript("OnClick", function()
        Addon.DataBrowser.ClearSearch()
    end)
    Addon.DataBrowser.clearSearchButton = clearSearchButton

    local itemsSummaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemsSummaryText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76)
    itemsSummaryText:SetText("")
    Addon.DataBrowser.itemsSummaryText = itemsSummaryText

    local function CreateListPane(name, parent, x, y, width, height)
        local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        scrollFrame:SetSize(width, height)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetWidth(width - 28)
        content:SetHeight(height)
        scrollFrame:SetScrollChild(content)

        return {
            scrollFrame = scrollFrame,
            content = content,
            buttons = {},
            width = width,
            height = height,
        }
    end

    Addon.DataBrowser.itemsPane = CreateListPane("TreenAH_DataBrowserItemsScroll", frame, 16, -94, 270, 240)
    Addon.DataBrowser.daysPane = CreateListPane("TreenAH_DataBrowserDaysScroll", frame, 310, -52, 160, 300)
    Addon.DataBrowser.hoursPane = CreateListPane("TreenAH_DataBrowserHoursScroll", frame, 494, -52, 160, 300)

    local detailsBox = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    detailsBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 678, -52)
    detailsBox:SetSize(240, 300)
    Addon.DataBrowser.detailsBox = detailsBox

    local detailsText = detailsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailsText:SetPoint("TOPLEFT", detailsBox, "TOPLEFT", 10, -10)
    detailsText:SetPoint("TOPRIGHT", detailsBox, "TOPRIGHT", -10, -10)
    detailsText:SetJustifyH("LEFT")
    detailsText:SetJustifyV("TOP")
    detailsText:SetText("No record selected.")
    Addon.DataBrowser.detailsText = detailsText

    local prevPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    prevPageButton:SetSize(70, 22)
    prevPageButton:SetPoint("TOPLEFT", Addon.DataBrowser.itemsPane.scrollFrame, "BOTTOMLEFT", 16, -3)
    prevPageButton:SetText("Prev")
    prevPageButton:SetScript("OnClick", function()
        Addon.DataBrowser.GoToPreviousPage()
    end)
    Addon.DataBrowser.prevPageButton = prevPageButton

    local nextPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextPageButton:SetSize(70, 22)
    nextPageButton:SetPoint("LEFT", prevPageButton, "RIGHT", 6, 0)
    nextPageButton:SetText("Next")
    nextPageButton:SetScript("OnClick", function()
        Addon.DataBrowser.GoToNextPage()
    end)
    Addon.DataBrowser.nextPageButton = nextPageButton

    local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pageText:SetPoint("LEFT", nextPageButton, "RIGHT", 10, 0)
    pageText:SetText("Page 1 / 1")
    Addon.DataBrowser.pageText = pageText

    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(120, 22)
    refreshButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        Addon.DataBrowser.RefreshAll()
    end)
    Addon.DataBrowser.refreshButton = refreshButton

    local deleteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteButton:SetSize(170, 22)
    deleteButton:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)
    deleteButton:SetText("Delete Selected Record")
    deleteButton:SetScript("OnClick", function()
        StaticPopup_Show("TREENAH_CONFIRM_DELETE")
    end)
    Addon.DataBrowser.deleteButton = deleteButton

    local clearHistoryButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearHistoryButton:SetSize(175, 22)
    clearHistoryButton:SetPoint("LEFT", deleteButton, "RIGHT", 64, 0)
    clearHistoryButton:SetText("Delete ALL Market Data")
    clearHistoryButton:SetScript("OnClick", function()
        StaticPopup_Show("TREENAH_CONFIRM_CLEAR_HISTORY")
    end)
    Addon.DataBrowser.clearHistoryButton = clearHistoryButton

    local hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    hintText:SetPoint("TOP", clearHistoryButton, "TOP", 0, -2)
    hintText:SetText("Search items, browse pages, then select item -> day -> hour.")
end

function Addon.DataBrowser.GetOrCreateRowButton(pane, index)
    if pane.buttons[index] then
        return pane.buttons[index]
    end

    local button = CreateFrame("Button", nil, pane.content)
    button:SetHeight(Addon.DataBrowser.rowHeight)
    button:SetPoint("TOPLEFT", pane.content, "TOPLEFT", 0, -((index - 1) * Addon.DataBrowser.rowHeight))
    button:SetPoint("TOPRIGHT", pane.content, "TOPRIGHT", 0, -((index - 1) * Addon.DataBrowser.rowHeight))

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0)

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 4, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText("")

    button.bg = bg
    button.text = text

    pane.buttons[index] = button
    return button
end

function Addon.DataBrowser.HideUnusedButtons(pane, usedCount)
    for i = usedCount + 1, #pane.buttons do
        pane.buttons[i]:Hide()
    end
end

function Addon.DataBrowser.UpdatePaneHeight(pane, itemCount)
    local minHeight = pane.height
    local neededHeight = math.max(minHeight, (itemCount * Addon.DataBrowser.rowHeight) + 4)
    pane.content:SetHeight(neededHeight)
end

function Addon.DataBrowser.StyleRow(button, isSelected)
    if isSelected then
        button.bg:SetVertexColor(0.2, 0.45, 0.85, 0.35)
        button.text:SetTextColor(1.0, 0.82, 0.0)
    else
        button.bg:SetVertexColor(0, 0, 0, 0)
        button.text:SetTextColor(1, 1, 1)
    end
end

function Addon.DataBrowser.RenderItems()
    local pane = Addon.DataBrowser.itemsPane
    local items = Addon.DataBrowser.BuildFilteredItemsList()

    for index, itemEntry in ipairs(items) do
        local button = Addon.DataBrowser.GetOrCreateRowButton(pane, index)
        button:Show()
        local itemKey = GetItemEntryKey(itemEntry)
        button.text:SetText(FormatItemEntryLabel(itemEntry))
        Addon.DataBrowser.StyleRow(button, Addon.DataBrowser.selectedItemID == itemKey)

        button:SetScript("OnClick", function()
            Addon.DataBrowser.selectedItemID = itemKey
            Addon.DataBrowser.ClearSelectionBelowItem()
            Addon.DataBrowser.RefreshAll()
        end)
    end

    Addon.DataBrowser.HideUnusedButtons(pane, #items)
    Addon.DataBrowser.UpdatePaneHeight(pane, #items)
    Addon.DataBrowser.UpdateItemsSummaryText()
    Addon.DataBrowser.UpdatePaginationButtons()
end

function Addon.DataBrowser.RenderDays()
    local pane = Addon.DataBrowser.daysPane
    local itemID = Addon.DataBrowser.selectedItemID
    local days = itemID and Addon.DB.GetRecordedDays(itemID) or {}
    Addon.DataBrowser.daysList = days

    for index, day in ipairs(days) do
        local button = Addon.DataBrowser.GetOrCreateRowButton(pane, index)
        button:Show()
        button.text:SetText(tostring(day))
        Addon.DataBrowser.StyleRow(button, Addon.DataBrowser.selectedDay == day)

        button:SetScript("OnClick", function()
            Addon.DataBrowser.selectedDay = day
            Addon.DataBrowser.ClearSelectionBelowDay()
            Addon.DataBrowser.RefreshAll()
        end)
    end

    Addon.DataBrowser.HideUnusedButtons(pane, #days)
    Addon.DataBrowser.UpdatePaneHeight(pane, #days)
end

function Addon.DataBrowser.RenderHours()
    local pane = Addon.DataBrowser.hoursPane
    local itemID = Addon.DataBrowser.selectedItemID
    local day = Addon.DataBrowser.selectedDay
    local hours = (itemID and day) and Addon.DB.GetRecordedHours(itemID, day) or {}
    Addon.DataBrowser.hoursList = hours

    for index, hour in ipairs(hours) do
        local record = Addon.DB.GetHourRecord(itemID, day, hour)
        local button = Addon.DataBrowser.GetOrCreateRowButton(pane, index)
        button:Show()
        button.text:SetText(Addon.DataBrowser.FormatHourLabel(hour, record))
        Addon.DataBrowser.StyleRow(button, Addon.DataBrowser.selectedHour == hour)

        button:SetScript("OnClick", function()
            Addon.DataBrowser.selectedHour = hour
            Addon.DataBrowser.RefreshDetails()
            Addon.DataBrowser.RenderHours()
        end)
    end

    Addon.DataBrowser.HideUnusedButtons(pane, #hours)
    Addon.DataBrowser.UpdatePaneHeight(pane, #hours)
end

function Addon.DataBrowser.RefreshDetails()
    local detailsText = Addon.DataBrowser.detailsText
    if not detailsText then
        return
    end

    local itemID = Addon.DataBrowser.selectedItemID
    local day = Addon.DataBrowser.selectedDay
    local hour = Addon.DataBrowser.selectedHour

    if not itemID then
        detailsText:SetText("No item selected.")
        return
    end

    local itemData = Addon.DB.GetItemData(itemID)
    local itemName = (itemData and itemData.name) or (Addon.DB.GetRecordDisplayName and Addon.DB.GetRecordDisplayName(itemID))
    local historicalAvg = Addon.DB.GetHistoricalAverageLowPrice(itemID)
    local record = Addon.DataBrowser.GetSelectedRecord()
    local displayItemID = (itemData and itemData.baseItemID) or (Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(itemID)) or itemID

    local lines = {}
    lines[#lines + 1] = string.format("Item: %s", SafeText(itemName))
    lines[#lines + 1] = string.format("Item ID: %s", tostring(displayItemID))
    lines[#lines + 1] = " "
    lines[#lines + 1] = string.format("Selected Day: %s", tostring(day or "None"))
    lines[#lines + 1] = string.format(
        "Selected Hour: %s",
        hour ~= nil and string.format("%02d:00", tonumber(hour) or 0) or "None"
    )
    lines[#lines + 1] = " "
    lines[#lines + 1] = string.format(
        "Historical Avg: %s",
        historicalAvg and Addon.Utils.ConvertToCoinTextureString(math.floor(historicalAvg)) or "N/A"
    )

    if record then
        lines[#lines + 1] = string.format(
            "Recorded Low: %s",
            record.low and Addon.Utils.ConvertToCoinTextureString(record.low) or "N/A"
        )
        lines[#lines + 1] = string.format("Seen At: %s", Addon.DataBrowser.FormatSeenAt(record.seenAt))
    else
        lines[#lines + 1] = "Recorded Low: N/A"
        lines[#lines + 1] = "Seen At: N/A"
    end

    detailsText:SetText(table.concat(lines, "\n"))
end

function Addon.DataBrowser.RefreshAll()
    Addon.DataBrowser.EnsureFrame()
    Addon.DataBrowser.BuildFilteredItemsList()
    Addon.DataBrowser.ValidateSelection()
    Addon.DataBrowser.RenderItems()
    Addon.DataBrowser.RenderDays()
    Addon.DataBrowser.RenderHours()
    Addon.DataBrowser.RefreshDetails()
end

function Addon.DataBrowser.DeleteSelectedRecord()
    local itemID = Addon.DataBrowser.selectedItemID
    local day = Addon.DataBrowser.selectedDay
    local hour = Addon.DataBrowser.selectedHour

    if not itemID then
        Addon.Utils.Print("Select an item, day, or hour first.")
        return
    end

    local selectedItemData = Addon.DB.GetItemData(itemID)
    local itemName = Addon.DB.GetRecordDisplayName and Addon.DB.GetRecordDisplayName(itemID) or Addon.Utils.GetItemDisplayNameByItemID(itemID) or ("Item " .. tostring(itemID))
    local displayItemID = (selectedItemData and selectedItemData.baseItemID) or (Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(itemID)) or itemID

    -- Highest priority: delete selected hour
    if day and hour ~= nil then
        local record = Addon.DB.GetHourRecord(itemID, day, hour)
        local ok, message = Addon.DB.DeleteHourRecord(itemID, day, hour)

        if not ok then
            Addon.Utils.Print(message or "Could not delete hour record.")
            return
        end

        Addon.DataBrowser.selectedHour = nil
        Addon.DataBrowser.ValidateSelection()
        Addon.DataBrowser.RefreshAll()

        Addon.Utils.Print(string.format(
            "Deleted hour record: %s | %s %02d:00 | %s. %s",
            itemName,
            tostring(day),
            tonumber(hour) or 0,
            record and record.low and Addon.Utils.FormatMoneyShort(record.low) or "-",
            message or ""
        ))
        return
    end

    -- Next priority: delete selected day
    if day then
        local ok, message = Addon.DB.DeleteDayRecord(itemID, day)

        if not ok then
            Addon.Utils.Print(message or "Could not delete day record.")
            return
        end

        Addon.DataBrowser.selectedDay = nil
        Addon.DataBrowser.selectedHour = nil
        Addon.DataBrowser.ValidateSelection()
        Addon.DataBrowser.RefreshAll()

        Addon.Utils.Print(string.format(
            "Deleted day record: %s | %s. %s",
            itemName,
            tostring(day),
            message or ""
        ))
        return
    end

    -- Fallback: delete whole item
    local ok, message = Addon.DB.DeleteItemRecord(itemID)

    if not ok then
        Addon.Utils.Print(message or "Could not delete item record.")
        return
    end

    Addon.DataBrowser.selectedItemID = nil
    Addon.DataBrowser.selectedDay = nil
    Addon.DataBrowser.selectedHour = nil
    Addon.DataBrowser.ValidateSelection()
    Addon.DataBrowser.RefreshAll()

    Addon.Utils.Print(string.format(
        "Deleted item record: %s [%s]. %s",
        itemName,
        tostring(displayItemID),
        message or ""
    ))
end

function Addon.DataBrowser.ClearAllPriceHistory()
    if not Addon.DB.ClearPriceHistory then
        Addon.Utils.Print("ClearPriceHistory() is missing from DB.lua.")
        return
    end

    Addon.DB.ClearPriceHistory()

    Addon.DataBrowser.selectedItemID = nil
    Addon.DataBrowser.selectedDay = nil
    Addon.DataBrowser.selectedHour = nil
    Addon.DataBrowser.searchText = ""
    Addon.DataBrowser.currentPage = 1
    Addon.DataBrowser.pendingSearchToken = (Addon.DataBrowser.pendingSearchToken or 0) + 1

    if Addon.DataBrowser.searchBox then
        Addon.DataBrowser.searchBox:SetText("")
    end

    Addon.DataBrowser.RefreshAll()
end

function Addon.DataBrowser.ShowClearAllHistoryConfirmation()
    StaticPopup_Show("TREENAH_CONFIRM_CLEAR_HISTORY")
end

function Addon.DataBrowser.Toggle()
    Addon.DataBrowser.EnsureFrame()

    if Addon.DataBrowser.frame:IsShown() then
        Addon.DataBrowser.frame:Hide()
    else
        Addon.DataBrowser.RefreshAll()
        Addon.DataBrowser.frame:Show()
        Addon.DataBrowser.frame:Raise()
    end
end

StaticPopupDialogs["TREENAH_CONFIRM_DELETE"] = {
    text = "Delete the currently selected hour, day, or item?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        Addon.DataBrowser.DeleteSelectedRecord()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["TREENAH_CONFIRM_CLEAR_HISTORY"] = {
    text = "Type DELETE EVERYTHING to delete ALL recorded price history for ALL items on the current server/faction.\n\nLists and settings will be kept.",
    button1 = "Delete History",
    button2 = "Cancel",
    hasEditBox = 1,
    maxLetters = 32,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,

    EditBoxOnTextChanged = function(editBox)
        local parent = editBox:GetParent()
        local entered = SafeTrim(editBox:GetText() or "")
        local button1 = parent and parent.GetName and _G[parent:GetName() .. "Button1"]

        if button1 then
            button1:SetEnabled(entered == "DELETE EVERYTHING")
        end
    end,

    OnShow = function(self)
        local editBox = self.GetName and _G[self:GetName() .. "EditBox"]
        local button1 = self.GetName and _G[self:GetName() .. "Button1"]

        if editBox then
            editBox:SetText("")
            editBox:SetFocus()
        end

        if button1 then
            button1:SetEnabled(false)
        end
    end,

    OnAccept = function(self)
        local editBox = self.GetName and _G[self:GetName() .. "EditBox"]
        local entered = editBox and SafeTrim(editBox:GetText() or "") or ""

        if entered ~= "DELETE EVERYTHING" then
            Addon.Utils.Print("Clear history cancelled. Confirmation text did not match.")
            return
        end

        Addon.DataBrowser.ClearAllPriceHistory()
    end,
}
