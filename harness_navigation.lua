-- Navigation harness for lib_navigation.lua
-- Run on a CC:Tweaked turtle to validate navigation planning and recovery.

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local navigation = require("lib_navigation")
local common = require("harness_common")
local reporter = require("lib_reporter")
local steps = require("harness_navigation_steps")

local DEFAULT_CONTEXT = {
    origin = { x = 0, y = 0, z = 0 },
    pointer = { x = 0, y = 0, z = 0 },
    config = {
        verbose = true,
        initialFacing = "north",
        homeFacing = "north",
        moveRetryDelay = 0.4,
        maxMoveRetries = 12,
        navigation = {
            waypoints = {
                origin = { 0, 0, 0 },
            },
            returnAxisOrder = { "z", "x", "y" },
        },
    },
}

local function run(ctxOverrides, ioOverrides)
    local ok, err = steps.checkTurtle()
    if not ok then
        error("Navigation harness cannot start: " .. tostring(err))
    end

    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)

    steps.seedRandom()

    movement.ensureState(ctx)
    movement.setPosition(ctx, ctx.origin)
    movement.setFacing(ctx, ctx.config.initialFacing)
    navigation.ensureState(ctx)

    if io.print then
        io.print("Navigation harness starting. Ensure a clear area and sufficient fuel.")
    end

    local suite = common.createSuite({ name = "Navigation Harness", io = io })

    suite:step("Wander and explore", function()
        return steps.wander(ctx, io, 5)
    end)

    suite:step("Return to origin", function()
        return steps.returnHome(ctx, io)
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
