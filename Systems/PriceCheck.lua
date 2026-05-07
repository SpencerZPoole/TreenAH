local AddonName, Addon = ...
Addon.PriceCheck = Addon.PriceCheck or {}
Addon.PriceCheck.replyCooldowns = Addon.PriceCheck.replyCooldowns or {}
Addon.PriceCheck.cooldownWarningsSent = Addon.PriceCheck.cooldownWarningsSent or {}
Addon.PriceCheck.globalReplyTimestamps = Addon.PriceCheck.globalReplyTimestamps or {}

local GLOBAL_REPLY_WINDOW_SECONDS = 10
local GLOBAL_REPLY_MAX_MESSAGES = 4

local AUTO_REPLY_PREFIX = "pc "
local AUTO_REPLY_COOLDOWN_SECONDS = 8

function Addon.PriceCheck.ResolveRecordedItemMatch(itemInput)
    itemInput = itemInput and strtrim(itemInput)
    if not itemInput or itemInput == "" then
        return nil, nil, "Enter an item name or item ID first."
    end

    local linkedRecordKey = Addon.DB.GetRecordedKeyFromLink and Addon.DB.GetRecordedKeyFromLink(itemInput)
    if linkedRecordKey then
        local linkedName = Addon.Utils.GetPlainItemNameFromLink(itemInput)
        local displayName = linkedName
            or Addon.PriceCheck.GetCanonicalItemNameByItemID(linkedRecordKey, itemInput)
            or ("Item " .. tostring(linkedRecordKey))
        return linkedRecordKey, displayName
    end

    local linkedItemID = Addon.Utils.GetItemIdFromLink(itemInput)
    if linkedItemID then
        local linkedName = Addon.Utils.GetPlainItemNameFromLink(itemInput)
        return nil, nil, string.format("No recorded item match for '%s'.", tostring(linkedName or itemInput))
    end

    local numericItemID = tonumber(itemInput)
    if numericItemID then
        local numericMatches = Addon.DB.GetRecordedKeysByBaseItemID and Addon.DB.GetRecordedKeysByBaseItemID(numericItemID) or {}
        if #numericMatches == 1 then
            local matchedRecordKey = numericMatches[1]
            local displayName = Addon.PriceCheck.GetCanonicalItemNameByItemID(matchedRecordKey, itemInput)
                or ("Item " .. tostring(numericItemID))
            return matchedRecordKey, displayName
        end

        if #numericMatches > 1 then
            return nil, nil, string.format(
                "Multiple recorded item matches were found for item ID '%s'. Use the full item name or item link instead.",
                tostring(numericItemID)
            )
        end
    end

    local matches = Addon.DB.GetRecordedItemIDsByName and Addon.DB.GetRecordedItemIDsByName(itemInput) or {}
    if #matches == 1 then
        local matchedItemID = matches[1]
        local displayName = Addon.PriceCheck.GetCanonicalItemNameByItemID(matchedItemID, itemInput)
            or tostring(itemInput)
        return matchedItemID, displayName
    end

    if #matches > 1 then
        return nil, nil, string.format(
            "Multiple recorded item matches were found for '%s'. Use an item link or item ID instead.",
            tostring(itemInput)
        )
    end

    if GetItemInfo then
        local resolvedName, itemLink = GetItemInfo(itemInput)
        local resolvedItemID = itemLink and Addon.Utils.GetItemIdFromLink(itemLink) or nil
        local resolvedRecordKey = itemLink and Addon.DB.GetRecordedKeyFromLink and Addon.DB.GetRecordedKeyFromLink(itemLink) or nil

        if resolvedName and strtrim(resolvedName) ~= "" and resolvedRecordKey then
            return resolvedRecordKey, resolvedName
        end

        if resolvedName and strtrim(resolvedName) ~= "" and resolvedItemID and Addon.DB.HasItem(resolvedItemID) then
            return resolvedItemID, resolvedName
        end
    end

    return nil, nil, string.format("No recorded item match for '%s'.", tostring(itemInput))
end

