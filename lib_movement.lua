--[[-
Movement library for CC:Tweaked turtles.
Provides orientation tracking, safe movement primitives, and navigation helpers.
All public functions accept a shared ctx table and return success booleans
with optional error messages.
--]]

---@diagnostic disable: undefined-global, undefined-field

local movement = {}

local CARDINALS = {"north", "east", "south", "west"}
local DIRECTION_VECTORS = {
    north = { x = 0, y = 0, z = -1 },
    east = { x = 1, y = 0, z = 0 },
    south = { x = 0, y = 0, z = 1 },
    west = { x = -1, y = 0, z = 0 },
}

local AXIS_FACINGS = {
    x = { positive = "east", negative = "west" },
    z = { positive = "south", negative = "north" },
}

local DEFAULT_SOFT_BLOCKS = {
    ["minecraft:snow"] = true,
    ["minecraft:snow_layer"] = true,
    ["minecraft:powder_snow"] = true,
    ["minecraft:tall_grass"] = true,
    ["minecraft:large_fern"] = true,
    ["minecraft:grass"] = true,
    ["minecraft:fern"] = true,
    ["minecraft:cave_vines"] = true,
    ["minecraft:cave_vines_plant"] = true,
    ["minecraft:kelp"] = true,
    ["minecraft:kelp_plant"] = true,
    ["minecraft:sweet_berry_bush"] = true,
}

local DEFAULT_SOFT_TAGS = {
    ["minecraft:snow"] = true,
    ["minecraft:replaceable_plants"] = true,
    ["minecraft:flowers"] = true,
    ["minecraft:saplings"] = true,
    ["minecraft:carpets"] = true,
}

local DEFAULT_SOFT_NAME_HINTS = {
    "sapling",
    "propagule",
    "seedling",
}

local function cloneLookup(source)
    local lookup = {}
    for key, value in pairs(source) do
        if value then
            lookup[key] = true
        end
    end
    return lookup
end

local function extendLookup(lookup, entries)
    if type(entries) ~= "table" then
        return lookup
    end
    if #entries > 0 then
        for _, name in ipairs(entries) do
            if type(name) == "string" then
                lookup[name] = true
            end
        end
    else
        for name, enabled in pairs(entries) do
            if enabled and type(name) == "string" then
                lookup[name] = true
            end
        end
    end
    return lookup
end

