--[[
Fuel management helpers for CC:Tweaked turtles.
Tracks thresholds, detects low fuel conditions, and provides a simple
SERVICE routine that returns the turtle to origin and attempts to refuel
from configured sources.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local table_utils = require("lib_table")
local logger = require("lib_logger")

local fuel = {}

local DEFAULT_THRESHOLD = 80
local DEFAULT_RESERVE = 160
local DEFAULT_SIDES = { "forward", "down", "up" }
local DEFAULT_FUEL_ITEMS = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
    "minecraft:lava_bucket",
    "minecraft:blaze_rod",
    "minecraft:dried_kelp_block",
}

local function ensureFuelState(ctx)
    if type(ctx) ~= "table" then
        error("fuel library requires a context table", 2)
    end
    ctx.fuelState = ctx.fuelState or {}
    local state = ctx.fuelState
    local cfg = ctx.config or {}

    state.threshold = state.threshold or cfg.fuelThreshold or cfg.minFuel or DEFAULT_THRESHOLD
    state.reserve = state.reserve or cfg.fuelReserve or math.max(DEFAULT_RESERVE, state.threshold * 2)
    state.fuelItems = state.fuelItems or (cfg.fuelItems and #cfg.fuelItems > 0 and table_utils.copyArray(cfg.fuelItems)) or table_utils.copyArray(DEFAULT_FUEL_ITEMS)
    state.sides = state.sides or (cfg.fuelChestSides and #cfg.fuelChestSides > 0 and table_utils.copyArray(cfg.fuelChestSides)) or table_utils.copyArray(DEFAULT_SIDES)
    state.cycleLimit = state.cycleLimit or cfg.fuelCycleLimit or cfg.inventoryCycleLimit or 192
    state.history = state.history or {}
    state.serviceActive = state.serviceActive or false
    state.lastLevel = state.lastLevel or nil
    return state
end

function fuel.ensureState(ctx)
    return ensureFuelState(ctx)
end

local function readFuel()
    if not turtle or not turtle.getFuelLevel then
        return nil, nil, false
    end
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit and turtle.getFuelLimit() or nil
    if level == "unlimited" or limit == "unlimited" then
        return nil, nil, true
    end
    if level == math.huge or limit == math.huge then
        return nil, nil, true
    end
    if type(level) ~= "number" then
        return nil, nil, false
    end
    if type(limit) ~= "number" then
        limit = nil
    end
    return level, limit, false
end

local function resolveTarget(state, opts)
    opts = opts or {}
    local target = opts.target or 0
    if type(target) ~= "number" or target <= 0 then
        target = 0
    end
    local threshold = opts.threshold or state.threshold or 0
    local reserve = opts.reserve or state.reserve or 0
    if threshold > target then
        target = threshold
    end
    if reserve > target then
        target = reserve
    end
    if target <= 0 then
        target = threshold > 0 and threshold or DEFAULT_THRESHOLD
    end
    return target
end

local function resolveSides(state, opts)
    opts = opts or {}
    if type(opts.sides) == "table" and #opts.sides > 0 then
        return table_utils.copyArray(opts.sides)
    end
    return table_utils.copyArray(state.sides)
end

local function resolveFuelItems(state, opts)
    opts = opts or {}
    if type(opts.fuelItems) == "table" and #opts.fuelItems > 0 then
        return table_utils.copyArray(opts.fuelItems)
    end
    return table_utils.copyArray(state.fuelItems)
end

local function recordHistory(state, entry)
    state.history = state.history or {}
    state.history[#state.history + 1] = entry
    local limit = 20
    while #state.history > limit do
        table.remove(state.history, 1)
    end
end

local function consumeFromInventory(ctx, target)
    if not turtle or type(turtle.refuel) ~= "function" then
        return false, { error = "turtle API unavailable" }
    end
    local before = select(1, readFuel())
    if before == nil then
        return false, { error = "fuel unreadable" }
    end
    target = target or 0
    if target <= 0 then
        return false, {
            consumed = {},
            startLevel = before,
            endLevel = before,
            note = "no_target",
        }
    end

    local level = before
    local consumed = {}
    for slot = 1, 16 do
        if target > 0 and level >= target then
            break
        end

        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        local canRefuel = count and count > 0 and turtle.refuel(0)
        if canRefuel then
            while (target <= 0 or level < target) and turtle.getItemCount(slot) > 0 do
                if not turtle.refuel(1) then
                    break
                end
                consumed[slot] = (consumed[slot] or 0) + 1
                level = select(1, readFuel()) or level
                if target > 0 and level >= target then
                    break
                end
            end
        end
    end
    local after = select(1, readFuel()) or level
    if inventory.invalidate then
        inventory.invalidate(ctx)
    end
    return (after > before), {
        consumed = consumed,
        startLevel = before,
        endLevel = after,
    }
end

local function pullFromSources(ctx, state, opts)
    if not turtle then
        return false, { error = "turtle API unavailable" }
    end
    inventory.ensureState(ctx)
    local sides = resolveSides(state, opts)
    local items = resolveFuelItems(state, opts)
    local pulled = {}
    local errors = {}
    local attempts = 0
    local maxAttempts = opts and opts.maxPullAttempts or (#sides * #items)
    if maxAttempts < 1 then
        maxAttempts = #sides * #items
    end
    local cycleLimit = (opts and opts.inventoryCycleLimit) or state.cycleLimit or 192
    for _, side in ipairs(sides) do
        for _, material in ipairs(items) do
            if attempts >= maxAttempts then
                break
            end
            attempts = attempts + 1
            local ok, err = inventory.pullMaterial(ctx, material, nil, {
                side = side,
                deferScan = true,
                cycleLimit = cycleLimit,
            })
            if ok then
                pulled[#pulled + 1] = { side = side, material = material }
                logger.log(ctx, "debug", string.format("Pulled %s from %s", material, side))
            elseif err ~= "missing_material" then
                errors[#errors + 1] = { side = side, material = material, error = err }
                logger.log(ctx, "warn", string.format("Pull %s from %s failed: %s", material, side, tostring(err)))
            end
        end
        if attempts >= maxAttempts then
            break
        end
    end
    if #pulled > 0 then
        inventory.invalidate(ctx)
    end
    return #pulled > 0, { pulled = pulled, errors = errors }
end

local function refuelRound(ctx, target, report)
    local consumed, info = consumeFromInventory(ctx, target)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        round = report.round,
        success = consumed,
        info = info,
    }
    if consumed then
        logger.log(ctx, "debug", string.format("Consumed %d fuel items from inventory", table_utils.sumValues(info and info.consumed)))
    end
    local level = select(1, readFuel())
    if level and level >= target and target > 0 then
        report.finalLevel = level
        report.reachedTarget = true
        return true, report
    end

    local pulled, pullInfo = pullFromSources(ctx, state, opts)
    report.steps[#report.steps + 1] = {
        type = "pull",
        round = report.round,
        success = pulled,
        info = pullInfo,
    }

    if pulled then
        local consumedAfterPull, postInfo = consumeFromInventory(ctx, target)
        report.steps[#report.steps + 1] = {
            type = "inventory",
            stage = "post_pull",
            round = report.round,
            success = consumedAfterPull,
            info = postInfo,
        }
        if consumedAfterPull then
            logger.log(ctx, "debug", string.format("Post-pull consumption used %d fuel items", table_utils.sumValues(postInfo and postInfo.consumed)))
            local postLevel = select(1, readFuel())
            if postLevel and postLevel >= target and target > 0 then
                report.finalLevel = postLevel
                report.reachedTarget = true
                return true, report
            end
        end
    end

    return (pulled or consumed), report
end

local function refuelInternal(ctx, state, opts)
    local startLevel, limit, unlimited = readFuel()
    if unlimited then
        return true, {
            startLevel = startLevel,
            limit = limit,
            finalLevel = startLevel,
            unlimited = true,
        }
    end
    if not startLevel then
        return true, {
            startLevel = nil,
            limit = limit,
            finalLevel = nil,
            message = "fuel level unavailable",
        }
    end

    local target = resolveTarget(state, opts)
    local report = {
        startLevel = startLevel,
        limit = limit,
        target = target,
        steps = {},
    }

    local rounds = opts and opts.rounds or 3
    if rounds < 1 then
        rounds = 1
    end

    for i = 1, rounds do
        report.round = i
        local ok, roundReport = refuelRound(ctx, target, report)
        report = roundReport
        if report.reachedTarget then
            return true, report
        end
        if not ok then
            break
        end
    end

    report.finalLevel = select(1, readFuel()) or startLevel
    if report.finalLevel and report.finalLevel >= target and target > 0 then
        report.reachedTarget = true
        return true, report
    end
    report.reachedTarget = target <= 0
    return report.reachedTarget, report
end

function fuel.check(ctx, opts)
    local state = ensureFuelState(ctx)
    local level, limit, unlimited = readFuel()
    state.lastLevel = level or state.lastLevel

    local report = {
        level = level,
        limit = limit,
        unlimited = unlimited,
        threshold = state.threshold,
        reserve = state.reserve,
        history = state.history,
    }

    if unlimited then
        report.ok = true
        return true, report
    end
    if not level then
        report.ok = true
        report.note = "fuel level unavailable"
        return true, report
    end

    local threshold = opts and opts.threshold or state.threshold or 0
    report.threshold = threshold
    report.reserve = opts and opts.reserve or state.reserve
    report.ok = level >= threshold
    report.needsService = not report.ok
    report.depleted = level <= 0
    return report.ok, report
end

function fuel.refuel(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = refuelInternal(ctx, state, opts)
    recordHistory(state, {
        type = "refuel",
        timestamp = os and os.time and os.time() or nil,
        success = ok,
        report = report,
    })
    if ok then
        logger.log(ctx, "info", string.format("Refuel complete (fuel=%s)", tostring(report.finalLevel or "unknown")))
    else
        logger.log(ctx, "warn", "Refuel attempt did not reach target level")
    end
    return ok, report
end

function fuel.ensure(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = fuel.check(ctx, opts)
    if ok then
        return true, report
    end
    if opts and opts.nonInteractive then
        return false, report
    end
    local serviceOk, serviceReport = fuel.service(ctx, opts)
    if not serviceOk then
        report.service = serviceReport
        return false, report
    end
    return fuel.check(ctx, opts)
end

local function bootstrapFuel(ctx, state, opts, report)
    logger.log(ctx, "warn", "Fuel depleted; attempting to consume onboard fuel before navigating")
    local minimumMove = opts and opts.minimumMoveFuel or math.max(10, state.threshold or 0)
    if minimumMove <= 0 then
        minimumMove = 10
    end
    local consumed, info = consumeFromInventory(ctx, minimumMove)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        stage = "bootstrap",
        success = consumed,
        info = info,
    }
    local level = select(1, readFuel()) or (info and info.endLevel) or report.startLevel
    report.bootstrapLevel = level
    if level <= 0 then
        logger.log(ctx, "error", "Fuel depleted; cannot move to origin")
        report.error = "out_of_fuel"
        report.finalLevel = level
        return false, report
    end
    return true, report
end

local function runService(ctx, state, opts, report)
    state.serviceActive = true
    logger.log(ctx, "info", "Entering SERVICE mode: returning to origin for refuel")

    local ok, err = movement.returnToOrigin(ctx, opts and opts.navigation)
    if not ok then
        state.serviceActive = false
        logger.log(ctx, "error", "SERVICE return failed: " .. tostring(err))
        report.returnError = err
        return false, report
    end
    report.steps[#report.steps + 1] = { type = "return", success = true }

    local refuelOk, refuelReport = refuelInternal(ctx, state, opts)
    report.steps[#report.steps + 1] = {
        type = "refuel",
        success = refuelOk,
        report = refuelReport,
    }

    state.serviceActive = false
    recordHistory(state, {
        type = "service",
        timestamp = os and os.time and os.time() or nil,
        success = refuelOk,
        report = report,
    })

    if not refuelOk then
        logger.log(ctx, "warn", "SERVICE refuel did not reach target level")
        report.finalLevel = select(1, readFuel()) or (refuelReport and refuelReport.finalLevel) or report.startLevel
        return false, report
    end

    local finalLevel = select(1, readFuel()) or refuelReport.finalLevel
    report.finalLevel = finalLevel
    logger.log(ctx, "info", string.format("SERVICE complete (fuel=%s)", tostring(finalLevel or "unknown")))
    return true, report
end

function fuel.service(ctx, opts)
    local state = ensureFuelState(ctx)
    if state.serviceActive then
        return false, { error = "service_already_active" }
    end

    inventory.ensureState(ctx)
    movement.ensureState(ctx)

    local level, limit, unlimited = readFuel()
    local report = {
        startLevel = level,
        limit = limit,
        steps = {},
    }

    if unlimited then
        report.note = "fuel is unlimited"
        return true, report
    end

    if not level then
        logger.log(ctx, "warn", "Fuel level unavailable; skipping service")
        report.error = "fuel_unreadable"
        return false, report
    end

    if level <= 0 then
        local ok, bootstrapReport = bootstrapFuel(ctx, state, opts, report)
        if not ok then
            return false, bootstrapReport
        end
        report = bootstrapReport
    end

    return runService(ctx, state, opts, report)
end

function fuel.resolveFuelThreshold(ctx)
    local threshold = 0
    local function consider(value)
        if type(value) == "number" and value > threshold then
            threshold = value
        end
    end
    if type(ctx.fuelState) == "table" then
        local fuel = ctx.fuelState
        consider(fuel.threshold)
        consider(fuel.reserve)
        consider(fuel.min)
        consider(fuel.minFuel)
        consider(fuel.low)
    end
    if type(ctx.config) == "table" then
        local cfg = ctx.config
        consider(cfg.fuelThreshold)
        consider(cfg.fuelReserve)
        consider(cfg.minFuel)
    end
    return threshold
end

function fuel.isFuelLow(ctx)
    if not turtle or not turtle.getFuelLevel then
        return false
    end
    local level = turtle.getFuelLevel()
    if level == "unlimited" then
        return false
    end
    if type(level) ~= "number" then
        return false
    end
    local threshold = fuel.resolveFuelThreshold(ctx)
    if threshold <= 0 then
        return false
    end
    return level <= threshold
endfunction fuel.describeFuel(io, report)
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

function fuel.describeService(io, report)
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

return fuel