function Addon.PriceCheck.ResolveRecordedItemID(itemInput)
    local itemID, _, resolveError = Addon.PriceCheck.ResolveRecordedItemMatch(itemInput)
    return itemID, resolveError
end

function Addon.PriceCheck.ResolveItemID(itemInput)
    return Addon.PriceCheck.ResolveRecordedItemID(itemInput)
end

function Addon.PriceCheck.GetCanonicalItemNameByItemID(itemID, itemInput)
    if not itemID then
        return nil
    end

    local itemData = Addon.DB.GetItemData(itemID)
    if itemData and itemData.name and itemData.name ~= "" then
        return itemData.name
    end

    if itemInput and GetItemInfo then
        local resolvedName = GetItemInfo(itemInput)
        if resolvedName and strtrim(resolvedName) ~= "" then
            return resolvedName
        end
    end

    local baseItemID = Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(itemID) or itemID
    local itemInfo = Addon.Utils.GetItemInfoByID(baseItemID)
    local itemName = itemInfo and itemInfo.name or nil

    if itemName and strtrim(itemName) ~= "" then
        return itemName
    end

    return nil
end

function Addon.PriceCheck.ResolveRequestedItemName(itemInput)
    itemInput = itemInput and strtrim(itemInput)
    if not itemInput or itemInput == "" then
        return nil, nil
    end

    local linkedRecordKey = Addon.DB.GetRecordedKeyFromLink and Addon.DB.GetRecordedKeyFromLink(itemInput)
    if linkedRecordKey then
        local baseItemID = Addon.DB.GetRecordBaseItemID and Addon.DB.GetRecordBaseItemID(linkedRecordKey) or nil
        return Addon.PriceCheck.GetCanonicalItemNameByItemID(linkedRecordKey, itemInput), baseItemID or linkedRecordKey
    end

    local linkedItemID = Addon.Utils.GetItemIdFromLink(itemInput)
    if linkedItemID then
        return Addon.PriceCheck.GetCanonicalItemNameByItemID(linkedItemID, itemInput), linkedItemID
    end

    local numericItemID = tonumber(itemInput)
    if numericItemID then
        return Addon.PriceCheck.GetCanonicalItemNameByItemID(numericItemID), numericItemID
    end

    local recordedItemID = Addon.DB.FindRecordedItemIDByName(itemInput)
    if recordedItemID then
        return Addon.PriceCheck.GetCanonicalItemNameByItemID(recordedItemID, itemInput), recordedItemID
    end

    if GetItemInfo then
        local resolvedName, itemLink = GetItemInfo(itemInput)
        local resolvedItemID = itemLink and Addon.Utils.GetItemIdFromLink(itemLink) or nil

        if resolvedName and strtrim(resolvedName) ~= "" and resolvedItemID then
            return resolvedName, resolvedItemID
        end
    end

    return nil, nil
end

function Addon.PriceCheck.PruneGlobalReplyTimestamps(now)
    now = now or time()
    local timestamps = Addon.PriceCheck.globalReplyTimestamps or {}

    for i = #timestamps, 1, -1 do
        if (now - timestamps[i]) >= GLOBAL_REPLY_WINDOW_SECONDS then
            table.remove(timestamps, i)
        end
    end
end

function Addon.PriceCheck.CanSendGlobalAutoReply()
    local now = time()
    Addon.PriceCheck.PruneGlobalReplyTimestamps(now)

    local timestamps = Addon.PriceCheck.globalReplyTimestamps or {}
    if #timestamps >= GLOBAL_REPLY_MAX_MESSAGES then
        return false
    end

    return true
end

