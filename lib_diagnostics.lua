--[[
Diagnostics helper for capturing context snapshots and guarded access.
--]]

local diagnostics = {}

local function safeOrigin(origin)
    if type(origin) ~= "table" then
        return nil
    end
    return {
        x = origin.x,
        y = origin.y,
        z = origin.z,
        facing = origin.facing
    }
end

local function normalizeStrategy(strategy)
    if type(strategy) == "table" then
        return strategy
    end
    return nil
end

local function snapshot(ctx)
    if type(ctx) ~= "table" then
        return { error = "missing context" }
    end
    local config = type(ctx.config) == "table" and ctx.config or {}
    local origin = safeOrigin(ctx.origin)
    local strategyLen = 0
    if type(ctx.strategy) == "table" then
        strategyLen = #ctx.strategy
    end
    local stamp
    if os and type(os.time) == "function" then
        stamp = os.time()
    end

    return {
        state = ctx.state,
        mode = config.mode,
        pointer = ctx.pointer,
        strategySize = strategyLen,
        retries = ctx.retries,
        missingMaterial = ctx.missingMaterial,
        lastError = ctx.lastError,
        origin = origin,
        timestamp = stamp
    }
end

local function requireStrategy(ctx)
    local strategy = normalizeStrategy(ctx.strategy)
    if strategy then
        return strategy
    end

    local message = "Build strategy unavailable"
    if ctx and ctx.logger then
        ctx.logger:error(message, { context = snapshot(ctx) })
    end
    ctx.lastError = ctx.lastError or message
    return nil, message
end

diagnostics.snapshot = snapshot
diagnostics.requireStrategy = requireStrategy

return diagnostics