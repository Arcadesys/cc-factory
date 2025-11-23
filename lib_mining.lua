--[[
Mining library for CC:Tweaked turtles.
Handles ore detection, extraction, and hole filling.
]]

---@diagnostic disable: undefined-global

local mining = {}
local inventory = require("lib_inventory")
local movement = require("lib_movement")
local placement = require("lib_placement")
local logger = require("lib_logger")

-- Blocks that are considered "trash" and should be ignored during ore scanning.
-- Also used to determine what blocks can be used to fill holes.
mining.TRASH_BLOCKS = inventory.DEFAULT_TRASH

-- Blocks that should NEVER be placed to fill holes (liquids, gravity blocks, etc)
mining.FILL_BLACKLIST = {
    ["minecraft:air"] = true,
    ["minecraft:water"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:torch"] = true,
    ["minecraft:bedrock"] = true,
}

--- Check if a block is considered "ore" (valuable)
function mining.isOre(name)
    if not name then return false end
    return not mining.TRASH_BLOCKS[name]
end

--- Find a suitable trash block in inventory to use for filling
local function findFillMaterial(ctx)
    local state = inventory.scan(ctx)
    if not state or not state.slots then return nil end
    for slot, item in pairs(state.slots) do
        if mining.TRASH_BLOCKS[item.name] and not mining.FILL_BLACKLIST[item.name] then
            return slot, item.name
        end
    end
    return nil
end

--- Mine a block in a specific direction if it's valuable, then fill the hole
-- @param dir "front", "up", "down"
function mining.mineAndFill(ctx, dir)
    local inspect, dig, place
    if dir == "front" then
        inspect = turtle.inspect
        dig = turtle.dig
        place = turtle.place
    elseif dir == "up" then
        inspect = turtle.inspectUp
        dig = turtle.digUp
        place = turtle.placeUp
    elseif dir == "down" then
        inspect = turtle.inspectDown
        dig = turtle.digDown
        place = turtle.placeDown
    else
        return false, "Invalid direction"
    end

    local hasBlock, data = inspect()
    if hasBlock and mining.isOre(data.name) then
        logger.log(ctx, "info", "Mining valuable: " .. data.name)
        if dig() then
            -- Attempt to fill the hole
            local slot = findFillMaterial(ctx)
            if slot then
                turtle.select(slot)
                place()
            else
                logger.log(ctx, "warn", "No trash blocks available to fill hole")
            end
            return true
        else
            logger.log(ctx, "warn", "Failed to dig " .. data.name)
        end
    end
    return false
end

--- Scan all 6 directions around the turtle, mine ores, and fill holes.
-- The turtle will return to its original facing.
function mining.scanAndMineNeighbors(ctx)
    -- Check Up
    mining.mineAndFill(ctx, "up")
    
    -- Check Down
    mining.mineAndFill(ctx, "down")

    -- Check 4 horizontal directions
    for i = 1, 4 do
        mining.mineAndFill(ctx, "front")
        movement.turnRight(ctx)
    end
end

return mining
