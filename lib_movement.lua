--[[-
Movement library for CC:Tweaked turtles.
Provides orientation tracking, safe movement primitives, and navigation helpers.
All public functions accept a shared ctx table and return success booleans
with optional error messages.
--]]

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
        local cfg = ctx.config or {}
        state.homeFacing = canonicalFacing(cfg.homeFacing) or canonicalFacing(cfg.initialFacing) or "north"
    end

    if not state.facing then
        local cfg = ctx.config or {}
        state.facing = canonicalFacing(cfg.initialFacing) or state.homeFacing
    end

    state.position = copyPosition(state.position)

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
    local attempt = 0

    while attempt < maxRetries do
        attempt = attempt + 1
        if moveFns.move() then
            state.position = vecAdd(state.position, delta)
            log(ctx, "debug", string.format("Moved to x=%d y=%d z=%d", state.position.x, state.position.y, state.position.z))
            return true
        end

        local handled = false
        if moveFns.detect and moveFns.detect() then
            if allowDig and moveFns.dig then
                handled = moveFns.dig()
                if handled then
                    log(ctx, "debug", "Dug blocking block")
                end
            end
        else
            if allowAttack and moveFns.attack then
                handled = moveFns.attack()
                if handled then
                    log(ctx, "debug", "Attacked entity blocking movement")
                end
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
