--[[
Placement library for CC:Tweaked turtles.
Provides safe block placement helpers and a high-level build state executor.
All public functions accept a shared ctx table and return success booleans or
state transition hints, following the project conventions.
--]]

---@diagnostic disable: undefined-global

local placement = {}
local logger = require("lib_logger")
local world = require("lib_world")
local fuel = require("lib_fuel")
local schema_utils = require("lib_schema")
local strategy_utils = require("lib_strategy")

local SIDE_APIS = {
    forward = {
        place = turtle and turtle.place or nil,
        detect = turtle and turtle.detect or nil,
        inspect = turtle and turtle.inspect or nil,
        dig = turtle and turtle.dig or nil,
        attack = turtle and turtle.attack or nil,
    },
    up = {
        place = turtle and turtle.placeUp or nil,
        detect = turtle and turtle.detectUp or nil,
        inspect = turtle and turtle.inspectUp or nil,
        dig = turtle and turtle.digUp or nil,
        attack = turtle and turtle.attackUp or nil,
    },
    down = {
        place = turtle and turtle.placeDown or nil,
        detect = turtle and turtle.detectDown or nil,
        inspect = turtle and turtle.inspectDown or nil,
        dig = turtle and turtle.digDown or nil,
        attack = turtle and turtle.attackDown or nil,
    },
}

local function ensurePlacementState(ctx)
    if type(ctx) ~= "table" then
        error("placement library requires a context table", 2)
    end
    ctx.placement = ctx.placement or {}
    local state = ctx.placement
    state.cachedSlots = state.cachedSlots or {}
    return state
end

local function selectMaterialSlot(ctx, material)
    local state = ensurePlacementState(ctx)
    if not turtle or not turtle.getItemDetail or not turtle.select then
        return nil, "turtle API unavailable"
    end
    if type(material) ~= "string" or material == "" then
        return nil, "invalid_material"
    end

    local cached = state.cachedSlots[material]
    if cached then
        local detail = turtle.getItemDetail(cached)
        local count = detail and detail.count
        if (not count or count <= 0) and turtle.getItemCount then
            count = turtle.getItemCount(cached)
        end
        if detail and detail.name == material and count and count > 0 then
            if turtle.select(cached) then
                state.lastSlot = cached
                return cached
            end
            state.cachedSlots[material] = nil
        else
            state.cachedSlots[material] = nil
        end
    end

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        local count = detail and detail.count
        if (not count or count <= 0) and turtle.getItemCount then
            count = turtle.getItemCount(slot)
        end
        if detail and detail.name == material and count and count > 0 then
            if turtle.select(slot) then
                state.cachedSlots[material] = slot
                state.lastSlot = slot
                return slot
            end
        end
    end

    return nil, "missing_material"
end

local function resolveSide(ctx, block, opts)
    if type(opts) == "table" and opts.side then
        return opts.side
    end
    if type(block) == "table" and type(block.meta) == "table" and block.meta.side then
        return block.meta.side
    end
    if type(ctx.config) == "table" and ctx.config.defaultPlacementSide then
        return ctx.config.defaultPlacementSide
    end
    return "forward"
end

local function resolveOverwrite(ctx, block, opts)
    if type(opts) == "table" and opts.overwrite ~= nil then
        return opts.overwrite
    end
    if type(block) == "table" and type(block.meta) == "table" and block.meta.overwrite ~= nil then
        return block.meta.overwrite
    end
    if type(ctx.config) == "table" and ctx.config.allowOverwrite ~= nil then
        return ctx.config.allowOverwrite
    end
    return false
end

local function detectBlock(sideFns)
    if type(sideFns.inspect) == "function" then
        local hasBlock, data = sideFns.inspect()
        if hasBlock then
            return true, data
        end
        return false, nil
    end
    if type(sideFns.detect) == "function" then
        local exists = sideFns.detect()
        if exists then
            return true, nil
        end
    end
    return false, nil
end

