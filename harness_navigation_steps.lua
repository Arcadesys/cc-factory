local navigation_steps = {}

local movement = require("lib_movement")
local navigation = require("lib_navigation")
local reporter = require("lib_reporter")

function navigation_steps.checkTurtle()
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

function navigation_steps.seedRandom()
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

function navigation_steps.wander(ctx, io, steps)
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
            io.print(string.format("Wander step %d complete; pose %s", stepIndex, reporter.describePosition(ctx)))
        end
    end
    return true
end

function navigation_steps.returnHome(ctx, io)
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
        io.print("Returned to origin; pose " .. reporter.describePosition(ctx))
    end
    return true
end

return navigation_steps
