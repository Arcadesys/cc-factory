--[[
State: ERROR
Handles fatal errors.
--]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")

local function ERROR(ctx)
    local message = tostring(ctx.lastError or "Unknown fatal error")
    if ctx.logger then
        ctx.logger:error("Fatal Error: " .. message, { context = diagnostics.snapshot(ctx) })
    else
        logger.log(ctx, "error", "Fatal Error: " .. message)
    end
    print("Press Enter to exit...")
    ---@diagnostic disable-next-line: undefined-global
    read()
    return "EXIT"
end

return ERROR
