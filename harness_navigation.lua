-- Navigation harness for lib_navigation.lua
-- Run on a CC:Tweaked turtle to validate navigation planning and recovery.

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local navigation = require("lib_navigation")
local common = require("harness_common")

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

local function checkTurtle()
    if not turtle then
        return false, "turtle API unavailable"
    end
    if not turtle.getFuelLevel then
        return false, "turtle fuel API unavailable"
    end
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and fuel < 20 then
        return false, "not enough fuel (need >= 20)"
    end
    return true
end

local function seedRandom()
    local seed
    local epoch = os and rawget(os, "epoch")
    if type(epoch) == "function" then
        seed = epoch("utc")
    elseif os and os.time then
        seed = os.time()
    else
        seed = math.random(0, 10000) + math.random()
    end
    math.randomseed(seed)
    for _ = 1, 5 do
        math.random()
    end
end

local CARDINALS = { "north", "east", "south", "west" }

local function randomFacing()
    return CARDINALS[math.random(1, #CARDINALS)]
end

local function describePose(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

local function wander(ctx, io, steps)
    if io.print then
        io.print("-- Wander Phase --")
    end
    for stepIndex = 1, steps do
        local facing = randomFacing()
        local ok, err = movement.faceDirection(ctx, facing)
        if not ok then
            return false, string.format("step %d: %s", stepIndex, err or "face failed")
        end
        ok, err = movement.forward(ctx, { dig = true, attack = true })
        if not ok then
            return false, string.format("step %d: %s", stepIndex, err or "move failed")
        end
        if io.print then
            io.print(string.format("Wander step %d complete; pose %s", stepIndex, describePose(ctx)))
        end
    end
    return true
end

local function returnHome(ctx, io)
    if io.print then
        io.print("-- Return Phase --")
    end
    local moveOpts = {
        dig = false,
        attack = false,
        axisOrder = ctx.config.navigation and ctx.config.navigation.returnAxisOrder or { "z", "x", "y" },
    }
    local ok, err = navigation.travel(ctx, ctx.origin, {
        move = moveOpts,
        finalFacing = ctx.config.homeFacing or ctx.config.initialFacing or "north",
    })
    if not ok then
        return false, err
    end
    if io.print then
        io.print("Returned to origin; pose " .. describePose(ctx))
    end
    return true
end

local function run(ctxOverrides, ioOverrides)
    local ok, err = checkTurtle()
    if not ok then
        error("Navigation harness cannot start: " .. tostring(err))
    end

    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)

    seedRandom()

    movement.ensureState(ctx)
    movement.setPosition(ctx, ctx.origin)
    movement.setFacing(ctx, ctx.config.initialFacing)
    navigation.ensureState(ctx)

    if io.print then
        io.print("Navigation harness starting. Ensure a clear area and sufficient fuel.")
    end

    local suite = common.createSuite({ name = "Navigation Harness", io = io })
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    step("Wander and explore", function()
        return wander(ctx, io, 5)
    end)

    step("Return to origin", function()
        return returnHome(ctx, io)
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
