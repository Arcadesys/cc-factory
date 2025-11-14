--[[
Harness for lib_initialize.lua.
Guides the user through testing manifest validation against the turtle
inventory plus nearby chests. Designed for manual execution on a
CC:Tweaked turtle.
--]]

---@diagnostic disable: undefined-global, undefined-field

local initialize = require("lib_initialize")
local inventory = require("lib_inventory")
local parser = require("lib_parser")
local common = require("harness_common")

local DEFAULT_CONTEXT = {
    config = {
        verbose = true,
    },
    origin = { x = 0, y = 0, z = 0 },
}

local SAMPLE_TEXT = [[
legend:
# = minecraft:stone_bricks
G = minecraft:glass
L = minecraft:lantern
T = minecraft:torch
. = minecraft:air

layer:0
.....
.###.
.###.
.###.
.....

layer:1
.....
.#G#.
.#L#.
.#G#.
.....

layer:2
.....
..#..
..#..
..#..
.....

layer:3
.....
.....
..T..
.....
.....
]]

local function ensureParserSchema(ctx, io)
    if ctx.schema and ctx.schemaInfo then
        return true
    end
    if io.print then
        io.print("Parsing bundled sample schema for manifest demonstration...")
    end
    local ok, schema, info = parser.parseText(ctx, SAMPLE_TEXT, { format = "grid" })
    if not ok then
        return false, schema
    end
    ctx.schema = schema
    ctx.schemaInfo = info
    return true
end

local function describeMaterials(io, info)
    if not io.print then
        return
    end
    io.print("Schema manifest requirements:")
    if not info or not info.materials then
        io.print(" - <none>")
        return
    end
    for _, entry in ipairs(info.materials) do
        if entry.material ~= "minecraft:air" and entry.material ~= "air" then
            io.print(string.format(" - %s x%d", entry.material, entry.count or 0))
        end
    end
end

local function detectContainers(io)
    local found = {}
    local sides = { "forward", "down", "up" }
    local labels = {
        forward = "front",
        down = "below",
        up = "above",
    }
    for _, side in ipairs(sides) do
        local inspect
        if side == "forward" then
            inspect = turtle.inspect
        elseif side == "up" then
            inspect = turtle.inspectUp
        else
            inspect = turtle.inspectDown
        end
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok then
                local name = type(detail.name) == "string" and detail.name or "unknown"
                found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
            end
        end
    end
    if io.print then
        if #found == 0 then
            io.print("Detected containers: <none>")
        else
            io.print("Detected containers:")
            for _, line in ipairs(found) do
                io.print(" -" .. line)
            end
        end
    end
end

local function promptReady(io)
    common.promptEnter(io, "Arrange materials across the turtle inventory and chests, then press Enter to continue.")
end

local function runCheck(ctx, io, opts)
    local ok, report = initialize.ensureMaterials(ctx, { manifest = ctx.schemaInfo and ctx.schemaInfo.materials }, opts)
    if io.print then
        if ok then
            io.print("Material check passed. Turtle and chests meet manifest requirements.")
        else
            io.print("Material check failed. Missing materials:")
            for _, entry in ipairs(report.missing or {}) do
                io.print(string.format(" - %s: need %d, have %d", entry.material, entry.required, entry.have))
            end
        end
    end
    return ok, report
end

local function gatherSummary(io, report)
    if not io.print then
        return
    end
    io.print("\nDetailed totals:")
    io.print(" Turtle inventory:")
    for material, count in pairs(report.turtleTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    io.print(" Nearby chests:")
    for material, count in pairs(report.chestTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    if #report.chests > 0 then
        io.print(" Per-chest breakdown:")
        for _, entry in ipairs(report.chests) do
            io.print(string.format("   [%s] %s", entry.side, entry.name or "container"))
            for material, count in pairs(entry.totals or {}) do
                io.print(string.format("     * %s x%d", material, count))
            end
        end
    end
end

local function run(ctxOverrides, ioOverrides)
    if not turtle then
        error("Run this harness on a turtle.")
    end

    local io = common.resolveIo(ioOverrides)
    local ctx = common.merge(DEFAULT_CONTEXT, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)
    inventory.ensureState(ctx)

    if io.print then
        io.print("Initialization harness starting.")
        io.print("Goal: verify material manifest checks before starting a print.")
    end

    local ok, err = ensureParserSchema(ctx, io)
    if not ok then
        error("Failed to load sample schema: " .. tostring(err))
    end

    describeMaterials(io, ctx.schemaInfo)
    detectContainers(io)
    promptReady(io)

    local attempt = 1
    while true do
        if io.print then
            io.print(string.format("\n-- Check attempt %d --", attempt))
        end
        local success, report = runCheck(ctx, io, {})
        if success then
            gatherSummary(io, report)
            break
        end
        if io.print then
            io.print("Adjust supplies and press Enter to retry, or type 'cancel' to exit.")
        end
        local response = common.prompt(io, "Continue? (Enter to retry / cancel to stop)", { allowEmpty = true, default = "" })
        if response and response:lower() == "cancel" then
            gatherSummary(io, report)
            break
        end
        attempt = attempt + 1
    end

    if io.print then
        io.print("Initialization harness complete.")
    end

    return true
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
