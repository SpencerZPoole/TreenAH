local AddonName, Addon = ...
Addon.TrackedItems = Addon.TrackedItems or {}

local DEFAULT_LIST_KEY = "default"
local REQUESTS_LIST_KEY = "requests"

local function NormalizeListKey(listKey)
    local key = listKey and strtrim(tostring(listKey)) or ""
    key = key ~= "" and strlower(key) or nil
    return key
end

function Addon.TrackedItems.GetTrackedListsRoot(characterKey)
    local characterRoot = Addon.DB.GetCharacterRoot(characterKey)
    characterRoot.trackedLists = characterRoot.trackedLists or {}

    local root = characterRoot.trackedLists
    root.lists = root.lists or {}
    root.order = root.order or {}
    root.selectedKey = root.selectedKey or DEFAULT_LIST_KEY

    return root
end

function Addon.TrackedItems.EnsureListExists(listKey, displayName)
    local key = NormalizeListKey(listKey)
    if not key then
        return nil
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    root.lists[key] = root.lists[key] or {
        name = displayName or key,
        items = {},
    }

    root.lists[key].items = root.lists[key].items or {}

    if displayName and displayName ~= "" then
        root.lists[key].name = displayName
    elseif not root.lists[key].name or root.lists[key].name == "" then
        root.lists[key].name = key
    end

    local found = false
    for _, existingKey in ipairs(root.order) do
        if existingKey == key then
            found = true
            break
        end
    end

    if not found then
        table.insert(root.order, key)
    end

    return root.lists[key]
end

function Addon.TrackedItems.EnsureCoreLists()
    local root = Addon.TrackedItems.GetTrackedListsRoot()

    -- Requests is always a protected core utility list.
    Addon.TrackedItems.EnsureListExists(REQUESTS_LIST_KEY, "Requests")

    -- Default should exist on first-time setup, but if the user deletes it later,
    -- do not force it back into existence unless there are no non-Requests lists left.
    local hasNonRequestsList = false
    for key, listData in pairs(root.lists) do
        if key ~= REQUESTS_LIST_KEY and listData then
            hasNonRequestsList = true
            break
        end
    end

    if not hasNonRequestsList then
        Addon.TrackedItems.EnsureListExists(DEFAULT_LIST_KEY, "Default")
    end

    local selectedKey = NormalizeListKey(root.selectedKey)

    if not selectedKey or not root.lists[selectedKey] then
        if root.lists[DEFAULT_LIST_KEY] then
            root.selectedKey = DEFAULT_LIST_KEY
        else
            for _, key in ipairs(root.order) do
                if root.lists[key] and key ~= REQUESTS_LIST_KEY then
                    root.selectedKey = key
                    return
                end
            end

            root.selectedKey = REQUESTS_LIST_KEY
        end
    end
end

function Addon.TrackedItems.MigrateLegacyTrackedItems()
    Addon.TrackedItems.EnsureCoreLists()

    if not TreenAHDB.trackedItems then
        return 0
    end

    local movedCount = 0
    local defaultItems = Addon.TrackedItems.GetTrackedItems(DEFAULT_LIST_KEY)

    for key, itemName in pairs(TreenAHDB.trackedItems) do
        if defaultItems[key] == nil then
            defaultItems[key] = itemName
            movedCount = movedCount + 1
        end
    end

    TreenAHDB.trackedItems = nil
    return movedCount
end

function Addon.TrackedItems.GetTrackedItems(listKey)
    Addon.TrackedItems.EnsureCoreLists()

    local key = NormalizeListKey(listKey) or Addon.TrackedItems.GetSelectedListKey()
    local listData = Addon.TrackedItems.EnsureListExists(key)

    return listData.items
end

function Addon.TrackedItems.GetTrackedListData(listKey)
    Addon.TrackedItems.EnsureCoreLists()

    local key = NormalizeListKey(listKey) or Addon.TrackedItems.GetSelectedListKey()
    return Addon.TrackedItems.EnsureListExists(key)
end

