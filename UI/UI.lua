local AddonName, Addon = ...

Addon.UI = Addon.UI or {}
Addon.UI.outputLines = Addon.UI.outputLines or {}
Addon.UI.maxOutputLines = 60
Addon.UI.scanSummary = Addon.UI.scanSummary or nil
Addon.UI.maxScanEventLines = 5
Addon.UI.scanSpinnerFrames = { "|", "/", "-", "\\" }
Addon.UI.scanSpinnerIndex = 1
Addon.UI.spinnerElapsed = 0
Addon.UI.spinnerInterval = 0.15 -- tweak this (0.1 = faster, 0.2 = slower)
Addon.UI.spinnerTicker = nil

Addon.UI.mainPanel = nil
Addon.UI.outputText = nil

Addon.UI.importListFrame = nil
Addon.UI.importSourceCharacterKey = nil
Addon.UI.importSourceListKey = nil

Addon.UI.selectedTrackedItemName = nil
Addon.UI.fullScanMode = Addon.UI.fullScanMode or "fast"
Addon.UI.trackedScanTarget = Addon.UI.trackedScanTarget or "__selected__"

local function SafeTrim(text)
    return text and strtrim(text) or ""
end

local function GetPopupEditBox(dialog)
    if not dialog then
        return nil
    end

    if dialog.editBox then
        return dialog.editBox
    end

    local dialogName = dialog.GetName and dialog:GetName()
    if dialogName and _G[dialogName .. "EditBox"] then
        return _G[dialogName .. "EditBox"]
    end

    return nil
end