local function clearBlockingBlock(sideFns, allowDig, allowAttack)
    if not allowDig and not allowAttack then
        return false
    end

    local attempts = 0
    local maxAttempts = 4

    while attempts < maxAttempts do
        attempts = attempts + 1
        local cleared = false

        if allowDig and type(sideFns.dig) == "function" then
            cleared = sideFns.dig() or cleared
        end

        if not cleared and allowAttack and type(sideFns.attack) == "function" then
            cleared = sideFns.attack() or cleared
        end

        if cleared then
            if type(sideFns.detect) ~= "function" or not sideFns.detect() then
                return true
            end
        end

        if sleep and attempts < maxAttempts then
            sleep(0)
        end
    end

    return false
end

function placement.placeMaterial(ctx, material, opts)
    local state = ensurePlacementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end
    if material == nil or material == "" or material == "minecraft:air" or material == "air" then
        state.lastPlacement = { skipped = true, reason = "air", material = material }
        return true
    end

    local side = resolveSide(ctx, opts and opts.block or nil, opts)
    local sideFns = SIDE_APIS[side]
    if not sideFns or type(sideFns.place) ~= "function" then
        return false, "invalid_side"
    end

    local slot, slotErr = selectMaterialSlot(ctx, material)
    if not slot then
        state.lastPlacement = { success = false, material = material, error = slotErr }
        return false, slotErr
    end

    local allowDig = opts and opts.dig
    if allowDig == nil then
        allowDig = true
    end
    local allowAttack = opts and opts.attack
    if allowAttack == nil then
        allowAttack = true
    end
    local allowOverwrite = resolveOverwrite(ctx, opts and opts.block or nil, opts)

    local blockPresent, blockData = detectBlock(sideFns)
    local blockingName = blockData and blockData.name or nil
    if blockPresent then
        if blockData and blockData.name == material then
            state.lastPlacement = { success = true, material = material, reused = true, side = side, blocking = blockingName }
            return true, "already_present"
        end

        local needsReplacement = not (blockData and blockData.name == material)
        local canForce = allowOverwrite or needsReplacement

        if not canForce then
            state.lastPlacement = { success = false, material = material, error = "occupied", side = side, blocking = blockingName }
            return false, "occupied"
        end

        local cleared = clearBlockingBlock(sideFns, allowDig, allowAttack)
        if not cleared then
            local reason = needsReplacement and "mismatched_block" or "blocked"
            state.lastPlacement = { success = false, material = material, error = reason, side = side, blocking = blockingName }
            return false, reason
        end
    end

    if not turtle.select(slot) then
        state.cachedSlots[material] = nil
        state.lastPlacement = { success = false, material = material, error = "select_failed", side = side, slot = slot }
        return false, "select_failed"
    end

    local placed, placeErr = sideFns.place()
    if not placed then
        if placeErr then
            logger.log(ctx, "debug", string.format("Place failed for %s: %s", material, placeErr))
        end

        local stillBlocked = type(sideFns.detect) == "function" and sideFns.detect()
        local slotCount
        if turtle.getItemCount then
            slotCount = turtle.getItemCount(slot)
        elseif turtle.getItemDetail then
            local detail = turtle.getItemDetail(slot)
            slotCount = detail and detail.count or nil
        end

        local lowerErr = type(placeErr) == "string" and placeErr:lower() or nil

        if slotCount ~= nil and slotCount <= 0 then
            state.cachedSlots[material] = nil
            state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
            return false, "missing_material"
        end

        if lowerErr then
            if lowerErr:find("no items") or lowerErr:find("no block") or lowerErr:find("missing item") then
                state.cachedSlots[material] = nil
                state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
                return false, "missing_material"
            end
            if lowerErr:find("protect") or lowerErr:find("denied") or lowerErr:find("cannot place") or lowerErr:find("can't place") or lowerErr:find("occupied") then
                state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
                return false, "blocked"
            end
        end

        if stillBlocked then
            state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
            return false, "blocked"
        end

        state.lastPlacement = { success = false, material = material, error = "placement_failed", side = side, slot = slot, message = placeErr }
        return false, "placement_failed"
    end

    state.lastPlacement = {
        success = true,
        material = material,
        side = side,
        slot = slot,
        timestamp = os and os.time and os.time() or nil,
    }
    return true
end

function placement.advancePointer(ctx)
    return strategy_utils.advancePointer(ctx)