function Addon.TrackedItems.GetTrackedListKeys()
    Addon.TrackedItems.EnsureCoreLists()

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    local keys = {}

    for _, key in ipairs(root.order) do
        if root.lists[key] then
            keys[#keys + 1] = key
        end
    end

    return keys
end

function Addon.TrackedItems.GetSelectedListKey()
    Addon.TrackedItems.EnsureCoreLists()

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    local key = NormalizeListKey(root.selectedKey)

    if not key or not root.lists[key] then
        root.selectedKey = DEFAULT_LIST_KEY
        return DEFAULT_LIST_KEY
    end

    return key
end

function Addon.TrackedItems.SetSelectedListKey(listKey)
    Addon.TrackedItems.EnsureCoreLists()

    local key = NormalizeListKey(listKey)
    if not key then
        return false, "Invalid tracked list key."
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    if not root.lists[key] then
        return false, "Tracked list not found."
    end

    root.selectedKey = key
    return true, key
end

function Addon.TrackedItems.GetSelectedListName()
    local listData = Addon.TrackedItems.GetTrackedListData(Addon.TrackedItems.GetSelectedListKey())
    return listData and listData.name or "Default"
end

function Addon.TrackedItems.CreateTrackedList(displayName, preferredKey)
    Addon.TrackedItems.EnsureCoreLists()

    local cleanName = displayName and strtrim(displayName) or ""
    if cleanName == "" then
        return false, "Enter a list name first."
    end

    local key = NormalizeListKey(preferredKey or cleanName:gsub("%s+", "_"))
    if not key then
        return false, "Could not create a valid list key."
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    if root.lists[key] then
        return false, "A tracked list with that name already exists."
    end

    Addon.TrackedItems.EnsureListExists(key, cleanName)
    return true, key
end

function Addon.TrackedItems.GetTrackedItemsList(listKey)
    local trackedItems = Addon.TrackedItems.GetTrackedItems(listKey)
    local list = {}

    for _, itemName in pairs(trackedItems) do
        table.insert(list, itemName)
    end

    table.sort(list)
    return list
end

function Addon.TrackedItems.RefreshTrackedItemsList()
    if Addon.UI and Addon.UI.RefreshTrackedListsPane then
        Addon.UI.RefreshTrackedListsPane()
    end

    if Addon.UI and Addon.UI.RefreshTrackedItemsPane then
        Addon.UI.RefreshTrackedItemsPane()
    end

    if Addon.UI and Addon.UI.UpdateStatusLine then
        Addon.UI.UpdateStatusLine()
    end
end

function Addon.TrackedItems.IsPlaceholderItemName(itemName)
    if not itemName then
        return false
    end

    local trimmed = strtrim(itemName)
    return trimmed:match("^Item%s+%d+$") ~= nil
end

function Addon.TrackedItems.TryResolveTrackedName(itemName)
    if not itemName then
        return nil
    end

    local trimmed = strtrim(itemName)
    if trimmed == "" then
        return nil
    end

    if not Addon.TrackedItems.IsPlaceholderItemName(trimmed) then
        return trimmed
    end

    local itemID = tonumber(trimmed:match("^Item%s+(%d+)$"))
    if not itemID then
        return trimmed
    end

    local itemData = Addon.DB.GetItemData(itemID)
    if itemData and itemData.name and not Addon.TrackedItems.IsPlaceholderItemName(itemData.name) then
        return itemData.name
    end

    local itemInfo = Addon.Utils.GetItemInfoByID(itemID)
    if itemInfo and itemInfo.name then
        return itemInfo.name
    end

    return trimmed
end

function Addon.TrackedItems.AuditTrackedList(listKey)
    local trackedItems = Addon.TrackedItems.GetTrackedItems(listKey)
    local replacements = 0
    local removals = 0
    local rebuilt = {}

    for _, storedName in pairs(trackedItems) do
        local resolvedName = Addon.TrackedItems.TryResolveTrackedName(storedName)

        if resolvedName and resolvedName ~= "" and not Addon.TrackedItems.IsPlaceholderItemName(resolvedName) then
            local key = Addon.Utils.NormalizeItemName(resolvedName)
            if key and not rebuilt[key] then
                rebuilt[key] = resolvedName
            end

            if resolvedName ~= storedName then
                replacements = replacements + 1
            end
        else
            local originalKey = Addon.Utils.NormalizeItemName(storedName)
            if originalKey and not rebuilt[originalKey] and not Addon.TrackedItems.IsPlaceholderItemName(storedName) then
                rebuilt[originalKey] = storedName
            else
                removals = removals + 1
            end
        end
    end

    wipe(trackedItems)
    for key, value in pairs(rebuilt) do
        trackedItems[key] = value
    end

    return replacements, removals
end

function Addon.TrackedItems.AuditAllTrackedLists()
    Addon.TrackedItems.EnsureCoreLists()

    local totalReplacements = 0
    local totalRemovals = 0

    for _, listKey in ipairs(Addon.TrackedItems.GetTrackedListKeys()) do
        local replacements, removals = Addon.TrackedItems.AuditTrackedList(listKey)
        totalReplacements = totalReplacements + (replacements or 0)
        totalRemovals = totalRemovals + (removals or 0)
    end

    return totalReplacements, totalRemovals
end

function Addon.TrackedItems.AddTrackedItem(itemName, listKey)
    local cleanName = Addon.TrackedItems.TryResolveTrackedName(itemName)
    local key = Addon.Utils.NormalizeItemName(cleanName)

    if not key then
        return false, "Enter an item name first."
    end

    if Addon.TrackedItems.IsPlaceholderItemName(cleanName) then
        return false, "Could not determine the real item name yet."
    end

    local trackedItems = Addon.TrackedItems.GetTrackedItems(listKey)

    if trackedItems[key] then
        return false, "That item is already being tracked."
    end

    trackedItems[key] = cleanName
    return true, cleanName
end

function Addon.TrackedItems.RemoveTrackedItem(itemName, listKey)
    local key = Addon.Utils.NormalizeItemName(itemName)
    if not key then
        return false, "Invalid item name."
    end

    local trackedItems = Addon.TrackedItems.GetTrackedItems(listKey)
    if not trackedItems or not trackedItems[key] then
        return false, "That item is not in the tracked list."
    end

    local removedName = trackedItems[key]
    trackedItems[key] = nil

    return true, removedName
end

function Addon.TrackedItems.IsTracked(itemName, listKey)
    local resolvedName = Addon.TrackedItems.TryResolveTrackedName(itemName)
    local key = Addon.Utils.NormalizeItemName(resolvedName)
    if not key then
        return false
    end

    local trackedItems = Addon.TrackedItems.GetTrackedItems(listKey)
    return trackedItems[key] ~= nil
end

function Addon.TrackedItems.IsTrackedByItemID(itemID, listKey)
    if not itemID then
        return false
    end

    local itemData = Addon.DB.GetItemData(itemID)
    local itemName = itemData and itemData.name or nil

    if not itemName then
        local itemInfo = Addon.Utils.GetItemInfoByID(itemID)
        itemName = itemInfo and itemInfo.name or nil
    end

    if not itemName or itemName == "" then
        return false
    end

    return Addon.TrackedItems.IsTracked(itemName, listKey)
end

function Addon.TrackedItems.IsTrackedInAnyList(itemName, excludedListKey)
    Addon.TrackedItems.EnsureCoreLists()

    local resolvedName = Addon.TrackedItems.TryResolveTrackedName(itemName)
    local key = Addon.Utils.NormalizeItemName(resolvedName)
    if not key then
        return false
    end

    local excludedKey = NormalizeListKey(excludedListKey)
    local root = Addon.TrackedItems.GetTrackedListsRoot()

    for _, listKey in ipairs(root.order or {}) do
        if listKey ~= excludedKey then
            local listData = root.lists[listKey]
            local trackedItems = listData and listData.items or nil

            if trackedItems and trackedItems[key] ~= nil then
                return true, listKey, listData.name or listKey
            end
        end
    end

    return false
end

function Addon.TrackedItems.AddTrackedItemByItemID(itemID, listKey)
    if not itemID then
        return false, "Invalid item ID."
    end

    local itemData = Addon.DB.GetItemData(itemID)
    local itemName = itemData and itemData.name or nil

    if not itemName then
        local itemInfo = Addon.Utils.GetItemInfoByID(itemID)
        itemName = itemInfo and itemInfo.name or nil
    end

    if not itemName then
        return false, "Could not determine item name yet."
    end

    return Addon.TrackedItems.AddTrackedItem(itemName, listKey)
end

function Addon.TrackedItems.GetRequestsListKey()
    return REQUESTS_LIST_KEY
end

function Addon.TrackedItems.GetDefaultListKey()
    return DEFAULT_LIST_KEY
end

function Addon.TrackedItems.GetTrackedListEntries()
    Addon.TrackedItems.EnsureCoreLists()

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    local entries = {}
    local requestsEntry = nil

    for _, key in ipairs(root.order) do
        local listData = root.lists[key]
        if listData then
            local itemCount = 0
            for _ in pairs(listData.items or {}) do
                itemCount = itemCount + 1
            end

            local entry = {
                key = key,
                name = listData.name or key,
                itemCount = itemCount,
                isDefault = (key == Addon.TrackedItems.GetDefaultListKey()),
                isRequests = (key == Addon.TrackedItems.GetRequestsListKey()),
            }

            if entry.isRequests then
                requestsEntry = entry
            else
                entries[#entries + 1] = entry
            end
        end
    end

    if requestsEntry then
        entries[#entries + 1] = requestsEntry
    end

    return entries
end

function Addon.TrackedItems.CanModifyList(listKey)
    local key = NormalizeListKey(listKey)
    if not key then
        return false
    end

    return key ~= DEFAULT_LIST_KEY and key ~= REQUESTS_LIST_KEY
end

function Addon.TrackedItems.CanDeleteList(listKey)
    local key = NormalizeListKey(listKey)
    if not key then
        return false
    end

    return key ~= REQUESTS_LIST_KEY
end

function Addon.TrackedItems.RenameTrackedList(listKey, newDisplayName)
    Addon.TrackedItems.EnsureCoreLists()

    local key = NormalizeListKey(listKey)
    local cleanName = newDisplayName and strtrim(newDisplayName) or ""

    if not key or not cleanName or cleanName == "" then
        return false, "Enter a valid list name."
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    local listData = root.lists[key]

    if not listData then
        return false, "Tracked list not found."
    end

    if not Addon.TrackedItems.CanModifyList(key) then
        return false, "That core tracked list cannot be renamed."
    end

    for otherKey, otherList in pairs(root.lists) do
        if otherKey ~= key and otherList and otherList.name and strlower(strtrim(otherList.name)) == strlower(cleanName) then
            return false, "Another tracked list already has that name."
        end
    end

    listData.name = cleanName
    return true, cleanName
end

function Addon.TrackedItems.DeleteTrackedList(listKey)
    Addon.TrackedItems.EnsureCoreLists()

    local key = NormalizeListKey(listKey)
    if not key then
        return false, "Invalid tracked list."
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    if not root.lists[key] then
        return false, "Tracked list not found."
    end

    if not Addon.TrackedItems.CanDeleteList(key) then
        local cantDeleteRequestsMsg = "The Requests list is a protected utility list used for auto-tracking requested items. It cannot be deleted, but you can remove individual items from it if you don't want them tracked."
        local cantDeleteMsg = "That core tracked list cannot be deleted."
        if key == REQUESTS_LIST_KEY then
            Addon.Utils.PrintError(cantDeleteRequestsMsg)
            return false, cantDeleteRequestsMsg
        else
            Addon.Utils.PrintError(cantDeleteMsg)
            return false, cantDeleteMsg
        end
    end

    root.lists[key] = nil

    for index = #root.order, 1, -1 do
        if root.order[index] == key then
            table.remove(root.order, index)
            break
        end
    end

    if root.selectedKey == key then
        if root.lists[DEFAULT_LIST_KEY] then
            root.selectedKey = DEFAULT_LIST_KEY
        else
            local fallbackKey = nil

            for _, orderedKey in ipairs(root.order) do
                if root.lists[orderedKey] and orderedKey ~= REQUESTS_LIST_KEY then
                    fallbackKey = orderedKey
                    break
                end
            end

            root.selectedKey = fallbackKey or REQUESTS_LIST_KEY
        end
    end

    return true, key
end

function Addon.TrackedItems.DuplicateTrackedList(sourceListKey, newDisplayName)
    Addon.TrackedItems.EnsureCoreLists()

    local sourceKey = NormalizeListKey(sourceListKey)
    local cleanName = newDisplayName and strtrim(newDisplayName) or ""

    if not sourceKey then
        return false, "Invalid source tracked list."
    end

    if cleanName == "" then
        return false, "Enter a name for the duplicated list."
    end

    local root = Addon.TrackedItems.GetTrackedListsRoot()
    local sourceList = root.lists[sourceKey]
    if not sourceList then
        return false, "Source tracked list not found."
    end

    local newKey = NormalizeListKey(cleanName:gsub("%s+", "_"))
    if not newKey then
        return false, "Could not create a valid tracked list key."
    end

    if root.lists[newKey] then
        return false, "A tracked list with that name already exists."
    end

    local newList = Addon.TrackedItems.EnsureListExists(newKey, cleanName)
    wipe(newList.items)

    for itemKey, itemName in pairs(sourceList.items or {}) do
        newList.items[itemKey] = itemName
    end

    return true, newKey
end

function Addon.TrackedItems.GetAvailableCharacterKeys()
    TreenAHDB = TreenAHDB or {}
    TreenAHDB.characterData = TreenAHDB.characterData or {}

    local currentKey = Addon.DB.GetCurrentCharacterKey()
    local keys = {}

    for key, data in pairs(TreenAHDB.characterData) do
        if key ~= currentKey and data and data.trackedLists and data.trackedLists.lists then
            local hasAnyList = next(data.trackedLists.lists) ~= nil
            if hasAnyList then
                keys[#keys + 1] = key
            end
        end
    end

    table.sort(keys)
    return keys
end

function Addon.TrackedItems.GetTrackedListEntriesForCharacter(characterKey)
    local root = Addon.TrackedItems.GetTrackedListsRoot(characterKey)
    local entries = {}
    local requestsEntry = nil

    for _, key in ipairs(root.order or {}) do
        local listData = root.lists[key]
        if listData then
            local itemCount = 0
            for _ in pairs(listData.items or {}) do
                itemCount = itemCount + 1
            end

            local entry = {
                key = key,
                name = listData.name or key,
                itemCount = itemCount,
                isDefault = (key == DEFAULT_LIST_KEY),
                isRequests = (key == REQUESTS_LIST_KEY),
            }

            if entry.isRequests then
                requestsEntry = entry
            else
                entries[#entries + 1] = entry
            end
        end
    end

    if requestsEntry then
        entries[#entries + 1] = requestsEntry
    end

    return entries
end

function Addon.TrackedItems.ImportTrackedListFromCharacter(sourceCharacterKey, sourceListKey, newDisplayName)
    local cleanName = newDisplayName and strtrim(newDisplayName) or ""
    if cleanName == "" then
        return false, "Enter a name for the imported list."
    end

    local sourceRoot = Addon.TrackedItems.GetTrackedListsRoot(sourceCharacterKey)
    local sourceList = sourceRoot.lists and sourceRoot.lists[sourceListKey]

    if not sourceList then
        return false, "Source list not found."
    end

    local ok, result = Addon.TrackedItems.CreateTrackedList(cleanName)
    if not ok then
        return false, result
    end

    local newKey = result
    local targetList = Addon.TrackedItems.GetTrackedListData(newKey)
    wipe(targetList.items)

    for itemKey, itemName in pairs(sourceList.items or {}) do
        targetList.items[itemKey] = itemName
    end

    return true, newKey
end

function Addon.TrackedItems.GetTrackedScanTargetEntries()
    Addon.TrackedItems.EnsureCoreLists()

    local entries = {
    { value = "__selected__", text = "Selected List" },
    { value = "__all__", text = "All Lists" },
    { value = "__all_no_requests__", text = "All Lists (Except Requests)" },
    }

    for _, listEntry in ipairs(Addon.TrackedItems.GetTrackedListEntries()) do
        entries[#entries + 1] = {
            value = listEntry.key,
            text = listEntry.name,
        }
    end

    return entries
end