local function CreateSectionLabel(parent, text, point, relativeTo, relativePoint, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint(point, relativeTo, relativePoint, x, y)
    label:SetText(text)
    return label
end

local function CreateListPane(parent, name, width, height)
    local frame = CreateFrame("Frame", nil, parent, "InsetFrameTemplate3")
    frame:SetSize(width, height)

    local scrollFrame = CreateFrame("ScrollFrame", name, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(width - 30)
    content:SetHeight(height)

    scrollFrame:SetScrollChild(content)

    return {
        frame = frame,
        scrollFrame = scrollFrame,
        content = content,
        buttons = {},
        rowHeight = 20,
    }
end

local function GetOrCreatePaneButton(pane, index)
    if pane.buttons[index] then
        return pane.buttons[index]
    end

    local button = CreateFrame("Button", nil, pane.content)
    button:SetHeight(pane.rowHeight)
    button:SetPoint("TOPLEFT", pane.content, "TOPLEFT", 0, -((index - 1) * pane.rowHeight))
    button:SetPoint("TOPRIGHT", pane.content, "TOPRIGHT", 0, -((index - 1) * pane.rowHeight))

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.bg:SetVertexColor(0, 0, 0, 0)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.highlight:SetVertexColor(1, 1, 1, 0.08)

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetPoint("RIGHT", -6, 0)
    button.text:SetJustifyH("LEFT")

    pane.buttons[index] = button
    return button
end

local function HideUnusedPaneButtons(pane, usedCount)
    for i = usedCount + 1, #pane.buttons do
        pane.buttons[i]:Hide()
    end
end

local function UpdatePaneHeight(pane, itemCount)
    local minHeight = pane.scrollFrame:GetHeight()
    local neededHeight = math.max(minHeight, (itemCount * pane.rowHeight) + 4)
    pane.content:SetHeight(neededHeight)
end

local function StylePaneButton(button, isSelected)
    if isSelected then
        button.bg:SetVertexColor(0.20, 0.45, 0.80, 0.35)
    else
        button.bg:SetVertexColor(0, 0, 0, 0)
    end
end

function Addon.UI.ToggleMainPanel()
    if not Addon.UI.mainPanel then
        Addon.UI.CreateMainPanel()
    end

    if not Addon.UI.mainPanel then
        return
    end

    if Addon.UI.mainPanel:IsShown() then
        Addon.UI.HideMainPanel()
    else
        Addon.UI.ShowMainPanel()
    end
end

function Addon.UI.CreateAuctionHouseToggleButton()
    if Addon.UI.auctionHouseToggleButton then
        return
    end

    local button = CreateFrame("Button", "TreenAH_AuctionHouseToggleButton", AuctionFrame, "UIPanelButtonTemplate")
    button:SetSize(70, 18)
    button:SetText("TreenAH")

    -- Anchor near the top-right of the AH window, just left of the close button area.
    button:SetPoint("TOPRIGHT", AuctionFrameCloseButton, "TOPLEFT", -8, -7)

    button:SetScript("OnClick", function()
        Addon.UI.ToggleMainPanel()
    end)

    Addon.UI.auctionHouseToggleButton = button
end

function Addon.UI.ShowMainPanel()
    if not Addon.UI.mainPanel then
        Addon.UI.CreateMainPanel()
    end

    if Addon.UI.mainPanel then
        Addon.UI.mainPanel:Show()
        Addon.UI.UpdateStatusLine()
    end
end

function Addon.UI.HideMainPanel()
    if Addon.UI.mainPanel then
        Addon.UI.mainPanel:Hide()
    end
end

local function BuildTrackedListSummaryText(listEntry)
    if not listEntry then
        return ""
    end

    return string.format("%s (%d)", listEntry.name or "Unknown", listEntry.itemCount or 0)
end

function Addon.UI.UpdateStatusLine()
    if not Addon.UI.statusText then
        return
    end

    local selectedName = Addon.TrackedItems.GetSelectedListName and Addon.TrackedItems.GetSelectedListName() or "Default"

    if Addon.Scanner and Addon.Scanner.IsScanActive and Addon.Scanner.IsScanActive() and Addon.scanSession then
        local mode = Addon.scanSession.mode or "scan"

        if mode == "tracked" then
            local listName = Addon.scanSession.trackedScanDisplayName or selectedName
            local currentIndex = Addon.scanSession.trackedItemsSearchingIndex or 0
            local total = #(Addon.scanSession.trackedItemsList or {})
            Addon.UI.statusText:SetText(string.format("List Scan: %s (%d/%d)", listName, currentIndex, total))
            Addon.UI.RefreshStopScanButton()
            return
        elseif mode == "item" then
            Addon.UI.statusText:SetText("Single Item Scan in progress...")
            Addon.UI.RefreshStopScanButton()
            return
        elseif mode == "getall" then
            Addon.UI.statusText:SetText("Fast Full Scan in progress...")
            Addon.UI.RefreshStopScanButton()
            return
        elseif mode == "full" then
            Addon.UI.statusText:SetText("Slow Full Scan in progress...")
            Addon.UI.RefreshStopScanButton()
            return
        end
    end

    Addon.UI.statusText:SetText("Selected List: " .. tostring(selectedName))
    Addon.UI.RefreshStopScanButton()
end

function Addon.UI.RefreshStopScanButton()
    if not Addon.UI.stopScanButton then
        return
    end

    local isActive = Addon.Scanner and Addon.Scanner.IsScanActive and Addon.Scanner.IsScanActive()
    Addon.UI.stopScanButton:SetEnabled(isActive and true or false)
end

function Addon.UI.RefreshTrackedListsPane()
    if not Addon.UI.trackedListsPane then
        return
    end

    local pane = Addon.UI.trackedListsPane
    local entries = Addon.TrackedItems.GetTrackedListEntries and Addon.TrackedItems.GetTrackedListEntries() or {}
    local selectedKey = Addon.TrackedItems.GetSelectedListKey and Addon.TrackedItems.GetSelectedListKey() or nil

    Addon.UI.trackedListEntries = entries

    for index, entry in ipairs(entries) do
        local button = GetOrCreatePaneButton(pane, index)
        button:Show()
        button.text:SetText(BuildTrackedListSummaryText(entry))
        StylePaneButton(button, entry.key == selectedKey)

        button:SetScript("OnClick", function()
            local ok = Addon.TrackedItems.SetSelectedListKey(entry.key)
            if ok then
                Addon.UI.selectedTrackedItemName = nil
                Addon.UI.RefreshTrackedListsPane()
                Addon.UI.RefreshTrackedItemsPane()
                Addon.UI.UpdateStatusLine()
            end
        end)
    end

    HideUnusedPaneButtons(pane, #entries)
    UpdatePaneHeight(pane, #entries)
end

function Addon.UI.RefreshTrackedItemsPane()
    if not Addon.UI.trackedItemsPane then
        return
    end

    local pane = Addon.UI.trackedItemsPane
    local selectedListKey = Addon.TrackedItems.GetSelectedListKey()
    local items = Addon.TrackedItems.GetTrackedItemsList(selectedListKey) or {}

    Addon.UI.currentTrackedItemEntries = items

    local selectedStillExists = false
    for _, itemName in ipairs(items) do
        if itemName == Addon.UI.selectedTrackedItemName then
            selectedStillExists = true
            break
        end
    end

    if not selectedStillExists then
        Addon.UI.selectedTrackedItemName = nil
    end

    for index, itemName in ipairs(items) do
        local button = GetOrCreatePaneButton(pane, index)
        button:Show()
        button.text:SetText(itemName)
        StylePaneButton(button, itemName == Addon.UI.selectedTrackedItemName)

        button:SetScript("OnClick", function()
            Addon.UI.selectedTrackedItemName = itemName
            Addon.UI.RefreshTrackedItemsPane()
        end)
    end

    HideUnusedPaneButtons(pane, #items)
    UpdatePaneHeight(pane, #items)
end

function Addon.UI.RefreshAllTrackedUI()
    Addon.UI.RefreshTrackedListsPane()
    Addon.UI.RefreshTrackedItemsPane()
    Addon.UI.RefreshTrackedScanTargetDropdown()
    Addon.UI.UpdateStatusLine()
end

function Addon.UI.SetFullScanMode(value)
    Addon.UI.fullScanMode = value or "fast"
    UIDropDownMenu_SetText(Addon.UI.fullScanModeDropdown, Addon.UI.fullScanMode == "fast" and "Fast Full Scan" or "Slow Full Scan")
end

function Addon.UI.RefreshFullScanModeDropdown()
    if not Addon.UI.fullScanModeDropdown then
        return
    end

    UIDropDownMenu_Initialize(Addon.UI.fullScanModeDropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Slow Full Scan"
        info.func = function()
            Addon.UI.SetFullScanMode("slow")
        end
        info.checked = (Addon.UI.fullScanMode == "slow")
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Fast Full Scan"
        info.func = function()
            Addon.UI.SetFullScanMode("fast")
        end
        info.checked = (Addon.UI.fullScanMode == "fast")
        UIDropDownMenu_AddButton(info, level)
    end)

    Addon.UI.SetFullScanMode(Addon.UI.fullScanMode or "fast")
end

function Addon.UI.SetTrackedScanTarget(value, text)
    Addon.UI.trackedScanTarget = value or "__selected__"
    UIDropDownMenu_SetText(Addon.UI.trackedScanTargetDropdown, text or "Selected List")
end

function Addon.UI.RefreshTrackedScanTargetDropdown()
    if not Addon.UI.trackedScanTargetDropdown then
        return
    end

    local entries = Addon.TrackedItems.GetTrackedScanTargetEntries and Addon.TrackedItems.GetTrackedScanTargetEntries() or {}
    local foundCurrent = false
    local currentText = "Selected List"

    UIDropDownMenu_Initialize(Addon.UI.trackedScanTargetDropdown, function(self, level)
        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.func = function()
                Addon.UI.SetTrackedScanTarget(entry.value, entry.text)
            end
            info.checked = (Addon.UI.trackedScanTarget == entry.value)
            UIDropDownMenu_AddButton(info, level)

            if Addon.UI.trackedScanTarget == entry.value then
                foundCurrent = true
                currentText = entry.text
            end
        end
    end)

    if not foundCurrent then
        Addon.UI.trackedScanTarget = "__selected__"
        currentText = "Selected List"
    end

    UIDropDownMenu_SetText(Addon.UI.trackedScanTargetDropdown, currentText)
end

function Addon.UI.StartSelectedFullScan()
    if Addon.Scanner.IsScanActive() then
        Addon.Utils.PrintError("A scan is already in progress.")
        return
    end

    if Addon.UI.fullScanMode == "fast" then
        Addon.Scanner.StartGetAllScan()
    else
        Addon.Scanner.StartFullScan()
    end

    Addon.UI.UpdateStatusLine()
end

function Addon.UI.StartItemScanFromInput()
    if Addon.Scanner.IsScanActive() then
        Addon.Utils.PrintError("A scan is already in progress.")
        return
    end

    local itemName = SafeTrim(Addon.UI.itemInput and Addon.UI.itemInput:GetText() or "")
    if itemName == "" then
        Addon.Utils.PrintError("Enter an item name first.")
        return
    end

    Addon.Scanner.StartItemScan(itemName)
    Addon.UI.UpdateStatusLine()
end

function Addon.UI.OutputItemHistoryFromInput()
    local itemInput = SafeTrim(Addon.UI.itemInput and Addon.UI.itemInput:GetText() or "")
    if itemInput == "" then
        Addon.Utils.PrintError("Enter an item name or item ID first.")
        return
    end

    local itemID, resolveError = Addon.PriceCheck.ResolveRecordedItemID(itemInput)
    if not itemID then
        Addon.Utils.PrintError(resolveError or ("No recorded item match for '" .. itemInput .. "'."))
        return
    end

    Addon.UI.OutputItemHistory(itemID)
end

function Addon.UI.AddTrackedItemFromInput()
    local itemName = SafeTrim(Addon.UI.trackedItemInput and Addon.UI.trackedItemInput:GetText() or "")
    local selectedListKey = Addon.TrackedItems.GetSelectedListKey()

    local ok, result = Addon.TrackedItems.AddTrackedItem(itemName, selectedListKey)
    if ok then
        Addon.UI.trackedItemInput:SetText("")
        Addon.UI.selectedTrackedItemName = result
        Addon.TrackedItems.RefreshTrackedItemsList()
        Addon.UI.RenderSummary("Now tracking in " .. Addon.TrackedItems.GetSelectedListName() .. ":\n" .. result)
    else
        Addon.UI.RenderSummary(result or "Could not add item.")
    end
end

function Addon.UI.RemoveSelectedTrackedItem()
    local itemName = Addon.UI.selectedTrackedItemName or SafeTrim(Addon.UI.trackedItemInput and Addon.UI.trackedItemInput:GetText() or "")
    local selectedListKey = Addon.TrackedItems.GetSelectedListKey()

    if not itemName or itemName == "" then
        Addon.Utils.PrintError("Select or enter an item to remove.")
        return
    end

    local ok, result = Addon.TrackedItems.RemoveTrackedItem(itemName, selectedListKey)
    if ok then
        Addon.UI.selectedTrackedItemName = nil
        Addon.UI.trackedItemInput:SetText("")
        Addon.TrackedItems.RefreshTrackedItemsList()
        Addon.UI.RenderSummary("Removed item:\n" .. result)
    else
        Addon.UI.RenderSummary(result or "Could not remove item.")
    end
end

function Addon.UI.StartTrackedScanFromSelection()
    if Addon.Scanner.IsScanActive() then
        Addon.Utils.PrintError("A scan is already in progress.")
        return
    end

    Addon.Scanner.StartTrackedItemsScan(Addon.UI.trackedScanTarget or "__selected__")
    Addon.UI.UpdateStatusLine()
end

function Addon.UI.ShowCreateListPopup()
    StaticPopup_Show("TREENAH_NEW_TRACKED_LIST")
end

function Addon.UI.ShowRenameListPopup()
    local selectedKey = Addon.TrackedItems.GetSelectedListKey()
    local entries = Addon.TrackedItems.GetTrackedListEntries()

    for _, entry in ipairs(entries) do
        if entry.key == selectedKey and not Addon.TrackedItems.CanModifyList(selectedKey) then
            Addon.Utils.PrintError("That core list cannot be renamed.")
            return
        end
    end

    local dialog = StaticPopup_Show("TREENAH_RENAME_TRACKED_LIST")
    local editBox = GetPopupEditBox(dialog)
    if editBox then
        editBox:SetText(Addon.TrackedItems.GetSelectedListName() or "")
        editBox:HighlightText()
        editBox:SetFocus()
    end
end

function Addon.UI.ShowDuplicateListPopup()
    local dialog = StaticPopup_Show("TREENAH_DUPLICATE_TRACKED_LIST")
    local editBox = GetPopupEditBox(dialog)
    if editBox then
        editBox:SetText((Addon.TrackedItems.GetSelectedListName() or "List") .. " Copy")
        editBox:HighlightText()
        editBox:SetFocus()
    end
end

function Addon.UI.DeleteSelectedTrackedList()
    local selectedKey = Addon.TrackedItems.GetSelectedListKey()
    local ok, result = Addon.TrackedItems.DeleteTrackedList(selectedKey)

    if ok then
        Addon.UI.selectedTrackedItemName = nil
        Addon.TrackedItems.RefreshTrackedItemsList()
        Addon.UI.RenderSummary("Deleted list:\n" .. tostring(result))
    else
        Addon.UI.RenderSummary(result or "Could not delete list.")
    end
end

local function BuildImportCharacterDisplayText(characterKey)
    if not characterKey or characterKey == "" then
        return "Select Character"
    end

    return tostring(characterKey)
end

function Addon.UI.RefreshImportListSourceListDropdown()
    if not Addon.UI.importSourceListDropdown then
        return
    end

    local sourceCharacterKey = Addon.UI.importSourceCharacterKey
    local entries = {}

    if sourceCharacterKey then
        entries = Addon.TrackedItems.GetTrackedListEntriesForCharacter(sourceCharacterKey) or {}
    end

    local selectedText = "Select List"
    local foundSelected = false

    UIDropDownMenu_Initialize(Addon.UI.importSourceListDropdown, function(self, level)
        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = string.format("%s (%d)", entry.name or "Unknown", entry.itemCount or 0)
            info.func = function()
                Addon.UI.importSourceListKey = entry.key
                UIDropDownMenu_SetText(Addon.UI.importSourceListDropdown, info.text)

                if Addon.UI.importListNameInput then
                    local currentText = strtrim(Addon.UI.importListNameInput:GetText() or "")
                    if currentText == "" then
                        Addon.UI.importListNameInput:SetText(entry.name or "")
                    end
                end
            end
            info.checked = (Addon.UI.importSourceListKey == entry.key)
            UIDropDownMenu_AddButton(info, level)

            if Addon.UI.importSourceListKey == entry.key then
                selectedText = info.text
                foundSelected = true
            end
        end
    end)

    if not foundSelected then
        Addon.UI.importSourceListKey = nil
    end

    UIDropDownMenu_SetText(Addon.UI.importSourceListDropdown, selectedText)
end

function Addon.UI.RefreshImportListSourceCharacterDropdown()
    if not Addon.UI.importSourceCharacterDropdown then
        return
    end

    local characterKeys = Addon.TrackedItems.GetAvailableCharacterKeys() or {}
    local selectedText = "Select Character"
    local foundSelected = false

    UIDropDownMenu_Initialize(Addon.UI.importSourceCharacterDropdown, function(self, level)
        for _, characterKey in ipairs(characterKeys) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = BuildImportCharacterDisplayText(characterKey)
            info.func = function()
                Addon.UI.importSourceCharacterKey = characterKey
                Addon.UI.importSourceListKey = nil
                UIDropDownMenu_SetText(Addon.UI.importSourceCharacterDropdown, info.text)
                Addon.UI.RefreshImportListSourceListDropdown()
            end
            info.checked = (Addon.UI.importSourceCharacterKey == characterKey)
            UIDropDownMenu_AddButton(info, level)

            if Addon.UI.importSourceCharacterKey == characterKey then
                selectedText = info.text
                foundSelected = true
            end
        end
    end)

    if not foundSelected then
        Addon.UI.importSourceCharacterKey = nil
        Addon.UI.importSourceListKey = nil
    end

    UIDropDownMenu_SetText(Addon.UI.importSourceCharacterDropdown, selectedText)
    Addon.UI.RefreshImportListSourceListDropdown()
end

function Addon.UI.ConfirmImportTrackedList()
    local sourceCharacterKey = Addon.UI.importSourceCharacterKey
    local sourceListKey = Addon.UI.importSourceListKey
    local newListName = strtrim(Addon.UI.importListNameInput and Addon.UI.importListNameInput:GetText() or "")

    if not sourceCharacterKey then
        Addon.Utils.PrintError("Select a source character first.")
        return
    end

    if not sourceListKey then
        Addon.Utils.PrintError("Select a source list first.")
        return
    end

    if newListName == "" then
        Addon.Utils.PrintError("Enter a name for the imported list.")
        return
    end

    local ok, result = Addon.TrackedItems.ImportTrackedListFromCharacter(sourceCharacterKey, sourceListKey, newListName)
    if ok then
        Addon.TrackedItems.SetSelectedListKey(result)
        Addon.UI.selectedTrackedItemName = nil
        Addon.TrackedItems.RefreshTrackedItemsList()
        Addon.UI.RenderSummary("Imported list:\n" .. newListName)

        if Addon.UI.importListFrame then
            Addon.UI.importListFrame:Hide()
        end
    else
        Addon.UI.RenderSummary(result or "Could not import list.")
    end
end

function Addon.UI.CreateImportListFrame()
    if Addon.UI.importListFrame then
        return
    end

    local frame = CreateFrame("Frame", "TreenAH_ImportListFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(360, 250)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Import Tracked List")

    local sourceCharacterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceCharacterLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    sourceCharacterLabel:SetText("Source Character")

    local sourceCharacterDropdown = CreateFrame("Frame", "TreenAH_ImportSourceCharacterDropdown", frame, "UIDropDownMenuTemplate")
    sourceCharacterDropdown:SetPoint("TOPLEFT", sourceCharacterLabel, "BOTTOMLEFT", -14, -2)
    UIDropDownMenu_SetWidth(sourceCharacterDropdown, 220)
    UIDropDownMenu_SetText(sourceCharacterDropdown, "Select Character")
    Addon.UI.importSourceCharacterDropdown = sourceCharacterDropdown

    local sourceListLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceListLabel:SetPoint("TOPLEFT", sourceCharacterDropdown, "BOTTOMLEFT", 18, -10)
    sourceListLabel:SetText("Source List")

    local sourceListDropdown = CreateFrame("Frame", "TreenAH_ImportSourceListDropdown", frame, "UIDropDownMenuTemplate")
    sourceListDropdown:SetPoint("TOPLEFT", sourceListLabel, "BOTTOMLEFT", -14, -2)
    UIDropDownMenu_SetWidth(sourceListDropdown, 220)
    UIDropDownMenu_SetText(sourceListDropdown, "Select List")
    Addon.UI.importSourceListDropdown = sourceListDropdown

    local newNameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    newNameLabel:SetPoint("TOPLEFT", sourceListDropdown, "BOTTOMLEFT", 18, -12)
    newNameLabel:SetText("Imported List Name")

    local nameInput = CreateFrame("EditBox", "TreenAH_ImportListNameInput", frame, "InputBoxTemplate")
    nameInput:SetSize(180, 20)
    nameInput:SetPoint("TOPLEFT", newNameLabel, "BOTTOMLEFT", 0, -6)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    nameInput:SetScript("OnEnterPressed", function(self)
        Addon.UI.ConfirmImportTrackedList()
        self:ClearFocus()
    end)
    Addon.UI.importListNameInput = nameInput

    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpText:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -10)
    helpText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Copies one tracked list from another character into this character's saved lists.")

    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(80, 22)
    importButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        Addon.UI.ConfirmImportTrackedList()
    end)

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(80, 22)
    cancelButton:SetPoint("RIGHT", importButton, "LEFT", -6, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    Addon.UI.importListFrame = frame
end

function Addon.UI.ShowImportListPopup()
    Addon.UI.CreateImportListFrame()

    Addon.UI.importSourceCharacterKey = nil
    Addon.UI.importSourceListKey = nil

    if Addon.UI.importListNameInput then
        Addon.UI.importListNameInput:SetText("")
    end

    Addon.UI.RefreshImportListSourceCharacterDropdown()

    Addon.UI.importListFrame:Show()
    Addon.UI.importListFrame:Raise()
end

function Addon.UI.CreateMainPanel()
    if Addon.UI.mainPanel then
        return
    end

    local panel = CreateFrame("Frame", "TreenAH_MainPanel", AuctionFrame, "BasicFrameTemplateWithInset")
    panel:SetSize(350, 560)
    panel:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 1, 10)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -3)
    title:SetText(AddonName)

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOP", title, "BOTTOM", 0, -10)
    statusText:SetText("Selected List: Default")
    Addon.UI.statusText = statusText

    Addon.UI.mainPanel = panel

    local fullScanLabel = CreateSectionLabel(panel, "Full Scan", "TOPLEFT", panel, "TOPLEFT", 14, -36)

    local fullScanModeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fullScanModeLabel:SetPoint("TOPLEFT", fullScanLabel, "BOTTOMLEFT", 6, -12)
    fullScanModeLabel:SetText("Mode:")

    local fullScanModeDropdown = CreateFrame("Frame", "TreenAH_FullScanModeDropdown", panel, "UIDropDownMenuTemplate")
    fullScanModeDropdown:SetPoint("LEFT", fullScanModeLabel, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(fullScanModeDropdown, 120)
    UIDropDownMenu_SetText(fullScanModeDropdown, "Fast Full Scan")
    Addon.UI.fullScanModeDropdown = fullScanModeDropdown

    local startFullScanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    startFullScanButton:SetSize(110, 22)
    startFullScanButton:SetPoint("TOPLEFT", fullScanModeDropdown, "TOPRIGHT", -10, -3)
    startFullScanButton:SetText("Start Full Scan")
    startFullScanButton:SetScript("OnClick", function()
        Addon.UI.StartSelectedFullScan()
    end)

    local itemLabel = CreateSectionLabel(panel, "Item Tools", "TOP", fullScanModeLabel, "BOTTOM", 0, -12)
    itemLabel:SetPoint("LEFT", fullScanLabel, "LEFT", 0, 0)

    local itemInput = CreateFrame("EditBox", "TreenAH_ItemInput", panel, "InputBoxTemplate")
    itemInput:SetSize(135, 20)
    itemInput:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 4, -3)
    itemInput:SetAutoFocus(false)
    itemInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    itemInput:SetScript("OnEnterPressed", function(self)
        Addon.UI.StartItemScanFromInput()
        self:ClearFocus()
    end)
    Addon.UI.itemInput = itemInput

    local scanItemButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanItemButton:SetSize(80, 22)
    scanItemButton:SetPoint("LEFT", itemInput, "RIGHT", 8, 0)
    scanItemButton:SetText("Scan Item")
    scanItemButton:SetScript("OnClick", function()
        Addon.UI.StartItemScanFromInput()
    end)

    local itemHistoryButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    itemHistoryButton:SetSize(95, 22)
    itemHistoryButton:SetPoint("LEFT", scanItemButton, "RIGHT", 3, 0)
    itemHistoryButton:SetText("Item History")
    itemHistoryButton:SetScript("OnClick", function()
        Addon.UI.OutputItemHistoryFromInput()
    end)

    local trackedScanLabel = CreateSectionLabel(panel, "List Scan", "TOPLEFT", itemInput, "BOTTOMLEFT", -4, -6)

    local trackedScanDropdown = CreateFrame("Frame", "TreenAH_TrackedScanTargetDropdown", panel, "UIDropDownMenuTemplate")
    trackedScanDropdown:SetPoint("TOPLEFT", trackedScanLabel, "BOTTOMLEFT", -12, -2)
    UIDropDownMenu_SetWidth(trackedScanDropdown, 155)
    UIDropDownMenu_SetText(trackedScanDropdown, "Selected List")
    Addon.UI.trackedScanTargetDropdown = trackedScanDropdown

    local startTrackedScanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    startTrackedScanButton:SetSize(120, 22)
    startTrackedScanButton:SetPoint("LEFT", trackedScanDropdown, "RIGHT", -6, 1)
    startTrackedScanButton:SetText("Start List Scan")
    startTrackedScanButton:SetScript("OnClick", function()
        Addon.UI.StartTrackedScanFromSelection()
    end)

    local trackedListsLabel = CreateSectionLabel(panel, "Lists", "TOPLEFT", trackedScanDropdown, "BOTTOMLEFT", 12, -6)
   
    local trackedListsPane = CreateListPane(panel, "TreenAH_TrackedListsScrollFrame", 150, 150)
    trackedListsPane.frame:SetPoint("TOPLEFT", trackedListsLabel, "BOTTOMLEFT", -5, -4)
    Addon.UI.trackedListsPane = trackedListsPane

    local trackedItemsPane = CreateListPane(panel, "TreenAH_TrackedItemsScrollFrame", 184, 150)
    trackedItemsPane.frame:SetPoint("TOPLEFT", trackedListsPane.frame, "TOPRIGHT", 1, 0)
    Addon.UI.trackedItemsPane = trackedItemsPane

    local itemsInListLabel = CreateSectionLabel(panel, "Items in List", "LEFT", trackedItemsPane.frame, "LEFT", 6, 0)
    itemsInListLabel:SetPoint("BOTTOM", trackedListsLabel, "BOTTOM", 0, 0)

    local leftPaneWidth = trackedListsPane.frame:GetWidth()
    local leftButtonsRowWidth = 72 + 6 + 72
    local leftButtonsX = math.floor((leftPaneWidth - leftButtonsRowWidth) / 2)

    local newListButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newListButton:SetSize(72, 20)
    newListButton:SetPoint("TOPLEFT", trackedListsPane.frame, "BOTTOMLEFT", leftButtonsX, -8)
    newListButton:SetText("New")
    newListButton:SetScript("OnClick", function()
        Addon.UI.ShowCreateListPopup()
    end)

    local renameListButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    renameListButton:SetSize(72, 20)
    renameListButton:SetPoint("LEFT", newListButton, "RIGHT", 6, 0)
    renameListButton:SetText("Rename")
    renameListButton:SetScript("OnClick", function()
        Addon.UI.ShowRenameListPopup()
    end)

    local importListButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importListButton:SetSize(72, 20)
    importListButton:SetPoint("TOPLEFT", newListButton, "BOTTOMLEFT", 0, -6)
    importListButton:SetText("Import")
    importListButton:SetScript("OnClick", function()
        Addon.UI.ShowImportListPopup()
    end)

    local deleteListButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    deleteListButton:SetSize(72, 20)
    deleteListButton:SetPoint("LEFT", importListButton, "RIGHT", 6, 0)
    deleteListButton:SetText("Delete")
    deleteListButton:SetScript("OnClick", function()
        Addon.UI.DeleteSelectedTrackedList()
    end)

    local rightPaneWidth = trackedItemsPane.frame:GetWidth()
    local rightInputWidth = 110
    local rightButtonsRowWidth = 72 + 6 + 72
    local rightInputX = math.floor((rightPaneWidth - rightInputWidth) / 2)
    local rightButtonsX = math.floor((rightPaneWidth - rightButtonsRowWidth) / 2)

    local trackedItemInput = CreateFrame("EditBox", "TreenAH_TrackedItemInput", panel, "InputBoxTemplate")
    trackedItemInput:SetSize(rightInputWidth, 20)
    trackedItemInput:SetPoint("TOPLEFT", trackedItemsPane.frame, "BOTTOMLEFT", rightInputX, -8)
    trackedItemInput:SetAutoFocus(false)
    trackedItemInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    trackedItemInput:SetScript("OnEnterPressed", function(self)
        Addon.UI.AddTrackedItemFromInput()
        self:ClearFocus()
    end)
    Addon.UI.trackedItemInput = trackedItemInput

    local addTrackedItemButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addTrackedItemButton:SetSize(72, 20)
    addTrackedItemButton:SetPoint("TOPLEFT", trackedItemsPane.frame, "BOTTOMLEFT", rightButtonsX, -34)
    addTrackedItemButton:SetText("Add")
    addTrackedItemButton:SetScript("OnClick", function()
        Addon.UI.AddTrackedItemFromInput()
    end)

    local removeTrackedItemButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    removeTrackedItemButton:SetSize(72, 20)
    removeTrackedItemButton:SetPoint("LEFT", addTrackedItemButton, "RIGHT", 6, 0)
    removeTrackedItemButton:SetText("Remove")
    removeTrackedItemButton:SetScript("OnClick", function()
        Addon.UI.RemoveSelectedTrackedItem()
    end)

    local outputLabel = CreateSectionLabel(panel, "Output", "TOP", addTrackedItemButton, "BOTTOM", 0, -9)
    outputLabel:SetPoint("LEFT", panel, "LEFT", 14, 0)

    local outputScrollFrame = CreateFrame("ScrollFrame", "TreenAH_OutputScrollFrame", panel, "UIPanelScrollFrameTemplate")
    outputScrollFrame:SetPoint("TOPLEFT", outputLabel, "BOTTOMLEFT", 0, -6)
    outputScrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 40)
    Addon.UI.outputScrollFrame = outputScrollFrame

    local outputContent = CreateFrame("Frame", nil, outputScrollFrame)
    outputContent:SetWidth(300)
    outputContent:SetHeight(200)
    Addon.UI.outputContent = outputContent

    local outputText = outputContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    outputText:SetPoint("TOPLEFT", outputContent, "TOPLEFT", 0, 0)
    outputText:SetPoint("TOPRIGHT", outputContent, "TOPRIGHT", 0, 0)
    outputText:SetJustifyH("LEFT")
    outputText:SetJustifyV("TOP")
    outputText:SetText("")
    Addon.UI.outputText = outputText

    outputScrollFrame:SetScrollChild(outputContent)

    local openDataBrowserButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openDataBrowserButton:SetSize(80, 22)
    openDataBrowserButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
    openDataBrowserButton:SetText("Data Browser")
    openDataBrowserButton:SetScript("OnClick", function()
        if Addon.DataBrowser and Addon.DataBrowser.Toggle then
            Addon.DataBrowser.Toggle()
        end
    end)

    local stopScanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    stopScanButton:SetSize(78, 22)
    stopScanButton:SetPoint("LEFT", openDataBrowserButton, "RIGHT", 6, 0)
    stopScanButton:SetText("Stop Scan")
    stopScanButton:SetScript("OnClick", function()
        if Addon.Scanner and Addon.Scanner.StopScan then
            Addon.Scanner.StopScan()
        end
    end)
    Addon.UI.stopScanButton = stopScanButton

    local optionsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    optionsButton:SetSize(70, 22)
    optionsButton:SetPoint("LEFT", stopScanButton, "RIGHT", 6, 0)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        Addon.UI.OpenOptionsPanel()
    end)

    local helpGuideButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    helpGuideButton:SetSize(70, 22)
    helpGuideButton:SetPoint("LEFT", optionsButton, "RIGHT", 6, 0)
    helpGuideButton:SetText("Help/Guide")
    helpGuideButton:SetScript("OnClick", function()
        Addon.UI.ShowQuickStartGuide()
    end)

    Addon.UI.RefreshFullScanModeDropdown()
    Addon.UI.RefreshTrackedScanTargetDropdown()
    Addon.UI.RefreshAllTrackedUI()
    Addon.UI.RefreshStopScanButton()
end

function Addon.UI.GetScanSpinnerFrame()
    local frames = Addon.UI.scanSpinnerFrames or { "|", "/", "-", "\\" }
    local index = Addon.UI.scanSpinnerIndex or 1
    return frames[index] or "|"
end

function Addon.UI.BuildScanSummaryText()
    local summary = Addon.UI.scanSummary
    if not summary then
        return nil
    end

    local lines = {}

    if summary.isActive then
        local left = Addon.UI.GetScanSpinnerFrame()
        local mirrorMap = {
            ["|"] = "|",
            ["/"] = "\\",
            ["-"] = "-",
            ["\\"] = "/",
        }
        local right = mirrorMap[left] or left

        local percentText = summary.progressText or ""
        local pageText = summary.pageText or ""

        local headerText

        if percentText ~= "" then
            headerText = string.format("%s %s Scanning %s", left, percentText, right)
        else
            headerText = string.format("%s Scanning %s", left, right)
        end

        if pageText ~= "" then
            headerText = string.format("%s  %s", headerText, pageText)
        end

        table.insert(lines, headerText)
    else
        table.insert(lines, summary.title or "TreenAH Scan Report")
    end

    table.insert(lines, "-------------------------")

    for _, line in ipairs(summary.lines or {}) do
        if line and line ~= "" then
            table.insert(lines, line)
        end
    end

    local eventLines = summary.eventLines or {}
    if #eventLines > 0 then
        table.insert(lines, "")
        table.insert(lines, "|cffffcc66Recent events:|r")

        for _, eventLine in ipairs(eventLines) do
            if eventLine and eventLine ~= "" then
                table.insert(lines, eventLine)
            end
        end
    end

    if summary.isActive then
        local latestLabel = "|cffffcc66Latest update:|r"
        local latestLine = (summary.latestNewLow and summary.latestNewLow ~= "") and summary.latestNewLow or "none yet"

        table.insert(lines, "")
        table.insert(lines, latestLabel)
        table.insert(lines, latestLine)
    end

    if summary.footer and summary.footer ~= "" then
        table.insert(lines, "")
        table.insert(lines, summary.footer)
    end

    return table.concat(lines, "\n")
end

function Addon.UI.RenderScanSummary()
    local text = Addon.UI.BuildScanSummaryText()
    if text then
        Addon.UI.RenderSummary(text, false)
    end
end

function Addon.UI.BeginScanSummary(title, initialLines)
    Addon.UI.scanSummary = {
        title = title or "Scan",
        lines = initialLines or {},
        eventLines = {},
        latestNewLow = nil,
        footer = nil,
        isActive = true,
        progressText = nil,
        pageText = nil,
    }

    Addon.UI.StartSpinnerTicker()
    Addon.UI.RenderScanSummary()
end

function Addon.UI.SetScanProgressText(text)
    if not Addon.UI.scanSummary then
        return
    end

    Addon.UI.scanSummary.progressText = text
    Addon.UI.RenderScanSummary()
end

function Addon.UI.SetScanPageText(text)
    if not Addon.UI.scanSummary then
        return
    end

    Addon.UI.scanSummary.pageText = text
    Addon.UI.RenderScanSummary()
end

function Addon.UI.UpdateScanSummaryLines(lines)
    if not Addon.UI.scanSummary then
        return
    end

    Addon.UI.scanSummary.lines = lines or {}
    Addon.UI.RenderScanSummary()
end

function Addon.UI.AddScanEventLine(text)
    if not Addon.UI.scanSummary or not text or text == "" then
        return
    end

    local eventLines = Addon.UI.scanSummary.eventLines
    table.insert(eventLines, text)

    while #eventLines > (Addon.UI.maxScanEventLines or 5) do
        table.remove(eventLines, 1)
    end

    Addon.UI.RenderScanSummary()
end

function Addon.UI.SetLatestNewLowLine(text)
    if not Addon.UI.scanSummary then
        return
    end

    Addon.UI.scanSummary.latestNewLow = text
    Addon.UI.RenderScanSummary()
end

function Addon.UI.FinishScanSummary(footerText)
    if not Addon.UI.scanSummary then
        return
    end

    Addon.UI.scanSummary.footer = footerText or "Scan complete."
    Addon.UI.scanSummary.isActive = false
    Addon.UI.scanSummary.progressText = nil
    Addon.UI.scanSummary.pageText = nil

    Addon.UI.spinnerElapsed = 0
    Addon.UI.scanSpinnerIndex = 1

    Addon.UI.RenderScanSummary()
end

function Addon.UI.ClearScanSummary()
    Addon.UI.scanSummary = nil
end

function Addon.UI.ClearOutput()
    Addon.UI.outputLines = {}

    if Addon.UI.outputText then
        Addon.UI.outputText:SetText("")
    end

    if Addon.UI.outputContent and Addon.UI.outputScrollFrame then
        local minHeight = Addon.UI.outputScrollFrame:GetHeight() or 0
        Addon.UI.outputContent:SetHeight(minHeight)
        Addon.UI.outputScrollFrame:SetVerticalScroll(0)
    end

    Addon.UI.UpdateStatusLine()
end

function Addon.UI.RenderSummary(msg, append)
    if not Addon.UI.outputText then
        return
    end

    Addon.UI.outputLines = Addon.UI.outputLines or {}
    local lines = Addon.UI.outputLines

    if append then
        table.insert(lines, msg or "")
        while #lines > (Addon.UI.maxOutputLines or 60) do
            table.remove(lines, 1)
        end
    else
        wipe(lines)
        table.insert(lines, msg or "No data")
    end

    Addon.UI.outputText:SetText(table.concat(lines, "\n"))

    if Addon.UI.outputContent and Addon.UI.outputScrollFrame then
        local textHeight = Addon.UI.outputText:GetStringHeight() or 0
        local minHeight = Addon.UI.outputScrollFrame:GetHeight()
        Addon.UI.outputContent:SetHeight(math.max(minHeight, textHeight + 8))
    end

    if append and Addon.UI.outputScrollFrame then
        local maxScroll = Addon.UI.outputScrollFrame:GetVerticalScrollRange() or 0
        Addon.UI.outputScrollFrame:SetVerticalScroll(maxScroll)
    end

    Addon.UI.UpdateStatusLine()
end

function Addon.UI.OutputItemHistory(itemID)
    local itemData = Addon.DB.GetItemData(itemID)
    if not itemData then
        Addon.UI.RenderSummary("No data for item ID " .. itemID)
        return
    end

    local baseItemID = (itemData and itemData.baseItemID) or (Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(itemID)) or itemID
    local itemInfo = Addon.Utils.GetItemInfoByID(baseItemID) or {}
    local displayName = (itemData and itemData.name) or itemInfo.name or tostring(itemID)
    local historicalAvg = Addon.DB.GetHistoricalAverageLowPrice(itemID)

    local summaryLines = {}
    if itemInfo.link and Addon.Utils.NormalizeItemName(itemInfo.name) == Addon.Utils.NormalizeItemName(displayName) then
        table.insert(summaryLines, itemInfo.link)
    else
        table.insert(summaryLines, Addon.DB.GetRecordLabel and Addon.DB.GetRecordLabel(itemID, itemData) or displayName)
    end
    table.insert(summaryLines, "-------------------------")
    table.insert(summaryLines, string.format(
        "Historical Average Price: %s",
        historicalAvg and Addon.Utils.ConvertToCoinTextureString(math.floor(historicalAvg)) or "N/A"
    ))
    table.insert(summaryLines, "-------------------------")
    table.insert(summaryLines, string.format(
        "Historical prices for item %s:",
        displayName
    ))

    local sortedDays = Addon.Utils.GetSortedKeysDescending(itemData.days or {})

    for _, day in ipairs(sortedDays) do
        local dayData = itemData.days[day]
        local sortedHours = Addon.Utils.GetSortedKeysDescending(dayData.hours or {})

        for _, hour in ipairs(sortedHours) do
            local hourData = dayData.hours[hour]
            if hourData.low then
                table.insert(
                    summaryLines,
                    string.format(
                        "%s %02d:00 - Price: %s",
                        day,
                        hour,
                        Addon.Utils.ConvertToCoinTextureString(hourData.low)
                    )
                )
            end
        end
    end

    Addon.UI.RenderSummary(table.concat(summaryLines, "\n"))
end

function Addon.UI.GetSelectedAuctionItemIndex()
    local selectedIndex = GetSelectedAuctionItem("list")
    if not selectedIndex or selectedIndex <= 0 then
        return nil
    end

    return selectedIndex
end

function Addon.UI.GetSelectedAuctionItemID()
    local selectedIndex = Addon.UI.GetSelectedAuctionItemIndex()
    if not selectedIndex then
        return nil
    end

    local itemLink = GetAuctionItemLink("list", selectedIndex)
    return Addon.Utils.GetItemIdFromLink(itemLink)
end

function Addon.UI.GetSelectedAuctionRecordKey()
    local selectedIndex = Addon.UI.GetSelectedAuctionItemIndex()
    if not selectedIndex then
        return nil
    end

    local auctionData = Addon.Scanner and Addon.Scanner.GetAuctionData and Addon.Scanner.GetAuctionData(selectedIndex)
    return auctionData and (auctionData.recordKey or auctionData.itemID) or nil
end

function Addon.UI.OutputSelectedAuctionItemHistory()
    local selectedIndex = Addon.UI.GetSelectedAuctionItemIndex()
    if not selectedIndex then
        Addon.Utils.PrintError("No auction item selected.")
        return
    end

    local itemID = Addon.UI.GetSelectedAuctionRecordKey()
    if not itemID then
        Addon.Utils.PrintError("Could not determine item ID from selected auction.")
        return
    end

    Addon.UI.OutputItemHistory(itemID)
end

local function GetPlainItemNameFromLink(link)
    return Addon.Utils.GetPlainItemNameFromLink(link)
end

function Addon.UI.GetFocusedItemInputBox()
    if Addon.UI.itemInput and Addon.UI.itemInput:HasFocus() then
        return Addon.UI.itemInput
    end

    if Addon.UI.trackedItemInput and Addon.UI.trackedItemInput:HasFocus() then
        return Addon.UI.trackedItemInput
    end

    if Addon.DataBrowser and Addon.DataBrowser.searchBox and Addon.DataBrowser.searchBox:HasFocus() then
        return Addon.DataBrowser.searchBox
    end

    return nil
end

function Addon.UI.TryInsertShiftClickedItem(link)
    if not IsShiftKeyDown() then
        return false
    end

    local targetBox = Addon.UI.GetFocusedItemInputBox()
    if not targetBox then
        return false
    end

    local itemName = GetPlainItemNameFromLink(link)
    if not itemName or itemName == "" then
        return false
    end

    targetBox:SetText(itemName)
    targetBox:HighlightText(0, 0)
    targetBox:SetCursorPosition(string.len(itemName))
    return true
end

function Addon.UI.StartSpinnerTicker()
    if Addon.UI.spinnerTicker then return end

    local frame = CreateFrame("Frame")
    Addon.UI.spinnerTicker = frame

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not Addon.UI.scanSummary or not Addon.UI.scanSummary.isActive then
            return
        end

        Addon.UI.spinnerElapsed = Addon.UI.spinnerElapsed + elapsed

        if Addon.UI.spinnerElapsed >= Addon.UI.spinnerInterval then
            Addon.UI.spinnerElapsed = 0

            -- advance spinner
            local frames = Addon.UI.scanSpinnerFrames
            local index = Addon.UI.scanSpinnerIndex + 1
            if index > #frames then index = 1 end
            Addon.UI.scanSpinnerIndex = index

            -- re-render ONLY the title (but we just re-render whole summary, it's fine)
            Addon.UI.RenderScanSummary()
        end
    end)
end

StaticPopupDialogs["TREENAH_NEW_TRACKED_LIST"] = {
    text = "Enter a name for the new list:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        local editBox = GetPopupEditBox(self)
        if editBox then
            editBox:SetText("")
            editBox:SetFocus()
            editBox:HighlightText()
        end
    end,
    OnAccept = function(self)
        local editBox = GetPopupEditBox(self)
        local text = SafeTrim(editBox and editBox:GetText() or "")
        local ok, result = Addon.TrackedItems.CreateTrackedList(text)

        if ok then
            Addon.TrackedItems.SetSelectedListKey(result)
            Addon.UI.selectedTrackedItemName = nil
            Addon.TrackedItems.RefreshTrackedItemsList()
            Addon.UI.RenderSummary("Created tracked list:\n" .. text)
        else
            Addon.UI.RenderSummary(result or "Could not create list.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
}

StaticPopupDialogs["TREENAH_RENAME_TRACKED_LIST"] = {
    text = "Enter a new name for this list:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        local selectedKey = Addon.TrackedItems.GetSelectedListKey()
        local editBox = GetPopupEditBox(self)
        local text = SafeTrim(editBox and editBox:GetText() or "")
        local ok, result = Addon.TrackedItems.RenameTrackedList(selectedKey, text)

        if ok then
            Addon.TrackedItems.RefreshTrackedItemsList()
            Addon.UI.RenderSummary("Renamed list to:\n" .. result)
        else
            Addon.UI.RenderSummary(result or "Could not rename list.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
}

StaticPopupDialogs["TREENAH_DUPLICATE_TRACKED_LIST"] = {
    text = "Enter a name for the duplicated list:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        local selectedKey = Addon.TrackedItems.GetSelectedListKey()
        local editBox = GetPopupEditBox(self)
        local text = SafeTrim(editBox and editBox:GetText() or "")
        local ok, result = Addon.TrackedItems.DuplicateTrackedList(selectedKey, text)

        if ok then
            Addon.TrackedItems.SetSelectedListKey(result)
            Addon.UI.selectedTrackedItemName = nil
            Addon.TrackedItems.RefreshTrackedItemsList()
            Addon.UI.RenderSummary("Duplicated list:\n" .. text)
        else
            Addon.UI.RenderSummary(result or "Could not duplicate list.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
}

do
    local originalHandleModifiedItemClick = HandleModifiedItemClick

    function HandleModifiedItemClick(link, itemLocation, ...)
        if Addon and Addon.UI and Addon.UI.TryInsertShiftClickedItem and Addon.UI.TryInsertShiftClickedItem(link) then
            return true
        end

        if originalHandleModifiedItemClick then
            return originalHandleModifiedItemClick(link, itemLocation, ...)
        end
    end
end

-- Set to nil first to avoid accidentally using an old reference if this file is reloaded
Addon.UI.optionsPanel = nil

local function CreateOptionsTitle(panel, text, point, relativeTo, relativePoint, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint(point, relativeTo, relativePoint, x, y)
    fs:SetText(text)
    return fs
end

local function CreateOptionsText(panel, text, point, relativeTo, relativePoint, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint(point, relativeTo, relativePoint, x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function CreateOptionsCheckButton(panel, name, labelText, tooltipText, anchorTo, offsetY, getter, setter, onChanged)
    local check = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)

    local label = _G[check:GetName() .. "Text"]
    if label then
        label:SetText(labelText or "")
    end

    check.tooltipText = labelText
    check.tooltipRequirement = tooltipText

    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        setter(checked)

        if onChanged then
            onChanged(checked)
        end
    end)

    check.RefreshValue = function(self)
        self:SetChecked(getter() and true or false)
    end

    return check
end

local function CreateOptionsNumericSetting(panel, labelText, tooltipText, anchorTo, offsetY, getter, setter, successMessageBuilder)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)
    label:SetText(labelText or "")

    local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    editBox:SetSize(50, 20)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("LEFT", label, "RIGHT", 12, 0)
    editBox:SetTextInsets(6, 6, 0, 0)

    local setButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    setButton:SetSize(44, 20)
    setButton:SetPoint("LEFT", editBox, "RIGHT", 6, 0)
    setButton:SetText("Set")

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    hint:SetJustifyH("LEFT")
    hint:SetText(tooltipText or "")

    local function refreshValue()
        local current = getter()
        editBox:SetText(tostring(current or ""))
    end

    local function applyValue()
        local ok, result = setter(editBox:GetText())
        if ok then
            editBox:SetText(tostring(result))
            if successMessageBuilder then
                Addon.Utils.Print(successMessageBuilder(result))
            else
                Addon.Utils.Print("Value set to " .. tostring(result) .. ".")
            end
        else
            Addon.Utils.PrintError(result or "Invalid value.")
            refreshValue()
        end
    end

    setButton:SetScript("OnClick", applyValue)

    editBox:SetScript("OnEnterPressed", function(self)
        applyValue()
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        refreshValue()
        self:ClearFocus()
    end)

    return {
        label = label,
        editBox = editBox,
        button = setButton,
        hint = hint,
        RefreshValue = refreshValue,
    }
end

local function AddOptionsUtilityButtons(panel)
    local restoreDefaultsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    restoreDefaultsButton:SetSize(140, 22)
    restoreDefaultsButton:SetText("Restore Defaults")
    restoreDefaultsButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16)
    restoreDefaultsButton:SetScript("OnClick", function()
        Addon.UI.ResetOptionsToDefaults()
    end)
    panel.restoreDefaultsButton = restoreDefaultsButton

    local restoreDefaultsNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    restoreDefaultsNote:SetPoint("TOPRIGHT", restoreDefaultsButton, "BOTTOMRIGHT", 0, -6)
    restoreDefaultsNote:SetJustifyH("LEFT")
    restoreDefaultsNote:SetText("Resets TreenAH settings to their original defaults.")

    local slashCommandsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    slashCommandsButton:SetSize(140, 22)
    slashCommandsButton:SetText("Slash Commands Guide")
    slashCommandsButton:SetPoint("TOPRIGHT", restoreDefaultsButton, "BOTTOMRIGHT", 0, -28)
    slashCommandsButton:SetScript("OnClick", function()
        Addon.UI.ShowSlashCommandsHelp()
    end)
    panel.slashCommandsButton = slashCommandsButton

    local quickStartButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    quickStartButton:SetSize(140, 22)
    quickStartButton:SetText("Quick Start Guide")
    quickStartButton:SetPoint("TOPRIGHT", slashCommandsButton, "BOTTOMRIGHT", 0, -10)
    quickStartButton:SetScript("OnClick", function()
        Addon.UI.ShowQuickStartGuide()
    end)
    panel.quickStartButton = quickStartButton
end

local function CreateOptionsPage(name, parentCategory)
    local panel = CreateFrame("Frame")
    panel.name = name
    panel.parent = parentCategory

    panel:Hide()

    panel:SetScript("OnShow", function()
        Addon.UI.RefreshOptionsPanel()
    end)

    panel.okay = function() end
    panel.cancel = function() end
    panel.default = function()
        Addon.UI.ResetOptionsToDefaults()
    end

    local title = CreateOptionsTitle(panel, name, "TOPLEFT", panel, "TOPLEFT", 16, -16)
    panel.pageTitle = title

    AddOptionsUtilityButtons(panel)

    return panel, title
end

function Addon.UI.CreateOptionsLandingPage()
    local panel, title = CreateOptionsPage(AddonName, nil)

    local subtitle = CreateOptionsText(
        panel,
        "Auction house pricing helper settings.",
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )

    local intro = CreateOptionsText(
        panel,
        "Use the subpages on the left to configure General, Tooltips, Auto-Reply, and Advanced settings.",
        "TOPLEFT",
        subtitle,
        "BOTTOMLEFT",
        0,
        -20
    )

    local overviewHeader = CreateOptionsText(
        panel,
        "Overview",
        "TOPLEFT",
        intro,
        "BOTTOMLEFT",
        0,
        -20
    )

    CreateOptionsText(
        panel,
        "- General: Main panel behavior, passive scanning, and browse column display.\n" ..
        "- Tooltips: Control TreenAH tooltip injection and which tooltip lines appear.\n" ..
        "- Auto-Reply: Configure price-check replies and allowed chat channels.\n" ..
        "- Advanced: Outlier threshold, recent average window, and debug mode.",
        "TOPLEFT",
        overviewHeader,
        "BOTTOMLEFT",
        0,
        -10
    )

    return panel
end

function Addon.UI.CreateGeneralOptionsPage()
    local panel, title = CreateOptionsPage("General", AddonName)

    local subtitle = CreateOptionsText(
        panel,
        "Main TreenAH behavior and Auction House display settings.",
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )

    local header = CreateOptionsText(
        panel,
        "General",
        "TOPLEFT",
        subtitle,
        "BOTTOMLEFT",
        0,
        -20
    )

    panel.autoShowCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoShow",
        "Automatically show TreenAH panel when the Auction House opens",
        "Shows the TreenAH panel automatically when you open the Auction House.",
        header,
        -10,
        function() return Addon.DB.IsAutoShowMainPanelEnabled() end,
        function(value) Addon.DB.SetAutoShowMainPanelEnabled(value) end,
        function(value)
            if Addon.UI.mainPanel and AuctionFrame and AuctionFrame:IsShown() and value then
                Addon.UI.ShowMainPanel()
            end
        end
    )

    panel.autoScanCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoScan",
        "Passive scan visible AH pages while browsing",
        "When enabled, TreenAH automatically records price data from visible auction results while you browse the Auction House.",
        panel.autoShowCheckbox,
        -8,
        function() return Addon.DB.IsAutoScanEnabled() end,
        function(value) Addon.DB.SetAutoScanEnabled(value) end
    )

    panel.browseColumnCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_BrowseColumn",
        "Show average price column in browse results",
        "Shows the TreenAH Avg / Δ% column in the Auction House browse list.",
        panel.autoScanCheckbox,
        -8,
        function() return Addon.DB.IsBrowsePriceColumnEnabled() end,
        function(value) Addon.DB.SetBrowsePriceColumnEnabled(value) end,
        function()
            if Addon.BrowseColumn and Addon.BrowseColumn.RefreshVisibility then
                Addon.BrowseColumn.RefreshVisibility()
            end
            if Addon.BrowseColumn and Addon.BrowseColumn.UpdateBrowseColumn then
                Addon.BrowseColumn.UpdateBrowseColumn()
            end
        end
    )

    return panel