end

function placement.ensureState(ctx)
    return ensurePlacementState(ctx)
end

function placement.executeBuildState(ctx, opts)
    opts = opts or {}
    local state = ensurePlacementState(ctx)

    local pointer, pointerErr = strategy_utils.ensurePointer(ctx)
    if not pointer then
        logger.log(ctx, "debug", "No build pointer available: " .. tostring(pointerErr))
        return "DONE", { reason = pointerErr or "no_pointer" }
    end

    if fuel.isFuelLow(ctx) then
        state.resumeState = "BUILD"
        logger.log(ctx, "info", "Fuel below threshold, switching to REFUEL")
        return "REFUEL", { reason = "fuel_low", pointer = world.copyPosition(pointer) }
    end

    local block, schemaErr = schema_utils.fetchSchemaEntry(ctx.schema, pointer)
    if not block then
        logger.log(ctx, "debug", string.format("No schema entry at x=%d y=%d z=%d (%s)", pointer.x or 0, pointer.y or 0, pointer.z or 0, tostring(schemaErr)))
        local autoAdvance = opts.autoAdvance
        if autoAdvance == nil then
            autoAdvance = true
        end
        if autoAdvance then
            local advanced = placement.advancePointer(ctx)
            if advanced then
                return "BUILD", { reason = "skip_empty", pointer = world.copyPosition(ctx.pointer) }
            end
        end
        return "DONE", { reason = "schema_exhausted" }
    end

    if block.material == nil or block.material == "minecraft:air" or block.material == "air" then
        local autoAdvance = opts.autoAdvance
        if autoAdvance == nil then
            autoAdvance = true
        end
        if autoAdvance then
            local advanced = placement.advancePointer(ctx)
            if advanced then
                return "BUILD", { reason = "skip_air", pointer = world.copyPosition(ctx.pointer) }
            end
        end
        return "DONE", { reason = "no_material" }
    end

    local side = resolveSide(ctx, block, opts)
    local overwrite = resolveOverwrite(ctx, block, opts)
    local allowDig = opts.dig
    local allowAttack = opts.attack
    if allowDig == nil and block.meta and block.meta.dig ~= nil then
        allowDig = block.meta.dig
    end
    if allowAttack == nil and block.meta and block.meta.attack ~= nil then
        allowAttack = block.meta.attack
    end

    local placementOpts = {
        side = side,
        overwrite = overwrite,
        dig = allowDig,
        attack = allowAttack,
        block = block,
    }

    local ok, err = placement.placeMaterial(ctx, block.material, placementOpts)
    if not ok then
        if err == "missing_material" then
            state.resumeState = "BUILD"
            state.pendingMaterial = block.material
            logger.log(ctx, "warn", string.format("Need to restock %s", block.material))
            return "RESTOCK", {
                reason = err,
                material = block.material,
                pointer = world.copyPosition(pointer),
            }
        end
        if err == "blocked" then
            state.resumeState = "BUILD"
            logger.log(ctx, "warn", "Placement blocked; invoking BLOCKED state")
            return "BLOCKED", {
                reason = err,
                pointer = world.copyPosition(pointer),
                material = block.material,
            }
        end
        if err == "turtle API unavailable" then
            state.lastError = err
            return "ERROR", { reason = err }
        end
        state.lastError = err
        logger.log(ctx, "error", string.format("Placement failed for %s: %s", block.material, tostring(err)))
        return "ERROR", {
            reason = err,
            material = block.material,
            pointer = world.copyPosition(pointer),
        }
    end

    state.lastPlaced = {
        material = block.material,
        pointer = world.copyPosition(pointer),
        side = side,
        meta = block.meta,
        timestamp = os and os.time and os.time() or nil,
    }

    local autoAdvance = opts.autoAdvance
    if autoAdvance == nil then
        autoAdvance = true
    end
    if autoAdvance then
        local advanced = placement.advancePointer(ctx)
        if advanced then
            return "BUILD", { reason = "continue", pointer = world.copyPosition(ctx.pointer) }
        end
        return "DONE", { reason = "complete" }
    end

    return "BUILD", { reason = "await_pointer_update" }
end

return placement