function Addon.PriceCheck.RecordGlobalAutoReplySent()
    local timestamps = Addon.PriceCheck.globalReplyTimestamps or {}
    timestamps[#timestamps + 1] = time()
    Addon.PriceCheck.globalReplyTimestamps = timestamps
end

function Addon.PriceCheck.GetDeltaLabel(percentDiff)
    if not percentDiff then
        return nil
    end

    if percentDiff <= -2 then
        return "(Falling)"
    elseif percentDiff >= 2 then
        return "(Rising)"
    end

    return nil
end

function Addon.PriceCheck.IsLikelyItemQuery(itemInput)
    itemInput = itemInput and strtrim(itemInput)
    if not itemInput or itemInput == "" then
        return false
    end

    if Addon.Utils.GetItemIdFromLink(itemInput) or tonumber(itemInput) then
        return true
    end

    if GetItemInfo then
        local resolvedName = GetItemInfo(itemInput)
        if resolvedName and strtrim(resolvedName) ~= "" then
            return true
        end
    end

    return false
end

function Addon.PriceCheck.BuildPriceReply(itemInput)
    local itemID, displayName, resolveError = Addon.PriceCheck.ResolveRecordedItemMatch(itemInput)
    if not itemID then
        return string.format("[TreenAH]: %s", tostring(resolveError or "No recorded item match.")), true
    end

    local historicalAvgLow = Addon.DB.GetHistoricalAverageLowPrice(itemID)
    local mostRecentLow = Addon.DB.GetItemMostRecentLow(itemID)
    local itemName = displayName or Addon.Utils.GetItemDisplayNameByItemID(itemID, itemInput)

    if not historicalAvgLow and not mostRecentLow then
        return string.format("[TreenAH]: [%s] No price data recorded yet.", itemName), true
    end

    local avgText = historicalAvgLow and Addon.Utils.FormatMoneyShort(math.floor(historicalAvgLow)) or "N/A"
    local lastText = mostRecentLow and Addon.Utils.FormatMoneyShort(mostRecentLow) or "N/A"
    local percentDiff = Addon.Utils.GetPercentDiffFromAverage(mostRecentLow, historicalAvgLow)
    local deltaText = percentDiff and Addon.Utils.FormatPercentDiff(percentDiff) or "N/A"
    local deltaLabel = Addon.PriceCheck.GetDeltaLabel(percentDiff)

    local prefix = "[TreenAH]"

    local reply = string.format("%s %s: Avg: %s - Last: %s - Δ: %s", prefix, itemName, avgText, lastText, deltaText)

    if deltaLabel then
        reply = reply .. " " .. deltaLabel
    end

    return reply, false
end

function Addon.PriceCheck.ExtractAutoReplyQuery(message)
    if not message then
        return nil
    end

    local trimmed = strtrim(message)
    local lowered = strlower(trimmed)

    if strsub(lowered, 1, strlen(AUTO_REPLY_PREFIX)) == AUTO_REPLY_PREFIX then
        local itemInput = strsub(trimmed, strlen(AUTO_REPLY_PREFIX) + 1)
        itemInput = itemInput and strtrim(itemInput)
        if itemInput ~= "" then
            return itemInput
        end
    end

    return nil
end

function Addon.PriceCheck.HandleIncomingWhisper(message, sender)
    if not Addon.DB.IsAutoReplyEnabled() then
        return
    end

    if not Addon.DB.IsAutoReplyChannelEnabled("whisper") then
        return
    end

    local itemInput = Addon.PriceCheck.ExtractAutoReplyQuery(message)
    if not itemInput or not sender then
        return
    end

    local normalizedSender = Addon.PriceCheck.NormalizeSenderName(sender)
    if not normalizedSender then
        return
    end

    local cooldownKey = "char:" .. normalizedSender
    local canReply, shouldWarn = Addon.PriceCheck.CheckAutoReplyCooldown(cooldownKey)

    if not canReply then
        if shouldWarn then
            C_ChatInfo.SendChatMessage("[TreenAH]: Cooldown active. Please wait a few seconds.", "WHISPER", nil, sender)
        end
        return
    end

    Addon.PriceCheck.TryTrackRequestedItem(itemInput)

    local reply = Addon.PriceCheck.BuildPriceReply(itemInput)
    if reply then
        if not Addon.PriceCheck.CanSendGlobalAutoReply() then
            return
        end

        C_ChatInfo.SendChatMessage(reply, "WHISPER", nil, sender)
        Addon.PriceCheck.RecordGlobalAutoReplySent()
    end
end

function Addon.PriceCheck.HandleIncomingBNWhisper(message, bnSenderID, senderName)
    if not Addon.DB.IsAutoReplyEnabled() then
        return
    end

    if not Addon.DB.IsAutoReplyChannelEnabled("whisper") then
        return
    end

    local itemInput = Addon.PriceCheck.ExtractAutoReplyQuery(message)
    if not itemInput or not bnSenderID then
        return
    end

    local cooldownKey = "bn:" .. tostring(bnSenderID)
    local canReply, shouldWarn = Addon.PriceCheck.CheckAutoReplyCooldown(cooldownKey)

    if not canReply then
        if shouldWarn then
            BNSendWhisper(bnSenderID, "[TreenAH]: Cooldown active. Please wait a few seconds.")
        end
        return
    end

    Addon.PriceCheck.TryTrackRequestedItem(itemInput)

    local reply = Addon.PriceCheck.BuildPriceReply(itemInput)
    if reply then
        if not Addon.PriceCheck.CanSendGlobalAutoReply() then
            return
        end

        BNSendWhisper(bnSenderID, reply)
        Addon.PriceCheck.RecordGlobalAutoReplySent()
    end
end

function Addon.PriceCheck.HandleIncomingChannelMessage(message, sender, channelKey, chatType)
    if not Addon.DB.IsAutoReplyEnabled() then
        return
    end

    if not Addon.DB.IsAutoReplyChannelEnabled(channelKey) then
        return
    end

    local itemInput = Addon.PriceCheck.ExtractAutoReplyQuery(message)
    if not itemInput or not sender or not chatType then
        return
    end

    local normalizedSender = Addon.PriceCheck.NormalizeSenderName(sender)
    if not normalizedSender then
        return
    end

    -- Prevent the addon from responding to your own messages.
    local playerName = UnitName and UnitName("player")
    if playerName and Addon.PriceCheck.NormalizeSenderName(playerName) == normalizedSender then
        return
    end

    local cooldownKey = string.format("%s:%s", tostring(channelKey), tostring(normalizedSender))
    local canReply, shouldWarn = Addon.PriceCheck.CheckAutoReplyCooldown(cooldownKey)

    if not canReply then
        -- Do not post cooldown warnings into public/group chat.
        -- Just silently ignore repeated requests during cooldown.
        return
    end

    Addon.PriceCheck.TryTrackRequestedItem(itemInput)

    local reply = Addon.PriceCheck.BuildPriceReply(itemInput)
    if reply then
        if not Addon.PriceCheck.CanSendGlobalAutoReplyForChannel(channelKey) then
            return
        end

        C_ChatInfo.SendChatMessage(reply, chatType)
        Addon.PriceCheck.RecordGlobalAutoReplySent()
    end
end

function Addon.PriceCheck.CanSendGlobalAutoReplyForChannel(channelKey)
    local now = time()
    Addon.PriceCheck.PruneGlobalReplyTimestamps(now)

    local timestamps = Addon.PriceCheck.globalReplyTimestamps or {}
    local maxMessages = GLOBAL_REPLY_MAX_MESSAGES

    if channelKey ~= "whisper" then
        maxMessages = 2
    end

    return #timestamps < maxMessages
end

function Addon.PriceCheck.NormalizeBattleNetName(text)
    text = text and strtrim(text) or ""
    if text == "" then
        return nil
    end

    return strlower(text)
end

function Addon.PriceCheck.FindBNFriendAccountID(targetText)
    local normalizedTarget = Addon.PriceCheck.NormalizeBattleNetName(targetText)
    if not normalizedTarget then
        return nil
    end

    if not BNGetNumFriends or not BNGetFriendInfo then
        return nil
    end

    local numFriends = BNGetNumFriends() or 0

    for i = 1, numFriends do
        local bnetAccountID, accountName, battleTag, isBattleTagPresence = BNGetFriendInfo(i)

        if bnetAccountID then
            local normalizedAccountName = Addon.PriceCheck.NormalizeBattleNetName(accountName)
            local normalizedBattleTag = Addon.PriceCheck.NormalizeBattleNetName(battleTag)

            if normalizedAccountName == normalizedTarget or normalizedBattleTag == normalizedTarget then
                return bnetAccountID
            end
        end
    end

    return nil
end

function Addon.PriceCheck.GetSlashTargetInfo(targetToken)
    local rawToken = targetToken and strtrim(targetToken) or ""
    local token = strlower(rawToken)

    if token == "" then
        return nil
    end

    if token == "raid" then
        return { chatType = "RAID", target = nil, display = "raid" }
    elseif token == "party" then
        return { chatType = "PARTY", target = nil, display = "party" }
    elseif token == "guild" then
        return { chatType = "GUILD", target = nil, display = "guild" }
    elseif token == "say" then
        return { chatType = "SAY", target = nil, display = "say" }
    end

    local bnTarget = rawToken:match("^[Bb][Nn]%:(.+)$") or rawToken:match("^[Bb][Nn][Ee][Tt]%:(.+)$")
    if bnTarget then
        bnTarget = strtrim(bnTarget)
        if bnTarget == "" then
            return nil
        end

        local bnetAccountID = Addon.PriceCheck.FindBNFriendAccountID(bnTarget)
        if not bnetAccountID then
            return {
                chatType = "BN_WHISPER",
                target = nil,
                display = bnTarget,
                error = "No online Battle.net friend matched '" .. bnTarget .. "'.",
            }
        end

        return {
            chatType = "BN_WHISPER",
            target = bnetAccountID,
            display = bnTarget,
        }
    end

    return { chatType = "WHISPER", target = rawToken, display = rawToken }
end

function Addon.PriceCheck.CanSendToChatType(chatType)
    if chatType == "RAID" then
        return UnitInRaid("player") ~= nil, "You are not in a raid."
    end

    if chatType == "PARTY" then
        if UnitInRaid("player") then
            return false, "You are in a raid, not a party."
        end

        if UnitInParty and UnitInParty("player") then
            return true
        end

        if GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) > 0 then
            return true
        end

        return false, "You are not in a party."
    end

    if chatType == "GUILD" then
        if GetGuildInfo and GetGuildInfo("player") then
            return true
        end

        return false, "You are not in a guild."
    end

    if chatType == "SAY" or chatType == "WHISPER" or chatType == "BN_WHISPER" then
        return true
    end

    return false, "Unsupported chat channel."
