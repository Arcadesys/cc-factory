--[[
Inventory library for CC:Tweaked turtles.
Tracks slot contents, provides material lookup helpers, and wraps chest
interactions used by higher-level states. All public functions accept a shared
ctx table and follow the project convention of returning success booleans with
optional error messages.
--]]

---@diagnostic disable: undefined-global

local inventory = {}
local movement = require("lib_movement")

local SIDE_ACTIONS = {
    forward = {
        drop = turtle and turtle.drop or nil,
        suck = turtle and turtle.suck or nil,
    },
    up = {
        drop = turtle and turtle.dropUp or nil,
        suck = turtle and turtle.suckUp or nil,
    },
    down = {
        drop = turtle and turtle.dropDown or nil,
        suck = turtle and turtle.suckDown or nil,
    },
}

local PUSH_TARGETS = {
    "front",
    "back",
    "left",
    "right",
    "top",
    "bottom",
    "north",
    "south",
    "east",
    "west",
    "up",
    "down",
}

local OPPOSITE_FACING = {
    north = "south",
    south = "north",
    east = "west",
    west = "east",
}

local function log(ctx, level, message)
    if type(ctx) ~= "table" then
        return
    end
    local logger = ctx.logger
    if type(logger) ~= "table" then
        return
    end
    local fn = logger[level]
    if type(fn) == "function" then
        fn(message)
        return
    end
    if type(logger.log) == "function" then
        logger.log(level, message)
    end
end

local CONTAINER_KEYWORDS = {
    "chest",
    "barrel",
    "drawer",
    "cabinet",
    "crate",
    "locker",
    "storage",
    "box",
    "bin",
    "cache",
    "shelf",
    "cupboard",
    "depot",
    "controller",
    "shulker",
    "shulkerbox",
}

local function noop()
end

local function normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

local function resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

local function tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function copyArray(list)
    if type(list) ~= "table" then
        return {}
    end
    local result = {}
    for index = 1, #list do
        result[index] = list[index]
    end
    return result
end

local function copySummary(summary)
    if type(summary) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(summary) do
        result[key] = value
    end
    return result
end

local function copySlots(slots)
    if type(slots) ~= "table" then
        return {}
    end
    local result = {}
    for slot, info in pairs(slots) do
        if type(info) == "table" then
            result[slot] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = info.detail,
            }
        else
            result[slot] = info
        end
    end
    return result
end

local function hasContainerTag(tags)
    if type(tags) ~= "table" then
        return false
    end
    for key, value in pairs(tags) do
        if value and type(key) == "string" then
            local lower = key:lower()
            for _, keyword in ipairs(CONTAINER_KEYWORDS) do
                if lower:find(keyword, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return hasContainerTag(tags)
end

local function inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    return isContainerBlock(data.name, data.tags)
end

local function shouldSearchAllSides(opts)
    if type(opts) ~= "table" then
        return true
    end
    if opts.searchAllSides == false then
        return false
    end
    return true
end

local function peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

local function computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

local function tryPushItems(chest, periphSide, slot, amount, targetSlot, primaryDirection)
    if type(chest) ~= "table" or type(chest.pushItems) ~= "function" then
        return 0
    end

    local tried = {}

    local function attempt(direction)
        if not direction or tried[direction] then
            return 0
        end
        tried[direction] = true
        local ok, moved
        if targetSlot then
            ok, moved = pcall(chest.pushItems, direction, slot, amount, targetSlot)
        else
            ok, moved = pcall(chest.pushItems, direction, slot, amount)
        end
        if ok and type(moved) == "number" and moved > 0 then
            return moved
        end
        return 0
    end

    local moved = attempt(primaryDirection)
    if moved > 0 then
        return moved
    end

    for _, direction in ipairs(PUSH_TARGETS) do
        moved = attempt(direction)
        if moved > 0 then
            return moved
        end
    end

    return 0
end

local function collectStacks(chest, material)
    local stacks = {}
    if type(chest) ~= "table" or not material then
        return stacks
    end

    if type(chest.list) == "function" then
        local ok, list = pcall(chest.list)
        if ok and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot and type(stack) == "table" then
                    local name = stack.name or stack.id
                    local count = stack.count or stack.qty or stack.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = numericSlot, count = count }
                    end
                end
            end
        end
    end

    if #stacks == 0 and type(chest.size) == "function" and type(chest.getItemDetail) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size > 0 then
            for slot = 1, size do
                local okDetail, detail = pcall(chest.getItemDetail, slot)
                if okDetail and type(detail) == "table" then
                    local name = detail.name
                    local count = detail.count or detail.qty or detail.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = slot, count = count }
                    end
                end
            end
        end
    end

    table.sort(stacks, function(a, b)
        return a.slot < b.slot
    end)

    return stacks
