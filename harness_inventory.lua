--[[
Inventory harness for lib_inventory.lua.
Run on a CC:Tweaked turtle to validate scanning, pulling, pushing, and slot management.
--]]

---@diagnostic disable: undefined-global, undefined-field
local inventory = require("lib_inventory")
local common = require("harness_common")
local reporter = require("lib_reporter")
local world = require("lib_world")

local DEFAULT_CONTEXT = {
    config = {
        verbose = true,
    },
}

local function ensureContainer(io, side)
    while true do
        local inspect = world.getInspect(side)
        if type(inspect) ~= "function" then
            return false
        end
        local ok, detail = inspect()
        if ok and world.isContainer(detail) then
            if io.print then
                io.print(string.format("Detected %s on %s", detail.name or "container", side))
            end
            return true
        end
        local location
        if side == "forward" then
            location = "in front"
        elseif side == "up" then
            location = "above"
        else
            location = "below"
        end
        common.promptEnter(io, string.format("No chest detected %s. Place a chest there and press Enter.", location))
    end
end

local function firstMaterial(ctx)
    local state = ctx.inventoryState or {}
    if type(state.materialTotals) ~= "table" then
        return nil
    end
    for material in pairs(state.materialTotals) do
        return material
    end
    return nil
end

local function stepInitialScan(ctx, io)
    return function()
        local ok, err = inventory.scan(ctx, { force = true })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx)
        reporter.describeTotals(io, totals or {})
        if inventory.isEmpty(ctx) and io.print then
            io.print("Inventory is empty. Pull step will fetch items from chest.")
        end
        return true
    end
end

local function stepPullItems(ctx, io, supplySide, pulledMaterial)
    return function()
        local amountStr = common.promptInput(io, "Enter amount to pull", "4")
        local amount = tonumber(amountStr) or 4
        local ok, err = inventory.pullMaterial(ctx, nil, amount, { side = supplySide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        reporter.describeTotals(io, totals or {})
        pulledMaterial.value = pulledMaterial.value or firstMaterial(ctx)
        if not pulledMaterial.value then
            return false, "nothing pulled"
        end
        if io.print then
            io.print("Primary material detected: " .. pulledMaterial.value)
        end
        return true
    end
end

local function stepSelectMaterial(ctx, io, pulledMaterial)
    return function()
        if not pulledMaterial.value then
            return false, "no material available"
        end
        local ok, err = inventory.selectMaterial(ctx, pulledMaterial.value)
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Selected slot: " .. tostring(turtle.getSelectedSlot and turtle.getSelectedSlot() or "?"))
        end
        return true
    end
end

local function stepCountAndVerify(ctx, io, pulledMaterial)
    return function()
        if not pulledMaterial.value then
            return false, "no material available"
        end
        local count, err = inventory.countMaterial(ctx, pulledMaterial.value)
        if err then
            return false, err
        end
        if io.print then
            io.print(string.format("Material %s count: %d", pulledMaterial.value, count))
        end
        if count <= 0 then
            return false, "count did not increase"
        end
        return true
    end
end

local function stepPushItems(ctx, io, dropSide, pulledMaterial)
    return function()
        if not pulledMaterial.value then
            return false, "no material available"
        end
        local dropAmountStr = common.promptInput(io, "Enter amount to push", "2")
        local dropAmount = tonumber(dropAmountStr) or 2
        local ok, err = inventory.pushMaterial(ctx, pulledMaterial.value, dropAmount, { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        reporter.describeTotals(io, totals or {})
        return true
    end
end

local function stepClearFirstSlot(ctx, io, dropSide, pulledMaterial)
    return function()
        local state = ctx.inventoryState or {}
        if type(state.materialSlots) ~= "table" then
            return true
        end
        local list = state.materialSlots[pulledMaterial.value]
        if not list or not list[1] then
            return true
        end
        local ok, err = inventory.clearSlot(ctx, list[1], { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        reporter.describeTotals(io, totals or {})
        return true
    end
end

local function stepSnapshot(ctx, io)
    return function()
        local snap, err = inventory.snapshot(ctx, { force = true })
        if not snap then
            return false, err
        end
        if io.print then
            io.print(string.format("Snapshot version %d with %d total items", snap.scanVersion or 0, snap.totalItems or 0))
        end
        return true
    end
end

local function run(ctxOverrides, ioOverrides)
    if not turtle then
        error("turtle API unavailable. Run this on a CC:Tweaked turtle.")
    end

    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)
    inventory.ensureState(ctx)

    if io.print then
        io.print("Inventory harness starting.")
        io.print("Setup: place a supply chest in front of the turtle. Optionally place an output chest below or above.")
    end

    local suite = common.createSuite({ name = "Inventory Harness", io = io })
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    local containers = world.detectContainers()
    if #containers == 0 then
        common.promptEnter(io, "No chests detected. Place at least one chest (front/up/down) and press Enter.")
        containers = world.detectContainers()
    end

    local supplySide = "forward"
    local dropSide = "forward"
    local seen = {}
    for _, entry in ipairs(containers) do
        seen[entry.side] = entry
    end
    if not seen[supplySide] then
        if seen.up then
            supplySide = "up"
        elseif seen.down then
            supplySide = "down"
        end
    end
    if seen.down and supplySide ~= "down" then
        dropSide = "down"
    elseif seen.up and supplySide ~= "up" then
        dropSide = "up"
    else
        dropSide = supplySide
    end

    ensureContainer(io, supplySide)
    ensureContainer(io, dropSide)

    local pulledMaterial = { value = nil }

    step("Initial scan", stepInitialScan(ctx, io))
    step("Pull items from chest", stepPullItems(ctx, io, supplySide, pulledMaterial))
    step("Select material", stepSelectMaterial(ctx, io, pulledMaterial))
    step("Count and verify", stepCountAndVerify(ctx, io, pulledMaterial))
    step("Push items to output chest", stepPushItems(ctx, io, dropSide, pulledMaterial))
    step("Clear first slot", stepClearFirstSlot(ctx, io, dropSide, pulledMaterial))
    step("Snapshot", stepSnapshot(ctx, io))

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