local function buildSoftNameHintList(configHints)
    local seen = {}
    local list = {}

    local function append(value)
        if type(value) ~= "string" then
            return
        end
        local normalized = value:lower()
        if normalized == "" or seen[normalized] then
            return
        end
        seen[normalized] = true
        list[#list + 1] = normalized
    end

    for _, hint in ipairs(DEFAULT_SOFT_NAME_HINTS) do
        append(hint)
    end

    if type(configHints) == "table" then
        if #configHints > 0 then
            for _, entry in ipairs(configHints) do
                append(entry)
            end
        else
            for name, enabled in pairs(configHints) do
                if enabled then
                    append(name)
                end
            end
        end
    elseif type(configHints) == "string" then
        append(configHints)
    end

    return list
end

local function matchesSoftNameHint(hints, blockName)
    if type(blockName) ~= "string" then
        return false
    end
    local lowered = blockName:lower()
    for _, hint in ipairs(hints or {}) do
        if lowered:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function isSoftBlock(state, inspectData)
    if type(state) ~= "table" or type(inspectData) ~= "table" then
        return false
    end
    local name = inspectData.name
    if type(name) == "string" then
        if state.softBlockLookup and state.softBlockLookup[name] then
            return true
        end
        if matchesSoftNameHint(state.softNameHints, name) then
            return true
        end
    end
    local tags = inspectData.tags
    if type(tags) == "table" and state.softTagLookup then
        for tag, value in pairs(tags) do
            if value and state.softTagLookup[tag] then
                return true
            end
        end
    end
    return false
end

local function canonicalFacing(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:lower()
    if DIRECTION_VECTORS[name] then
        return name
    end
    return nil
end

local function copyPosition(pos)
    if not pos then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

local function vecAdd(a, b)
    return { x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0), z = (a.z or 0) + (b.z or 0) }
end

local function getPlannedMaterial(ctx, pos)
    if type(ctx) ~= "table" or type(pos) ~= "table" then
        return nil
    end

    local plan = ctx.buildPlan
    if type(plan) ~= "table" then
        return nil
    end

    local x = pos.x
    local xLayer = plan[x] or plan[tostring(x)]
    if type(xLayer) ~= "table" then
        return nil
    end

    local y = pos.y
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if type(yLayer) ~= "table" then
        return nil
    end

    local z = pos.z
    return yLayer[z] or yLayer[tostring(z)]
end

local function tryInspect(inspectFn)
    if type(inspectFn) ~= "function" then
        return nil
    end

    local ok, success, data = pcall(inspectFn)
    if not ok or not success then
        return nil
    end

    if type(data) == "table" then
        return data
    end

    return nil
end

local function log(ctx, level, message)
    if not ctx then
        return
    end
    local logger = ctx.logger
    if not logger then
        return
    end

    if type(logger[level]) == "function" then
        logger[level](message)
    elseif type(logger.log) == "function" then
        logger.log(level, message)
    end
end

local function ensureMovementState(ctx)
    if type(ctx) ~= "table" then
        error("movement library requires a context table", 2)
    end

    ctx.movement = ctx.movement or {}
    local state = ctx.movement
    local cfg = ctx.config or {}

    if not state.position then
        if ctx.pointer then
            state.position = copyPosition(ctx.pointer)
        elseif ctx.origin then
            state.position = copyPosition(ctx.origin)
        else
            state.position = { x = 0, y = 0, z = 0 }
        end
    end

    if not state.homeFacing then
        state.homeFacing = canonicalFacing(cfg.homeFacing) or canonicalFacing(cfg.initialFacing) or "north"
    end

    if not state.facing then
        state.facing = canonicalFacing(cfg.initialFacing) or state.homeFacing
    end

    state.position = copyPosition(state.position)

    if not state.softBlockLookup then
        state.softBlockLookup = extendLookup(cloneLookup(DEFAULT_SOFT_BLOCKS), cfg.movementSoftBlocks)
    end
    if not state.softTagLookup then
        state.softTagLookup = extendLookup(cloneLookup(DEFAULT_SOFT_TAGS), cfg.movementSoftTags)
    end
    if not state.softNameHints then
        state.softNameHints = buildSoftNameHintList(cfg.movementSoftNameHints)
    end
    state.hasSoftClearRules = (next(state.softBlockLookup) ~= nil)
        or (next(state.softTagLookup) ~= nil)
        or ((state.softNameHints and #state.softNameHints > 0) or false)

    return state
end

function movement.ensureState(ctx)
    return ensureMovementState(ctx)
end

function movement.getPosition(ctx)
    local state = ensureMovementState(ctx)
    return copyPosition(state.position)
end

function movement.setPosition(ctx, pos)
    local state = ensureMovementState(ctx)
    state.position = copyPosition(pos)
    return true
end

function movement.getFacing(ctx)
    local state = ensureMovementState(ctx)
    return state.facing
end

function movement.setFacing(ctx, facing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(facing)
    if not canonical then
        return false, "unknown facing: " .. tostring(facing)
    end
    state.facing = canonical
    log(ctx, "debug", "Set facing to " .. canonical)
    return true
end

local function turn(ctx, direction)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local rotateFn
    if direction == "left" then
        rotateFn = turtle.turnLeft
    elseif direction == "right" then
        rotateFn = turtle.turnRight
    else
        return false, "invalid turn direction"
    end

    if not rotateFn then
        return false, "turn function missing"
    end

    local ok = rotateFn()
    if not ok then
        return false, "turn " .. direction .. " failed"
    end

    local current = state.facing
    local index
    for i, name in ipairs(CARDINALS) do
        if name == current then
            index = i
            break
        end
    end
    if not index then
        index = 1
        current = CARDINALS[index]
    end

    if direction == "left" then
        index = ((index - 2) % #CARDINALS) + 1
    else
        index = (index % #CARDINALS) + 1
    end

    state.facing = CARDINALS[index]
    log(ctx, "debug", "Turned " .. direction .. ", now facing " .. state.facing)
    return true
end

function movement.turnLeft(ctx)
    return turn(ctx, "left")
end

function movement.turnRight(ctx)
    return turn(ctx, "right")
end

function movement.turnAround(ctx)
    local ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    return true
end

function movement.faceDirection(ctx, targetFacing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(targetFacing)
    if not canonical then
        return false, "unknown facing: " .. tostring(targetFacing)
    end

    local currentIndex
    local targetIndex
    for i, name in ipairs(CARDINALS) do
        if name == state.facing then
            currentIndex = i
        end
        if name == canonical then
            targetIndex = i
        end
    end

    if not targetIndex then
        return false, "cannot face unknown cardinal"
    end

    if currentIndex == targetIndex then
        return true
    end

    if not currentIndex then
        state.facing = canonical
        return true
    end

    local diff = (targetIndex - currentIndex) % #CARDINALS
    if diff == 0 then
        return true
    elseif diff == 1 then
        return movement.turnRight(ctx)
    elseif diff == 2 then
        local ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        return true
    else -- diff == 3
        return movement.turnLeft(ctx)
    end
end

local function getMoveConfig(ctx, opts)
    local cfg = ctx.config or {}
    local maxRetries = (opts and opts.maxRetries) or cfg.maxMoveRetries or 5
    local allowDig = opts and opts.dig
    if allowDig == nil then
        allowDig = cfg.digOnMove
        if allowDig == nil then
            allowDig = true
        end
    end
    local allowAttack = opts and opts.attack
    if allowAttack == nil then
        allowAttack = cfg.attackOnMove
        if allowAttack == nil then
            allowAttack = true
        end
    end
    local delay = (opts and opts.retryDelay) or cfg.moveRetryDelay or 0.5
    return maxRetries, allowDig, allowAttack, delay
end

local function moveWithRetries(ctx, opts, moveFns, delta)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local maxRetries, allowDig, allowAttack, delay = getMoveConfig(ctx, opts)
    if type(maxRetries) ~= "number" or maxRetries < 1 then
        maxRetries = 1
    else
        maxRetries = math.floor(maxRetries)
    end
    if (allowDig or state.hasSoftClearRules) and maxRetries < 2 then
        -- Ensure we attempt at least two cycles whenever we might clear obstructions.
        maxRetries = 2
    end
    local attempt = 0

    while attempt < maxRetries do
        attempt = attempt + 1
        local targetPos = vecAdd(state.position, delta)

        if moveFns.move() then
            state.position = targetPos
            log(ctx, "debug", string.format("Moved to x=%d y=%d z=%d", state.position.x, state.position.y, state.position.z))
            return true
        end

        local handled = false

        if allowAttack and moveFns.attack then
            if moveFns.attack() then
                handled = true
                log(ctx, "debug", "Attacked entity blocking movement")
            end
        end

        local blocked = moveFns.detect and moveFns.detect() or false
        local inspectData
        if blocked then
            inspectData = tryInspect(moveFns.inspect)
        end

        if blocked and moveFns.dig then
            local plannedMaterial
            local canClear = false
            local softBlock = inspectData and isSoftBlock(state, inspectData)

            if softBlock then
                canClear = true
            elseif allowDig then
                plannedMaterial = getPlannedMaterial(ctx, targetPos)
                canClear = true

                if plannedMaterial then
                    if inspectData and inspectData.name then
                        if inspectData.name == plannedMaterial then
                            canClear = false
                        end
                    else
                        canClear = false
                    end
                end
            end

            if canClear and moveFns.dig() then
                handled = true
                if softBlock then
                    local foundName = inspectData and inspectData.name or "unknown"
                    log(ctx, "debug", string.format(
                        "Cleared soft obstruction %s at x=%d y=%d z=%d",
                        tostring(foundName),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                elseif plannedMaterial then
                    local foundName = inspectData and inspectData.name or "unknown"
                    log(ctx, "debug", string.format(
                        "Cleared mismatched block %s (expected %s) at x=%d y=%d z=%d",
                        tostring(foundName),
                        tostring(plannedMaterial),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                else
                    local foundName = inspectData and inspectData.name
                    if foundName then
                        log(ctx, "debug", string.format(
                            "Dug blocking block %s at x=%d y=%d z=%d",
                            foundName,
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    else
                        log(ctx, "debug", string.format(
                            "Dug blocking block at x=%d y=%d z=%d",
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    end
                end
            elseif plannedMaterial and not canClear and allowDig then
                log(ctx, "debug", string.format(
                    "Preserving planned block %s at x=%d y=%d z=%d",
                    tostring(plannedMaterial),
                    targetPos.x or 0,
                    targetPos.y or 0,
                    targetPos.z or 0
                ))
            end
        end

        if attempt < maxRetries then
            if delay and delay > 0 and _G.sleep then
                sleep(delay)
            end
        end
    end

    local axisDelta = string.format("(dx=%d, dy=%d, dz=%d)", delta.x or 0, delta.y or 0, delta.z or 0)
    return false, "unable to move " .. axisDelta .. " after " .. tostring(maxRetries) .. " attempts"
end

function movement.forward(ctx, opts)
    local state = ensureMovementState(ctx)
    local facing = state.facing or "north"
    local delta = copyPosition(DIRECTION_VECTORS[facing])

    local moveFns = {
        move = turtle and turtle.forward or nil,
        detect = turtle and turtle.detect or nil,
        dig = turtle and turtle.dig or nil,
        attack = turtle and turtle.attack or nil,
        inspect = turtle and turtle.inspect or nil,
    }

    if not moveFns.move then
        return false, "turtle API unavailable"
    end

    return moveWithRetries(ctx, opts, moveFns, delta)
end

function movement.up(ctx, opts)
    local moveFns = {
        move = turtle and turtle.up or nil,
        detect = turtle and turtle.detectUp or nil,
        dig = turtle and turtle.digUp or nil,
        attack = turtle and turtle.attackUp or nil,
        inspect = turtle and turtle.inspectUp or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = 1, z = 0 })
end

function movement.down(ctx, opts)
    local moveFns = {
        move = turtle and turtle.down or nil,
        detect = turtle and turtle.detectDown or nil,
        dig = turtle and turtle.digDown or nil,
        attack = turtle and turtle.attackDown or nil,
        inspect = turtle and turtle.inspectDown or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = -1, z = 0 })
end

local function axisFacing(axis, delta)
    if delta > 0 then
        return AXIS_FACINGS[axis].positive
    else
        return AXIS_FACINGS[axis].negative
    end
end

local function moveAxis(ctx, axis, delta, opts)
    if delta == 0 then
        return true
    end

    if axis == "y" then
        local moveFn = delta > 0 and movement.up or movement.down
        for _ = 1, math.abs(delta) do
            local ok, err = moveFn(ctx, opts)
            if not ok then
                return false, err
            end
        end
        return true
    end

    local targetFacing = axisFacing(axis, delta)
    local ok, err = movement.faceDirection(ctx, targetFacing)
    if not ok then
        return false, err
    end

    for step = 1, math.abs(delta) do
        ok, err = movement.forward(ctx, opts)
        if not ok then
            return false, string.format("failed moving along %s on step %d: %s", axis, step, err or "unknown")
        end
    end
    return true
end

function movement.goTo(ctx, targetPos, opts)
    ensureMovementState(ctx)
    if type(targetPos) ~= "table" then
        return false, "target position must be a table"
    end

    local state = ctx.movement
    local axisOrder = (opts and opts.axisOrder) or (ctx.config and ctx.config.movementAxisOrder) or { "x", "z", "y" }

    for _, axis in ipairs(axisOrder) do
        local desired = targetPos[axis]
        if desired == nil then
            return false, "target position missing axis " .. axis
        end
        local delta = desired - (state.position[axis] or 0)
        local ok, err = moveAxis(ctx, axis, delta, opts)
        if not ok then
            return false, err
        end
    end

    return true
end

function movement.stepPath(ctx, pathNodes, opts)
    if type(pathNodes) ~= "table" then
        return false, "pathNodes must be a table"
    end

    for index, node in ipairs(pathNodes) do
        local ok, err = movement.goTo(ctx, node, opts)
        if not ok then
            return false, string.format("failed at path node %d: %s", index, err or "unknown")
        end
    end

    return true
end

function movement.returnToOrigin(ctx, opts)
    ensureMovementState(ctx)
    if not ctx.origin then
        return false, "ctx.origin is required"
    end

    local ok, err = movement.goTo(ctx, ctx.origin, opts)
    if not ok then
        return false, err
    end

    local desiredFacing = (opts and opts.facing) or ctx.movement.homeFacing
    if desiredFacing then
        ok, err = movement.faceDirection(ctx, desiredFacing)
        if not ok then
            return false, err
        end
    end

    return true
end

return movement
