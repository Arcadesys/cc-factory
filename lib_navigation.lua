--[[
Navigation library for CC:Tweaked turtles.
Resolves waypoint and route specs into concrete movement paths and wraps
movement helpers for higher-level states (restock, refuel, etc.).
All public functions accept the shared ctx table and return project-style
success booleans or data results with error diagnostics.
--]]

local okMovement, movement = pcall(require, "lib_movement")
if not okMovement then
    movement = nil
end
local logger = require("lib_logger")
local table_utils = require("lib_table")
local world = require("lib_world")

local navigation = {}

local function isCoordinateSpec(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    if tbl.route or tbl.waypoint or tbl.path or tbl.nodes or tbl.sequence or tbl.via or tbl.target or tbl.align then
        return false
    end
    local hasX = tbl.x ~= nil or tbl[1] ~= nil
    local hasY = tbl.y ~= nil or tbl[2] ~= nil
    local hasZ = tbl.z ~= nil or tbl[3] ~= nil
    return hasX and hasY and hasZ
end

local function cloneNodeDefinition(def)
    if type(def) ~= "table" then
        return nil, "invalid_route_definition"
    end
    local result = {}
    for index, value in ipairs(def) do
        if type(value) == "table" then
            result[index] = table_utils.copyValue(value)
        else
            result[index] = value
        end
    end
    return result
end

local function ensureNavigationState(ctx)
    if type(ctx) ~= "table" then
        error("navigation library requires a context table", 2)
    end

    if type(ctx.navigationState) ~= "table" then
        ctx.navigationState = ctx.navigation or {}
    end
    ctx.navigation = ctx.navigationState
    local state = ctx.navigationState

    state.waypoints = state.waypoints or {}
    state.routes = state.routes or {}
    state.restock = state.restock or {}
    state._configLoaded = state._configLoaded or false

    if ctx.origin then
        local originPos, originErr = world.normalisePosition(ctx.origin)
        if originPos then
            state.waypoints.origin = originPos
        elseif originErr then
            logger.log(ctx, "warn", "Origin position invalid: " .. tostring(originErr))
        end
    end

    if not state._configLoaded then
        state._configLoaded = true
        local cfg = ctx.config
        if type(cfg) == "table" and type(cfg.navigation) == "table" then
            local navCfg = cfg.navigation
            if type(navCfg.waypoints) == "table" then
                for name, pos in pairs(navCfg.waypoints) do
                    local normalised, err = world.normalisePosition(pos)
                    if normalised then
                        state.waypoints[name] = normalised
                    else
                        logger.log(ctx, "warn", string.format("Ignoring navigation waypoint '%s': %s", tostring(name), tostring(err)))
                    end
                end
            end
            if type(navCfg.routes) == "table" then
                for name, def in pairs(navCfg.routes) do
                    local cloned, err = cloneNodeDefinition(def)
                    if cloned then
                        state.routes[name] = cloned
                    else
                        logger.log(ctx, "warn", string.format("Ignoring navigation route '%s': %s", tostring(name), tostring(err)))
                    end
                end
            end
            if type(navCfg.restock) == "table" then
                state.restock = table_utils.copyValue(navCfg.restock)
            end
        end
    end

    return state
end

local function resolveWaypoint(ctx, name)
    local state = ensureNavigationState(ctx)
    if type(name) ~= "string" or name == "" then
        return nil, "invalid_waypoint"
    end
    local pos = state.waypoints[name]
    if not pos then
        return nil, "unknown_waypoint"
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local expandSpec

local function expandListToNodes(ctx, list, visited)
    if type(list) ~= "table" then
        return nil, "invalid_path_list"
    end
    local nodes = {}
    local meta = {}
    for index, entry in ipairs(list) do
        local entryNodes, entryMeta = expandSpec(ctx, entry, visited)
        if not entryNodes then
            return nil, string.format("path[%d]: %s", index, tostring(entryMeta or "invalid"))
        end
        for _, node in ipairs(entryNodes) do
            nodes[#nodes + 1] = node
        end
        if entryMeta and entryMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = entryMeta.finalFacing
        end
    end
    return nodes, meta
end

local function expandRouteByName(ctx, name, visited)
    if type(name) ~= "string" or name == "" then
        return nil, "invalid_route_name"
    end
    local state = ensureNavigationState(ctx)
    local def = state.routes[name]
    if not def then
        return nil, "unknown_route"
    end
    visited = visited or {}
    if visited[name] then
        return nil, "route_cycle"
    end
    visited[name] = true
    local nodes, meta = expandListToNodes(ctx, def, visited)
    visited[name] = nil
    return nodes, meta
end

-- Expands a navigation spec (string, waypoint, route, or nested table) into absolute coordinates.
function expandSpec(ctx, spec, visited)
    local specType = type(spec)
    if specType == "string" then
        local routeNodes, routeMeta = expandRouteByName(ctx, spec, visited)
        if routeNodes then
            return routeNodes, routeMeta
        end
        if routeMeta ~= "unknown_route" then
            return nil, routeMeta
        end
        local pos, err = resolveWaypoint(ctx, spec)
        if not pos then
            return nil, err or "unknown_reference"
        end
        return { pos }, {}
    elseif specType == "function" then
        local ok, result = pcall(spec, ctx)
        if not ok then
            return nil, "navigation_callback_failed"
        end
        if result == nil then
            return {}, {}
        end
        return expandSpec(ctx, result, visited)
    elseif specType ~= "table" then
        return nil, "invalid_navigation_spec"
    end

    if isCoordinateSpec(spec) then
        local pos, err = world.normalisePosition(spec)
        if not pos then
            return nil, err
        end
        local meta = {}
        if spec.finalFacing or spec.facing then
            meta.finalFacing = spec.finalFacing or spec.facing
        end
        return { pos }, meta
    end

    local nodes = {}
    local meta = {}
    local facing = spec.finalFacing or spec.facing
    if facing then
        meta.finalFacing = facing
    end

    if spec.sequence then
        local seqNodes, seqMeta = expandListToNodes(ctx, spec.sequence, visited)
        if not seqNodes then
            return nil, seqMeta
        end
        for _, node in ipairs(seqNodes) do
            nodes[#nodes + 1] = node
        end
        if seqMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = seqMeta.finalFacing
        end
    end

    if spec.via then
        local viaNodes, viaMeta = expandListToNodes(ctx, spec.via, visited)
        if not viaNodes then
            return nil, viaMeta
        end
        for _, node in ipairs(viaNodes) do
            nodes[#nodes + 1] = node
        end
        if viaMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = viaMeta.finalFacing
        end
    end

    if spec.path then
        local pathNodes, pathMeta = expandListToNodes(ctx, spec.path, visited)
        if not pathNodes then
            return nil, pathMeta
        end
        for _, node in ipairs(pathNodes) do
            nodes[#nodes + 1] = node
        end
        if pathMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = pathMeta.finalFacing
        end
    elseif spec.nodes then
        local pathNodes, pathMeta = expandListToNodes(ctx, spec.nodes, visited)
        if not pathNodes then
            return nil, pathMeta
        end
        for _, node in ipairs(pathNodes) do
            nodes[#nodes + 1] = node
        end
        if pathMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = pathMeta.finalFacing
        end
    end

    if spec.route then
        if type(spec.route) == "table" then
            local routeNodes, routeMeta = expandListToNodes(ctx, spec.route, visited)
            if not routeNodes then
                return nil, routeMeta
            end
            for _, node in ipairs(routeNodes) do
                nodes[#nodes + 1] = node
            end
            if routeMeta.finalFacing and not meta.finalFacing then
                meta.finalFacing = routeMeta.finalFacing
            end
        else
            local routeNodes, routeMeta = expandRouteByName(ctx, spec.route, visited)
            if not routeNodes then
                return nil, routeMeta
            end
            for _, node in ipairs(routeNodes) do
                nodes[#nodes + 1] = node
            end
            if routeMeta and routeMeta.finalFacing and not meta.finalFacing then
                meta.finalFacing = routeMeta.finalFacing
            end
        end
    end

    if spec.waypoint then
        local pos, err = resolveWaypoint(ctx, spec.waypoint)
        if not pos then
            return nil, err
        end
        nodes[#nodes + 1] = pos
    end

    if spec.position then
        local pos, err = world.normalisePosition(spec.position)
        if not pos then
            return nil, err
        end
        nodes[#nodes + 1] = pos
    end

    if spec.target then
        local targetNodes, targetMeta = expandSpec(ctx, spec.target, visited)
        if not targetNodes then
            return nil, targetMeta
        end
        for _, node in ipairs(targetNodes) do
            nodes[#nodes + 1] = node
        end
        if targetMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = targetMeta.finalFacing
        end
    end

    if spec.align then
        local alignNodes, alignMeta = expandSpec(ctx, spec.align, visited)
        if not alignNodes then
            return nil, alignMeta
        end
        for _, node in ipairs(alignNodes) do
            nodes[#nodes + 1] = node
        end
        if alignMeta.finalFacing then
            meta.finalFacing = alignMeta.finalFacing
        end
    end

    return nodes, meta
end

function navigation.ensureState(ctx)
    return ensureNavigationState(ctx)
end

function navigation.registerWaypoint(ctx, name, position)
    if type(name) ~= "string" or name == "" then
        return false, "invalid_waypoint_name"
    end
    local state = ensureNavigationState(ctx)
    local pos, err = world.normalisePosition(position)
    if not pos then
        return false, err or "invalid_position"
    end
    state.waypoints[name] = pos
    return true
end

function navigation.getWaypoint(ctx, name)
    return resolveWaypoint(ctx, name)
end

function navigation.listWaypoints(ctx)
    local state = ensureNavigationState(ctx)
    local result = {}
    for name, pos in pairs(state.waypoints) do
        result[name] = { x = pos.x, y = pos.y, z = pos.z }
    end
    return result
end

function navigation.registerRoute(ctx, name, nodes)
    if type(name) ~= "string" or name == "" then
        return false, "invalid_route_name"
    end
    local state = ensureNavigationState(ctx)
    local cloned, err = cloneNodeDefinition(nodes)
    if not cloned then
        return false, err or "invalid_route"
    end
    state.routes[name] = cloned
    return true
end

function navigation.getRoute(ctx, name)
    local nodes, meta = expandRouteByName(ctx, name, {})
    if not nodes then
        return nil, meta
    end
    return nodes, meta
end

function navigation.plan(ctx, targetSpec, opts)
    ensureNavigationState(ctx)
    if targetSpec == nil then
        return nil, "missing_target"
    end
    local nodes, meta = expandSpec(ctx, targetSpec, {})
    if not nodes then
        return nil, meta
    end
    if opts and opts.includeCurrent == false and #nodes > 0 then
        -- no-op placeholder for future options
    end
    return nodes, meta
end

local function resolveRestockSpec(ctx, kind)
    local state = ensureNavigationState(ctx)
    local restock = state.restock
    local spec
    if type(restock) == "table" then
        if kind and restock[kind] ~= nil then
            spec = restock[kind]
        elseif restock.default ~= nil then
            spec = restock.default
        elseif restock.fallback ~= nil then
            spec = restock.fallback
        end
    end
    if spec == nil and state.waypoints.restock then
        spec = state.waypoints.restock
    end
    if spec == nil and state.waypoints.origin then
        spec = state.waypoints.origin
    end
    if spec == nil then
        return nil
    end
    return table_utils.copyValue(spec)
end

function navigation.getRestockTarget(ctx, kind)
    local spec = resolveRestockSpec(ctx, kind)
    if spec == nil then
        return nil, "restock_target_missing"
    end
    return spec
end

function navigation.setRestockTarget(ctx, kind, spec)
    local state = ensureNavigationState(ctx)
    if type(kind) ~= "string" or kind == "" then
        kind = "default"
    end
    if spec == nil then
        state.restock[kind] = nil
        return true
    end
    local specType = type(spec)
    if specType ~= "string" and specType ~= "table" and specType ~= "function" then
        return false, "invalid_restock_spec"
    end
    state.restock[kind] = table_utils.copyValue(spec)
    return true
end

function navigation.planRestock(ctx, opts)
    local kind = nil
    if type(opts) == "table" then
        kind = opts.kind or opts.type or opts.category
    end
    local spec = resolveRestockSpec(ctx, kind)
    if spec == nil then
        return nil, "restock_target_missing"
    end
    local nodes, meta = navigation.plan(ctx, spec, opts)
    if not nodes then
        return nil, meta
    end
    return nodes, meta
end

function navigation.travel(ctx, targetSpec, opts)
    ensureNavigationState(ctx)
    if not movement then
        return false, "movement_library_unavailable"
    end
    local nodes, meta = navigation.plan(ctx, targetSpec, opts)
    if not nodes then
        return false, meta
    end
    movement.ensureState(ctx)
    if #nodes > 0 then
        local moveOpts = opts and opts.move
        local ok, err = movement.stepPath(ctx, nodes, moveOpts)
        if not ok then
            return false, err
        end
    end
    local finalFacing = (opts and opts.finalFacing) or (meta and meta.finalFacing)
    if finalFacing then
        local ok, err = movement.faceDirection(ctx, finalFacing)
        if not ok then
            return false, err
        end
    end
    return true
end

function navigation.travelToRestock(ctx, opts)
    local kind = nil
    if type(opts) == "table" then
        kind = opts.kind or opts.type or opts.category
    end
    local spec, err = navigation.getRestockTarget(ctx, kind)
    if not spec then
        return false, err
    end
    return navigation.travel(ctx, spec, opts)
end

return navigation
