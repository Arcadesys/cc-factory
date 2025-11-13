-- Movement harness for lib_movement.lua
-- Run on a CC:Tweaked turtle to exercise movement helpers in-world.

local movement = require("lib_movement")

local function makeLogger(ctx)
    local logger = {}

    function logger.info(msg)
        print("[INFO] " .. msg)
    end

    function logger.warn(msg)
        print("[WARN] " .. msg)
    end

    function logger.error(msg)
        print("[ERROR] " .. msg)
    end

    function logger.debug(msg)
        if ctx.config and ctx.config.verbose then
            print("[DEBUG] " .. msg)
        end
    end

    return logger
end

local function prompt(message)
    print(message)
    if _G.read then
        read()
    else
        if _G.sleep then
            sleep(3)
        end
    end
end

local function describePosition(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

local function step(name, fn)
    print("\n== " .. name .. " ==")
    local ok, err = fn()
    if ok then
        print("Result: PASS")
    else
        print("Result: FAIL - " .. tostring(err))
    end
end

local function main()
    local ctx = {
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

    ctx.logger = makeLogger(ctx)

    movement.ensureState(ctx)

    print("Movement harness starting.\n")
    print("Before running, ensure the turtle is in an open area with at least a 3x3 clearing and fuel available.")
    print("The harness assumes the turtle starts at origin (0,0,0) facing north relative to your coordinate system.")

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
        print("Orientation complete: " .. describePosition(ctx))
        return true
    end)

    step("Forward with obstacle clearing", function()
        if not turtle then
            return false, "turtle API unavailable"
        end
        prompt("Place a disposable block in front of the turtle, then press Enter.")
        local digAttempted = false
        if not turtle.detect() then
            turtle.place()
        end
        local ok, err = movement.forward(ctx, { dig = true, attack = true })
        if not ok then
            return false, err
        end
        print("Moved forward to: " .. describePosition(ctx))
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        print("Returned to origin: " .. describePosition(ctx))
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
        print("Vertical traversal successful: " .. describePosition(ctx))
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
        print("Path completed, position: " .. describePosition(ctx))
        ok, err = movement.returnToOrigin(ctx, {})
        if not ok then
            return false, err
        end
        print("Returned to origin: " .. describePosition(ctx))
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
        print("Final pose: " .. describePosition(ctx))
        return true
    end)

    print("\nHarness complete. Review the results above for any failures.")
end

main()
