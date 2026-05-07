local AddonName, Addon = ...

-- SavedVariables bootstrap
TreenAHDB = TreenAHDB or { items = {} }

-- Main frame for events
Addon.frame = CreateFrame("Frame", "TreenAH_EventFrame")

-- -------------------------
-- Top-level lifecycle
-- -------------------------

function Addon:OnAddonLoaded(loadedName)
    -- Ensure we're only initializing when our addon is loaded, not when other addons are loaded
    if loadedName ~= AddonName then
        return
    end

    Addon.frame:UnregisterEvent("ADDON_LOADED")
    Addon.DB.InitDB()
    Addon.VersionCheck.Initialize()

    local migratedMarketCount = Addon.DB.MigrateLegacyGlobalMarketData()
    local migratedTrackedListsCount = Addon.DB.MigrateLegacyTrackedListsToCurrentCharacter()

    Addon.DB.RebuildNameIndex()
    Addon.TrackedItems.EnsureCoreLists()

    local migratedCount = Addon.TrackedItems.MigrateLegacyTrackedItems()

    if migratedCount > 0 then
        local debugMode = Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print(string.format(
                "Migrated %d legacy tracked item(s) into the Default list.",
                migratedCount
            ))
        end
    end
    
    if migratedMarketCount > 0 then
        local debugMode = Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print(string.format(
                "Migrated %d legacy market item record(s) into the current server/faction database.",
                migratedMarketCount
            ))
        end
    end

    if migratedTrackedListsCount > 0 then
        local debugMode = Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print(string.format(
                "Migrated %d legacy tracked list(s) into this character's list database.",
                migratedTrackedListsCount
            ))
        end
    end

    Addon.scanSession.scanID = 0
    Addon.Tooltip.HookTooltips()
    Addon.UI.RegisterOptionsPanel()
    Addon.Utils.Print("Loaded.")
end

function Addon:OnPlayerLogin()
    Addon.VersionCheck.RunStartupCheck()
end

function Addon:OnAuctionHouseShow()
    Addon.TrackedItems.EnsureCoreLists()
    local replacements, removals = Addon.TrackedItems.AuditAllTrackedLists()

    if not Addon.UI.mainPanel then
        Addon.UI.CreateMainPanel()
    end

    Addon.UI.CreateAuctionHouseToggleButton()
    Addon.UI.auctionHouseToggleButton:Show()

    Addon.TrackedItems.RefreshTrackedItemsList()

    if Addon.DB.IsAutoShowMainPanelEnabled and Addon.DB.IsAutoShowMainPanelEnabled() then
        Addon.UI.ShowMainPanel()
    else
        Addon.UI.HideMainPanel()
    end

    Addon.BrowseColumn.CreateBrowseColumn()

    if replacements > 0 or removals > 0 then
        local debugMode = Addon.DB.IsDebugModeEnabled()
        if debugMode then
            Addon.Utils.Print(string.format(
                "Tracked items audit complete. Fixed: %d, Removed unresolved placeholders: %d",
                replacements,
                removals
            ))
        end
    end
end

function Addon:OnAuctionHouseClosed()
    Addon.Scanner.ResetScanSession()

    if Addon.UI and Addon.UI.ClearScanSummary then
        Addon.UI.ClearScanSummary()
    end

    if Addon.UI and Addon.UI.ClearOutput then
        Addon.UI.ClearOutput()
    end

    if Addon.UI and Addon.UI.mainPanel then
        Addon.UI.mainPanel:Hide()
    end

    if Addon.UI and Addon.UI.auctionHouseToggleButton then
        Addon.UI.auctionHouseToggleButton:Hide()
    end
end

function Addon:OnAuctionItemListUpdate()
    if Addon.Scanner.IsScanActive() then
        Addon.Scanner.ScheduleProcessCurrentResults()
    elseif Addon.DB.IsAutoScanEnabled() and Addon.Scanner.CanAutoScanCurrentResults() then
        Addon.Scanner.ScanCurrentPage()
    end

    if Addon.BrowseColumn and Addon.BrowseColumn.UpdateBrowseColumn then
        Addon.BrowseColumn.UpdateBrowseColumn()
    end