end

function Addon.PriceCheck.SendPriceReply(targetInfo, itemInput)
    if not targetInfo or not targetInfo.chatType then
        Addon.Utils.PrintError("Invalid price check target.")
        return
    end

    if targetInfo.error then
        Addon.Utils.PrintError(targetInfo.error)
        return
    end

    local canSend, err = Addon.PriceCheck.CanSendToChatType(targetInfo.chatType)
    if not canSend then
        Addon.Utils.PrintError(err or "Cannot send to that channel right now.")
        return
    end

    local reply = Addon.PriceCheck.BuildPriceReply(itemInput)
    if not reply then
        Addon.Utils.PrintError("Could not build price check reply.")
        return
    end

    if targetInfo.chatType == "WHISPER" then
        C_ChatInfo.SendChatMessage(reply, "WHISPER", nil, targetInfo.target)
    elseif targetInfo.chatType == "BN_WHISPER" then
        BNSendWhisper(targetInfo.target, reply)
    else
        C_ChatInfo.SendChatMessage(reply, targetInfo.chatType)
    end
end

function Addon.PriceCheck.HandleSlashPriceCheck(msg)
    local trimmed = msg and strtrim(msg) or ""

    if trimmed == "" then
        Addon.Utils.PrintError("Usage: /pc <item name or itemID>  OR  /pc <raid|party|guild|say|player|bn:BattleTag> <item name or itemID>")
        return
    end

    -- First, prefer treating the entire input as an item name/itemID.
    local directItemID = Addon.PriceCheck.ResolveItemID(trimmed)
    if directItemID then
        local reply, isError = Addon.PriceCheck.BuildPriceReply(trimmed)
        if not reply then
            Addon.Utils.PrintError("Could not build price check reply.")
            return
        end

        reply = reply:gsub("^%[TreenAH%]%s*", "")
        if isError then
            Addon.Utils.PrintError(reply)
        else
            Addon.Utils.Print(reply)
        end
        return
    end

    local firstToken, remainder = trimmed:match("^(%S+)%s+(.+)$")

    if firstToken and remainder then
        local targetInfo = Addon.PriceCheck.GetSlashTargetInfo(firstToken)

        if targetInfo then
            local tokenLower = strlower(firstToken)

            if tokenLower == "raid"
                or tokenLower == "party"
                or tokenLower == "guild"
                or tokenLower == "say" then
                Addon.PriceCheck.SendPriceReply(targetInfo, remainder)
                return
            end

            if firstToken:match("^[Bb][Nn]%:") or firstToken:match("^[Bb][Nn][Ee][Tt]%:") then
                Addon.PriceCheck.SendPriceReply(targetInfo, remainder)
                return
            end

            if targetInfo.chatType == "WHISPER" and not Addon.PriceCheck.IsLikelyItemQuery(trimmed) then
                local whisperItemID = Addon.PriceCheck.ResolveItemID(remainder)
                if whisperItemID then
                    Addon.PriceCheck.SendPriceReply(targetInfo, remainder)
                    return
                end
            end
        end
    end

    local reply, isError = Addon.PriceCheck.BuildPriceReply(trimmed)
    if not reply then
        Addon.Utils.PrintError("Could not build price check reply.")
        return
    end

    reply = reply:gsub("^%[TreenAH%]%s*", "")
    if isError then
        Addon.Utils.PrintError(reply)
    else
        Addon.Utils.Print(reply)
    end
