local AddonName, Addon = ...

Addon.VersionCheck = Addon.VersionCheck or {}

local VERSION_MESSAGE_PREFIX = "TREENAH_VER"
local VERSION_MESSAGE_PROTOCOL = 1
local VERSION_REQUEST_TYPE = "REQ"
local VERSION_RESPONSE_TYPE = "RESP"

local state = {
    initialized = false,
    startupRequestSent = false,
    updateNoticeShown = false,
    highestDetectedVersion = nil,
}

local function GetAddonMetadataValue(fieldName)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(AddonName, fieldName)
    end

    if GetAddOnMetadata then
        return GetAddOnMetadata(AddonName, fieldName)
    end

    return nil
end

function Addon.VersionCheck.GetCurrentVersion()
    local version = GetAddonMetadataValue("Version")
    if version and version ~= "" then
        return tostring(version)
    end

    return "0.0.0"
end

local function ParseVersionParts(versionText)
    local parts = {}

    if not versionText then
        return parts
    end

    for value in tostring(versionText):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(value) or 0
    end

    return parts
end

function Addon.VersionCheck.IsVersionNewer(candidateVersion, currentVersion)
    local candidateParts = ParseVersionParts(candidateVersion)
    local currentParts = ParseVersionParts(currentVersion)
    local maxCount = math.max(#candidateParts, #currentParts)

    if maxCount == 0 then
        return false
    end

    for i = 1, maxCount do
        local candidateValue = candidateParts[i] or 0
        local currentValue = currentParts[i] or 0

        if candidateValue > currentValue then
            return true
        end

        if candidateValue < currentValue then
            return false
        end
    end

    return false
end

local function NormalizePlayerName(fullName)
    if not fullName or fullName == "" then
        return nil
    end

    local shortName = Ambiguate and Ambiguate(fullName, "short") or fullName
    return strlower(shortName)
end

function Addon.VersionCheck.IsSenderSelf(sender)
    local senderName = NormalizePlayerName(sender)
    local playerName = UnitName and UnitName("player")

    if not senderName or not playerName then
        return false
    end

    return senderName == strlower(playerName)
end

local function BuildPayload(messageType, versionText)
    return string.format("%s;%d;%s", messageType, VERSION_MESSAGE_PROTOCOL, tostring(versionText or "0.0.0"))
end

local function ParsePayload(payloadText)
    local messageType, protocolText, versionText = tostring(payloadText or ""):match("^([A-Z]+);(%d+);(.+)$")
    local protocolVersion = tonumber(protocolText)

    if not messageType or protocolVersion ~= VERSION_MESSAGE_PROTOCOL then
        return nil, nil
    end

    if not versionText or versionText == "" then
        return nil, nil
    end

    return messageType, versionText
end

local function RegisterVersionPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        return C_ChatInfo.RegisterAddonMessagePrefix(VERSION_MESSAGE_PREFIX)
    end

    if RegisterAddonMessagePrefix then
        return RegisterAddonMessagePrefix(VERSION_MESSAGE_PREFIX)
    end

    return false
end

local function DispatchAddonMessage(prefix, payload, distribution, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, payload, distribution, target)
        return
    end

    if SendAddonMessage then
        SendAddonMessage(prefix, payload, distribution, target)
    end
end

local function TrySendPayload(distribution, target, payload)
    DispatchAddonMessage(VERSION_MESSAGE_PREFIX, payload, distribution, target)
    return 1
end

local function SendVersionResponse(distribution, sender)
    local payload = BuildPayload(VERSION_RESPONSE_TYPE, Addon.VersionCheck.GetCurrentVersion())

    if distribution == "WHISPER" and sender and sender ~= "" then
        TrySendPayload("WHISPER", sender, payload)
        return
    end

    if distribution == "GUILD" or distribution == "PARTY" or distribution == "RAID" or distribution == "INSTANCE_CHAT" then
        TrySendPayload(distribution, nil, payload)
    end
end

local function MaybeShowNewerVersionNotice(remoteVersion, sender)
    local currentVersion = Addon.VersionCheck.GetCurrentVersion()
    if not Addon.VersionCheck.IsVersionNewer(remoteVersion, currentVersion) then
        return
    end

    if state.highestDetectedVersion and not Addon.VersionCheck.IsVersionNewer(remoteVersion, state.highestDetectedVersion) then
        return
    end

    state.highestDetectedVersion = remoteVersion

    if state.updateNoticeShown then
        return
    end

    state.updateNoticeShown = true

    local senderName = sender and (Ambiguate and Ambiguate(sender, "short") or sender) or "another player"
    Addon.Utils.Print(string.format(
        "New version detected: %s (you are on %s). Seen from %s.",
        remoteVersion,
        currentVersion,
        tostring(senderName)
    ))
end

local function SendVersionRequest(isManual)
    local payload = BuildPayload(VERSION_REQUEST_TYPE, Addon.VersionCheck.GetCurrentVersion())
    local sentCount = 0

    if IsInGuild and IsInGuild() then
        sentCount = sentCount + TrySendPayload("GUILD", nil, payload)
    end

    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        sentCount = sentCount + TrySendPayload("INSTANCE_CHAT", nil, payload)
    end

    local inHomeRaid = IsInRaid and LE_PARTY_CATEGORY_HOME and IsInRaid(LE_PARTY_CATEGORY_HOME)
    local inHomeParty = IsInGroup and LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)

    if inHomeRaid then
        sentCount = sentCount + TrySendPayload("RAID", nil, payload)
    elseif inHomeParty then
        sentCount = sentCount + TrySendPayload("PARTY", nil, payload)
    end

    if isManual then
        if sentCount > 0 then
            Addon.Utils.Print("Version check request sent.")
        else
            Addon.Utils.Print("No group or guild channel available for version check.")
        end
    end
end

function Addon.VersionCheck.Initialize()
    if state.initialized then
        return
    end

    state.initialized = true

    local registered = RegisterVersionPrefix()
    if not registered and Addon.DB and Addon.DB.IsDebugModeEnabled and Addon.DB.IsDebugModeEnabled() then
        Addon.Utils.PrintError("Version check prefix registration failed.")
    end
end

function Addon.VersionCheck.RunStartupCheck()
    if state.startupRequestSent then
        return
    end

    state.startupRequestSent = true

    if C_Timer and C_Timer.After then
        C_Timer.After(4, function()
            SendVersionRequest(false)
        end)
    else
        SendVersionRequest(false)
    end
end

function Addon.VersionCheck.RequestVersionCheck()
    SendVersionRequest(true)
end

function Addon.VersionCheck.HandleIncomingAddonMessage(prefix, payloadText, distribution, sender)
    if prefix ~= VERSION_MESSAGE_PREFIX then
        return
    end

    if Addon.VersionCheck.IsSenderSelf(sender) then
        return
    end

    local messageType, remoteVersion = ParsePayload(payloadText)
    if not messageType or not remoteVersion then
        return
    end

    if messageType == VERSION_REQUEST_TYPE then
        MaybeShowNewerVersionNotice(remoteVersion, sender)
        SendVersionResponse(distribution, sender)
    elseif messageType == VERSION_RESPONSE_TYPE then
        MaybeShowNewerVersionNotice(remoteVersion, sender)
    end
end