end

local function extractFromContainer(ctx, periphSide, material, amount, targetSlot)
    if not material or not peripheral or type(peripheral.wrap) ~= "function" then
        return 0
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return 0
    end
    if type(chest.pushItems) ~= "function" then
        return 0
    end

    local desired = amount
    if not desired or desired <= 0 then
        desired = 64
    end

    local stacks = collectStacks(chest, material)
    if #stacks == 0 then
        return 0
    end

    local remaining = desired
    local transferred = 0
    local primaryDirection = computePrimaryPushDirection(ctx, periphSide)

    for _, stack in ipairs(stacks) do
        local available = stack.count or 0
        while remaining > 0 and available > 0 do
            local toMove = math.min(available, remaining, 64)
            local moved = tryPushItems(chest, periphSide, stack.slot, toMove, targetSlot, primaryDirection)
            if moved <= 0 then
                break
            end
            transferred = transferred + moved
            remaining = remaining - moved
            available = available - moved
        end
        if remaining <= 0 then
            break
        end
    end

    return transferred
end

local function ensureChestAhead(ctx, opts)
    if not shouldSearchAllSides(opts) then
        return true, noop
    end
    if inspectForwardForContainer() then
        return true, noop
    end
    if not turtle then
        return true, noop
    end

    movement.ensureState(ctx)
    local startFacing = movement.getFacing(ctx)

    local function restoreToStart()
        if startFacing then
            movement.faceDirection(ctx, startFacing)
        end
    end

    -- Check left
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end
    if inspectForwardForContainer() then
        log(ctx, "debug", "Found container on left side; using that")
        return true, function()
            movement.turnRight(ctx)
            if startFacing and movement.getFacing(ctx) ~= startFacing then
                movement.faceDirection(ctx, startFacing)
            end
        end
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end

    -- Check behind (turn right twice from original orientation)
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end
    if inspectForwardForContainer() then
        log(ctx, "debug", "Found container behind; using that")
        return true, function()
            movement.turnLeft(ctx)
            movement.turnLeft(ctx)
            if startFacing and movement.getFacing(ctx) ~= startFacing then
                movement.faceDirection(ctx, startFacing)
            end
        end
    end
    -- Restore to original orientation before next check
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end

    -- Check right
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end
    if inspectForwardForContainer() then
        log(ctx, "debug", "Found container on right side; using that")
        return true, function()
            movement.turnLeft(ctx)
            if startFacing and movement.getFacing(ctx) ~= startFacing then
                movement.faceDirection(ctx, startFacing)
            end
        end
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreToStart()
        return false, err or "turn_failed"
    end

    restoreToStart()
    return false, "container_not_found"
end

local function ensureInventoryState(ctx)
    if type(ctx) ~= "table" then
        error("inventory library requires a context table", 2)
    end

    if type(ctx.inventoryState) ~= "table" then
        ctx.inventoryState = ctx.inventory or {}
    end
    ctx.inventory = ctx.inventoryState

    local state = ctx.inventoryState
    state.scanVersion = state.scanVersion or 0
    state.slots = state.slots or {}
    state.materialSlots = state.materialSlots or {}
    state.materialTotals = state.materialTotals or {}
    state.emptySlots = state.emptySlots or {}
    state.totalItems = state.totalItems or 0
    if state.dirty == nil then
        state.dirty = true
    end
    return state