end

function Addon.UI.CreateTooltipOptionsPage()
    local panel, title = CreateOptionsPage("Tooltips", AddonName)

    local subtitle = CreateOptionsText(
        panel,
        "Control TreenAH item tooltip price data.",
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )

    local header = CreateOptionsText(
        panel,
        "Tooltip",
        "TOPLEFT",
        subtitle,
        "BOTTOMLEFT",
        0,
        -20
    )

    panel.tooltipPriceDataCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_TooltipPriceData",
        "Show TreenAH price data in item tooltips",
        "When enabled, TreenAH adds recorded price info to supported item tooltips.",
        header,
        -10,
        function() return Addon.DB.IsTooltipPriceDataEnabled() end,
        function(value) Addon.DB.SetTooltipPriceDataEnabled(value) end,
        function()
            Addon.UI.RefreshOptionsPanel()
        end
    )

    panel.tooltipHeaderCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_TooltipHeader",
        "Show TreenAH tooltip header",
        "Shows the TreenAH header line above tooltip price data.",
        panel.tooltipPriceDataCheckbox,
        -8,
        function() return Addon.DB.IsTooltipHeaderEnabled() end,
        function(value) Addon.DB.SetTooltipHeaderEnabled(value) end
    )

    panel.tooltipAverageCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_TooltipAverage",
        "Show Average Price in tooltip",
        "Shows the recorded historical average price in the tooltip.",
        panel.tooltipHeaderCheckbox,
        -8,
        function() return Addon.DB.IsTooltipAveragePriceEnabled() end,
        function(value) Addon.DB.SetTooltipAveragePriceEnabled(value) end
    )

    panel.tooltipLastSeenCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_TooltipLastSeen",
        "Show Last Seen Price in tooltip",
        "Shows the most recent recorded low price in the tooltip.",
        panel.tooltipAverageCheckbox,
        -8,
        function() return Addon.DB.IsTooltipLastSeenPriceEnabled() end,
        function(value) Addon.DB.SetTooltipLastSeenPriceEnabled(value) end
    )

    panel.tooltipDeltaCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_TooltipDelta",
        "Show Last Seen vs Avg in tooltip",
        "Shows the percent difference between the most recent low and the displayed average.",
        panel.tooltipLastSeenCheckbox,
        -8,
        function() return Addon.DB.IsTooltipDeltaEnabled() end,
        function(value) Addon.DB.SetTooltipDeltaEnabled(value) end
    )

    return panel
