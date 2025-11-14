-- Movement harness for lib_movement.lua
-- Run on a CC:Tweaked turtle to exercise movement helpers in-world.

local movement = require("lib_movement")
local common = require("harness_common")

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

local function describePosition(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

local function prompt(io, message)
    return common.promptEnter(io, message)
end

local function run(ctxOverrides, ioOverrides)
    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)

    movement.ensureState(ctx)

    local suite = common.createSuite({ name = "Movement Harness", io = io })
    local function step(name, fn)
        return suite:step(name, fn)
    end

    if io.print then
        io.print("Movement harness starting.\n")
        io.print("Before running, ensure the turtle is in an open area with at least a 3x3 clearing and fuel available.")
        io.print("The harness assumes the turtle starts at origin (0,0,0) facing north relative to your coordinate system.")
    end

    step("Orientation exercises", function()
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
            io.print("Orientation complete: " .. describePosition(ctx))
        end
        return true
    end)

    step("Forward with obstacle clearing", function()
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
            io.print("Moved forward to: " .. describePosition(ctx))
        end
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Returned to origin: " .. describePosition(ctx))
        end
        return true
    end)

    step("Vertical movement", function()
        local ok, err = movement.up(ctx, {})
        if not ok then
            return false, err
        end
        ok, err = movement.down(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Vertical traversal successful: " .. describePosition(ctx))
        end
        return true
    end)

    step("goTo square loop", function()
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
            io.print("Path completed, position: " .. describePosition(ctx))
        end
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Returned to origin: " .. describePosition(ctx))
        end
        return true
    end)

    step("Return to origin alignment", function()
        local ok, err = movement.faceDirection(ctx, "east")
        if not ok then
            return false, err
        end
        ok, err = movement.returnToOrigin(ctx, { facing = "north" })
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Final pose: " .. describePosition(ctx))
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
