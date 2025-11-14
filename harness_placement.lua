--[[
Placement harness for lib_placement.lua.
Run on a CC:Tweaked turtle to exercise placement helpers and build-state logic.
--]]

---@diagnostic disable: undefined-global, undefined-field
local placement = require("lib_placement")
local movement = require("lib_movement")
local common = require("harness_common")

local BASE_CONTEXT = {
    origin = { x = 0, y = 0, z = 0 },
    pointer = { x = 0, y = 0, z = 0 },
    state = "BUILD",
    config = {
        verbose = true,
        allowOverwrite = false,
        defaultPlacementSide = "forward",
        fuelThreshold = 0,
    },
}

local function copyPosition(pos)
    if type(pos) ~= "table" then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

local function setSchemaBlock(schema, pos, block)
    schema[pos.x] = schema[pos.x] or {}
    schema[pos.x][pos.y] = schema[pos.x][pos.y] or {}
    schema[pos.x][pos.y][pos.z] = block
end

local function hasMaterial(material)
    if not turtle or not turtle.getItemDetail then
        return false
    end
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == material and detail.count and detail.count > 0 then
            return true
        end
    end
    return false
end

local function ensureMaterialPresent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Turtle is missing " .. material .. ". Load it, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until hasMaterial(material)
end

local function ensureMaterialAbsent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if not hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Remove all " .. material .. " from the turtle inventory, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until not hasMaterial(material)
end

local function detailToString(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then
        return "..."
    end
    if type(value) ~= "table" then
        return tostring(value)
    end
    if textutils and textutils.serialize then
        return textutils.serialize(value)
    end
    local parts = {}
    for k, v in pairs(value) do
        parts[#parts + 1] = tostring(k) .. "=" .. detailToString(v, depth)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function computeManifest(list)
    local totals = {}
    for _, sc in ipairs(list) do
        if sc.material and sc.material ~= "" then
            totals[sc.material] = (totals[sc.material] or 0) + 1
        end
    end
    return totals
end

local function printManifest(io, manifest)
    if not io.print then
        return
    end
    io.print("\nRequested manifest (minimum counts):")
    local shown = false
    for material, count in pairs(manifest) do
        io.print(string.format(" - %s x%d", material, count))
        shown = true
    end
    if not shown then
        io.print(" - <empty>")
    end
end

local scenarios = {
    {
        name = "Forward placement",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Step 1: clear the space in front of the turtle and ensure cobblestone is in inventory.",
        inventory = "present",
        expect = "DONE",
    },
    {
        name = "Reuse existing block",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Leave the cobblestone block from step 1 in place to trigger already-present handling.",
        expect = "DONE",
    },
    {
        name = "Upward placement",
        material = "minecraft:oak_planks",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "up" },
        prompt = "Clear the space directly above the turtle and load oak planks (adjust material if needed).",
        inventory = "present",
        expect = "DONE",
    },
    {
        name = "Blocked fallback",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward", overwrite = true, dig = false, attack = false },
        prompt = "Place an indestructible block in front (e.g., obsidian). Turtle should switch to BLOCKED.",
        expect = "BLOCKED",
        after = function(io)
            common.promptEnter(io, "Break the blocking block before continuing.")
        end,
    },
    {
        name = "Restock detection",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Remove all cobblestone from inventory so the turtle requests RESTOCK.",
        inventory = "absent",
        expect = "RESTOCK",
    },
}

local function newContext(def, ctxOverrides, io)
    local ctx = common.merge(BASE_CONTEXT, ctxOverrides or {})
    ctx.pointer = copyPosition(def.pointer or ctx.pointer)
    if ctx.config then
        ctx.config.allowOverwrite = def.meta and def.meta.overwrite or ctx.config.allowOverwrite
    end
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)
    ctx.schema = {}
    setSchemaBlock(ctx.schema, ctx.pointer, {
        material = def.material,
        meta = def.meta,
    })
    ctx.strategy = {
        order = { copyPosition(ctx.pointer) },
        index = 1,
    }
    placement.ensureState(ctx)
    movement.ensureState(ctx)
    return ctx
end

local function runScenario(io, def, ctxOverrides)
    if io.print then
        io.print("\nScenario: " .. def.name)
        if def.prompt then
            io.print(def.prompt)
        end
    end

    if def.inventory == "present" then
        ensureMaterialPresent(io, def.material)
    elseif def.inventory == "absent" then
        ensureMaterialAbsent(io, def.material)
    end

    common.promptEnter(io, "Press Enter to execute placement.")

    local ctx = newContext(def, ctxOverrides, io)
    local nextState, detail = placement.executeBuildState(ctx, def.opts or {})

    if io.print then
        io.print("Next state: " .. tostring(nextState))
        if detail then
            io.print("Detail: " .. detailToString(detail))
        end
        if ctx.placement and ctx.placement.lastPlacement then
            io.print("Placement summary: " .. detailToString(ctx.placement.lastPlacement))
        end
    end

    if def.expect and def.expect ~= nextState then
        return false, string.format("expected %s but observed %s", tostring(def.expect), tostring(nextState))
    end

    if def.after then
        def.after(io)
    else
        common.promptEnter(io, "Press Enter when ready for the next scenario.")
    end

    return true
end

local function run(ctxOverrides, ioOverrides)
    if not turtle then
        error("turtle API unavailable. Run this on a CC:Tweaked turtle.")
    end

    local io = common.resolveIo(ioOverrides)

    if io.print then
        io.print("Placement harness starting.")
        io.print("Ensure the turtle has fuel, faces north, and sits at the chosen origin before continuing.")
    end

    local manifest = computeManifest(scenarios)
    printManifest(io, manifest)
    common.promptEnter(io, "Gather at least the listed materials before continuing. Press Enter once ready.")

    local suite = common.createSuite({ name = "Placement Harness", io = io })
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    for _, def in ipairs(scenarios) do
        step(def.name, function()
            return runScenario(io, def, ctxOverrides)
        end)
    end

    suite:summary()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
