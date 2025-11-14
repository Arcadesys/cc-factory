-- Logger harness for lib_logger.lua
-- Run on a CC:Tweaked computer or turtle to exercise logging capabilities.

local loggerLib = require("lib_logger")
local common = require("harness_common")

local function showHistory(io, entries)
    if not io.print then
        return
    end
    if not entries or #entries == 0 then
        io.print("Captured history: <empty>")
        return
    end
    io.print("Captured history:")
    for _, entry in ipairs(entries) do
        local label = entry.levelLabel or entry.level
        local stamp = entry.timestamp and (entry.timestamp .. " ") or ""
        local tag = entry.tag and (entry.tag .. " ") or ""
        io.print(string.format(" - %s%s%s%s", stamp, tag, label, entry.message and (" " .. entry.message) or ""))
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
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    step("Baseline output", function()
        log:info("Logger initialized")
        log:warn("Warnings highlight potential issues")
        log:error("Errors bubble to the console")
        return true
    end)

    step("Debug filtered by default", function()
        log:setLevel("info")
        local ok = log:debug("This debug message should be filtered")
        if ok then
            return false, "debug should not emit at info level"
        end
        return true
    end)

    step("Enable debug level", function()
        local ok = log:setLevel("debug")
        if not ok then
            return false, "failed to set debug level"
        end
        local emitted = log:debug("Debug is now visible")
        if not emitted then
            return false, "debug was not emitted"
        end
        return true
    end)

    step("Capture history buffer", function()
        log:clearHistory()
        log:enableCapture(8)
        log:info("Captured info", { phase = "capture", index = 1 })
        log:warn("Captured warn", { phase = "capture", index = 2 })
        local history = log:getHistory()
        if not history or #history ~= 2 then
            return false, "unexpected history length"
        end
        showHistory(io, history)
        return true
    end)

    step("Custom writer hook", function()
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
    end)

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
