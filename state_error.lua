--[[
State: ERROR
Handles fatal errors.
--]]

local logger = require("lib_logger")

local function ERROR(ctx)
    logger.error("Fatal Error: " .. tostring(ctx.lastError))
    print("Press Enter to exit...")
    ---@diagnostic disable-next-line: undefined-global
    read()
    return "EXIT"
end

return ERROR
