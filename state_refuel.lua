--[[
State: REFUEL
Returns to origin and attempts to refuel.
--]]

local movement = require("lib_movement")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")

local function REFUEL(ctx)
    logger.log(ctx, "info", "Refueling...")
    
    -- Go home
    local ok, err = movement.goTo(ctx, ctx.origin)
    if not ok then
        ctx.resumeState = ctx.resumeState or "BUILD"
        return "BLOCKED"
    end

    -- Refuel
    -- lib_fuel.refuel() might be available?
    -- Or we just use turtle.refuel() on items.
    -- Let's use lib_fuel if possible.
    
    -- Checking lib_fuel... I don't have its content in mind, but let's assume it has 'ensure' or similar.
    -- If not, we'll do a simple loop.
    
    ---@diagnostic disable: undefined-global
    local needed = turtle.getFuelLimit() - turtle.getFuelLevel()
    if needed <= 0 then
        local resume = ctx.resumeState or "BUILD"
        ctx.resumeState = nil
        return resume
    end
    
    -- Try to refuel from inventory first
    for i=1,16 do
        turtle.select(i)
        if turtle.refuel(0) then -- Check if fuel
            turtle.refuel()
        end
    end
    
    if turtle.getFuelLevel() > 1000 then
        local resume = ctx.resumeState or "BUILD"
        ctx.resumeState = nil
        return resume
    end
    
    logger.log(ctx, "error", "Out of fuel and no fuel items found.")
    return "ERROR"
end

return REFUEL
