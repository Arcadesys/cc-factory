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
local logger = require("lib_logger")

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

inventory.DEFAULT_TRASH = {
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
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
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

local function newContainerManifest()
    return {
        totals = {},
        slots = {},
        totalItems = 0,
        orderedSlots = {},
        size = nil,
        metadata = nil,
    }
end

local function addManifestEntry(manifest, slot, stack)
    if type(manifest) ~= "table" or type(slot) ~= "number" then
        return
    end
    if type(stack) ~= "table" then
        return
    end
    local name = stack.name or stack.id
    local count = stack.count or stack.qty or stack.quantity or stack.Count
    if type(name) ~= "string" or type(count) ~= "number" or count <= 0 then
        return
    end
    manifest.slots[slot] = {
        name = name,
        count = count,
        tags = stack.tags,
        nbt = stack.nbt,
        displayName = stack.displayName or stack.label or stack.Name,
        detail = stack,
    }
    manifest.totals[name] = (manifest.totals[name] or 0) + count
    manifest.totalItems = manifest.totalItems + count
end

local function populateManifestSlots(manifest)
    local ordered = {}
    for slot in pairs(manifest.slots) do
        ordered[#ordered + 1] = slot
    end
    table.sort(ordered)
    manifest.orderedSlots = ordered

    local materials = {}
    for material in pairs(manifest.totals) do
        materials[#materials + 1] = material
    end
    table.sort(materials)
    manifest.materials = materials
end

local function attachMetadata(manifest, periphSide)
    if not peripheral then
        return
    end
    local metadata = manifest.metadata or {}
    if type(peripheral.call) == "function" then
        local okMeta, meta = pcall(peripheral.call, periphSide, "getMetadata")
        if okMeta and type(meta) == "table" then
            metadata.name = meta.name or metadata.name
            metadata.displayName = meta.displayName or meta.label or metadata.displayName
            metadata.tags = meta.tags or metadata.tags
        end
    end
    if type(peripheral.getType) == "function" then
        local okType, perType = pcall(peripheral.getType, periphSide)
        if okType then
            if type(perType) == "string" then
                metadata.peripheralType = perType
            elseif type(perType) == "table" and type(perType[1]) == "string" then
                metadata.peripheralType = perType[1]
            end
        end
    end
    if next(metadata) ~= nil then
        manifest.metadata = metadata
    end
end

local function readContainerManifest(periphSide)
    if not peripheral or type(peripheral.wrap) ~= "function" then
        return nil, "peripheral_api_unavailable"
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return nil, "wrap_failed"
    end

    local manifest = newContainerManifest()

    if type(chest.list) == "function" then
        local okList, list = pcall(chest.list)
        if okList and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot then
                    addManifestEntry(manifest, numericSlot, stack)
                end
            end
        end
    end

    local haveSlots = next(manifest.slots) ~= nil
    if type(chest.size) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size >= 0 then
            manifest.size = size
            if not haveSlots and type(chest.getItemDetail) == "function" then
                for slot = 1, size do
                    local okDetail, detail = pcall(chest.getItemDetail, slot)
                    if okDetail then
                        addManifestEntry(manifest, slot, detail)
                    end
                end
            end
        end
    end

    populateManifestSlots(manifest)
    attachMetadata(manifest, periphSide)

    return manifest
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
    local frontOk, frontDetail = inspectForwardForContainer()
    if frontOk then
        return true, noop, { side = "forward", detail = frontDetail }
    end

    if not shouldSearchAllSides(opts) then
        return false, nil, nil, "container_not_found"
    end
    if not turtle then
        return false, nil, nil, "turtle_api_unavailable"
    end

    movement.ensureState(ctx)
    local startFacing = movement.getFacing(ctx)

    local function restoreFacing()
        if not startFacing then
            return
        end
        if movement.getFacing(ctx) ~= startFacing then
            local okFace, faceErr = movement.faceDirection(ctx, startFacing)
            if not okFace and faceErr then
                logger.log(ctx, "warn", "Failed to restore facing: " .. tostring(faceErr))
            end
        end
    end

    local function makeRestore()
        if not startFacing then
            return noop
        end
        return function()
            restoreFacing()
        end
    end

    -- Check left
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local leftOk, leftDetail = inspectForwardForContainer()
    if leftOk then
        logger.log(ctx, "debug", "Found container on left side; using that")
        return true, makeRestore(), { side = "left", detail = leftDetail }
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check right
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local rightOk, rightDetail = inspectForwardForContainer()
    if rightOk then
        logger.log(ctx, "debug", "Found container on right side; using that")
        return true, makeRestore(), { side = "right", detail = rightDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check behind
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local backOk, backDetail = inspectForwardForContainer()
    if backOk then
        logger.log(ctx, "debug", "Found container behind; using that")
        return true, makeRestore(), { side = "back", detail = backDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    restoreFacing()
    return false, nil, nil, "container_not_found"
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

    logger.log(ctx, "debug", string.format("Inventory scan complete: %d items across %d materials", totalItems, tableCount(materialSlots)))
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

function inventory.detectContainer(ctx, opts)
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    if side == "forward" then
        local chestOk, restoreFn, info, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFn()
        end
        local result = info or { side = "forward" }
        result.peripheralSide = "front"
        return result
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if okUp then
            return { side = "up", detail = detail, peripheralSide = "top" }
        end
        return nil, "container_not_found"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if okDown then
            return { side = "down", detail = detail, peripheralSide = "bottom" }
        end
        return nil, "container_not_found"
    end
    return nil, "unsupported_side"
end

function inventory.getContainerManifest(ctx, opts)
    if not turtle then
        return nil, "turtle API unavailable"
    end
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    local restoreFacing = noop
    local info

    if side == "forward" then
        local chestOk, restoreFn, chestInfo, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
        info = chestInfo or { side = "forward" }
        periphSide = "front"
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if not okUp then
            return nil, "container_not_found"
        end
        info = { side = "up", detail = detail }
        periphSide = "top"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if not okDown then
            return nil, "container_not_found"
        end
        info = { side = "down", detail = detail }
        periphSide = "bottom"
    else
        return nil, "unsupported_side"
    end

    local manifest, manifestErr = readContainerManifest(periphSide)
    restoreFacing()
    if not manifest then
        return nil, manifestErr or "wrap_failed"
    end

    manifest.peripheralSide = periphSide
    if info then
        manifest.relativeSide = info.side
        manifest.inspectDetail = info.detail
        if not manifest.metadata and info.detail then
            manifest.metadata = {
                name = info.detail.name,
                displayName = info.detail.displayName or info.detail.label,
                tags = info.detail.tags,
            }
        elseif manifest.metadata and info.detail then
            manifest.metadata.name = manifest.metadata.name or info.detail.name
            manifest.metadata.displayName = manifest.metadata.displayName or info.detail.displayName or info.detail.label
            manifest.metadata.tags = manifest.metadata.tags or info.detail.tags
        end
    end

    return manifest
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
        logger.log(ctx, "warn", "Inventory rescan failed: " .. tostring(err))
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
        local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
    elseif side == "up" then
        local okUp = inspectUpForContainer()
        if not okUp then
            return false, "container_not_found"
        end
    elseif side == "down" then
        local okDown = inspectDownForContainer()
        if not okDown then
            return false, "container_not_found"
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
        local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
    elseif side == "up" then
        local okUp = inspectUpForContainer()
        if not okUp then
            return false, "container_not_found"
        end
    elseif side == "down" then
        local okDown = inspectDownForContainer()
        if not okDown then
            return false, "container_not_found"
        end
    end

    local desired = nil
    if material then
        if amount and amount > 0 then
            desired = math.min(amount, 64)
        else
            -- Accept any positive stack when no explicit amount is requested.
            desired = nil
        end
    elseif amount and amount > 0 then
        desired = amount
    end

    local transferred = 0
    if material then
        transferred = extractFromContainer(ctx, periphSide, material, desired, targetSlot)
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
    local stashSet = {}

    local function addStashSlot(slot)
        stashSlots[#stashSlots + 1] = slot
        stashSet[slot] = true
    end

    local function markSlotEmpty(slot)
        if not slot then
            return
        end
        local info = state.slots[slot]
        if info then
            info.count = 0
            info.name = nil
            info.detail = nil
        end
        for index = #state.emptySlots, 1, -1 do
            if state.emptySlots[index] == slot then
                return
            end
        end
        state.emptySlots[#state.emptySlots + 1] = slot
    end

    local function freeAdditionalSlot()
        local pushOpts = makePushOpts()
        pushOpts.deferScan = true
        for slot = 16, 1, -1 do
            if slot ~= targetSlot and not stashSet[slot] then
                local count = turtle.getItemCount(slot)
                if count > 0 then
                    local info = state.slots[slot]
                    if not info or info.name ~= material then
                        local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
                        if pushOk then
                            inventory.invalidate(ctx)
                            markSlotEmpty(slot)
                            local newState = ensureScanned(ctx, { force = true })
                            if newState then
                                state = newState
                            end
                            if turtle.getItemCount(slot) == 0 then
                                return slot
                            end
                        else
                            if pushErr then
                                logger.log(ctx, "debug", string.format("Unable to clear slot %d while restocking %s: %s", slot, material or "unknown", pushErr))
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function findTemporarySlot()
        for slot = 1, 16 do
            if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
                return slot
            end
        end
        local cleared = freeAdditionalSlot()
        if cleared then
            return cleared
        end
        for slot = 1, 16 do
            if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
                return slot
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
                logger.log(ctx, "warn", string.format("Failed to return cycled item from slot %d: %s", slot, tostring(pushErr)))
            end
        end
        turtle.select(targetSlot)
        inventory.invalidate(ctx)
        local newState = ensureScanned(ctx, { force = true })
        if newState then
            state = newState
        end
        stashSlots = {}
        stashSet = {}
    end

    local cycles = 0
    local maxCycles = (type(opts) == "table" and opts.cycleLimit) or 48
    local success = false
    local failureReason
    local cycled = 0
    local assumedMatch = false

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

        local detail
        if turtle and turtle.getItemDetail then
            detail = turtle.getItemDetail(targetSlot)
            if detail == nil then
                local okDetailed, detailed = pcall(turtle.getItemDetail, targetSlot, true)
                if okDetailed then
                    detail = detailed
                end
            end
        end
        local updatedCount = turtle.getItemCount(targetSlot)

        local assumedMatch = false
        if not detail and material and updatedCount > 0 then
            -- Non-advanced turtles cannot inspect stacks; assume the pulled stack
            -- matches the requested material when we cannot obtain metadata.
            assumedMatch = true
        end

        if (detail and detail.name == material) or assumedMatch then
            if not desired or updatedCount >= desired then
                success = true
                break
            end
        else
            assumedMatch = false
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
            addStashSlot(stashSlot)
            cycled = cycled + 1
            inventory.invalidate(ctx)
            turtle.select(targetSlot)
        end
    end

    if success then
        if assumedMatch then
            logger.log(ctx, "debug", string.format("Pulled %s without detailed item metadata", material or "unknown"))
        elseif cycled > 0 then
            logger.log(ctx, "debug", string.format("Pulled %s after cycling %d other stacks", material, cycled))
        else
            logger.log(ctx, "debug", string.format("Pulled %s directly via turtle.suck", material))
        end
        returnStash(true)
        restoreFacing()
        rescanIfNeeded(ctx, opts)
        return true
    end

    returnStash(true)
    restoreFacing()
    if failureReason then
        logger.log(ctx, "debug", string.format("Failed to pull %s after cycling %d stacks: %s", material, cycled, failureReason))
    end
    if failureReason == "suck_failed" then
        return false, "missing_material"
    end
    return false, failureReason or "missing_material"
end

function inventory.dumpTrash(ctx, trashList)
    if not turtle then return false, "turtle API unavailable" end
    trashList = trashList or inventory.DEFAULT_TRASH
    
    local state, err = ensureScanned(ctx)
    if not state then return false, err end

    for slot, info in pairs(state.slots) do
        if info and info.name and trashList[info.name] then
            turtle.select(slot)
            turtle.drop()
        end
    end
    
    -- Force rescan after dumping
    inventory.scan(ctx)
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

function inventory.describeMaterials(io, info)
    if not io.print then
        return
    end
    io.print("Schema manifest requirements:")
    if not info or not info.materials then
        io.print(" - <none>")
        return
    end
    for _, entry in ipairs(info.materials) do
        if entry.material ~= "minecraft:air" and entry.material ~= "air" then
            io.print(string.format(" - %s x%d", entry.material, entry.count or 0))
        end
    end
end

function inventory.runCheck(ctx, io, opts)
    local ok, report = initialize.ensureMaterials(ctx, { manifest = ctx.schemaInfo and ctx.schemaInfo.materials }, opts)
    if io.print then
        if ok then
            io.print("Material check passed. Turtle and chests meet manifest requirements.")
        else
            io.print("Material check failed. Missing materials:")
            for _, entry in ipairs(report.missing or {}) do
                io.print(string.format(" - %s: need %d, have %d", entry.material, entry.required, entry.have))
            end
        end
    end
    return ok, report
end

function inventory.gatherSummary(io, report)
    if not io.print then
        return
    end
    io.print("\nDetailed totals:")
    io.print(" Turtle inventory:")
    for material, count in pairs(report.turtleTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    io.print(" Nearby chests:")
    for material, count in pairs(report.chestTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    if #report.chests > 0 then
        io.print(" Per-chest breakdown:")
        for _, entry in ipairs(report.chests) do
            io.print(string.format("   [%s] %s", entry.side, entry.name or "container"))
            for material, count in pairs(entry.totals or {}) do
                io.print(string.format("     * %s x%d", material, count))
            end
        end
    end
end

function inventory.describeTotals(io, totals)
    totals = totals or {}
    local keys = {}
    for material in pairs(totals) do
        keys[#keys + 1] = material
    end
    table.sort(keys)
    if io.print then
        if #keys == 0 then
            io.print("Inventory totals: <empty>")
        else
            io.print("Inventory totals:")
            for _, material in ipairs(keys) do
                io.print(string.format(" - %s x%d", material, totals[material] or 0))
            end
        end
    end
end

function inventory.computeManifest(list)
    local totals = {}
    for _, sc in ipairs(list) do
        if sc.material and sc.material ~= "" then
            totals[sc.material] = (totals[sc.material] or 0) + 1
        end
    end
    return totals
end

function inventory.printManifest(io, manifest)
    if not io.print then
        return
    end
    io.print("\nRequested manifest (minimum counts):")
    local shown = false
    for material, count in pairs(manifest) do
        io.print(string.format(" - %s x%d", material, count))
        shown = true
    end
    if not shown then
        io.print(" - <empty>")
    end
end

return inventory
