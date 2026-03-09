--[[ TLO Info here: https://docs.macroquest.org/reference/data-types/datatype-item/ ]]
--[[ Save this file as: config/parcel_sources.lua ]]

local NoParcelItems = {
    "Bone Chips",
    "Pearl",
    "Tiny Jade Inlaid Coffin",
    "Malachite",
    "Peridot",
    "Filleting Knife",
    "Bulwark of Many Portals",
    "Tiny Dagger",
}

local function findNoParcel(t, value)
    for _, v in ipairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

return {
    noParcelItems = NoParcelItems,

    sources = {
        {
            name = "NoParcel Filtered TS Items",
            filter = function(item)
                return item.Tradeskills()
                    and item.Stackable()
                    and not findNoParcel(NoParcelItems, item.Name())
            end,
        },
        {
            name = "Tradable Armor",
            filter = function(item)
                return item.Type() == "Armor"
            end,
        },
        {
            name = "Tradable Augs",
            filter = function(item)
                return item.Type() == "Augmentation"
            end,
        },
        {
            name = "Food",
            filter = function(item)
                return item.Type() == "Food"
            end,
        },
        {
            name = "Drink",
            filter = function(item)
                return item.Type() == "Drink"
            end,
        },
        {
            name = "Fabled",
            filter = function(item)
                return item.Name():find("Fabled", 1, true) ~= nil
            end,
        },
        {
            name = "Enchant",
            filter = function(item)
                return item.Name():find("Ability:", 1, true) ~= nil
            end,
        },
        {
            name = "Gallant",
            filter = function(item)
                return item.Name():find("Gallant", 1, true) ~= nil
            end,
        },
        {
            name = "Items Under Level 50",
            filter = function(item)
                return (tonumber(item.RequiredLevel()) or 0) < 50
            end,
        },
        {
            name = "Items With ManaRegen",
            filter = function(item)
                return (tonumber(item.ManaRegen()) or 0) > 0
            end,
        },
        {
            name = "Items that start with A",
            filter = function(item)
                return item.Name():find("^[Aa]") ~= nil
            end,
        },
    }
}