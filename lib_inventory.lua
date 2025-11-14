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

local function noop()
    return
end

local function copySummary(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        result[k] = v
    end
    return result
end

local function copyArray(source)
    local result = {}
    for i = 1, #source do
        result[i] = source[i]
    end
    return result
end

local function copySlots(slots)
    local result = {}
    for index, info in pairs(slots) do
        if type(info) == "table" then
            local detailCopy
            if type(info.detail) == "table" then
                detailCopy = copySummary(info.detail)
            end
            result[index] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = detailCopy,
            }
        end
    end
    return result
end

local function tableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function resolveSide(opts)
    if type(opts) ~= "table" then
        return "forward"
    end
    local side = opts.side or opts.direction or "forward"
    if side == "front" then
        side = "forward"
    end
    if side ~= "forward" and side ~= "up" and side ~= "down" then
        return "forward"
    end
    return side
end

local CONTAINER_KEYWORDS = {
    "chest",
    "barrel",
    "drawer",
    "crate",
    "shulker_box",
    "shulkerbox",
}

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
    local side = resolveSide(opts)
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

    local side = resolveSide(opts)
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
    if material then
        local hasMaterial, hasErr = inventory.hasMaterial(ctx, material, 1, { force = true })
        if hasErr then
            return true
        end
        if not hasMaterial then
            log(ctx, "debug", string.format("Pulled from %s but expected material %s not found", side, material))
        end
    end
    return true
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
