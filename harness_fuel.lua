--[[
Harness for lib_fuel.lua.
Guides manual testing of the fuel management helpers by exercising the
check, ensure, and service flows on a CC:Tweaked turtle.
--]]

---@diagnostic disable: undefined-global

local fuel = require("lib_fuel")
local movement = require("lib_movement")
local inventory = require("lib_inventory")
local common = require("harness_common")

local DEFAULT_CONTEXT = {
    origin = { x = 0, y = 0, z = 0 },
    config = {
        verbose = true,
        fuelThreshold = 80,
        fuelReserve = 160,
        fuelChestSides = { "forward", "down", "up" },
        digOnMove = false,
        attackOnMove = false,
    },
}

local function describeFuel(io, report)
    if not io.print then
        return
    end
    if report.unlimited then
        io.print("Fuel: unlimited")
        return
    end
    local levelText = report.level and tostring(report.level) or "unknown"
    local limitText = report.limit and ("/" .. tostring(report.limit)) or ""
    io.print(string.format("Fuel level: %s%s", levelText, limitText))
    if report.threshold then
        io.print(string.format("Threshold: %d", report.threshold))
    end
    if report.reserve then
        io.print(string.format("Reserve target: %d", report.reserve))
    end
    if report.needsService then
        io.print("Status: below threshold (service required)")
    else
        io.print("Status: sufficient for now")
    end
end

local function describeService(io, report)
    if not io.print then
        return
    end
    if not report then
        io.print("No service report available.")
        return
    end
    if report.returnError then
        io.print("Return-to-origin failed: " .. tostring(report.returnError))
    end
    if report.steps then
        for _, step in ipairs(report.steps) do
            if step.type == "return" then
                io.print("Return to origin: " .. (step.success and "OK" or "FAIL"))
            elseif step.type == "refuel" then
                local info = step.report or {}
                local final = info.finalLevel ~= nil and info.finalLevel or (info.endLevel or "unknown")
                io.print(string.format("Refuel step: %s (final=%s)", step.success and "OK" or "FAIL", tostring(final)))
            end
        end
    end
    if report.finalLevel then
        io.print("Service final fuel level: " .. tostring(report.finalLevel))
    end
end

local function ensureOriginPose(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

local function ensureOnboardFuel(ctx, io)
    inventory.ensureState(ctx)
    fuel.ensureState(ctx)

    local function hasFuel()
        local state = ctx.inventoryState or {}
        local totals = state.materialTotals or {}
        local fuelItems = (ctx.fuelState and ctx.fuelState.fuelItems) or {}
        for _, name in ipairs(fuelItems) do
            if (totals[name] or 0) > 0 then
                return true
            end
        end
        return false
    end

    inventory.scan(ctx)
    if hasFuel() then
        return true
    end

    if io.print then
        io.print("No onboard fuel detected. Place at least one recognized fuel item in the turtle's inventory.")
    end
    common.promptEnter(io, "Press Enter after placing onboard fuel.")

    inventory.invalidate(ctx)
    inventory.scan(ctx)
    return hasFuel()
end

local function run(ctxOverrides, ioOverrides)
    if not turtle then
        error("Run this harness on a turtle.")
    end

    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)

    inventory.ensureState(ctx)
    movement.ensureState(ctx)
    movement.setPosition(ctx, ctx.origin)
    fuel.ensureState(ctx)

    if io.print then
        io.print("Fuel harness starting.")
        io.print("Ensure the turtle starts at origin facing north with a clear path back to origin.")
        io.print("Place a chest containing turtle fuel (coal, charcoal, lava buckets, etc.) on one of the configured sides.")
    end

    common.promptEnter(io, "Press Enter when the supply chest is ready.")

    local suite = common.createSuite({ name = "Fuel Harness", io = io })

    suite:step("Baseline fuel status", function()
        local _, report = fuel.check(ctx, {})
        describeFuel(io, report)
        return true
    end)

    suite:step("Initial refuel attempt", function()
        local _, status = fuel.check(ctx, {})
        if status.unlimited then
            if io.print then
                io.print("Fuel reported as unlimited; skipping initial service.")
            end
            return true
        end

        local threshold = (ctx.fuelState and ctx.fuelState.threshold) or (ctx.config and ctx.config.fuelThreshold) or 80
        if threshold < 0 then
            threshold = 0
        end
        local defaultReserve = math.max((threshold > 0) and (threshold * 2) or 0, threshold + 64)
        local configuredReserve = (ctx.fuelState and ctx.fuelState.reserve) or (ctx.config and ctx.config.fuelReserve)
        local reserve = configuredReserve or defaultReserve
        if reserve < threshold then
            reserve = threshold
        end
        local target = reserve > 0 and reserve or threshold

        if status.ok and status.level and status.level >= target then
            if io.print then
                io.print(string.format("Fuel already above target (%d); skipping initial service.", target))
            end
            return true
        end

        if io.print then
            io.print(string.format("Initial service targeting fuel level %d.", target))
        end

        local ok, serviceReport = fuel.service(ctx, { target = target, rounds = 4 })
        describeService(io, serviceReport)
        if not ok then
            return false, serviceReport and (serviceReport.returnError or serviceReport.error or "service_failed") or "service_failed"
        end

        local _, after = fuel.check(ctx, {})
        describeFuel(io, after)
        return true
    end)

    suite:step("Move turtle away from origin", function()
        local ok, err = movement.goTo(ctx, { x = 2, y = 0, z = 1 }, {
            axisOrder = { "x", "z", "y" },
            dig = false,
            attack = false,
        })
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Turtle moved to " .. ensureOriginPose(ctx))
        end
        return true
    end)

    suite:step("Refuel using onboard items away from chest", function()
        local pos = movement.getPosition(ctx)
        if pos.x == ctx.origin.x and pos.y == ctx.origin.y and pos.z == ctx.origin.z then
            return false, "turtle_not_away_from_origin"
        end

        if not ensureOnboardFuel(ctx, io) then
            return false, "no_onboard_fuel"
        end

        local _, before = fuel.check(ctx, {})
        local startLevel = before.level or 0
        local increment = math.max(10, (ctx.fuelState and ctx.fuelState.threshold or 80) / 4)
        local target = startLevel + math.floor(increment)

        if io.print then
            io.print(string.format("Attempting onboard refuel to reach at least %d fuel.", target))
        end

        local ok, report = fuel.refuel(ctx, { target = target, rounds = 1 })
        if io.print then
            io.print(string.format("Onboard refuel %s (final=%s)", ok and "succeeded" or "failed", tostring(report.finalLevel or "unknown")))
        end

        if not ok then
            return false, report
        end

        local _, after = fuel.check(ctx, {})
        describeFuel(io, after)
        return true
    end)

    suite:step("Trigger SERVICE routine", function()
        local _, status = fuel.check(ctx, {})
        local level = status.level or 0
        local target = level + math.max(40, ctx.fuelState and ctx.fuelState.threshold or 80)
        if io.print then
            io.print(string.format("Requesting service to reach target fuel %d.", target))
        end
        local ok, serviceReport = fuel.service(ctx, { target = target, rounds = 4 })
        describeService(io, serviceReport)
        if not ok then
            return false, serviceReport and (serviceReport.returnError or "service_failed") or "service_failed"
        end
        local _, after = fuel.check(ctx, {})
        describeFuel(io, after)
        if io.print then
            io.print("Post-service pose: " .. ensureOriginPose(ctx))
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
