-- Logger harness for lib_logger.lua
-- Run on a CC:Tweaked computer or turtle to exercise logging capabilities.

local loggerLib = require("lib_logger")
local common = require("harness_common")
local reporter = require("lib_reporter")

local function stepBaselineOutput(log)
    return function()
        log:info("Logger initialized")
        log:warn("Warnings highlight potential issues")
        log:error("Errors bubble to the console")
        return true
    end
end

local function stepDebugFiltered(log)
    return function()
        log:setLevel("info")
        local ok = log:debug("This debug message should be filtered")
        if ok then
            return false, "debug should not emit at info level"
        end
        return true
    end
end

local function stepEnableDebug(log)
    return function()
        local ok = log:setLevel("debug")
        if not ok then
            return false, "failed to set debug level"
        end
        local emitted = log:debug("Debug is now visible")
        if not emitted then
            return false, "debug was not emitted"
        end
        return true
    end
end

local function stepCaptureHistory(log, io)
    return function()
        log:clearHistory()
        log:enableCapture(8)
        log:info("Captured info", { phase = "capture", index = 1 })
        log:warn("Captured warn", { phase = "capture", index = 2 })
        local history = log:getHistory()
        if not history or #history ~= 2 then
            return false, "unexpected history length"
        end
        reporter.showHistory(io, history)
        return true
    end
end

local function stepCustomWriter(log, io)
    return function()
        local buffer = {}
        local function sink(entry)
            buffer[#buffer + 1] = entry.level .. ":" .. entry.message
        end
        local ok = log:addWriter(sink)
        if not ok then
            return false, "failed to add custom writer"
        end
        log:info("Custom sink engaged")
        log:removeWriter(sink)
        if #buffer == 0 then
            return false, "custom writer did not capture entry"
        end
        if io.print then
            io.print("Custom sink stored: " .. table.concat(buffer, ", "))
        end
        return true
    end
end

local function run(ctxOverrides, ioOverrides)
    local io = common.resolveIo(ioOverrides)
    local ctx = ctxOverrides or {}

    local log = loggerLib.attach(ctx, {
        tag = "HARNESS",
        timestamps = true,
        capture = true,
        captureLimit = 32,
    })

    if io.print then
        io.print("Logger harness starting.")
        io.print("This script demonstrates leveled output, capture buffers, and writer management.")
    end

    local suite = common.createSuite({ name = "Logger Harness", io = io })

    suite:step("Baseline output", stepBaselineOutput(log))
    suite:step("Debug filtered by default", stepDebugFiltered(log))
    suite:step("Enable debug level", stepEnableDebug(log))
    suite:step("Capture history buffer", stepCaptureHistory(log, io))
    suite:step("Custom writer hook", stepCustomWriter(log, io))

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
