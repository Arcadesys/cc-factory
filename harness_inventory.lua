--[[
Inventory harness for lib_inventory.lua.
Run on a CC:Tweaked turtle to validate scanning, pulling, pushing, and slot management.
--]]

---@diagnostic disable: undefined-global, undefined-field
local inventory = require("lib_inventory")
local common = require("harness_common")

local DEFAULT_CONTEXT = {
    config = {
        verbose = true,
    },
}

local function getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local function isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = detail.name or ""
    local lowered = string.lower(name)
    if lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) or lowered:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local tagLower = string.lower(tag)
            if tagLower:find("chest", 1, true) or tagLower:find("container", 1, true) or tagLower:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

local function detectContainers()
    local found = {}
    for _, side in ipairs({ "forward", "up", "down" }) do
        local inspect = getInspect(side)
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok and isContainer(detail) then
                found[#found + 1] = {
                    side = side,
                    name = detail.name or "unknown",
                }
            end
        end
    end
    return found
end

local function ensureContainer(io, side)
    while true do
        local inspect = getInspect(side)
        if type(inspect) ~= "function" then
            return false
        end
        local ok, detail = inspect()
        if ok and isContainer(detail) then
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

local function describeTotals(io, totals)
    totals = totals or {}
    local keys = {}
    for material in pairs(totals) do
        keys[#keys + 1] = material
    end
    table.sort(keys)
    if io.print then
        if #keys == 0 then
            io.print("Inventory totals: <empty>")
        else
            io.print("Inventory totals:")
            for _, material in ipairs(keys) do
                io.print(string.format(" - %s x%d", material, totals[material] or 0))
            end
        end
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

    local containers = detectContainers()
    if #containers == 0 then
        common.promptEnter(io, "No chests detected. Place at least one chest (front/up/down) and press Enter.")
        containers = detectContainers()
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

    step("Initial scan", function()
        local ok, err = inventory.scan(ctx, { force = true })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx)
        describeTotals(io, totals or {})
        if inventory.isEmpty(ctx) and io.print then
            io.print("Inventory is empty. Pull step will fetch items from chest.")
        end
        return true
    end)

    local pulledMaterial

    step("Pull items from chest", function()
        local amountStr = common.promptInput(io, "Enter amount to pull", "4")
        local amount = tonumber(amountStr) or 4
        local ok, err = inventory.pullMaterial(ctx, nil, amount, { side = supplySide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(io, totals or {})
        pulledMaterial = pulledMaterial or firstMaterial(ctx)
        if not pulledMaterial then
            return false, "nothing pulled"
        end
        if io.print then
            io.print("Primary material detected: " .. pulledMaterial)
        end
        return true
    end)

    step("Select material", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local ok, err = inventory.selectMaterial(ctx, pulledMaterial)
        if not ok then
            return false, err
        end
        if io.print then
            io.print("Selected slot: " .. tostring(turtle.getSelectedSlot and turtle.getSelectedSlot() or "?"))
        end
        return true
    end)

    step("Count and verify", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local count, err = inventory.countMaterial(ctx, pulledMaterial)
        if err then
            return false, err
        end
        if io.print then
            io.print(string.format("Material %s count: %d", pulledMaterial, count))
        end
        if count <= 0 then
            return false, "count did not increase"
        end
        return true
    end)

    step("Push items to output chest", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local dropAmountStr = common.promptInput(io, "Enter amount to push", "2")
        local dropAmount = tonumber(dropAmountStr) or 2
        local ok, err = inventory.pushMaterial(ctx, pulledMaterial, dropAmount, { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(io, totals or {})
        return true
    end)

    step("Clear first slot", function()
        local state = ctx.inventoryState or {}
        if type(state.materialSlots) ~= "table" then
            return true
        end
        local list = state.materialSlots[pulledMaterial]
        if not list or not list[1] then
            return true
        end
        local ok, err = inventory.clearSlot(ctx, list[1], { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(io, totals or {})
        return true
    end)

    step("Snapshot", function()
        local snap, err = inventory.snapshot(ctx, { force = true })
        if not snap then
            return false, err
        end
        if io.print then
            io.print(string.format("Snapshot version %d with %d total items", snap.scanVersion or 0, snap.totalItems or 0))
        end
        return true
    end)

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
