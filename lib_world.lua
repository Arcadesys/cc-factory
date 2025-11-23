local world = {}

function world.getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local SIDE_ALIASES = {
    forward = "forward",
    front = "forward",
    down = "down",
    bottom = "down",
    up = "up",
    top = "up",
    left = "left",
    right = "right",
    back = "back",
    behind = "back",
}

function world.normaliseSide(side)
    if type(side) ~= "string" then
        return nil
    end
    return SIDE_ALIASES[string.lower(side)]
end

function world.toPeripheralSide(side)
    local normalised = world.normaliseSide(side) or side
    if normalised == "forward" then
        return "front"
    elseif normalised == "up" then
        return "top"
    elseif normalised == "down" then
        return "bottom"
    elseif normalised == "back" then
        return "back"
    elseif normalised == "left" then
        return "left"
    elseif normalised == "right" then
        return "right"
    end
    return normalised
end

function world.inspectSide(side)
    local normalised = world.normaliseSide(side)
    if normalised == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif normalised == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif normalised == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

function world.isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

function world.normalizeSide(value)
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

function world.resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = world.normalizeSide(opts)
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

    local normalised = world.normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

function world.isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return world.hasContainerTag(tags)
end

function world.inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.peripheralSideForDirection(side)
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

function world.computePrimaryPushDirection(ctx, periphSide)
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
endfunction world.normaliseCoordinate(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function world.normalisePosition(pos)
    if type(pos) ~= "table" then
        return nil, "invalid_position"
    end
    local xRaw = pos.x
    if xRaw == nil then
        xRaw = pos[1]
    end
    local yRaw = pos.y
    if yRaw == nil then
        yRaw = pos[2]
    end
    local zRaw = pos.z
    if zRaw == nil then
        zRaw = pos[3]
    end
    local x = world.normaliseCoordinate(xRaw)
    local y = world.normaliseCoordinate(yRaw)
    local z = world.normaliseCoordinate(zRaw)
    if not x or not y or not z then
        return nil, "invalid_position"
    end
    return { x = x, y = y, z = z }
endfunction world.normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

function world.facingVectors(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
function world.rotateLocalOffset(localOffset, facing)
    local vectors = world.facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * (-dz)),
        z = (right.z * dx) + (forward.z * (-dz)),
    }
endfunction world.localToWorld(localOffset, facing)
    facing = world.normaliseFacing(facing)
    local dx = localOffset and localOffset.x or 0
    local dz = localOffset and localOffset.z or 0
    local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
    return {
        x = rotated.x,
        y = localOffset and localOffset.y or 0,
        z = rotated.z,
    }
end
function world.copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

return world
