--[[
State: BLOCKED
Handles navigation failures.
--]]

local logger = require("lib_logger")

local function BLOCKED(ctx)
    logger.warn("Movement blocked. Retrying in 5 seconds...")
    ---@diagnostic disable-next-line: undefined-global
    sleep(5)
    ctx.retries = (ctx.retries or 0) + 1
    if ctx.retries > 5 then
        logger.error("Too many retries.")
        return "ERROR"
    end
    return "BUILD" -- Retry build step
end

return BLOCKED