end

function Addon.UI.CreateAutoReplyOptionsPage()
    local panel, title = CreateOptionsPage("Auto-Reply", AddonName)

    local subtitle = CreateOptionsText(
        panel,
        "Configure automatic price-check replies and allowed channels.",
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )

    local header = CreateOptionsText(
        panel,
        "Auto-Reply",
        "TOPLEFT",
        subtitle,
        "BOTTOMLEFT",
        0,
        -20
    )

    panel.autoReplyCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReply",
        "Enable automatic price-check replies",
        "When enabled, TreenAH can respond to 'pc <item>' messages in allowed channels.",
        header,
        -10,
        function() return Addon.DB.IsAutoReplyEnabled() end,
        function(value) Addon.DB.SetAutoReplyEnabled(value) end,
        function()
            Addon.UI.RefreshOptionsPanel()
        end
    )

    panel.autoTrackRequestsCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoTrackRequests",
        "Automatically add requested items to the Requests list",
        "When enabled, requested items are added to the Requests tracked list whenever WoW can resolve a clean item name, even if TreenAH does not have price history for them yet.",
        panel.autoReplyCheckbox,
        -8,
        function() return Addon.DB.IsAutoTrackRequestsEnabled() end,
        function(value) Addon.DB.SetAutoTrackRequestsEnabled(value) end
    )

    panel.autoReplyWhisperCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReplyWhisper",
        "Allow replies in whispers / Battle.net whispers",
        "Respond to direct whisper price checks.",
        panel.autoTrackRequestsCheckbox,
        -8,
        function() return Addon.DB.IsAutoReplyChannelEnabled("whisper") end,
        function(value) Addon.DB.SetAutoReplyChannelEnabled("whisper", value) end
    )

    panel.autoReplyGuildCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReplyGuild",
        "Allow replies in guild chat",
        "Respond to guild chat price checks.",
        panel.autoReplyWhisperCheckbox,
        -4,
        function() return Addon.DB.IsAutoReplyChannelEnabled("guild") end,
        function(value) Addon.DB.SetAutoReplyChannelEnabled("guild", value) end
    )

    panel.autoReplyPartyCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReplyParty",
        "Allow replies in party chat",
        "Respond to party chat price checks.",
        panel.autoReplyGuildCheckbox,
        -4,
        function() return Addon.DB.IsAutoReplyChannelEnabled("party") end,
        function(value) Addon.DB.SetAutoReplyChannelEnabled("party", value) end
    )

    panel.autoReplyRaidCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReplyRaid",
        "Allow replies in raid chat",
        "Respond to raid chat price checks.",
        panel.autoReplyPartyCheckbox,
        -4,
        function() return Addon.DB.IsAutoReplyChannelEnabled("raid") end,
        function(value) Addon.DB.SetAutoReplyChannelEnabled("raid", value) end
    )

    panel.autoReplySayCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_AutoReplySay",
        "Allow replies in say chat",
        "Respond to say chat price checks.",
        panel.autoReplyRaidCheckbox,
        -4,
        function() return Addon.DB.IsAutoReplyChannelEnabled("say") end,
        function(value) Addon.DB.SetAutoReplyChannelEnabled("say", value) end
    )

    return panel
