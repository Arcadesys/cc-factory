-- Navigation harness for lib_navigation.lua
-- Run on a CC:Tweaked turtle to validate navigation planning and recovery.

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local navigation = require("lib_navigation")

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
    -- Warm up RNG to avoid low-order correlations.
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

local ctx

local function wander(ctx, steps)
    print("\n== Wander Phase ==")
    for step = 1, steps do
        local facing = randomFacing()
        local ok, err = movement.faceDirection(ctx, facing)
        if not ok then
            return false, string.format("step %d: %s", step, err or "face failed")
        end
        ok, err = movement.forward(ctx, { dig = true, attack = true })
        if not ok then
            return false, string.format("step %d: %s", step, err or "move failed")
        end
        print(string.format("Wander step %d complete; pose %s", step, describePose(ctx)))
    end
    return true
end

local function returnHome(ctx)
    print("\n== Return Phase ==")
    local moveOpts = {
        dig = false,
        attack = false,
        axisOrder = ctx.config.navigation and ctx.config.navigation.returnAxisOrder or { "z", "x", "y" },
    }
    local ok, err = navigation.travel(ctx, ctx.origin, { move = moveOpts, finalFacing = ctx.config.homeFacing or ctx.config.initialFacing or "north" })
    if not ok then
        return false, err
    end
    print("Returned to origin; pose " .. describePose(ctx))
    return true
end

local function main()
    ctx = {
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

    ctx.logger = makeLogger(ctx)

    local ok, err = checkTurtle()
    if not ok then
        error("Navigation harness cannot start: " .. tostring(err))
    end

    seedRandom()

    movement.ensureState(ctx)
    movement.setPosition(ctx, ctx.origin)
    movement.setFacing(ctx, ctx.config.initialFacing)
    navigation.ensureState(ctx)

    print("Navigation harness starting. Ensure a clear area and sufficient fuel.")

    ok, err = wander(ctx, 5)
    if not ok then
        print("Result: FAIL - " .. tostring(err))
        return
    end

    ok, err = returnHome(ctx)
    if not ok then
        print("Result: FAIL - " .. tostring(err))
        return
    end

    print("\nHarness complete. Turtle should be back at origin with no blocks disturbed on the return path.")
end

main()
