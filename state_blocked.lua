--[[
State: BLOCKED
Handles navigation failures.
--]]

local logger = require("lib_logger")

local function BLOCKED(ctx)
    local resume = ctx.resumeState or "BUILD"
    logger.log(ctx, "warn", string.format("Movement blocked while executing %s. Retrying in 5 seconds...", resume))
    ---@diagnostic disable-next-line: undefined-global
    sleep(5)
    ctx.retries = (ctx.retries or 0) + 1
    if ctx.retries > 5 then
        logger.log(ctx, "error", "Too many retries.")
        ctx.resumeState = nil
        return "ERROR"
    end
    ctx.resumeState = nil
    ctx.retries = 0
    return resume
end

return BLOCKED
