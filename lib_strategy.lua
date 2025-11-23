--[[
Strategy library for CC:Tweaked turtles.
Provides helpers for managing build strategies.
--]]

---@diagnostic disable: undefined-global

local strategy_utils = {}

local world = require("lib_world")

function strategy_utils.ensurePointer(ctx)
    if type(ctx.pointer) == "table" then
        return ctx.pointer
    end
    local strategy = ctx.strategy
    if type(strategy) == "table" and type(strategy.order) == "table" then
        local idx = strategy.index or 1
        local pos = strategy.order[idx]
        if pos then
            ctx.pointer = world.copyPosition(pos)
            strategy.index = idx
            return ctx.pointer
        end
        return nil, "strategy_exhausted"
    end
    return nil, "no_pointer"
end

function strategy_utils.advancePointer(ctx)
    if type(ctx.strategy) == "table" then
        local strategy = ctx.strategy
        if type(strategy.advance) == "function" then
            local nextPos, doneFlag = strategy.advance(strategy, ctx)
            if nextPos then
                ctx.pointer = world.copyPosition(nextPos)
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
                ctx.pointer = world.copyPosition(nextPos)
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
                ctx.pointer = world.copyPosition(pos)
                return true
            end
            ctx.pointer = nil
            return false
        end
    elseif type(ctx.strategy) == "function" then
        local nextPos = ctx.strategy(ctx)
        if nextPos then
            ctx.pointer = world.copyPosition(nextPos)
            return true
        end
        ctx.pointer = nil
        return false
    end
    ctx.pointer = nil
    return false
end

return strategy_utils