end

function Addon.UI.CreateAdvancedOptionsPage()
    local panel, title = CreateOptionsPage("Advanced", AddonName)

    local subtitle = CreateOptionsText(
        panel,
        "Advanced filtering, averaging, and debugging settings.",
        "TOPLEFT",
        title,
        "BOTTOMLEFT",
        0,
        -8
    )

    local header = CreateOptionsText(
        panel,
        "Advanced",
        "TOPLEFT",
        subtitle,
        "BOTTOMLEFT",
        0,
        -20
    )

    panel.unreasonablePriceMultiplierControl = CreateOptionsNumericSetting(
        panel,
        "Outlier threshold",
        "Higher values are more permissive.\nLower values reject more unusually high prices during scan filtering. \nDefault: 5",
        header,
        -10,
        function()
            return Addon.DB.GetUnreasonablePriceMultiplier()
        end,
        function(value)
            return Addon.DB.SetUnreasonablePriceMultiplier(value)
        end,
        function(result)
            return "Outlier threshold set to " .. tostring(result) .. "."
        end
    )

    panel.displayAverageWindowControl = CreateOptionsNumericSetting(
        panel,
        "Recent average window (days)",
        "How many calendar days are used when calculating the displayed recent average price. \nDefault: 14",
        panel.unreasonablePriceMultiplierControl.hint,
        -16,
        function()
            return Addon.DB.GetDisplayAverageWindowDays()
        end,
        function(value)
            return Addon.DB.SetDisplayAverageWindowDays(value)
        end,
        function(result)
            return "Recent average window set to " .. tostring(result) .. " day(s)."
        end
    )

    panel.debugCheckbox = CreateOptionsCheckButton(
        panel,
        "TreenAH_Options_Debug",
        "Enable debug mode",
        "Shows extra TreenAH diagnostic messages in chat.",
        panel.displayAverageWindowControl.hint,
        -14,
        function() return Addon.DB.IsDebugModeEnabled() end,
        function(value) Addon.DB.SetDebugModeEnabled(value) end
    )

    return panel
