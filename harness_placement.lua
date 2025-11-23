--[[
Placement harness for lib_placement.lua.
Run on a CC:Tweaked turtle to exercise placement helpers and build-state logic.
--]]

---@diagnostic disable: undefined-global, undefined-field
local placement = require("lib_placement")
local movement = require("lib_movement")
local common = require("harness_common")
local reporter = require("lib_reporter")
local inventory_utils = require("lib_inventory_utils")
local data = require("harness_placement_data")

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
        inventory_utils.ensureMaterialPresent(io, def.material)
    elseif def.inventory == "absent" then
        inventory_utils.ensureMaterialAbsent(io, def.material)
    end

    common.promptEnter(io, "Press Enter to execute placement.")

    local ctx = newContext(def, ctxOverrides, io)
    local nextState, detail = placement.executeBuildState(ctx, def.opts or {})

    if io.print then
        io.print("Next state: " .. tostring(nextState))
        if detail then
            io.print("Detail: " .. reporter.detailToString(detail))
        end
        if ctx.placement and ctx.placement.lastPlacement then
            io.print("Placement summary: " .. reporter.detailToString(ctx.placement.lastPlacement))
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

    local manifest = reporter.computeManifest(data.scenarios)
    reporter.printManifest(io, manifest)
    common.promptEnter(io, "Gather at least the listed materials before continuing. Press Enter once ready.")

    local suite = common.createSuite({ name = "Placement Harness", io = io })
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    for _, def in ipairs(data.scenarios) do
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
