local mq                = require('mq')
local ICONS             = require('mq.Icons')
local ImGui             = require('ImGui')
local parcelInv         = require('parcel_inv')
local actors            = require 'actors'

local openGUI           = true
local shouldDrawGUI     = true

local terminate         = false

local parcelTarget      = ""
local startParcel       = false

local animItems         = mq.FindTextureAnimation("A_DragItem")

local status            = "Idle..."
local sourceIndex       = 1
local nearestVendor     = nil

local ColumnID_ItemIcon = 0
local ColumnID_Item     = 1
local ColumnID_Remove   = 2
local ColumnID_Sent     = 3
local ColumnID_LAST     = ColumnID_Sent + 1
local settings_file     = mq.configDir .. "/parcel.lua"
local custom_sources    = mq.configDir .. "/parcel_sources.lua"

local settings          = {}
local DEBUG             = false
local hideNoParcelItems = true

local function has_value(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local Output = function(msg, ...)
    local formatted = msg
    if ... then
        formatted = string.format(msg, ...)
    end
    printf('\aw[' .. mq.TLO.Time() .. '] [\aoParcel\aw] ::\a-t %s', formatted)
end

local function Debug(msg, ...)
    if not DEBUG then return end

    local formatted = msg
    if ... then
        formatted = string.format(msg, ...)
    end
    printf('\aw[' .. mq.TLO.Time() .. '] [\amParcel DEBUG\aw] ::\a-t %s', formatted)
end

local function SaveSettings()
    settings.HideNoParcelItems = hideNoParcelItems
    mq.pickle(settings_file, settings)
    actors.send({
        from = mq.TLO.Me.DisplayName(),
        script = "Parcel",
        event = "SaveSettings",
    })
end

local function LoadSettings()
    local config, err = loadfile(settings_file)
    if err or not config then
        Output("\ayNo valid configuration found. Creating a new one: %s", settings_file)
        settings = {}
    else
        settings = config()

        local function getKeysSortedByValue(tbl, sortFunction)
            local keys = {}
            local newtbl = {}

            for key in pairs(tbl) do
                table.insert(keys, key)
            end

            table.sort(keys, function(a, b)
                return sortFunction(tbl[a], tbl[b])
            end)

            for _, key in ipairs(keys) do
                table.insert(newtbl, tbl[key])
            end

            return newtbl
        end

        settings.History = settings.History or {}
        settings.History = getKeysSortedByValue(settings.History, function(a, b) return a < b end)
    end

    local customSourceList = {}
    local noParcelLookup = {}

    local customConfig, customErr = loadfile(custom_sources)
    if not customErr and customConfig then
        local customData = customConfig()

        if type(customData) == "table" then
            -- New format:
            -- return { noParcelItems = {...}, sources = {...} }
            if customData.sources then
                customSourceList = customData.sources
            else
                -- Backward compatible old format:
                -- return { {name=..., filter=...}, ... }
                customSourceList = customData
            end

            if customData.noParcelItems then
                for _, itemName in ipairs(customData.noParcelItems) do
                    noParcelLookup[itemName] = true
                end
            end
        end
    end

    settings.History = settings.History or {}
    settings.NoParcelLookup = noParcelLookup
    hideNoParcelItems = settings.HideNoParcelItems ~= false

    parcelInv = parcelInv:new(customSourceList)

    if not config then
        SaveSettings()
    end
end

local function isNoParcelItem(item)
    if not item or not item.Item or not item.Item.Name then
        return false
    end

    local name = item.Item.Name()
    return name ~= nil and settings.NoParcelLookup and settings.NoParcelLookup[name] == true
end

local function removeNoParcelItemsFromQueue()
    if not hideNoParcelItems or not parcelInv.items then
        return
    end

    local filtered = {}
    local removed = 0

    for _, item in ipairs(parcelInv.items) do
        if isNoParcelItem(item) then
            removed = removed + 1
            Debug("Removed NoParcel item from queue: %s", tostring(item.Item.Name()))
        else
            table.insert(filtered, item)
        end
    end

    parcelInv.items = filtered
    parcelInv:resetState()

    if removed > 0 then
        status = string.format("Removed %d NoParcel item%s from queue.", removed, removed == 1 and "" or "s")
    end
end

local function getInvSlotItem(item)
    if not item or not item.Item then
        return nil
    end

    local itemSlot = tonumber(item.Item.ItemSlot())
    local itemSlot2 = tonumber(item.Item.ItemSlot2())

    Debug("itemSlot=%s itemSlot2=%s", tostring(itemSlot), tostring(itemSlot2))

    if not itemSlot then
        return nil
    end

    local invSlot = mq.TLO.InvSlot(itemSlot)
    if not invSlot or not invSlot() then
        return nil
    end

    -- top-level inventory item
    if not itemSlot2 or itemSlot2 < 0 then
        if not invSlot.Item() then
            return nil
        end
        return invSlot.Item
    end

    -- item inside a bag
    local bagItem = invSlot.Item
    if not bagItem or not bagItem() then
        return nil
    end

    -- this path is working in your setup
    local containedItem = bagItem.Item(itemSlot2 + 1)
    if not containedItem or not containedItem() then
        return nil
    end

    return containedItem
end

local function isItemStillPresent(item)
    local invItem = getInvSlotItem(item)
    if not invItem or not invItem() then
        return false
    end

    local originalName = item.Item and item.Item.Name and item.Item.Name()
    local currentName = invItem.Name and invItem.Name()

    Debug("compare original=%s current=%s", tostring(originalName), tostring(currentName))

    if not originalName or not currentName then
        return false
    end

    return originalName == currentName
end

local function removeInvalidItem(item)
    if parcelInv:removeItem(item) then
        Debug("Removing stale item: %s", tostring(item.Item and item.Item.Name and item.Item.Name() or "Unknown"))
        return true
    end
    return false
end

local function waitForSendButton(timeoutMs)
    local startTime = os.clock()
    timeoutMs = timeoutMs or 2000

    while ((os.clock() - startTime) * 1000) < timeoutMs do
        local btn = mq.TLO.Window("MerchantWnd").Child("MW_Send_Button")
        if btn() == "TRUE" and btn.Enabled() then
            return true
        end
        mq.delay(10)
        mq.doevents()
    end

    return false
end

local function findParcelVendor()
    status = "Finding Nearest Parcel Vendor"

    local parcelSpawns = mq.getFilteredSpawns(function(spawn)
        return (string.find(spawn.Surname() or "", "Parcel") ~= nil) or
            (string.find(spawn.Surname() or "", "Parcel Services") ~= nil) or
            (string.find(spawn.Name() or "", "Postmaster") ~= nil) or
            (string.find(spawn.Name() or "", "A_Vendor_of_Reagents") ~= nil) or
            (string.find(spawn.Name() or "", "Marius_Carver") ~= nil) or
            (string.find(spawn.Name() or "", "Hyredel") ~= nil)
    end)

    if #parcelSpawns <= 0 then
        status = "Idle..."
        return nil
    end

    local dist = 999999
    for _, s in ipairs(parcelSpawns) do
        if s.Distance() < dist then
            nearestVendor = s
            dist = s.Distance()
        end
    end

    status = "Idle..."
    return nearestVendor
end

local function gotoParcelVendor()
    local spawn = findParcelVendor()
    if not spawn then return end

    status = "Naving to Parcel Vendor: " .. spawn.DisplayName()
    Output("\atFound parcel vendor: \am%s", spawn.DisplayName())

    mq.cmdf("/nav id %d | distance=10", spawn.ID())
end

local function targetParcelVendor()
    local spawn = findParcelVendor()
    if not spawn then return end

    Output("\atFound parcel vendor: \am%s", spawn.DisplayName())
    mq.cmdf("/target id %d", spawn.ID())
end

local function reloadCurrentItems()
    status = "Loading Bag Items..."
    parcelInv:getItems(sourceIndex)
    removeNoParcelItemsFromQueue()
    parcelInv:resetState()
    status = "Idle..."
end

local function doParceling()
    if openGUI and (not nearestVendor or not nearestVendor.ID() or nearestVendor.ID() <= 0) then
        findParcelVendor()
    end

    if not startParcel then return end

    settings.History = settings.History or {}
    if parcelTarget ~= "" and not has_value(settings.History, parcelTarget) then
        table.insert(settings.History, 1, parcelTarget)
        SaveSettings()
    end

    if not nearestVendor then
        Output("\arNo Parcel Vendor found in zone!")
        startParcel = false
        return
    end

    if not mq.TLO.Navigation.Active() and (nearestVendor.Distance() or 0) > 10 then
        gotoParcelVendor()
    end

    if mq.TLO.Navigation.Active() and not mq.TLO.Navigation.Paused() then
        status = string.format("Naving to %s (%d)", nearestVendor.DisplayName(), nearestVendor.Distance())
        return
    end

    if mq.TLO.Target.ID() ~= nearestVendor.ID() then
        status = "Targeting: " .. nearestVendor.DisplayName()
        targetParcelVendor()
        return
    end

    if not mq.TLO.Window("MerchantWnd").Open() then
        status = "Opening Parcel Window..."
        mq.cmd("/click right target")
        return
    end

    local merchantWnd = mq.TLO.Window("MerchantWnd")
    local tabPage = merchantWnd.Child("MW_MerchantSubWindows")

    if tabPage.CurrentTab.Name() ~= "MW_MailPage" then
        status = "Selecting Parcel Tab..." .. tostring(tabPage.CurrentTabIndex())
        tabPage.SetCurrentTab(tabPage.CurrentTabIndex() + 1)
        return
    end

    if merchantWnd.Child("MW_Send_To_Edit").Text() ~= parcelTarget then
        status = "Setting Name to send to..."
        merchantWnd.Child("MW_Send_To_Edit").SetText(parcelTarget)
        return
    end

    if merchantWnd.Child("MW_Send_Button").Enabled() == false and merchantWnd.Child("MW_Send_Button")() == "TRUE" then
        status = "Waiting on send to finish..."
        return
    end

    local item = parcelInv:getNextItem()
    if item then
        if item.Sent == ICONS.MD_CLOUD_DONE then
            return
        end

        if not isItemStillPresent(item) then
            status = string.format("Skipping missing item: %s", tostring(item.Item.Name() or "Unknown"))
            removeInvalidItem(item)
            return
        end

        if hideNoParcelItems and isNoParcelItem(item) then
            status = string.format("Skipping NoParcel item: %s", tostring(item.Item.Name() or "Unknown"))
            removeInvalidItem(item)
            return
        end

        status = string.format("Sending: %s", item.Item.Name())

        local itemSlot = tonumber(item.Item.ItemSlot())
        local itemSlot2 = tonumber(item.Item.ItemSlot2())

        local pack = parcelInv.toPack(itemSlot)
        local bagSlot = parcelInv.toBagSlot(itemSlot2)

        if not pack then
            status = string.format("Invalid item slot, removing: %s", tostring(item.Item.Name() or "Unknown"))
            removeInvalidItem(item)
            return
        end

        if bagSlot ~= nil and itemSlot2 ~= nil and itemSlot2 >= 0 then
            mq.cmdf("/itemnotify in %s %d leftmouseup", pack, bagSlot)
        else
            mq.cmdf("/itemnotify in %s leftmouseup", pack)
        end

        if not waitForSendButton(2000) then
            status = string.format("Item no longer available, removing: %s", tostring(item.Item.Name() or "Unknown"))
            removeInvalidItem(item)
            return
        end

        item.Sent = ICONS.MD_CLOUD_UPLOAD
        mq.cmd("/shift /notify MerchantWnd MW_Send_Button leftmouseup")
        item.Sent = ICONS.MD_CLOUD_DONE
    else
        startParcel = false
        status = "Idle..."
        parcelInv:resetState()
    end
end

local function renderItems()
    local itemCount = (parcelInv.items and #parcelInv.items) or 0
    ImGui.Text(string.format("Items to Send (%d):", itemCount))

    if ImGui.BeginTable("BagItemList", ColumnID_LAST, bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.Borders)) then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0, 1.0, 1)
        ImGui.TableSetupColumn('Icon',
            bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed),
            20.0,
            ColumnID_ItemIcon)
        ImGui.TableSetupColumn('Item',
            bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.PreferSortDescending, ImGuiTableColumnFlags.WidthStretch),
            150.0,
            ColumnID_Item)
        ImGui.TableSetupColumn('',
            bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed),
            20.0,
            ColumnID_Remove)
        ImGui.TableSetupColumn('Sent',
            bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthFixed),
            20.0,
            ColumnID_Sent)
        ImGui.PopStyleColor()
        ImGui.TableHeadersRow()

        for idx, item in ipairs(parcelInv.items or {}) do
            ImGui.PushID("#_itm_" .. tostring(idx))
            local currentItem = item.Item

            ImGui.TableNextColumn()
            local iconIndex = math.max(0, (tonumber(currentItem.Icon()) or 500) - 500)
            animItems:SetTextureCell(iconIndex)
            ImGui.DrawTextureAnimation(animItems, 20, 20)

            ImGui.TableNextColumn()
            if ImGui.Selectable(currentItem.Name(), false, 0) then
                currentItem.Inspect()
            end

            ImGui.TableNextColumn()
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
            ImGui.PushID("#_btn_" .. tostring(idx))
            if ImGui.Selectable(ICONS.MD_REMOVE_CIRCLE_OUTLINE) then
                parcelInv:removeItem(item)
            end
            ImGui.PopID()
            ImGui.PopStyleColor()

            ImGui.TableNextColumn()
            if item.Sent == ICONS.MD_CLOUD_DONE then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.8, 0.2, 1.0)
            end
            ImGui.Text(item.Sent)
            if item.Sent == ICONS.MD_CLOUD_DONE then
                ImGui.PopStyleColor()
            end

            ImGui.PopID()
        end

        ImGui.EndTable()
    end
