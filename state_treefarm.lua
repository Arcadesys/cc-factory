--[[
State: TREEFARM
Simple tree farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function TREEFARM(ctx)
    logger.log(ctx, "info", "State: TREEFARM")

    -- 1. Check Fuel
    if turtle.getFuelLevel() < 100 then
        logger.log(ctx, "warn", "Fuel low; switching to REFUEL")
        ctx.resumeState = "TREEFARM"
        return "REFUEL"
    end

    -- 2. Check Saplings
    local sapling = "minecraft:oak_sapling" -- Default
    if ctx.config.sapling then sapling = ctx.config.sapling end
    
    local hasSapling = inventory.countMaterial(ctx, sapling) > 0
    
    -- 3. Check if tree is in front
    local hasBlock, data = turtle.inspect()
    if hasBlock and data.name:find("log") then
        logger.log(ctx, "info", "Tree detected! Chopping...")
        
        -- Chop up
        local height = 0
        while true do
            local hasUp, dataUp = turtle.inspectUp()
            if hasUp and dataUp.name:find("log") then
                turtle.digUp()
                movement.up(ctx)
                height = height + 1
            else
                break
            end
        end
        
        -- Come down
        for i=1, height do
            movement.down(ctx)
        end
        
        -- Chop base
        turtle.dig()
        
        -- Replant
        if hasSapling then
            inventory.selectMaterial(ctx, sapling)
            turtle.place()
        end
        
    elseif not hasBlock then
        -- Empty space, plant if needed
        if hasSapling then
            inventory.selectMaterial(ctx, sapling)
            turtle.place()
        else
             -- No sapling, maybe wait?
             logger.log(ctx, "warn", "No saplings to plant.")
        end
    end
    
    -- 4. Wait for growth
    logger.log(ctx, "info", "Waiting for tree...")
    sleep(5)
    
    return "TREEFARM"
end

return TREEFARM