end

function inventory.ensureState(ctx)
    return ensureInventoryState(ctx)
end

function inventory.invalidate(ctx)
    local state = ensureInventoryState(ctx)
    state.dirty = true
    return true
end

local function fetchSlotDetail(slot)
    if not turtle then
        return { slot = slot, count = 0 }
    end
    local detail
    if turtle.getItemDetail then
        detail = turtle.getItemDetail(slot)
    end
    local count
    if turtle.getItemCount then
        count = turtle.getItemCount(slot)
    elseif detail then
        count = detail.count
    end
    count = count or 0
    local name = detail and detail.name or nil
    return {
        slot = slot,
        count = count,
        name = name,
        detail = detail,
    }
end

function inventory.scan(ctx, opts)
    local state = ensureInventoryState(ctx)
    if not turtle then
        state.slots = {}
        state.materialSlots = {}
        state.materialTotals = {}
        state.emptySlots = {}
        state.totalItems = 0
        state.dirty = false
        state.scanVersion = state.scanVersion + 1
        return false, "turtle API unavailable"
    end

    local slots = {}
    local materialSlots = {}
    local materialTotals = {}
    local emptySlots = {}
    local totalItems = 0

    for slot = 1, 16 do
        local info = fetchSlotDetail(slot)
        slots[slot] = info
        if info.count > 0 and info.name then
            local list = materialSlots[info.name]
            if not list then
                list = {}
                materialSlots[info.name] = list
            end
            list[#list + 1] = slot
            materialTotals[info.name] = (materialTotals[info.name] or 0) + info.count
            totalItems = totalItems + info.count
        else
            emptySlots[#emptySlots + 1] = slot
        end
    end

    state.slots = slots
    state.materialSlots = materialSlots
    state.materialTotals = materialTotals
    state.emptySlots = emptySlots
    state.totalItems = totalItems
    if os and type(os.clock) == "function" then
        state.lastScanClock = os.clock()
    else
        state.lastScanClock = nil
    end
    local epochFn = os and os["epoch"]
    if type(epochFn) == "function" then
        state.lastScanEpoch = epochFn("utc")
    else
        state.lastScanEpoch = nil
    end
    state.scanVersion = state.scanVersion + 1
    state.dirty = false

    log(ctx, "debug", string.format("Inventory scan complete: %d items across %d materials", totalItems, tableCount(materialSlots)))
    return true
end

local function ensureScanned(ctx, opts)
    local state = ensureInventoryState(ctx)
    if state.dirty or (type(opts) == "table" and opts.force) or not state.slots or next(state.slots) == nil then
        local ok, err = inventory.scan(ctx, opts)
        if not ok and err then
            return nil, err
        end
    end
    return state
end

function inventory.getMaterialSlots(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return nil, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local slots = state.materialSlots[material]
    if not slots then
        return {}
    end
    return copyArray(slots)
end

function inventory.getSlotForMaterial(ctx, material, opts)
    local slots, err = inventory.getMaterialSlots(ctx, material, opts)
    if slots == nil then
        return nil, err
    end
    if slots[1] then
        return slots[1]
    end
    return nil, "missing_material"
end

function inventory.countMaterial(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return 0, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.materialTotals[material] or 0
end

function inventory.hasMaterial(ctx, material, amount, opts)
    amount = amount or 1
    if amount <= 0 then
        return true
    end
    local total, err = inventory.countMaterial(ctx, material, opts)
    if err then
        return false, err
    end
    return total >= amount
end

function inventory.findEmptySlot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local empty = state.emptySlots
    if empty and empty[1] then
        return empty[1]
    end
    return nil, "no_empty_slot"
end

function inventory.isEmpty(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end
    return state.totalItems == 0
end

function inventory.totalItemCount(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.totalItems
end

function inventory.getTotals(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return copySummary(state.materialTotals)
end

function inventory.snapshot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return {
        slots = copySlots(state.slots),
        totals = copySummary(state.materialTotals),
        emptySlots = copyArray(state.emptySlots),
        totalItems = state.totalItems,
        scanVersion = state.scanVersion,
        lastScanClock = state.lastScanClock,
        lastScanEpoch = state.lastScanEpoch,
    }
end

function inventory.selectMaterial(ctx, material, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
    if not slot then
        return false, err or "missing_material"
    end
    if turtle.select(slot) then
        return true
    end
    return false, "select_failed"
end

local function selectSlot(slot)
    if not turtle then
        return false, "turtle API unavailable"
    end
    if type(slot) ~= "number" or slot < 1 or slot > 16 then
        return false, "invalid_slot"
    end
    if turtle.select(slot) then
        return true
    end
    return false, "select_failed"
end

local function rescanIfNeeded(ctx, opts)
    if opts and opts.deferScan then
        inventory.invalidate(ctx)
        return
    end
    local ok, err = inventory.scan(ctx)
    if not ok and err then
        log(ctx, "warn", "Inventory rescan failed: " .. tostring(err))
        inventory.invalidate(ctx)
    end
end

function inventory.pushSlot(ctx, slot, amount, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local side = resolveSide(ctx, opts)
    local actions = SIDE_ACTIONS[side]
    if not actions or type(actions.drop) ~= "function" then
        return false, "invalid_side"
    end

    local ok, err = selectSlot(slot)
    if not ok then
        return false, err
    end

    local restoreFacing = noop
    if side == "forward" then
        local chestOk, restoreFn, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) ~= "function" then
            restoreFacing = noop
        else
            restoreFacing = restoreFn
        end
    end

    local count = turtle.getItemCount and turtle.getItemCount(slot) or nil
    if count ~= nil and count <= 0 then
        restoreFacing()
        return false, "empty_slot"
    end

    if amount and amount > 0 then
        ok = actions.drop(amount)
    else
        ok = actions.drop()
    end
    if not ok then
        restoreFacing()
        return false, "drop_failed"
    end

    restoreFacing()
    rescanIfNeeded(ctx, opts)
    return true
end

function inventory.pushMaterial(ctx, material, amount, opts)
    if type(material) ~= "string" or material == "" then
        return false, "invalid_material"
    end
    local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
    if not slot then
        return false, err or "missing_material"
    end
    return inventory.pushSlot(ctx, slot, amount, opts)
end

local function resolveTargetSlotForPull(state, material, opts)
    if opts and opts.slot then
        return opts.slot
    end
    if material then
        local materialSlots = state.materialSlots[material]
        if materialSlots and materialSlots[1] then
            return materialSlots[1]
        end
    end
    local empty = state.emptySlots
    if empty and empty[1] then
        return empty[1]
    end
    return nil
end

function inventory.pullMaterial(ctx, material, amount, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end

    local side = resolveSide(ctx, opts)
    local actions = SIDE_ACTIONS[side]
    if not actions or type(actions.suck) ~= "function" then
        return false, "invalid_side"
    end

    if material ~= nil and (type(material) ~= "string" or material == "") then
        return false, "invalid_material"
    end

    local targetSlot = resolveTargetSlotForPull(state, material, opts)
    if not targetSlot then
        return false, "no_empty_slot"
    end

    local ok, selectErr = selectSlot(targetSlot)
    if not ok then
        return false, selectErr
    end

    local periphSide = peripheralSideForDirection(side)
    local restoreFacing = noop
    if side == "forward" then
        local chestOk, restoreFn, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) ~= "function" then
            restoreFacing = noop
        else
            restoreFacing = restoreFn
        end
    end

    local transferred = 0
    if material then
        transferred = extractFromContainer(ctx, periphSide, material, amount, targetSlot)
        if transferred > 0 then
            restoreFacing()
            rescanIfNeeded(ctx, opts)
            return true
        end
    end

    if material == nil then
        if amount and amount > 0 then
            ok = actions.suck(amount)
        else
            ok = actions.suck()
        end
        if not ok then
            restoreFacing()
            return false, "suck_failed"
        end
        restoreFacing()
        rescanIfNeeded(ctx, opts)
        return true
    end

    local function makePushOpts()
        local pushOpts = { side = side }
        if type(opts) == "table" and opts.searchAllSides ~= nil then
            pushOpts.searchAllSides = opts.searchAllSides
        end
        return pushOpts
    end

    local stashSlots = {}

    local function findTemporarySlot()
        for slot = 1, 16 do
            if slot ~= targetSlot and turtle.getItemCount(slot) == 0 then
                local used = false
                for _, usedSlot in ipairs(stashSlots) do
                    if usedSlot == slot then
                        used = true
                        break
                    end
                end
                if not used then
                    return slot
                end
            end
        end
        return nil
    end

    local function returnStash(deferScan)
        if #stashSlots == 0 then
            return
        end
        local pushOpts = makePushOpts()
        pushOpts.deferScan = deferScan
        for _, slot in ipairs(stashSlots) do
            local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
            if not pushOk and pushErr then
                log(ctx, "warn", string.format("Failed to return cycled item from slot %d: %s", slot, tostring(pushErr)))
            end
        end
        turtle.select(targetSlot)
        inventory.invalidate(ctx)
    end

    local desired = nil
    if amount and amount > 0 then
        desired = math.min(amount, 64)
    end

    local cycles = 0
    local maxCycles = (type(opts) == "table" and opts.cycleLimit) or 48
    local success = false
    local failureReason
    local cycled = 0

    while cycles < maxCycles do
        cycles = cycles + 1
        local currentCount = turtle.getItemCount(targetSlot)
        if desired and currentCount >= desired then
            success = true
            break
        end

        local need = desired and math.max(desired - currentCount, 1) or nil
        local pulled
        if need then
            pulled = actions.suck(math.min(need, 64))
        else
            pulled = actions.suck()
        end
        if not pulled then
            failureReason = failureReason or "suck_failed"
            break
        end

        local detail = turtle.getItemDetail and turtle.getItemDetail(targetSlot) or nil
        local updatedCount = turtle.getItemCount(targetSlot)

        if detail and detail.name == material then
            if not desired or updatedCount >= desired then
                success = true
                break
            end
        else
            local stashSlot = findTemporarySlot()
            if not stashSlot then
                failureReason = "no_empty_slot"
                break
            end
            local moved = turtle.transferTo(stashSlot)
            if not moved then
                failureReason = "transfer_failed"
                break
            end
            stashSlots[#stashSlots + 1] = stashSlot
            cycled = cycled + 1
            inventory.invalidate(ctx)
            turtle.select(targetSlot)
        end
    end

    if success then
        if cycled > 0 then
            log(ctx, "debug", string.format("Pulled %s after cycling %d other stacks", material, cycled))
        else
            log(ctx, "debug", string.format("Pulled %s directly via turtle.suck", material))
        end
        returnStash(true)
        restoreFacing()
        rescanIfNeeded(ctx, opts)
        return true
    end

    returnStash(true)
    restoreFacing()
    if failureReason then
        log(ctx, "debug", string.format("Failed to pull %s after cycling %d stacks: %s", material, cycled, failureReason))
    end
    if failureReason == "suck_failed" then
        return false, "missing_material"
    end
    return false, failureReason or "missing_material"
end

function inventory.clearSlot(ctx, slot, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end
    local info = state.slots[slot]
    if not info or info.count == 0 then
        return true
    end
    local ok, dropErr = inventory.pushSlot(ctx, slot, nil, opts)
    if not ok then
        return false, dropErr
    end
    return true
end

return inventory
