--[[
State: DONE
Cleanup and exit.
--]]

local movement = require("lib_movement")
local logger = require("lib_logger")

local function DONE(ctx)
    logger.info("Build complete!")
    movement.goTo(ctx, ctx.origin)
    return "EXIT"
end

return DONE