end

function Addon.UI.RefreshOptionsPanel()
    local panels = {
        Addon.UI.optionsPanel,
        Addon.UI.generalOptionsPanel,
        Addon.UI.tooltipOptionsPanel,
        Addon.UI.autoReplyOptionsPanel,
        Addon.UI.advancedOptionsPanel,
    }

    for _, panel in ipairs(panels) do
        if panel then
            if panel.autoShowCheckbox then panel.autoShowCheckbox:RefreshValue() end
            if panel.autoScanCheckbox then panel.autoScanCheckbox:RefreshValue() end
            if panel.autoTrackRequestsCheckbox then panel.autoTrackRequestsCheckbox:RefreshValue() end
            if panel.browseColumnCheckbox then panel.browseColumnCheckbox:RefreshValue() end
            if panel.autoReplyCheckbox then panel.autoReplyCheckbox:RefreshValue() end
            if panel.autoReplyWhisperCheckbox then panel.autoReplyWhisperCheckbox:RefreshValue() end
            if panel.autoReplyGuildCheckbox then panel.autoReplyGuildCheckbox:RefreshValue() end
            if panel.autoReplyPartyCheckbox then panel.autoReplyPartyCheckbox:RefreshValue() end
            if panel.autoReplyRaidCheckbox then panel.autoReplyRaidCheckbox:RefreshValue() end
            if panel.autoReplySayCheckbox then panel.autoReplySayCheckbox:RefreshValue() end
            if panel.debugCheckbox then panel.debugCheckbox:RefreshValue() end
            if panel.unreasonablePriceMultiplierControl then panel.unreasonablePriceMultiplierControl:RefreshValue() end
            if panel.displayAverageWindowControl then panel.displayAverageWindowControl:RefreshValue() end
            if panel.tooltipPriceDataCheckbox then panel.tooltipPriceDataCheckbox:RefreshValue() end
            if panel.tooltipHeaderCheckbox then panel.tooltipHeaderCheckbox:RefreshValue() end
            if panel.tooltipAverageCheckbox then panel.tooltipAverageCheckbox:RefreshValue() end
            if panel.tooltipLastSeenCheckbox then panel.tooltipLastSeenCheckbox:RefreshValue() end
            if panel.tooltipDeltaCheckbox then panel.tooltipDeltaCheckbox:RefreshValue() end

            local tooltipEnabled = Addon.DB.IsTooltipPriceDataEnabled and Addon.DB.IsTooltipPriceDataEnabled()
            if panel.tooltipHeaderCheckbox then panel.tooltipHeaderCheckbox:SetEnabled(tooltipEnabled) end
            if panel.tooltipAverageCheckbox then panel.tooltipAverageCheckbox:SetEnabled(tooltipEnabled) end
            if panel.tooltipLastSeenCheckbox then panel.tooltipLastSeenCheckbox:SetEnabled(tooltipEnabled) end
            if panel.tooltipDeltaCheckbox then panel.tooltipDeltaCheckbox:SetEnabled(tooltipEnabled) end

            local autoReplyEnabled = Addon.DB.IsAutoReplyEnabled()
            if panel.autoReplyWhisperCheckbox then panel.autoReplyWhisperCheckbox:SetEnabled(autoReplyEnabled) end
            if panel.autoReplyGuildCheckbox then panel.autoReplyGuildCheckbox:SetEnabled(autoReplyEnabled) end
            if panel.autoReplyPartyCheckbox then panel.autoReplyPartyCheckbox:SetEnabled(autoReplyEnabled) end
            if panel.autoReplyRaidCheckbox then panel.autoReplyRaidCheckbox:SetEnabled(autoReplyEnabled) end
            if panel.autoReplySayCheckbox then panel.autoReplySayCheckbox:SetEnabled(autoReplyEnabled) end
        end
    end
