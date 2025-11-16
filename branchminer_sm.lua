--[[
Branch mining routine refactored into a state machine.
Maintains feature parity with the legacy branchminer.lua implementation.
]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local placement = require("lib_placement")
local loggerLib = require("lib_logger")
local fuelLib = require("lib_fuel")

if not turtle then
    error("branchminer must run on a turtle")
end

local HELP = [[
branchminer - carved tunnel + branches

Usage:
  branchminer [options]

Options:
    --length <n>          Number of spine segments to dig (default 60)
    --branch-interval <n> Dig a branch every n spine segments (default 3)
    --branch-length <n>   Branch length in blocks (default 2)
	--torch-interval <n>  Place torches every n segments (default 6)
	--torch-item <id>     Item id for torches (default minecraft:torch)
	--fuel-item <id>      Allowed fuel item (repeatable; defaults include coal/charcoal)
	--no-torches          Disable torch placement
	--min-fuel <n>        Minimum fuel level before refueling (default 180)
	--facing <dir>        Initial/home facing (north|south|east|west)
	--verbose             Enable debug logging
	--help                Show this message
]]

local DEFAULT_OPTIONS = {
    length = 60,
    branchInterval = 3,
    branchLength = 16,
    torchInterval = 6,
    torchItem = "minecraft:torch",
    minFuel = 180,
    facing = "north",
    verbose = false,
    fuelItems = nil,
}

local MOVE_OPTS = { dig = true, attack = true }

local DEFAULT_TRASH = {
    ["minecraft:air"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:cobblestone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:calcite"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:end_stone"] = true,
    ["minecraft:basalt"] = true,
    ["minecraft:blackstone"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:coarse_dirt"] = true,
    ["minecraft:rooted_dirt"] = true,
    ["minecraft:mycelium"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:red_sand"] = true,
    ["minecraft:sandstone"] = true,
    ["minecraft:red_sandstone"] = true,
    ["minecraft:clay"] = true,
    ["minecraft:dripstone_block"] = true,
    ["minecraft:pointed_dripstone"] = true,
    ["minecraft:bedrock"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:water"] = true,
    ["minecraft:torch"] = true,
}

local TRASH_PLACEMENT_EXCLUDE = {
    ["minecraft:air"] = true,
    ["minecraft:bedrock"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:torch"] = true,
    ["minecraft:water"] = true,
}

local DEFAULT_FUEL_ITEMS = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
    "minecraft:lava_bucket",
    "minecraft:blaze_rod",
    "minecraft:dried_kelp_block",
}

local TURN_LEFT_OF = {
    north = "west",
    west = "south",
    south = "east",
    east = "north",
}

local TURN_RIGHT_OF = {
    north = "east",
    east = "south",
    south = "west",
    west = "north",
}

local TURN_BACK_OF = {
    north = "south",
    south = "north",
    east = "west",
    west = "east",
}

local ORE_TAG_HINTS = {
    "/ores",
    ":ores",
    "_ores",
    "is_ore",
}

local ORE_NAME_HINTS = {
    "_ore",
    "ancient_debris",
}

local MAX_VALUABLE_DIG_RETRIES = 3

local STATE = {
    INITIALIZE = "INITIALIZE",
    CHECK_FUEL = "CHECK_FUEL",
    CHECK_CAPACITY = "CHECK_CAPACITY",
    ADVANCE = "ADVANCE",
    BRANCH = "BRANCH",
    SCAN_VALUABLES = "SCAN_VALUABLES",
    UNLOAD = "UNLOAD",
    RETURN_HOME = "RETURN_HOME",
    DONE = "DONE",
    ERROR = "ERROR",
}

local function copyVector(vec)
    if type(vec) ~= "table" then
        return nil
    end
    return { x = vec.x or 0, y = vec.y or 0, z = vec.z or 0 }
end

local function positionsEqual(a, b)
    a = a or {}
    b = b or {}
    return (a.x or 0) == (b.x or 0)
        and (a.y or 0) == (b.y or 0)
        and (a.z or 0) == (b.z or 0)
end

local function copyOptions(base, overrides)
    local result = {}
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(overrides or {}) do
        result[k] = v
    end
    return result
end

local function expandFuelItems(custom)
    if type(custom) ~= "table" or #custom == 0 then
        return nil
    end
    local list = {}
    local seen = {}
    local function append(name)
        if type(name) ~= "string" or name == "" then
            return
        end
        if seen[name] then
            return
        end
        seen[name] = true
        list[#list + 1] = name
    end
    for _, name in ipairs(DEFAULT_FUEL_ITEMS) do
        append(name)
    end
    for _, name in ipairs(custom) do
        append(name)
    end
    return list
end

local function normaliseFacing(value)
    if type(value) ~= "string" then
        return DEFAULT_OPTIONS.facing
    end
    local name = value:lower()
    if name == "north" or name == "south" or name == "east" or name == "west" then
        return name
    end
    return DEFAULT_OPTIONS.facing
end

local function parseArgs(argv)
    local opts = {}
    local i = 1
    while i <= #argv do
        local arg = argv[i]
        if arg == "--length" then
            local value = tonumber(argv[i + 1])
            if value and value > 0 then
                opts.length = math.floor(value)
            end
            i = i + 2
        elseif arg == "--branch-interval" then
            local value = tonumber(argv[i + 1])
            if value and value > 0 then
                opts.branchInterval = math.floor(value)
            end
            i = i + 2
        elseif arg == "--branch-length" then
            local value = tonumber(argv[i + 1])
            if value and value > 0 then
                opts.branchLength = math.floor(value)
            end
            i = i + 2
        elseif arg == "--torch-interval" then
            local value = tonumber(argv[i + 1])
            if value and value >= 0 then
                opts.torchInterval = math.floor(value)
            end
            i = i + 2
        elseif arg == "--torch-item" then
            local value = argv[i + 1]
            if value then
                opts.torchItem = value
            end
            i = i + 2
        elseif arg == "--fuel-item" then
            local value = argv[i + 1]
            if value then
                opts.fuelItems = opts.fuelItems or {}
                opts.fuelItems[#opts.fuelItems + 1] = value
            end
            i = i + 2
        elseif arg == "--no-torches" then
            opts.torchInterval = 0
            i = i + 1
        elseif arg == "--min-fuel" then
            local value = tonumber(argv[i + 1])
            if value and value > 0 then
                opts.minFuel = math.floor(value)
            end
            i = i + 2
        elseif arg == "--facing" then
            local value = argv[i + 1]
            if value then
                opts.facing = normaliseFacing(value)
            end
            i = i + 2
        elseif arg == "--verbose" then
            opts.verbose = true
            i = i + 1
        elseif arg == "--help" or arg == "-h" then
            opts.help = true
            break
        else
            local value = tonumber(arg)
            if value and value > 0 then
                opts.length = math.floor(value)
            end
            i = i + 1
        end
    end
    return opts
end

local function buildTrashSet(extra)
    local set = {}
    for name, flag in pairs(DEFAULT_TRASH) do
        set[name] = flag and true or false
    end
    if type(extra) == "table" then
        for name, flag in pairs(extra) do
            if type(name) == "string" then
                set[name] = flag and true or false
            end
        end
    end

    local list = {}
    for name, flag in pairs(set) do
        if flag and not TRASH_PLACEMENT_EXCLUDE[name] then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return set, list
end

local function capturePersistableState(ctx)
    local snapshot = {}
    for k, v in pairs(ctx) do
        if k ~= "runtime" and k ~= "logger" then
            snapshot[k] = v
        end
    end
    return snapshot
end

local function hydrateRuntime(ctx)
    if type(ctx) ~= "table" then
        error("hydrateRuntime requires ctx table")
    end
    ctx.runtime = ctx.runtime or {}
    if not ctx.runtime.logger then
        if not ctx.options then
            error("ctx missing options for logger initialization")
        end
        ctx.runtime.logger = loggerLib.new({
            level = ctx.options.verbose and "debug" or "info",
            tag = "BranchMiner",
        })
    end

    ctx.logger = ctx.runtime.logger

    ctx.runtime.snapshot = function()
        return capturePersistableState(ctx)
    end

    movement.ensureState(ctx)
    inventory.ensureState(ctx)
    placement.ensureState(ctx)
    fuelLib.ensureState(ctx)
end

local function initContext(opts)
    local config = copyOptions(DEFAULT_OPTIONS, opts)
    config.facing = normaliseFacing(config.facing)
    config.fuelItems = expandFuelItems(config.fuelItems)

    local trashSet, trashList = buildTrashSet()

    local ctx = {
        origin = { x = 0, y = 0, z = 0 },
        pointer = { x = 0, y = 0, z = 0 },
        config = {
            verbose = config.verbose,
            initialFacing = config.facing,
            homeFacing = config.facing,
            digOnMove = true,
            attackOnMove = true,
            maxMoveRetries = 12,
            moveRetryDelay = 0.4,
            fuelItems = config.fuelItems,
        },
        options = config,
        trash = trashSet,
        trashList = trashList,
        torchEnabled = config.torchInterval and config.torchInterval > 0,
        torchItem = config.torchItem,
        stepCount = 0,
        chestAvailable = false,
        homeFacing = config.facing,
        detectedValuables = {},
        fuelItems = config.fuelItems,
        state = STATE.INITIALIZE,
        pendingBranch = false,
        lastError = nil,
        initialized = false,
        returnedHome = false,
        errorHandled = false,
    }

    hydrateRuntime(ctx)

    return ctx
end

local function getLogger(ctx)
    if not ctx or type(ctx.runtime) ~= "table" then
        return nil
    end
    return ctx.runtime.logger
end

local function isTrash(ctx, name)
    if name == nil then
        return false
    end
    return ctx.trash[name] == true
end

local function selectTrashForPlacement(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end
    if type(ctx.trashList) ~= "table" then
        return false, "no_trash_configured"
    end
    for _, name in ipairs(ctx.trashList) do
        local ok = inventory.selectMaterial(ctx, name)
        if ok then
            local count = turtle.getItemCount and turtle.getItemCount() or 0
            if count > 0 then
                return true
            end
        end
    end
    return false, "no_trash_available"
end

local function placeTrash(ctx, direction)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local selectOk, selectErr = selectTrashForPlacement(ctx)
    if not selectOk then
        return false, selectErr
    end

    local placeFn
    if direction == "up" then
        placeFn = turtle.placeUp
    elseif direction == "down" then
        placeFn = turtle.placeDown
    else
        placeFn = turtle.place
    end

    if type(placeFn) ~= "function" then
        return false, "place_unavailable"
    end

    local ok, err = placeFn()
    if not ok then
        if err == "No block to place against" then
            return false, "no_support"
        end
        if err == "Nothing to place" or err == "No items to place" then
            return false, "no_trash_available"
        end
        return false, err or "place_failed"
    end

    inventory.invalidate(ctx)
    return true
end

local logValuableDetail

local function getDirectionFns(direction)
    if direction == "forward" then
        return turtle.inspect, turtle.dig
    elseif direction == "up" then
        return turtle.inspectUp, turtle.digUp
    elseif direction == "down" then
        return turtle.inspectDown, turtle.digDown
    end
    return nil, nil
end

local function inspectAndMine(ctx, direction, opts)
    opts = opts or {}
    local force = opts.force
    local inspectFn, digFn = getDirectionFns(direction)
    if not digFn then
        return true
    end

    local hasBlock = false
    local detail
    if inspectFn then
        local ok, data = inspectFn()
        if ok and type(data) == "table" then
            hasBlock = true
            detail = data
            logValuableDetail(ctx, detail, direction)
        end
    end

    local name = detail and (detail.name or detail.id) or nil
    local shouldMine = force
    if not shouldMine and hasBlock then
        shouldMine = not isTrash(ctx, name)
    end

    if shouldMine then
        local ok = digFn()
        if ok then
            inventory.invalidate(ctx)
            if name then
                local logger = getLogger(ctx)
                if logger then
                    logger:debug(string.format("Mined %s (%s)", name, direction))
                end
            end
        elseif hasBlock then
            return false, string.format("dig_failed_%s", direction)
        end
    end
    return true
end

local function isValuableDetail(ctx, detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = detail.name or detail.id
    if type(name) ~= "string" or name == "" then
        return false
    end
    if isTrash(ctx, name) then
        return false
    end
    if name == ctx.torchItem then
        return false
    end
    for _, hint in ipairs(ORE_NAME_HINTS) do
        if name:find(hint, 1, true) then
            return true
        end
    end
    if type(detail.tags) == "table" then
        for tag, present in pairs(detail.tags) do
            if present and type(tag) == "string" then
                for _, fragment in ipairs(ORE_TAG_HINTS) do
                    if tag:find(fragment, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

logValuableDetail = function(ctx, detail, direction)
    local logger = getLogger(ctx)
    if not logger then
        return
    end
    if not isValuableDetail(ctx, detail) then
        return
    end
    local name = detail.name or detail.id or "unknown"
    logger:info(string.format("Detected ore %s at %s", name, direction or "unknown"))
end

local function safeInspectCall(inspectFn)
    if type(inspectFn) ~= "function" then
        return false
    end
    local ok, success, detail = pcall(inspectFn)
    if not ok or not success or type(detail) ~= "table" then
        return false
    end
    return true, detail
end

local function digValuableWithRetry(ctx, inspectFn, digFn, direction)
    if type(digFn) ~= "function" then
        return false, string.format("dig_unavailable_%s", direction or "unknown")
    end

    local attempts = 0
    while true do
        attempts = attempts + 1
        local digOk, digErr = digFn()
        if not digOk then
            return false, digErr or string.format("dig_failed_%s", direction or "unknown")
        end

        inventory.invalidate(ctx)

        local hasBlock, detail = safeInspectCall(inspectFn)
        if not hasBlock or not isValuableDetail(ctx, detail) then
            return true
        end

        if attempts >= MAX_VALUABLE_DIG_RETRIES then
            local logger = getLogger(ctx)
            if logger then
                logger:warn(string.format(
                    "Valuable persisted after %d dig attempts (%s)",
                    attempts,
                    direction or "unknown"
                ))
            end
            return false, string.format("valuable_persist_%s", direction or "unknown")
        end

        if type(sleep) == "function" then
            sleep(0)
        end
    end
end

local function warnBackfill(ctx, label, err)
    local logger = getLogger(ctx)
    if not logger then
        return
    end
    logger:warn(string.format("Backfill failed at %s: %s", label or "unknown", tostring(err or "unknown")))
end

local function harvestForward(ctx, label)
    if not turtle or type(turtle.inspect) ~= "function" or type(turtle.dig) ~= "function" then
        return true
    end
    local inspected, detail = safeInspectCall(turtle.inspect)
    if not inspected then
        return true
    end
    if not isValuableDetail(ctx, detail) then
        return true
    end
    logValuableDetail(ctx, detail, label or "forward")
    local digOk, digErr = digValuableWithRetry(ctx, turtle.inspect, turtle.dig, label or "forward")
    if not digOk then
        return false, digErr
    end
    local placeOk, placeErr = placeTrash(ctx, "forward")
    if not placeOk then
        warnBackfill(ctx, label or "forward", placeErr)
    end
    return true
end

local function harvestVertical(ctx, direction)
    if not turtle then
        return true
    end
    local inspectFn
    local digFn
    local placeDir = direction
    if direction == "up" then
        inspectFn = turtle.inspectUp
        digFn = turtle.digUp
    elseif direction == "down" then
        inspectFn = turtle.inspectDown
        digFn = turtle.digDown
    else
        return false, "invalid_direction"
    end
    if type(inspectFn) ~= "function" or type(digFn) ~= "function" then
        return true
    end
    local inspected, detail = safeInspectCall(inspectFn)
    if not inspected then
        return true
    end
    if not isValuableDetail(ctx, detail) then
        return true
    end
    logValuableDetail(ctx, detail, direction)
    local digOk, digErr = digValuableWithRetry(ctx, inspectFn, digFn, direction)
    if not digOk then
        return false, digErr
    end
    local placeOk, placeErr = placeTrash(ctx, placeDir)
    if not placeOk then
        warnBackfill(ctx, direction, placeErr)
    end
    return true
end

local function scanForValuables(ctx, opts)
    if not turtle then
        return true
    end

    opts = opts or {}
    local skipDown = opts.skipDown
    local skipUp = opts.skipUp

    local startFacing = movement.getFacing(ctx)

    local function restoreFacing()
        if not startFacing then
            return true
        end
        local ok, err = movement.faceDirection(ctx, startFacing)
        if not ok then
            return false, err
        end
        return true
    end

    if not skipUp then
        local ok, err = harvestVertical(ctx, "up")
        if not ok then
            return false, err
        end
    end

    if not skipDown then
        local ok, err = harvestVertical(ctx, "down")
        if not ok then
            return false, err
        end
    end

    local ok, err = harvestForward(ctx, "forward")
    if not ok then
        return false, err
    end

    local function harvestWithTurn(turnFn, undoFn, label)
        local aligned, alignErr = restoreFacing()
        if not aligned then
            return false, alignErr
        end
        local turnOk, turnErr = turnFn(ctx)
        if not turnOk then
            return false, turnErr
        end
        local harvestOk, harvestErr = harvestForward(ctx, label)
        local undoOk, undoErr = undoFn(ctx)
        if not undoOk then
            return false, undoErr
        end
        local faceOk, faceErr = restoreFacing()
        if not faceOk then
            return false, faceErr
        end
        if not harvestOk then
            return false, harvestErr
        end
        return true
    end

    ok, err = harvestWithTurn(movement.turnLeft, movement.turnRight, "left")
    if not ok then
        return false, err
    end

    ok, err = harvestWithTurn(movement.turnRight, movement.turnLeft, "right")
    if not ok then
        return false, err
    end

    ok, err = harvestWithTurn(movement.turnAround, movement.turnAround, "back")
    if not ok then
        return false, err
    end

    local restoreOk, restoreErr = restoreFacing()
    if not restoreOk then
        return false, restoreErr
    end

    return true
end

local function harvestNearbyValuables(ctx)
    local baseOk, baseErr = scanForValuables(ctx)
    if not baseOk then
        return false, baseErr
    end

    local upOk, upErr = movement.up(ctx, MOVE_OPTS)
    if upOk then
        local scanOk, scanErr = scanForValuables(ctx, { skipDown = true })
        local downOk, downErr = movement.down(ctx, MOVE_OPTS)
        if not downOk then
            return false, downErr
        end
        if not scanOk then
            return false, scanErr
        end
    else
        local logger = getLogger(ctx)
        if upErr and logger then
            logger:debug("Upper scan skipped: " .. tostring(upErr))
        end
    end

    return true
end

local function ensureFuel(ctx)
    local ok, report = fuelLib.check(ctx, { threshold = ctx.options.minFuel })
    if ok or (report and report.unlimited) then
        return true
    end

    local beforePos = movement.getPosition(ctx)
    local beforeFacing = movement.getFacing(ctx)
    local logger = getLogger(ctx)
    if logger then
        logger:info("Fuel below threshold; attempting refuel")
    end
    local refueled, info = fuelLib.ensure(ctx, {
        threshold = ctx.options.minFuel,
        fuelItems = ctx.options.fuelItems,
    })
    if not refueled then
        if logger then
            logger:error("Refuel failed; stopping")
        end
        if info and info.service and textutils and textutils.serialize and logger then
            logger:error("Service report: " .. textutils.serialize(info.service))
        end
        return false, "refuel_failed"
    end

    local afterPos = movement.getPosition(ctx)
    local afterFacing = movement.getFacing(ctx)
    if not positionsEqual(beforePos, afterPos) or (beforeFacing and afterFacing and beforeFacing ~= afterFacing) then
        if logger then
            logger:debug("Returning to work site after refuel")
        end
        local returnOk, returnErr = movement.goTo(ctx, beforePos, MOVE_OPTS)
        if not returnOk then
            if logger then
                logger:error("Failed to return after refuel: " .. tostring(returnErr))
            end
            return false, "post_refuel_return_failed"
        end
        if beforeFacing then
            local faceOk, faceErr = movement.faceDirection(ctx, beforeFacing)
            if not faceOk then
                if logger then
                    logger:error("Unable to restore facing after refuel: " .. tostring(faceErr))
                end
                return false, "post_refuel_face_failed"
            end
        end
    end

    return true
end

local function detectChest(ctx)
    local info = inventory.detectContainer(ctx, { side = "forward" })
    local logger = getLogger(ctx)
    if info then
        if logger then
            logger:info(string.format("Detected drop-off container (%s)", info.side or "forward"))
        end
        ctx.chestAvailable = true
    else
        if logger then
            logger:warn("No adjacent chest detected; auto-unload disabled")
        end
        ctx.chestAvailable = false
    end
    movement.faceDirection(ctx, ctx.homeFacing)
end

local function depositInventory(ctx)
    if not ctx.chestAvailable then
        return true
    end
    inventory.scan(ctx, { force = true })
    for slot = 1, 16 do
        local count = turtle.getItemCount(slot)
        if count and count > 0 then
            local ok, err = inventory.pushSlot(ctx, slot, nil, { side = "forward" })
            if not ok and err ~= "empty_slot" then
                local logger = getLogger(ctx)
                if logger then
                    logger:warn(string.format("Failed to drop slot %d: %s", slot, tostring(err)))
                end
            end
        end
    end
    return true
end

local function returnToDropoff(ctx, stayAtOrigin)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)

    local ok, err = movement.returnToOrigin(ctx, { facing = ctx.homeFacing })
    if not ok then
        return false, err
    end

    depositInventory(ctx)

    if stayAtOrigin then
        return true
    end

    ok, err = movement.goTo(ctx, pos, MOVE_OPTS)
    if not ok then
        return false, err
    end
    if facing then
        movement.faceDirection(ctx, facing)
    end
    return true
end

local function inventoryHasSpace(ctx)
    return inventory.findEmptySlot(ctx) ~= nil
end

local function ensureBranchCapacity(ctx)
    if inventoryHasSpace(ctx) then
        return true
    end
    if not ctx.chestAvailable then
        local logger = getLogger(ctx)
        if logger then
            logger:error("Inventory full and no chest available; stopping")
        end
        return false, "inventory_full"
    end
    local logger = getLogger(ctx)
    if logger then
        logger:info("Inventory full; returning to drop-off")
    end
    local ok, err = returnToDropoff(ctx, false)
    if not ok then
        return false, err
    end
    inventory.invalidate(ctx)
    return true
end

local function advanceForward(ctx)
    local ok, err = inspectAndMine(ctx, "forward", { force = true })
    if not ok then
        return false, err
    end
    ok, err = movement.forward(ctx, MOVE_OPTS)
    if not ok then
        return false, err
    end
    local headOk, headErr = inspectAndMine(ctx, "up", { force = true })
    if not headOk then
        return false, headErr
    end
    return true
end

local function clearLeftLane(ctx)
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        return false, err
    end

    local containerInfo = inventory.detectContainer(ctx, { side = "forward", searchAllSides = false })
    if containerInfo then
        local logger = getLogger(ctx)
        if logger then
            logger:info("Left lane blocked by container; skipping lane clear")
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        return true
    end

    local digOk, digErr = inspectAndMine(ctx, "forward", { force = true })
    if not digOk then
        movement.turnRight(ctx)
        return false, digErr
    end

    local moved = false
    ok, err = movement.forward(ctx, MOVE_OPTS)
    if ok then
        moved = true
        inspectAndMine(ctx, "up", { force = true })
        inspectAndMine(ctx, "forward", { force = false })
    else
        local logger = getLogger(ctx)
        if logger then
            logger:warn("Unable to open left lane: " .. tostring(err))
        end
    end

    if moved then
        ok, err = movement.turnAround(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.forward(ctx, MOVE_OPTS)
        if not ok then
            return false, err
        end
        ok, err = movement.turnAround(ctx)
        if not ok then
            return false, err
        end
    end

    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    return true
end

local function scanRightWall(ctx)
    local ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    inspectAndMine(ctx, "forward", { force = false })
    ok, err = movement.turnLeft(ctx)
    if not ok then
        return false, err
    end
    return true
end

local function shouldPlaceTorch(ctx)
    if not ctx.torchEnabled then
        return false
    end
    local interval = ctx.options.torchInterval
    if not interval or interval <= 0 then
        return false
    end
    return (ctx.stepCount % interval) == 0
end

local function placeTorchOnWall(ctx, side)
    local turnFn, restoreFn
    if side == "right" then
        turnFn = movement.turnRight
        restoreFn = movement.turnLeft
    elseif side == "left" then
        turnFn = movement.turnLeft
        restoreFn = movement.turnRight
    else
        return nil, "invalid_side"
    end

    local ok, err = turnFn(ctx)
    if not ok then
        return nil, err
    end

    local hasWall = false
    local inspectDetail
    if turtle then
        local inspectFn = turtle.inspect
        if inspectFn then
            local okInspect, success, detail = pcall(inspectFn)
            if okInspect and success then
                hasWall = true
                inspectDetail = detail
            end
        end
        if not hasWall then
            local detectFn = turtle.detect
            if detectFn then
                local okDetect, result = pcall(detectFn)
                if okDetect and result then
                    hasWall = true
                end
            end
        end
    end

    if inspectDetail and type(inspectDetail) == "table" then
        local name = inspectDetail.name or inspectDetail.id
        if name == ctx.torchItem then
            local restoreOk, restoreErr = restoreFn(ctx)
            if not restoreOk then
                return nil, restoreErr
            end
            return true, "already_present"
        end
    end

    local placed = false
    local perr
    if hasWall then
        local selectOk, selectErr = inventory.selectMaterial(ctx, ctx.torchItem)
        if not selectOk then
            perr = selectErr or "missing_material"
        else
            if turtle and turtle.getItemCount and turtle.getItemCount() <= 0 then
                perr = "missing_material"
            else
                local placeFn = turtle and turtle.place or nil
                if placeFn then
                    local placeOk, placeErr = placeFn()
                    if placeOk then
                        placed = true
                        perr = nil
                        if inventory.invalidate then
                            inventory.invalidate(ctx)
                        end
                    else
                        perr = placeErr or "place_failed"
                        if placeErr == "No block to place against" then
                            perr = "no_wall"
                        elseif placeErr == "No items to place" or placeErr == "Nothing to place" then
                            perr = "missing_material"
                        end
                    end
                else
                    perr = "turtle API unavailable"
                end
            end
        end
    else
        perr = "no_wall"
    end

    local restoreOk, restoreErr = restoreFn(ctx)
    if not restoreOk then
        return nil, restoreErr
    end

    return placed, perr
end

local function maybePlaceTorch(ctx)
    if not shouldPlaceTorch(ctx) then
        return true
    end
    local movedUp = false
    local placed, perr

    local upOk, upErr = movement.up(ctx, MOVE_OPTS)
    if upOk then
        movedUp = true
        placed, perr = placeTorchOnWall(ctx, "right")
    else
        local logger = getLogger(ctx)
        if upErr and logger then
            logger:debug("Torch placement: unable to elevate for wall mount: " .. tostring(upErr))
        end
    end

    if movedUp then
        local downOk, downErr = movement.down(ctx, MOVE_OPTS)
        if not downOk then
            return false, downErr
        end
        if placed == nil then
            return false, perr
        end
        if not placed and perr == "no_wall" then
            local retryPlaced, retryErr = placeTorchOnWall(ctx, "right")
            if retryPlaced == nil then
                return false, retryErr
            end
            placed, perr = retryPlaced, retryErr
        end
    else
        placed, perr = placeTorchOnWall(ctx, "right")
        if placed == nil then
            return false, perr
        end
    end

    if placed then
        return true
    end

    local logger = getLogger(ctx)
    if perr == "missing_material" then
        if logger then
            logger:warn("Out of torches; disabling torch placement")
        end
        ctx.torchEnabled = false
    elseif perr == "no_wall" then
        if logger then
            logger:debug("Torch placement skipped: missing wall surface")
        end
    elseif perr ~= "occupied" then
        if logger then
            logger:debug("Torch placement skipped: " .. tostring(perr))
        end
    end

    return true
end

local function scanBranchWalls(ctx)
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        return false, err
    end
    inspectAndMine(ctx, "forward", { force = false })

    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    inspectAndMine(ctx, "forward", { force = false })

    ok, err = movement.turnLeft(ctx)
    if not ok then
        return false, err
    end
    return true
end

local function digBranch(ctx)
    local ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end

    for _ = 1, ctx.options.branchLength do
        local digOk, digErr = inspectAndMine(ctx, "forward", { force = true })
        if not digOk then
            return false, digErr
        end
        ok, err = movement.forward(ctx, MOVE_OPTS)
        if not ok then
            return false, err
        end
        inspectAndMine(ctx, "up", { force = true })
        local wallOk, wallErr = scanBranchWalls(ctx)
        if not wallOk then
            return false, wallErr
        end

        local upOk, upErr = movement.up(ctx, MOVE_OPTS)
        if upOk then
            local scanOk, scanErr = scanBranchWalls(ctx)
            local downOk, downErr = movement.down(ctx, MOVE_OPTS)
            if not downOk then
                return false, downErr
            end
            if not scanOk then
                return false, scanErr
            end
        else
            local logger = getLogger(ctx)
            if upErr and logger then
                logger:debug("Upper branch scan skipped: " .. tostring(upErr))
            end
        end
    end

    inspectAndMine(ctx, "forward", { force = false })

    ok, err = movement.turnAround(ctx)
    if not ok then
        return false, err
    end
    for _ = 1, ctx.options.branchLength do
        ok, err = movement.forward(ctx, MOVE_OPTS)
        if not ok then
            return false, err
        end
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    return true
end

local function shouldBranch(ctx)
    local interval = ctx.options.branchInterval
    if not interval or interval <= 0 then
        return false
    end
    return (ctx.stepCount % interval) == 0
end

local function prepareStart(ctx)
    local ok, err = inspectAndMine(ctx, "up", { force = true })
    if not ok then
        return false, err
    end
    ok, err = clearLeftLane(ctx)
    if not ok then
        return false, err
    end
    local scanOk, scanErr = harvestNearbyValuables(ctx)
    if not scanOk then
        return false, scanErr
    end
    return true
end

local function wrapUp(ctx)
    if ctx.returnedHome then
        return true
    end

    if ctx.chestAvailable then
        local ok, err = returnToDropoff(ctx, true)
        if not ok then
            return false, err
        end
    else
        local ok, err = movement.returnToOrigin(ctx, { facing = ctx.homeFacing })
        if not ok then
            return false, err
        end
    end

    local logger = getLogger(ctx)
    if logger then
        logger:info(string.format("Branch miner complete after %d segments", ctx.stepCount))
    end

    ctx.returnedHome = true
    return true
end

-- State handlers -----------------------------------------------------------

local function STATE_INITIALIZE(ctx)
    if not ctx.initialized then
        local ok, err = ensureFuel(ctx)
        if not ok then
            ctx.lastError = err or "ensure_fuel_failed"
            return STATE.ERROR
        end
        detectChest(ctx)
        local prepOk, prepErr = prepareStart(ctx)
        if not prepOk then
            local logger = getLogger(ctx)
            if logger then
                logger:error("Startup preparation failed: " .. tostring(prepErr))
            end
            ctx.lastError = prepErr or "prepare_failed"
            return STATE.ERROR
        end
        ctx.initialized = true
    end
    return STATE.CHECK_FUEL
end

local function STATE_CHECK_FUEL(ctx)
    local target = ctx.options.length
    if target and ctx.stepCount >= target then
        return STATE.RETURN_HOME
    end
    local ok, err = ensureFuel(ctx)
    if not ok then
        local logger = getLogger(ctx)
        if logger then
            logger:error("Fuel check failed: " .. tostring(err))
        end
        ctx.lastError = err or "fuel_check_failed"
        return STATE.ERROR
    end
    return STATE.CHECK_CAPACITY
end

local function STATE_CHECK_CAPACITY(ctx)
    if inventoryHasSpace(ctx) then
        return STATE.ADVANCE
    end
    if not ctx.chestAvailable then
        local logger = getLogger(ctx)
        if logger then
            logger:error("Inventory full and no chest available; stopping")
        end
        ctx.lastError = "inventory_full"
        return STATE.ERROR
    end
    return STATE.UNLOAD
end

local function STATE_UNLOAD(ctx)
    local ok, err = returnToDropoff(ctx, false)
    if not ok then
        ctx.lastError = err or "unload_failed"
        return STATE.ERROR
    end
    inventory.invalidate(ctx)
    return STATE.CHECK_FUEL
end

local function STATE_ADVANCE(ctx)
    local ok, err = advanceForward(ctx)
    if not ok then
        local logger = getLogger(ctx)
        if logger then
            logger:error("Advance failed: " .. tostring(err))
        end
        ctx.lastError = err or "advance_failed"
        return STATE.ERROR
    end

    ctx.stepCount = ctx.stepCount + 1

    ok, err = clearLeftLane(ctx)
    if not ok then
        ctx.lastError = err or "clear_left_failed"
        return STATE.ERROR
    end

    ok, err = scanRightWall(ctx)
    if not ok then
        ctx.lastError = err or "scan_right_failed"
        return STATE.ERROR
    end

    ok, err = maybePlaceTorch(ctx)
    if not ok then
        ctx.lastError = err or "torch_failed"
        return STATE.ERROR
    end

    if shouldBranch(ctx) then
        ctx.pendingBranch = true
        return STATE.BRANCH
    end

    return STATE.SCAN_VALUABLES
end

local function STATE_BRANCH(ctx)
    if not ctx.pendingBranch then
        return STATE.SCAN_VALUABLES
    end
    ctx.pendingBranch = false

    local ok, err = ensureBranchCapacity(ctx)
    if not ok then
        ctx.lastError = err or "branch_capacity_failed"
        return STATE.ERROR
    end

    ok, err = digBranch(ctx)
    if not ok then
        ctx.lastError = err or "branch_dig_failed"
        return STATE.ERROR
    end

    return STATE.SCAN_VALUABLES
end

local function STATE_SCAN_VALUABLES(ctx)
    local ok, err = harvestNearbyValuables(ctx)
    if not ok then
        ctx.lastError = err or "valuable_scan_failed"
        return STATE.ERROR
    end
    return STATE.CHECK_FUEL
end

local function STATE_RETURN_HOME(ctx)
    local ok, err = wrapUp(ctx)
    if not ok then
        ctx.lastError = err or "wrap_up_failed"
        return STATE.ERROR
    end
    return STATE.DONE
end

local function STATE_ERROR(ctx)
    if not ctx.errorHandled then
        local logger = getLogger(ctx)
        if logger then
            logger:error("Branch miner halted: " .. tostring(ctx.lastError or "unknown_error"))
        end
        wrapUp(ctx)
        ctx.errorHandled = true
    end
    return STATE.DONE
end

local function STATE_DONE(ctx)
    return STATE.DONE
end

local STATES = {
    [STATE.INITIALIZE] = STATE_INITIALIZE,
    [STATE.CHECK_FUEL] = STATE_CHECK_FUEL,
    [STATE.CHECK_CAPACITY] = STATE_CHECK_CAPACITY,
    [STATE.UNLOAD] = STATE_UNLOAD,
    [STATE.ADVANCE] = STATE_ADVANCE,
    [STATE.BRANCH] = STATE_BRANCH,
    [STATE.SCAN_VALUABLES] = STATE_SCAN_VALUABLES,
    [STATE.RETURN_HOME] = STATE_RETURN_HOME,
    [STATE.ERROR] = STATE_ERROR,
    [STATE.DONE] = STATE_DONE,
}

local function run(ctx)
    hydrateRuntime(ctx)
    while ctx.state ~= STATE.DONE do
        local handler = STATES[ctx.state]
        if not handler then
            ctx.lastError = "unknown_state"
            ctx.state = STATE.ERROR
            handler = STATES[ctx.state]
        end
        ctx.state = handler(ctx) or STATE.DONE
    end
    local doneHandler = STATES[STATE.DONE]
    if doneHandler then
        doneHandler(ctx)
    end
end

local function main(...)
    local rawArgs = { ... }
    local parsed = parseArgs(rawArgs)
    if parsed.help then
        print(HELP)
        return
    end
    local ctx = initContext(parsed)
    run(ctx)
end

main(...)
