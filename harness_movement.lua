-- Movement harness for lib_movement.lua
-- Run on a CC:Tweaked turtle to exercise movement helpers in-world.

local movement = require("lib_movement")
local common = require("harness_common")
local reporter = require("lib_reporter")

local DEFAULT_CONTEXT = {
    origin = { x = 0, y = 0, z = 0 },
    pointer = { x = 0, y = 0, z = 0 },
    config = {
        maxMoveRetries = 12,
        movementAxisOrder = { "x", "z", "y" },
        initialFacing = "north",
        homeFacing = "north",
        digOnMove = true,
        attackOnMove = true,
        moveRetryDelay = 0.4,
        verbose = true,
    },
}

local function prompt(io, message)
    return common.promptEnter(io, message)
end

local function stepOrientationExercises(ctx, io)
    return function()
        local ok, err = movement.faceDirection(ctx, "north")
        if not ok then
            return false, err
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnLeft(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnLeft(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.faceDirection(ctx, "north")
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Orientation complete: " .. reporter.describePosition(ctx))
        end
        return true
    end
end

local function stepForwardWithObstacleClearing(ctx, io)
    return function()
        if not turtle then
            return false, "turtle API unavailable"
        end
        prompt(io, "Place a disposable block in front of the turtle, then press Enter.")
        if not turtle.detect() then
            turtle.place()
        end
        local ok, err = movement.forward(ctx, { dig = true, attack = true })
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Moved forward to: " .. reporter.describePosition(ctx))
        end
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Returned to origin: " .. reporter.describePosition(ctx))
        end
        return true
    end
end

local function stepVerticalMovement(ctx, io)
    return function()
        local ok, err = movement.up(ctx, {})
        if not ok then
            return false, err
        end
        ok, err = movement.down(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Vertical traversal successful: " .. reporter.describePosition(ctx))
        end
        return true
    end
end

local function stepGoToSquareLoop(ctx, io)
    return function()
        local path = {
            { x = 1, y = 0, z = 0 },
            { x = 1, y = 0, z = 1 },
            { x = 0, y = 0, z = 1 },
            { x = 0, y = 0, z = 0 },
        }
        local ok, err = movement.stepPath(ctx, path, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Path completed, position: " .. reporter.describePosition(ctx))
        end
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Returned to origin: " .. reporter.describePosition(ctx))
        end
        return true
    end
end

local function stepReturnToOriginAlignment(ctx, io)
    return function()
        local ok, err = movement.faceDirection(ctx, "east")
        if not ok then
            return false, err
        end
        ok, err = movement.returnToOrigin(ctx, { facing = "north" })
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Final pose: " .. reporter.describePosition(ctx))
        end
        return true
    end
end

local function run(ctxOverrides, ioOverrides)
    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)

    movement.ensureState(ctx)

    local suite = common.createSuite({ name = "Movement Harness", io = io })

    if io.print then
        io.print("Movement harness starting.\n")
        io.print("Before running, ensure the turtle is in an open area with at least a 3x3 clearing and fuel available.")
        io.print("The harness assumes the turtle starts at origin (0,0,0) facing north relative to your coordinate system.")
    end

    suite:step("Orientation exercises", stepOrientationExercises(ctx, io))
    suite:step("Forward with obstacle clearing", stepForwardWithObstacleClearing(ctx, io))
    suite:step("Vertical movement", stepVerticalMovement(ctx, io))
    suite:step("goTo square loop", stepGoToSquareLoop(ctx, io))
    suite:step("Return to origin alignment", stepReturnToOriginAlignment(ctx, io))

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
