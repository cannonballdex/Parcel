local mq                      = require('mq')
local ICONS                   = require('mq.Icons')

local parcel_inv              = {}

parcel_inv.sendSources        = {}
parcel_inv.items              = {}
parcel_inv.currentSendItemIdx = 0

local inventoryOffset         = 22

parcel_inv.genericSources     = {
    {
        name = "All TS Items",
        filter = function(item)
            return item.Tradeskills() and item.Stackable()
        end,
    },
    {
        name = "All Collectible Items",
        filter = function(item)
            return item.Collectible() and item.Stackable()
        end,
    },
}

parcel_inv.customSources      = {}

--[[
    Sample Custom Source in config/parcel_sources.lua

return {
    {
        name = "Tradable Armor",
        filter = function(item)
            return item.Type() == "Armor"
        end,
    },
}
]]

---@param additionalSource table
---@return table
function parcel_inv:new(additionalSource)
    local newInv = setmetatable({}, self)
    self.__index = self
    newInv.customSources = additionalSource or {}
    newInv.sendSources = {}
    newInv.items = {}
    newInv.currentSendItemIdx = 0
    return newInv
end

function parcel_inv:removeItem(target)
    for idx, item in ipairs(self.items) do
        if item == target then
            table.remove(self.items, idx)

            if self.currentSendItemIdx >= idx then
                self.currentSendItemIdx = self.currentSendItemIdx - 1
            end

            if self.currentSendItemIdx < 0 then
                self.currentSendItemIdx = 0
            end

            return true
        end
    end

    return false
end

function parcel_inv:createContainerInventory()
    self.sendSources = {}

    for _, v in ipairs(self.genericSources) do
        table.insert(self.sendSources, v)
    end

    for _, v in ipairs(self.customSources) do
        table.insert(self.sendSources, v)
    end

    for i = 23, 34, 1 do
        local slot = mq.TLO.Me.Inventory(i)
        if slot() and slot.Container() and slot.Container() > 0 then
            local bagName = string.format("%s (%d)", slot.Name(), slot.ItemSlot() - inventoryOffset)
            table.insert(self.sendSources, {
                name = bagName,
                slot = slot,
            })
        end
    end
end

-- Converts between ItemSlot and /itemnotify pack numbers
function parcel_inv.toPack(slot_number)
    slot_number = tonumber(slot_number)
    if not slot_number then return nil end
    return "pack" .. tostring(slot_number - 22)
end

-- Converts between ItemSlot2 and /itemnotify numbers
function parcel_inv.toBagSlot(slot_number)
    slot_number = tonumber(slot_number)
    if slot_number == nil then return nil end
    return slot_number + 1
end

function parcel_inv:resetState()
    self.currentSendItemIdx = 0
end

function parcel_inv:getNextItem()
    if #self.items == 0 then
        self.currentSendItemIdx = 0
        return nil
    end

    self.currentSendItemIdx = self.currentSendItemIdx + 1

    if self.currentSendItemIdx > #self.items then
        self.currentSendItemIdx = 0
        return nil
    end

    return self.items[self.currentSendItemIdx]
end

function parcel_inv:getFilteredItems(filterFn)
    self.items = {}

    for i = 23, 34, 1 do
        local slot = mq.TLO.Me.Inventory(i)

        if slot() and slot.Container() and slot.Container() > 0 then
            for j = 1, slot.Container(), 1 do
                local item = slot.Item(j)
                if item() and not item.NoDrop() and not item.NoRent() and filterFn(item) then
                    table.insert(self.items, {
                        Item = item,
                        Sent = ICONS.MD_CLOUD_QUEUE,
                    })
                end
            end
        else
            if slot() and not slot.NoDrop() and not slot.NoRent() and filterFn(slot) then
                table.insert(self.items, {
                    Item = slot,
                    Sent = ICONS.MD_CLOUD_QUEUE,
                })
            end
        end
    end

    self.currentSendItemIdx = 0
end

---@param index number
function parcel_inv:getItems(index)
    local data = self.sendSources[index]
    if not data then return end

    if data.filter ~= nil then
        self:getFilteredItems(data.filter)
    else
        self.items = {}

        local slot = data.slot
        if slot() and slot.Container() and slot.Container() > 0 then
            for j = 1, slot.Container(), 1 do
                local item = slot.Item(j)
                if item() and not item.NoDrop() and not item.NoRent() then
                    table.insert(self.items, {
                        Item = item,
                        Sent = ICONS.MD_CLOUD_QUEUE,
                    })
                end
            end
        end
    end

    self.currentSendItemIdx = 0
end

return parcel_inv