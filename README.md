# Parcel Tool for MacroQuest

## Overview

The Parcel Tool is a Lua script for MacroQuest that automates sending
items through the in-game parcel system. It scans your inventory or
selected bags, filters items based on rules, and sends them to a
specified character using the parcel vendor.

The tool includes: - A GUI for selecting items and sending parcels -
Built-in item filters (Tradeskill, Collectibles) - Custom filter support
via a configuration file - Automatic navigation to the nearest parcel
vendor - Detection and removal of missing or moved items - Debug mode
for troubleshooting

------------------------------------------------------------------------

# Features

## GUI Interface

The script provides a graphical window where you can: - Select which
items to send - Choose a filter source - View queued items - Remove
items from the queue - Send items to a target character

## Automatic Vendor Navigation

The script will: 1. Locate the nearest parcel vendor 2. Navigate to the
vendor 3. Open the parcel window 4. Send queued items

## Item Queue

Items are added to a queue before sending. Each item has a status icon:

  Icon   Meaning
  ------ ---------
  ☁️     queued
  ⬆️     sending
  ✔      sent

## Stale Item Detection

If an item disappears from inventory after the queue is created (for
example, consumed or moved), the script will automatically:

-   detect the missing item
-   remove it from the queue
-   continue sending the remaining items

This prevents the script from getting stuck.

------------------------------------------------------------------------

# Installation

## 1. Place Script Files

Put the main script in:

MQNext/lua/parcel/

Example directory structure:

MQNext/ └─ lua/ └─ parcel/ init.lua parcel_inv.lua

## 2. Create the Config File

Create this file:

MQNext/config/parcel_sources.lua

This file defines custom item filters.

Example:

``` lua
return {
    {
        name = "Tradable Armor",
        filter = function(item)
            return item.Type() == "Armor"
        end,
    },
}
```

------------------------------------------------------------------------

# Running the Script

Start the script:

/lua run parcel

Open the GUI:

/parcel

Stop the script:

/lua stop parcel

------------------------------------------------------------------------

# Debug Mode

Enable debug logging:

/parceldebug

Disable debug logging:

/parceldebug

Debug output shows: - item slot checks - item comparisons - stale item
removal - parcel send operations

------------------------------------------------------------------------

# Built-In Item Filters

  Filter                  Description
  ----------------------- ---------------------------------
  All TS Items            All stackable tradeskill items
  All Collectible Items   All stackable collectible items

------------------------------------------------------------------------

# Custom Filters

Custom filters are defined in:

config/parcel_sources.lua

Example:

``` lua
return {
    {
        name = "Fabled Items",
        filter = function(item)
            return item.Name():find("Fabled") ~= nil
        end,
    },
}
```

Filters must return **true** for items that should be included.

------------------------------------------------------------------------

# Example Filter File

config/parcel_sources.lua

``` lua
local NoParcelItems = {
    "Bone Chips",
    "Pearl"
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
    {
        name = "Filtered TS Items",
        filter = function(item)
            return item.Tradeskills()
                and item.Stackable()
                and not findNoParcel(NoParcelItems, item.Name())
        end,
    },
}
```

------------------------------------------------------------------------

# Inventory Sources

The script can send items from:

1.  Built-in filters
2.  Custom filters
3.  Individual bags

Bags are automatically detected from inventory slots **23--34**.

------------------------------------------------------------------------

# UI Controls

  Button            Function
  ----------------- --------------------------------
  Send              start parceling
  Cancel            stop parceling
  Refresh           rescan inventory
  Remove icon       remove item from queue
  Nav to Parcel     navigate to vendor
  Recheck Nearest   search for parcel vendor again

------------------------------------------------------------------------

# Requirements

Required: - MacroQuest - Lua enabled

Recommended: - MQ Navigation plugin - mq2nav

------------------------------------------------------------------------

# Troubleshooting

## Script won't send items

Check: - target character name is entered - parcel vendor is reachable -
items are tradable

## Items disappear from queue

This happens if: - items were consumed - items were moved - items were
already sent

The script automatically removes them.

## Filters show no items

Verify the filter conditions match the item properties.

------------------------------------------------------------------------

# Commands

  Command            Description
  ------------------ ----------------------
  /parcel            toggle GUI
  /parceldebug       toggle debug logging
  /lua stop parcel   stop script
