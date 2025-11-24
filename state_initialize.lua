--[[
State: INITIALIZE
Loads schema, parses it, and computes the build strategy.
--]]

local parser = require("lib_parser")
local orientation = require("lib_orientation")
local logger = require("lib_logger")
local strategyBranchMine = require("lib_strategy_branchmine")
local strategyFarm = require("lib_strategy_farm")
local ui = require("lib_ui")

local function getBlock(schema, x, y, z)
    local xLayer = schema[x] or schema[tostring(x)]
    if not xLayer then return nil end
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if not yLayer then return nil end
    return yLayer[z] or yLayer[tostring(z)]
end

local function isPlaceable(block)
    if not block then return false end
    local name = block.material
    if not name or name == "" then return false end
    if name == "minecraft:air" or name == "air" then return false end
    return true
end

local function computeApproachLocal(localPos, side)
    side = side or "down"
    if side == "up" then
        return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
    elseif side == "down" then
        return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
    else
        return { x = localPos.x, y = localPos.y, z = localPos.z }, side
    end
end

local function computeLocalXZ(bounds, x, z, orientationKey)
    local orient = orientation.resolveOrientationKey(orientationKey)
    local relativeX = x - bounds.minX
    local relativeZ = z - bounds.minZ
    local localZ = - (relativeZ + 1)
    local localX
    if orient == "forward_right" then
        localX = relativeX + 1
    else
        localX = - (relativeX + 1)
    end
    return localX, localZ
end

local function normaliseBounds(info)
    if not info or not info.bounds then return nil, "missing_bounds" end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    if not (minB and maxB) then return nil, "missing_bounds" end
    
    local function norm(t, k) return tonumber(t[k]) end
    
    return {
        minX = norm(minB, "x") or 0,
        minY = norm(minB, "y") or 0,
        minZ = norm(minB, "z") or 0,
        maxX = norm(maxB, "x") or 0,
        maxY = norm(maxB, "y") or 0,
        maxZ = norm(maxB, "z") or 0,
    }
end

local function buildOrder(schema, info, opts)
    local bounds, err = normaliseBounds(info)
    if not bounds then return nil, err or "missing_bounds" end
    
    opts = opts or {}
    local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    local offsetXLocal = offsetLocal.x or 0
    local offsetYLocal = offsetLocal.y or 0
    local offsetZLocal = offsetLocal.z or 0
    
    -- Default to forward_left if not specified
    local orientKey = opts.orientation or "forward_left"

    local order = {}
    for y = bounds.minY, bounds.maxY do
        for row = 0, bounds.maxZ - bounds.minZ do
            local z = bounds.minZ + row
            local forward = (row % 2) == 0
            local xStart = forward and bounds.minX or bounds.maxX
            local xEnd = forward and bounds.maxX or bounds.minX
            local step = forward and 1 or -1
            local x = xStart
            while true do
                local block = getBlock(schema, x, y, z)
                if isPlaceable(block) then
                    local baseX, baseZ = computeLocalXZ(bounds, x, z, orientKey)
                    local localPos = {
                        x = baseX + offsetXLocal,
                        y = y + offsetYLocal,
                        z = baseZ + offsetZLocal,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproachLocal(localPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        localPos = localPos,
                        approachLocal = approach,
                        block = block,
                        side = resolvedSide,
                    }
                end
                if x == xEnd then break end
                x = x + step
            end
        end
    end
    return order, bounds
end

local function INITIALIZE(ctx)
    logger.log(ctx, "info", "Initializing...")
    
    if ctx.config.mode == "mine" then
        logger.log(ctx, "info", "Generating mining strategy...")
        local length = tonumber(ctx.config.length) or 60
        local branchInterval = tonumber(ctx.config.branchInterval) or 3
        local branchLength = tonumber(ctx.config.branchLength) or 16
        local torchInterval = tonumber(ctx.config.torchInterval) or 6
        
        ctx.strategy = strategyBranchMine.generate(length, branchInterval, branchLength, torchInterval)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Mining Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "farm" then
        logger.log(ctx, "info", "Generating farm strategy...")
        local farmType = ctx.config.farmType or "tree"
        local width = tonumber(ctx.config.width) or 9
        local length = tonumber(ctx.config.length) or 9
        
        local schema = strategyFarm.generate(farmType, width, length)
        
        -- Preview
        ui.clear()
        ui.drawPreview(schema, 2, 2, 30, 15)
        term.setCursorPos(1, 18)
        print("Previewing " .. farmType .. " farm.")
        print("Press Enter to confirm, 'q' to quit.")
        local input = read()
        if input == "q" or input == "Q" then
            return "DONE"
        end
        
        -- Normalize schema for buildOrder
        -- We need to calculate bounds manually since we don't have parser info
        local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
        local minY, maxY = 0, 1 -- Assuming 2 layers for now
        
        for sx, row in pairs(schema) do
            local nx = tonumber(sx)
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz < minZ then minZ = nz end
                    if nz > maxZ then maxZ = nz end
                end
            end
        end
        
        ctx.schema = schema
        ctx.schemaInfo = {
            bounds = {
                min = { x = minX, y = minY, z = minZ },
                max = { x = maxX, y = maxY, z = maxZ }
            }
        }
        
        logger.log(ctx, "info", "Computing build strategy...")
        local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
        if not order then
            ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
            return "ERROR"
        end

        ctx.strategy = order
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
        ctx.nextState = "BUILD"
        return "CHECK_REQUIREMENTS"
    end
    
    if not ctx.config.schemaPath then
        ctx.lastError = "No schema path provided"
        return "ERROR"
    end

    logger.log(ctx, "info", "Loading schema: " .. ctx.config.schemaPath)
    local ok, schemaOrErr, info = parser.parseFile(ctx, ctx.config.schemaPath, { formatHint = nil })
    if not ok then
        ctx.lastError = "Failed to parse schema: " .. tostring(schemaOrErr)
        return "ERROR"
    end

    ctx.schema = schemaOrErr
    ctx.schemaInfo = info

    logger.log(ctx, "info", "Computing build strategy...")
    local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
    if not order then
        ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
        return "ERROR"
    end

    ctx.strategy = order
    ctx.pointer = 1
    
    logger.log(ctx, "info", string.format("Plan: %d steps.", #order))

    ctx.nextState = "BUILD"
    return "CHECK_REQUIREMENTS"
end

return INITIALIZE
