--[[
Placement library for CC:Tweaked turtles.
Provides safe block placement helpers and a high-level build state executor.
All public functions accept a shared ctx table and return success booleans or
state transition hints, following the project conventions.
--]]

---@diagnostic disable: undefined-global

local placement = {}

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

local function copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

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

local function ensurePlacementState(ctx)
    if type(ctx) ~= "table" then
        error("placement library requires a context table", 2)
    end
    ctx.placement = ctx.placement or {}
    local state = ctx.placement
    state.cachedSlots = state.cachedSlots or {}
    return state
end

local function resolveFuelThreshold(ctx)
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

local function isFuelLow(ctx)
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
    local threshold = resolveFuelThreshold(ctx)
    if threshold <= 0 then
        return false
    end
    return level <= threshold
end

local function fetchSchemaEntry(schema, pos)
    if type(schema) ~= "table" or type(pos) ~= "table" then
        return nil, "missing_schema"
    end
    local xLayer = schema[pos.x] or schema[tostring(pos.x)]
    if type(xLayer) ~= "table" then
        return nil, "empty"
    end
    local yLayer = xLayer[pos.y] or xLayer[tostring(pos.y)]
    if type(yLayer) ~= "table" then
        return nil, "empty"
    end
    local block = yLayer[pos.z] or yLayer[tostring(pos.z)]
    if block == nil then
        return nil, "empty"
    end
    return block
end

local function ensurePointer(ctx)
    if type(ctx.pointer) == "table" then
        return ctx.pointer
    end
    local strategy = ctx.strategy
    if type(strategy) == "table" and type(strategy.order) == "table" then
        local idx = strategy.index or 1
        local pos = strategy.order[idx]
        if pos then
            ctx.pointer = copyPosition(pos)
            strategy.index = idx
            return ctx.pointer
        end
        return nil, "strategy_exhausted"
    end
    return nil, "no_pointer"
end

local function advancePointer(ctx)
    if type(ctx.strategy) == "table" then
        local strategy = ctx.strategy
        if type(strategy.advance) == "function" then
            local nextPos, doneFlag = strategy.advance(strategy, ctx)
            if nextPos then
                ctx.pointer = copyPosition(nextPos)
                return true
            end
            if doneFlag == false then
                return false
            end
            ctx.pointer = nil
            return false
        end
        if type(strategy.next) == "function" then
            local nextPos = strategy.next(strategy, ctx)
            if nextPos then
                ctx.pointer = copyPosition(nextPos)
                return true
            end
            ctx.pointer = nil
            return false
        end
        if type(strategy.order) == "table" then
            local idx = (strategy.index or 1) + 1
            strategy.index = idx
            local pos = strategy.order[idx]
            if pos then
                ctx.pointer = copyPosition(pos)
                return true
            end
            ctx.pointer = nil
            return false
        end
    elseif type(ctx.strategy) == "function" then
        local nextPos = ctx.strategy(ctx)
        if nextPos then
            ctx.pointer = copyPosition(nextPos)
            return true
        end
        ctx.pointer = nil
        return false
    end
    ctx.pointer = nil
    return false
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
    local cleared = false
    if allowDig and type(sideFns.dig) == "function" then
        cleared = sideFns.dig()
    end
    if not cleared and allowAttack and type(sideFns.attack) == "function" then
        cleared = sideFns.attack()
    end
    if cleared and type(sideFns.detect) == "function" then
        if sideFns.detect() then
            return false
        end
    end
    return cleared
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
    if blockPresent then
        if blockData and blockData.name == material then
            state.lastPlacement = { success = true, material = material, reused = true, side = side }
            return true, "already_present"
        end
        if not allowOverwrite then
            state.lastPlacement = { success = false, material = material, error = "occupied", side = side }
            return false, "occupied"
        end
        local cleared = clearBlockingBlock(sideFns, allowDig, allowAttack)
        if not cleared then
            state.lastPlacement = { success = false, material = material, error = "blocked", side = side }
            return false, "blocked"
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
            log(ctx, "debug", string.format("Place failed for %s: %s", material, placeErr))
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
    return advancePointer(ctx)
end

function placement.ensureState(ctx)
    return ensurePlacementState(ctx)
end

function placement.executeBuildState(ctx, opts)
    opts = opts or {}
    local state = ensurePlacementState(ctx)

    local pointer, pointerErr = ensurePointer(ctx)
    if not pointer then
        log(ctx, "debug", "No build pointer available: " .. tostring(pointerErr))
        return "DONE", { reason = pointerErr or "no_pointer" }
    end

    if isFuelLow(ctx) then
        state.resumeState = "BUILD"
        log(ctx, "info", "Fuel below threshold, switching to REFUEL")
        return "REFUEL", { reason = "fuel_low", pointer = copyPosition(pointer) }
    end

    local block, schemaErr = fetchSchemaEntry(ctx.schema, pointer)
    if not block then
        log(ctx, "debug", string.format("No schema entry at x=%d y=%d z=%d (%s)", pointer.x or 0, pointer.y or 0, pointer.z or 0, tostring(schemaErr)))
        local autoAdvance = opts.autoAdvance
        if autoAdvance == nil then
            autoAdvance = true
        end
        if autoAdvance then
            local advanced = placement.advancePointer(ctx)
            if advanced then
                return "BUILD", { reason = "skip_empty", pointer = copyPosition(ctx.pointer) }
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
                return "BUILD", { reason = "skip_air", pointer = copyPosition(ctx.pointer) }
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
            log(ctx, "warn", string.format("Need to restock %s", block.material))
            return "RESTOCK", {
                reason = err,
                material = block.material,
                pointer = copyPosition(pointer),
            }
        end
        if err == "blocked" then
            state.resumeState = "BUILD"
            log(ctx, "warn", "Placement blocked; invoking BLOCKED state")
            return "BLOCKED", {
                reason = err,
                pointer = copyPosition(pointer),
                material = block.material,
            }
        end
        if err == "turtle API unavailable" then
            state.lastError = err
            return "ERROR", { reason = err }
        end
        state.lastError = err
        log(ctx, "error", string.format("Placement failed for %s: %s", block.material, tostring(err)))
        return "ERROR", {
            reason = err,
            material = block.material,
            pointer = copyPosition(pointer),
        }
    end

    state.lastPlaced = {
        material = block.material,
        pointer = copyPosition(pointer),
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
            return "BUILD", { reason = "continue", pointer = copyPosition(ctx.pointer) }
        end
        return "DONE", { reason = "complete" }
    end

    return "BUILD", { reason = "await_pointer_update" }
end

return placement