end

function Addon.PriceCheck.NormalizeSenderName(sender)
    if not sender then
        return nil
    end

    return sender:match("^[^-]+") or sender
end

function Addon.PriceCheck.CheckAutoReplyCooldown(senderKey)
    if not senderKey then
        return false, false
    end

    local now = time()
    local lastReplyAt = Addon.PriceCheck.replyCooldowns[senderKey]

    if lastReplyAt and (now - lastReplyAt) < AUTO_REPLY_COOLDOWN_SECONDS then
        local alreadyWarned = Addon.PriceCheck.cooldownWarningsSent[senderKey]

        if not alreadyWarned then
            Addon.PriceCheck.cooldownWarningsSent[senderKey] = true
            return false, true
        end

        return false, false
    end

    Addon.PriceCheck.replyCooldowns[senderKey] = now
    Addon.PriceCheck.cooldownWarningsSent[senderKey] = nil
    return true, false
end

function Addon.PriceCheck.TryTrackRequestedItem(itemInput)
    if not Addon.DB.IsAutoTrackRequestsEnabled or not Addon.DB.IsAutoTrackRequestsEnabled() then
        return
    end

    local itemName = Addon.PriceCheck.ResolveRequestedItemName(itemInput)
    if not itemName then
        return
    end

    local requestsKey = Addon.TrackedItems.GetRequestsListKey()

    if Addon.TrackedItems.IsTracked(itemName, requestsKey) then
        return
    end

    local alreadyTrackedElsewhere, existingListKey, existingListName =
        Addon.TrackedItems.IsTrackedInAnyList(itemName, requestsKey)
    if alreadyTrackedElsewhere then
        local debugMode = Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled() or false
        if debugMode then
            Addon.Utils.Print(string.format(
                "Skipped adding item into Requests list because it is already tracked in %s.",
                tostring(existingListName or existingListKey or "another list")
            ))
        end
        return
    end

    local ok, result = Addon.TrackedItems.AddTrackedItem(itemName, requestsKey)
    if ok then
        local debugMode = Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled() or false
        if debugMode then
            Addon.Utils.Print("Added item into Requests list: " .. result)
        end
        Addon.TrackedItems.RefreshTrackedItemsList()
    end
end