end

function Addon:OnChatMsgWhisper(message, sender)
    Addon.PriceCheck.HandleIncomingWhisper(message, sender)
end

function Addon:OnChatMsgBNWhisper(message, sender, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    Addon.PriceCheck.HandleIncomingBNWhisper(message, bnSenderID, sender)
end

function Addon:OnChatMsgGuild(message, sender)
    Addon.PriceCheck.HandleIncomingChannelMessage(message, sender, "guild", "GUILD")
end

function Addon:OnChatMsgParty(message, sender)
    Addon.PriceCheck.HandleIncomingChannelMessage(message, sender, "party", "PARTY")
end

function Addon:OnChatMsgRaid(message, sender)
    Addon.PriceCheck.HandleIncomingChannelMessage(message, sender, "raid", "RAID")
end

function Addon:OnChatMsgSay(message, sender)
    Addon.PriceCheck.HandleIncomingChannelMessage(message, sender, "say", "SAY")
end

function Addon:OnChatMsgAddon(prefix, message, distribution, sender)
    Addon.VersionCheck.HandleIncomingAddonMessage(prefix, message, distribution, sender)
end

-- -------------------------
-- Slash commands
-- -------------------------

SLASH_TREENAHCLEARDB1 = "/treenahcleardb"
SlashCmdList["TREENAHCLEARDB"] = function()
    Addon.Scanner.ResetScanSession()
    Addon.DataBrowser.ShowClearAllHistoryConfirmation()
end

SLASH_TREENAHSTATS1 = "/treenahstats"
SlashCmdList["TREENAHSTATS"] = function()
    local items = Addon.DB.GetRecordedItemsList()
    Addon.Utils.Print("Items in current market database: " .. tostring(#items))
end

SLASH_TREENAHPRICECHECK1 = "/pc"
SLASH_TREENAHPRICECHECK2 = "/tahpc"
SLASH_TREENAHPRICECHECK3 = "/treenahpc"
SlashCmdList["TREENAHPRICECHECK"] = function(msg)
    Addon.PriceCheck.HandleSlashPriceCheck(msg)
end

SLASH_TREENAHAUTOREPLY1 = "/treenahautoreply"
SlashCmdList["TREENAHAUTOREPLY"] = function(msg)
    local value = msg and strlower(strtrim(msg)) or ""

    if value == "" then
        Addon.Utils.Print("Auto-reply is currently " .. (Addon.DB.IsAutoReplyEnabled() and "ON" or "OFF") .. ".")
        return
    end

    if value == "on" then
        Addon.DB.SetAutoReplyEnabled(true)
        Addon.Utils.Print("Auto-reply enabled.")
    elseif value == "off" then
        Addon.DB.SetAutoReplyEnabled(false)
        Addon.Utils.Print("Auto-reply disabled.")
    else
        Addon.Utils.PrintError("Usage: /treenahautoreply [on|off]")
    end
end

SLASH_TREENAHAUTOSHOW1 = "/treenahautoshow"
SlashCmdList["TREENAHAUTOSHOW"] = function(msg)
    local value = msg and strlower(strtrim(msg)) or ""

    if value == "" then
        Addon.Utils.Print("Auto-show main panel is currently " .. (Addon.DB.IsAutoShowMainPanelEnabled() and "ON" or "OFF") .. ".")
        return
    end

    if value == "on" then
        Addon.DB.SetAutoShowMainPanelEnabled(true)
        Addon.Utils.Print("Auto-show main panel enabled.")
    elseif value == "off" then
        Addon.DB.SetAutoShowMainPanelEnabled(false)
        Addon.Utils.Print("Auto-show main panel disabled.")
    else
        Addon.Utils.PrintError("Usage: /treenahautoshow [on|off]")
    end
end


SLASH_TREENAHTESTDB1 = "/treenahtestdb"
SlashCmdList["TREENAHTESTDB"] = function()
    local items = Addon.DB.GetRecordedItemsList()
    Addon.Utils.Print("Recorded items: " .. tostring(#items))

    if items[1] then
        local firstItemKey = items[1].itemKey or items[1].itemID
        Addon.Utils.Print("First item: " .. items[1].name .. " [" .. tostring(items[1].itemID or firstItemKey) .. "]")

        local days = Addon.DB.GetRecordedDays(firstItemKey)
        Addon.Utils.Print("Days for first item: " .. tostring(#days))

        if days[1] then
            local hours = Addon.DB.GetRecordedHours(firstItemKey, days[1])
            Addon.Utils.Print("Hours for latest day: " .. tostring(#hours))

            if hours[1] then
                local record = Addon.DB.GetHourRecord(firstItemKey, days[1], hours[1])
                Addon.Utils.Print("Latest hour low: " .. tostring(record and record.low or "nil"))
            end
        end
    end
end


SLASH_TREENAHDATA1 = "/treenahdata"
SLASH_TREENAHDATA2 = "/tahdata"
SlashCmdList["TREENAHDATA"] = function()
    Addon.DataBrowser.Toggle()
end

SLASH_TREENAHDEBUG1 = "/treenahdebug"
SlashCmdList["TREENAHDEBUG"] = function(msg)
    local value = msg and strlower(strtrim(msg)) or ""

    if value == "" then
        Addon.Utils.Print("Debug mode is currently " .. (Addon.DB.IsDebugModeEnabled() and "ON" or "OFF") .. ".")
        return
    end

    if value == "on" then
        Addon.DB.SetDebugModeEnabled(true)
        Addon.Utils.Print("Debug mode enabled.")
    elseif value == "off" then
        Addon.DB.SetDebugModeEnabled(false)
        Addon.Utils.Print("Debug mode disabled.")
    else
        Addon.Utils.PrintError("Usage: /treenahdebug [on|off]")
    end
end

SLASH_TREENAHAUTOSCAN1 = "/treenahautoscan"
SlashCmdList["TREENAHAUTOSCAN"] = function(msg)
    local value = msg and strlower(strtrim(msg)) or ""

    if value == "" then
        Addon.Utils.Print("Auto-scan is currently " .. (Addon.DB.IsAutoScanEnabled() and "ON" or "OFF") .. ".")
        return
    end

    if value == "on" then
        Addon.DB.SetAutoScanEnabled(true)
        Addon.Utils.Print("Auto-scan enabled.")
    elseif value == "off" then
        Addon.DB.SetAutoScanEnabled(false)
        Addon.Utils.Print("Auto-scan disabled.")
    else
        Addon.Utils.PrintError("Usage: /treenahautoscan [on|off]")
    end
end

SLASH_TREENAHVERSION1 = "/treenahversion"
SLASH_TREENAHVERSION2 = "/tahversion"
SlashCmdList["TREENAHVERSION"] = function()
    Addon.VersionCheck.RequestVersionCheck()
end

SLASH_TREENAHAUTOTRACKREQUESTS1 = "/treenahautotrackrequests"
SLASH_TREENAHAUTOTRACKREQUESTS2 = "/treenahrequestsautotrack"
SlashCmdList["TREENAHAUTOTRACKREQUESTS"] = function(msg)
    local value = msg and strlower(strtrim(msg)) or ""

    if value == "" then
        Addon.Utils.Print("Auto-track Requests is currently " .. (Addon.DB.IsAutoTrackRequestsEnabled() and "ON" or "OFF") .. ".")
        return
    end

    if value == "on" then
        Addon.DB.SetAutoTrackRequestsEnabled(true)
        Addon.Utils.Print("Auto-track Requests enabled.")
    elseif value == "off" then
        Addon.DB.SetAutoTrackRequestsEnabled(false)
        Addon.Utils.Print("Auto-track Requests disabled.")
    else
        Addon.Utils.PrintError("Usage: /treenahautotrackrequests [on|off]")
    end
end

SLASH_TREENAHTHRESHOLD1 = "/treenahthreshold"
SLASH_TREENAHTHRESHOLD2 = "/tahthreshold"
SlashCmdList["TREENAHTHRESHOLD"] = function(msg)
    local value = msg and strtrim(msg) or ""

    if value == "" then
        Addon.Utils.Print("Outlier threshold is currently " .. tostring(Addon.DB.GetUnreasonablePriceMultiplier()) .. ".")
        return
    end

    local ok, result = Addon.DB.SetUnreasonablePriceMultiplier(value)
    if ok then
        Addon.Utils.Print("Outlier threshold set to " .. tostring(result) .. ".")
    else
        Addon.Utils.PrintError(result or "Invalid outlier threshold.")
    end
end

SLASH_TREENAHAVGWINDOW1 = "/treenahavgwindow"
SLASH_TREENAHAVGWINDOW2 = "/tahavgwindow"
SlashCmdList["TREENAHAVGWINDOW"] = function(msg)
    local value = msg and strtrim(msg) or ""

    if value == "" then
        Addon.Utils.Print("Recent average window is currently " .. tostring(Addon.DB.GetDisplayAverageWindowDays()) .. " day(s).")
        return
    end

    local ok, result = Addon.DB.SetDisplayAverageWindowDays(value)
    if ok then
        Addon.Utils.Print("Recent average window set to " .. tostring(result) .. " day(s).")
    else
        Addon.Utils.PrintError(result or "Invalid recent average window.")
    end
end

SLASH_TREENAHHELP1 = "/treenahhelp"
SLASH_TREENAHHELP2 = "/tahhelp"
SlashCmdList["TREENAHHELP"] = function()
    if Addon.UI and Addon.UI.ShowQuickStartGuide then
        Addon.UI.ShowQuickStartGuide()
        Addon.Utils.Print("Opened Quick Start Guide.")
    else
        Addon.Utils.PrintError("Quick Start Guide is not available.")
    end
end

SLASH_TREENAHCOMMANDS1 = "/treenahcommands"
SLASH_TREENAHCOMMANDS2 = "/tahcommands"
SlashCmdList["TREENAHCOMMANDS"] = function()
    if Addon.UI and Addon.UI.ShowSlashCommandsHelp then
        Addon.UI.ShowSlashCommandsHelp()
        Addon.Utils.Print("Opened Slash Command Guide.")
    else
        Addon.Utils.PrintError("Slash Command Guide is not available.")
    end
end

-- -------------------------
-- Event registration
-- -------------------------

Addon.frame:RegisterEvent("ADDON_LOADED")
Addon.frame:RegisterEvent("PLAYER_LOGIN")
Addon.frame:RegisterEvent("AUCTION_HOUSE_SHOW")
Addon.frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
Addon.frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
Addon.frame:RegisterEvent("CHAT_MSG_WHISPER")
Addon.frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
Addon.frame:RegisterEvent("CHAT_MSG_ADDON")
Addon.frame:RegisterEvent("CHAT_MSG_GUILD")
Addon.frame:RegisterEvent("CHAT_MSG_PARTY")
Addon.frame:RegisterEvent("CHAT_MSG_RAID")
Addon.frame:RegisterEvent("CHAT_MSG_SAY")

Addon.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        Addon:OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        Addon:OnPlayerLogin()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Addon:OnAuctionHouseShow()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Addon:OnAuctionHouseClosed()
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        Addon:OnAuctionItemListUpdate()
    elseif event == "CHAT_MSG_ADDON" then
        Addon:OnChatMsgAddon(...)
    elseif event == "CHAT_MSG_WHISPER" then
        Addon:OnChatMsgWhisper(...)
    elseif event == "CHAT_MSG_BN_WHISPER" then
        Addon:OnChatMsgBNWhisper(...)
    elseif event == "CHAT_MSG_GUILD" then
        Addon:OnChatMsgGuild(...)
    elseif event == "CHAT_MSG_PARTY" then
        Addon:OnChatMsgParty(...)
    elseif event == "CHAT_MSG_RAID" then
        Addon:OnChatMsgRaid(...)
    elseif event == "CHAT_MSG_SAY" then
        Addon:OnChatMsgSay(...)
    end
end)
