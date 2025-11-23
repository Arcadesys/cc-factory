--[[
State: RESTOCK
Returns to origin and attempts to restock the missing material.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function RESTOCK(ctx)
    logger.info("Restocking " .. tostring(ctx.missingMaterial))
    
    -- Go home
    local ok, err = movement.goTo(ctx, ctx.origin)
    if not ok then
        return "BLOCKED"
    end

    -- Attempt to pull
    -- We assume chest is 'forward' relative to origin facing?
    -- Or maybe we just try all sides?
    -- lib_inventory.pullMaterial might handle finding it if we are close?
    -- Actually lib_inventory usually requires a side.
    -- Let's assume chest is BELOW or ABOVE or FRONT.
    -- For now, let's try to pull from 'front' (relative to turtle).
    -- We should probably face the chest.
    -- If origin is where we started, maybe chest is behind us?
    -- 3dprinter.lua prompts for chest location.
    -- Let's assume chest is at (0,0,0) and we are at (0,0,0).
    -- We'll try pulling from all sides.
    
    local material = ctx.missingMaterial
    if not material then return "BUILD" end -- Should not happen

    local pulled = false
    for _, side in ipairs({"front", "up", "down", "left", "right", "back"}) do
        local okPull, pullErr = inventory.pullMaterial(ctx, material, 64, { side = side })
        if okPull then
            pulled = true
            break
        end
    end

    if not pulled then
        logger.error("Could not find " .. material .. " in nearby inventories.")
        return "ERROR"
    end

    ctx.missingMaterial = nil
    return "BUILD"
end

return RESTOCK
