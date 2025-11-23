--[[
State: BUILD
Executes the build plan step by step.
--]]

local movement = require("lib_movement")
local placement = require("lib_placement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local orientation = require("lib_orientation")

local function localToWorld(localPos, facing)
    -- Transform local (x=right, z=forward) to world based on facing
    -- This assumes the turtle started at (0,0,0) facing 'facing'
    -- and 'localPos' is relative to that start.
    -- Actually, ctx.origin has the start pos/facing.
    -- But the buildOrder computed localPos relative to start.
    
    -- Simple rotation:
    -- North: x=East, z=South (Wait, standard MC: x+ East, z+ South)
    -- Turtle local: x+ Right, z+ Forward, y+ Up
    
    -- If facing North (z-): Right is East (x+), Forward is North (z-)
    -- If facing East (x+): Right is South (z+), Forward is East (x+)
    -- If facing South (z+): Right is West (x-), Forward is South (z+)
    -- If facing West (x-): Right is North (z-), Forward is West (x-)
    
    local x, y, z = localPos.x, localPos.y, localPos.z
    local wx, wz
    
    if facing == "north" then
        wx, wz = x, -z -- Right(x) -> East(+x), Forward(z) -> North(-z)
        -- Wait, if local z is forward (positive), and we face north (-z), then world z change is -localZ.
        -- If local x is right (positive), and we face north, right is East (+x).
        -- So: wx = x, wz = -z.
        -- BUT: computeLocalXZ in state_initialize used a specific logic.
        -- Let's stick to what 3dprinter.lua likely did or standard turtle logic.
        -- 3dprinter.lua used `localToWorld`. Let's check its implementation if possible.
        -- But for now, I'll implement standard turtle relative coords.
        
        -- Re-reading 3dprinter.lua logic:
        -- "All offsets are specified in turtle-local coordinates (x = right/left, y = up/down, z = forward/back)."
        
        wx = x
        wz = -z -- Forward is -z (North)
    elseif facing == "east" then
        wx = z  -- Forward is +x (East)
        wz = x  -- Right is +z (South)
    elseif facing == "south" then
        wx = -x -- Right is -x (West)
        wz = z  -- Forward is +z (South)
    elseif facing == "west" then
        wx = -z -- Forward is -x (West)
        wz = -x -- Right is -z (North)
    else
        wx, wz = x, z -- Fallback
    end
    
    return { x = wx, y = y, z = wz }
end

local function addPos(p1, p2)
    return { x = p1.x + p2.x, y = p1.y + p2.y, z = p1.z + p2.z }
end

local function BUILD(ctx)
    if ctx.pointer > #ctx.strategy then
        return "DONE"
    end

    local step = ctx.strategy[ctx.pointer]
    local material = step.block.material
    
    -- 1. Check Fuel
    -- Simple check: do we have enough to move?
    -- Real logic should be in REFUEL state or a robust check here.
    ---@diagnostic disable-next-line: undefined-global
    if turtle.getFuelLevel() < 100 and turtle.getFuelLevel() ~= "unlimited" then
        return "REFUEL"
    end

    -- 2. Check Inventory
    local count = inventory.countMaterial(ctx, material)
    if count == 0 then
        logger.warn("Out of material: " .. material)
        ctx.missingMaterial = material
        return "RESTOCK"
    end

    -- 3. Move to position
    -- Convert local approach position to world position
    -- We assume ctx.origin is where we started.
    local origin = ctx.origin
    local worldOffset = localToWorld(step.approachLocal, origin.facing)
    local targetPos = addPos(origin, worldOffset)
    
    -- Use movement lib to go there
    -- We might want a "travel clearance" (fly high) strategy, but for now direct.
    local ok, err = movement.goTo(ctx, targetPos)
    if not ok then
        logger.warn("Movement blocked: " .. tostring(err))
        return "BLOCKED"
    end

    -- 4. Place Block
    -- Ensure we are facing the right way if needed, or just place.
    -- placement.placeMaterial handles orientation if we pass 'side'.
    -- step.side is the side of the block to place ON.
    -- We are at 'approachLocal'.
    
    local placed, placeErr = placement.placeMaterial(ctx, material, {
        side = step.side,
        block = step.block,
        dig = true, -- Clear obstacles
        attack = true
    })

    if not placed then
        if placeErr == "already_present" then
            -- It's fine
        else
            logger.warn("Placement failed: " .. tostring(placeErr))
            -- Could be empty inventory (handled above?) or something else.
            -- If it's "out of items", we should restock.
            -- But placeMaterial might not return specific enough error.
            -- Let's assume if we had count > 0, it's an obstruction or failure.
            -- Retry?
            return "ERROR" -- For now, fail hard so we can debug.
        end
    end

    ctx.pointer = ctx.pointer + 1
    return "BUILD"
end

return BUILD