end

function Addon.UI.RegisterOptionsPanel()
    if Addon.UI.optionsPanel then
        return
    end

    local landing = Addon.UI.CreateOptionsLandingPage()
    local general = Addon.UI.CreateGeneralOptionsPage()
    local tooltips = Addon.UI.CreateTooltipOptionsPage()
    local autoReply = Addon.UI.CreateAutoReplyOptionsPage()
    local advanced = Addon.UI.CreateAdvancedOptionsPage()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local landingCategory = Settings.RegisterCanvasLayoutCategory(landing, AddonName, AddonName)
        Settings.RegisterAddOnCategory(landingCategory)
        Addon.UI.optionsCategory = landingCategory

        local generalCategory = Settings.RegisterCanvasLayoutSubcategory(landingCategory, general, "General")
        Settings.RegisterAddOnCategory(generalCategory)

        local tooltipsCategory = Settings.RegisterCanvasLayoutSubcategory(landingCategory, tooltips, "Tooltips")
        Settings.RegisterAddOnCategory(tooltipsCategory)

        local autoReplyCategory = Settings.RegisterCanvasLayoutSubcategory(landingCategory, autoReply, "Auto-Reply")
        Settings.RegisterAddOnCategory(autoReplyCategory)

        local advancedCategory = Settings.RegisterCanvasLayoutSubcategory(landingCategory, advanced, "Advanced")
        Settings.RegisterAddOnCategory(advancedCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(landing)
        InterfaceOptions_AddCategory(general)
        InterfaceOptions_AddCategory(tooltips)
        InterfaceOptions_AddCategory(autoReply)
        InterfaceOptions_AddCategory(advanced)
    else
        Addon.Utils.PrintError("This client does not expose Blizzard's addon options registration API.")
    end

    Addon.UI.optionsPanel = landing
    Addon.UI.generalOptionsPanel = general
    Addon.UI.tooltipOptionsPanel = tooltips
    Addon.UI.autoReplyOptionsPanel = autoReply
    Addon.UI.advancedOptionsPanel = advanced
end

function Addon.UI.OpenOptionsPanel()
    Addon.UI.RegisterOptionsPanel()
    Addon.UI.RefreshOptionsPanel()

    if Settings and Settings.OpenToCategory and Addon.UI.optionsCategory then
        Settings.OpenToCategory(Addon.UI.optionsCategory:GetID())
        return
    end

    if InterfaceAddOnsList_Update then
        InterfaceAddOnsList_Update()
    end

    if InterfaceOptionsFrame_OpenToCategory and Addon.UI.optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(Addon.UI.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(Addon.UI.optionsPanel)
        return
    end

    Addon.Utils.PrintError("Could not open addon options on this client.")
end

function Addon.UI.ResetOptionsToDefaults()
    Addon.DB.SetAutoShowMainPanelEnabled(true)
    Addon.DB.SetAutoScanEnabled(true)
    Addon.DB.SetAutoReplyEnabled(true)

    Addon.DB.SetAutoReplyChannelEnabled("whisper", true)
    Addon.DB.SetAutoReplyChannelEnabled("guild", false)
    Addon.DB.SetAutoReplyChannelEnabled("party", false)
    Addon.DB.SetAutoReplyChannelEnabled("raid", false)
    Addon.DB.SetAutoReplyChannelEnabled("say", false)

    Addon.DB.SetBrowsePriceColumnEnabled(true)
    Addon.DB.SetAutoTrackRequestsEnabled(true)
    Addon.DB.SetUnreasonablePriceMultiplier(5)
    Addon.DB.SetDisplayAverageWindowDays(14)
    Addon.DB.SetDebugModeEnabled(false)
    Addon.DB.SetTooltipPriceDataEnabled(true)
    Addon.DB.SetTooltipHeaderEnabled(true)
    Addon.DB.SetTooltipAveragePriceEnabled(true)
    Addon.DB.SetTooltipLastSeenPriceEnabled(true)
    Addon.DB.SetTooltipDeltaEnabled(true)

    if Addon.BrowseColumn and Addon.BrowseColumn.RefreshVisibility then
        Addon.BrowseColumn.RefreshVisibility()
    end

    if Addon.BrowseColumn and Addon.BrowseColumn.UpdateBrowseColumn then
        Addon.BrowseColumn.UpdateBrowseColumn()
    end

    if Addon.UI and Addon.UI.UpdateStatusLine then
        Addon.UI.UpdateStatusLine()
    end

    Addon.UI.RefreshOptionsPanel()
    Addon.Utils.Print("Options reset to defaults.")
end

function Addon.UI.CreateSlashCommandsHelpFrame()
    if Addon.UI.slashCommandsHelpFrame then
        return
    end

    local frame = CreateFrame("Frame", "TreenAH_SlashCommandsHelpFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
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
    title:SetText("TreenAH Slash Commands")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -34)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Quick reference for TreenAH slash commands and price-check usage.")

    local scrollFrame = CreateFrame("ScrollFrame", "TreenAH_SlashCommandsHelpScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 46)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(550)
    content:SetHeight(900)
    scrollFrame:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")

    text:SetText(table.concat({
        "|cffffcc66Help Commands|r",
        " ",
        "/treenahhelp",
        "Opens the TreenAH Quick Start Guide.",
        " ",
        "/tahhelp",
        "Also opens the TreenAH Quick Start Guide.",
        " ",
        "/treenahcommands",
        "Opens the TreenAH Slash Command Guide.",
        " ",
        "/tahcommands",
        "Also opens the TreenAH Slash Command Guide.",
        " ",
        "|cffffcc66Price Check Commands|r",
        " ",
        "/pc <item name or itemID>",
        "Prints a TreenAH price check for yourself in your own chat window.",
        "Example: /pc mana potion",
        "Example: /pc 13444",
        " ",
        "/pc party <item name or itemID>",
        "Posts a price check to party chat.",
        " ",
        "/pc raid <item name or itemID>",
        "Posts a price check to raid chat.",
        " ",
        "/pc guild <item name or itemID>",
        "Posts a price check to guild chat.",
        " ",
        "/pc say <item name or itemID>",
        "Posts a price check to say chat.",
        " ",
        "/pc <player> <item name or itemID>",
        "Whispers a price check to a character.",
        "Example: /pc Someplayer primal fire",
        " ",
        "/pc bn:BattleTag <item name or itemID>",
        "Sends a price check to an online Battle.net friend.",
        "Example: /pc bn:Friend#1234 netherweave cloth",
        " ",
        "|cffffcc66Addon Commands|r",
        " ",
        "/treenahdata",
        "Opens the TreenAH data browser.",
        " ",
        "/treenahstats",
        "Shows how many recorded items exist in the current market database.",
        " ",
        "/treenahcleardb",
        "Opens the confirmation flow to delete all recorded price history for the current server/faction.",
        " ",
        "/treenahautoreply [on|off]",
        "Enables or disables automatic replies to 'pc <item>' messages.",
        " ",
        "/treenahautoshow [on|off]",
        "Controls whether the TreenAH main panel opens automatically at the auction house.",
        " ",
        "/treenahautoscan [on|off]",
        "Controls passive auto-scanning of currently visible auction results.",
        " ",
        "/treenahautotrackrequests [on|off]",
        "Controls whether resolvable requested items are added to the Requests list automatically, even before TreenAH has price history for them.",
        " ",
        "/treenahthreshold <number>",
        "Sets the outlier filter threshold used to ignore unreasonable prices.",
        " ",
        "/treenahavgwindow <days>",
        "Sets how many recent calendar days are used for the displayed historical average.",
        " ",
        "/treenahdebug [on|off]",
        "Enables or disables TreenAH debug mode.",
        " ",
        "|cffffcc66Notes|r",
        " ",
        "- Price checks only work for items that already have recorded TreenAH data.",
        "- Use item scans, list scans, or full scans to build your price history.",
        "- Battle.net price checks require the target friend to be online and matched by BattleTag or account name.",
    }, "\n"))

    content.text = text

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 22)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    Addon.UI.slashCommandsHelpFrame = frame
end

function Addon.UI.ShowSlashCommandsHelp()
    Addon.UI.CreateSlashCommandsHelpFrame()
    Addon.UI.slashCommandsHelpFrame:Show()
    Addon.UI.slashCommandsHelpFrame:Raise()
end

function Addon.UI.CreateQuickStartGuideFrame()
    if Addon.UI.quickStartGuideFrame then
        return
    end

    local frame = CreateFrame("Frame", "TreenAH_QuickStartGuideFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(660, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
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
    title:SetText("TreenAH Quick Start Guide")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -34)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("What TreenAH does, how to get started, and the best ways to use it.")

    local scrollFrame = CreateFrame("ScrollFrame", "TreenAH_QuickStartGuideScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 46)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(585)
    content:SetHeight(1200)
    scrollFrame:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")

    text:SetText(table.concat({
        "|cffffcc66What TreenAH does|r",
        " ",
        "TreenAH records auction house low prices over time and builds a recent historical average for items it has seen.",
        "It can show this data in item tooltips, in the Auction House browse list, and through /pc price checks.",
        " ",
        "|cffffcc66Getting started|r",
        " ",
        "1. Open the Auction House.",
        "2. Browse normally and let TreenAH collect price data.",
        "3. Run manual scans when you want better data faster.",
        "4. Use tooltips, the browse column, or /pc <item> to check prices.",
        " ",
        "|cffffcc66Scan types|r",
        " ",
        "Passive browsing scan",
        "When auto-scan is enabled, TreenAH quietly records visible auction results while you browse the Auction House.",
        " ",
        "Single Item Scan",
        "Best when you want data for one specific item right now.",
        " ",
        "List Scan",
        "Best for checking groups of tracked items you care about often.",
        " ",
        "Fast Full Scan",
        "A quick large snapshot of auction results. Good for building data quickly, but not always complete.",
        " ",
        "Slow Full Scan",
        "A slower, more thorough scan of auction pages.",
        " ",
        "|cffffcc66Best results advice|r",
        " ",
        "The more often TreenAH sees the market, the better its averages become.",
        "You do not need to obsess over scanning constantly.",
        "Scanning whenever you visit the Auction House is usually enough to build useful data over time.",
        " ",
        "If you care about one item, use a Single Item Scan.",
        "If you care about a group of items, use tracked lists and run a List Scan.",
        "If you want to build data broadly, use a Fast Full Scan or Slow Full Scan.",
        " ",
        "|cffffcc66How TreenAH keeps data useful|r",
        " ",
        "TreenAH is designed to avoid obviously wild or misleading prices from distorting your history.",
        "The Outlier Threshold setting helps block extreme prices that are far outside an item's normal recorded range.",
        "By default, this is set to 5.",
        "If you want stricter filtering, lower it.",
        "If you want TreenAH to allow more unusual prices into history, raise it.",
        " ",
        "TreenAH does not try to use every old price forever by default.",
        "TreenAH uses a Recent Average Window to keep displayed averages relevant to the current market.",
        "By default, TreenAH only uses the previous 14 calendar days when calculating the displayed historical average.",
        "This helps keep old stale prices from dragging the average away from what the market looks like now.",
        "If you want a broader average, increase the Recent Average Window Days setting in Options.",
        " ",
        "|cffffcc66Tracked lists|r",
        " ",
        "Use tracked lists to organize items you care about.",
        "List scans can scan your selected list, all lists, or all lists except Requests.",
        "The Requests list is a protected utility list.",
        "If auto-track Requests is enabled, requested items can be added there automatically when WoW can resolve the item cleanly, even before TreenAH has price data for them.",
        " ",
        "|cffffcc66Price checks|r",
        " ",
        "Use /pc <item> to check a price for yourself.",
        "Use /pc party <item>, /pc raid <item>, /pc guild <item>, /pc say <item>, /pc <player> <item>, or /pc bn:BattleTag <item> to send a price check to others.",
        " ",
        "Important:",
        "Price checks themselves only work for items TreenAH has already recorded.",
        "If TreenAH has not seen an item yet, scan it first.",
        " ",
        "|cffffcc66Extra tools|r",
        " ",
        "Use the Data Browser if you want to inspect recorded item history in more detail or clean up stored data.",
        " ",
        "|cffffcc66Need more help?|r",
        " ",
        "Use the Slash Command Guide button or type /treenahcommands for command syntax and examples.",
        "You can also type /treenahhelp or /tahhelp to open TreenAH help.",
        " ",
        "Need help getting started?",
        "Visit the TreenAH CurseForge page for screenshots, setup notes, and quick-start info.",
    }, "\n"))

    content.text = text

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 22)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    Addon.UI.quickStartGuideFrame = frame
end

function Addon.UI.ShowQuickStartGuide()
    Addon.UI.CreateQuickStartGuideFrame()
    Addon.UI.quickStartGuideFrame:Show()
    Addon.UI.quickStartGuideFrame:Raise()
end