end

local COMBO_POPUP_FLAGS = bit32.bor(
    ImGuiWindowFlags.NoTitleBar,
    ImGuiWindowFlags.NoMove,
    ImGuiWindowFlags.NoResize,
    ImGuiWindowFlags.ChildWindow
)

local function popupcombo(label, current_value, options)
    local result, changed = ImGui.InputText(label, current_value)
    local active = ImGui.IsItemActive()
    local activated = ImGui.IsItemActivated()

    if activated then
        ImGui.OpenPopup('##combopopup' .. label)
    end

    local itemrectX, _ = ImGui.GetItemRectMin()
    local _, itemRectY = ImGui.GetItemRectMax()
    ImGui.SetNextWindowPos(itemrectX, itemRectY)
    ImGui.SetNextWindowSize(ImVec2(200, 200))

    if ImGui.BeginPopup('##combopopup' .. label, COMBO_POPUP_FLAGS) then
        for _, value in ipairs(options or {}) do
            if ImGui.Selectable(value) then
                result = value
            end
        end

        if changed or (not active and not ImGui.IsWindowFocused()) then
            ImGui.CloseCurrentPopup()
        end

        ImGui.EndPopup()
    end

    return result
end

local function parcelGUI()
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    if openGUI then
        openGUI, shouldDrawGUI = ImGui.Begin('Parcel', openGUI)
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)

        local pressed
        if shouldDrawGUI then
            if nearestVendor then
                ImGui.Text(string.format("Nearest Parcel Vendor: %s", nearestVendor.DisplayName()))
                ImGui.SameLine()
                if ImGui.SmallButton("Nav to Parcel") then
                    gotoParcelVendor()
                end
            end

            ImGui.SameLine()
            if ImGui.SmallButton("Recheck Nearest") then
                findParcelVendor()
            end

            ImGui.SameLine()
            if ImGui.SmallButton("Exit Parcel") then
                mq.cmd('/lua stop parcel')
                if mq.TLO.Window("MerchantWnd").Open() then
                    mq.cmd('/windowstate MerchantWnd close')
                end
            end

            ImGui.Separator()

            ImGui.Text("Send To:      ")
            ImGui.SameLine()
            parcelTarget = popupcombo('', parcelTarget, settings.History)

            ImGui.Separator()

            ImGui.Text("Select Items: ")
            ImGui.SameLine()
            sourceIndex, pressed = ImGui.Combo(
                "##Select Bag",
                sourceIndex,
                function(idx) return parcelInv.sendSources[idx].name end,
                #parcelInv.sendSources
            )

            if pressed then
                reloadCurrentItems()
            end

            ImGui.SameLine()
            if ImGui.SmallButton(ICONS.MD_REFRESH) then
                status = "Loading Bag Items..."
                parcelInv:createContainerInventory()
                reloadCurrentItems()
            end

            local newHideNoParcel, changedHideNoParcel = ImGui.Checkbox("Hide NoParcel Items", hideNoParcelItems)
            if changedHideNoParcel then
                hideNoParcelItems = newHideNoParcel
                settings.HideNoParcelItems = hideNoParcelItems
                SaveSettings()
                reloadCurrentItems()
            end

            ImGui.Separator()
            ImGui.Text(string.format("Status: %s", status))
            ImGui.Separator()

            local itemCount = (parcelInv.items and #parcelInv.items) or 0
            if itemCount > 0 and parcelTarget:len() >= 4 then
                if ImGui.Button(startParcel and "Cancel" or "Send", 150, 25) then
                    startParcel = not startParcel
                    mq.cmdf("/nav stop")
                    parcelInv:resetState()
                end
            end

            renderItems()
        end

        ImGui.PopStyleColor()
        ImGui.End()
    end
end

mq.imgui.init('parcelGUI', parcelGUI)

mq.bind("/parcel", function()
    openGUI = not openGUI
end)

mq.bind("/parceldebug", function()
    DEBUG = not DEBUG
    Output("Debug mode: %s", DEBUG and "ON" or "OFF")
end)

LoadSettings()
findParcelVendor()

parcelInv:createContainerInventory()
parcelInv:getItems(sourceIndex)
removeNoParcelItemsFromQueue()

Output("\aw>>> \ayParcel tool loaded! Use \at/parcel\ay to open UI!")

---@diagnostic disable-next-line: unused-local
local script_actor = actors.register(function(message)
    local msg = message()

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end

    if msg["script"] ~= "Parcel" then
        return
    end

    Output("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"])

    if msg["event"] == "SaveSettings" then
        LoadSettings()
    end
end)

while not terminate do
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then
        mq.delay(1000)
        mq.doevents()
        goto continue
    end

    doParceling()

    mq.doevents()
    mq.delay(400)

    ::continue::
end