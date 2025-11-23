--[[
Harness for lib_initialize.lua.
Guides the user through testing manifest validation against the turtle
inventory plus nearby chests. Designed for manual execution on a
CC:Tweaked turtle.
--]]

---@diagnostic disable: undefined-global, undefined-field

local inventory = require("lib_inventory")
local parser = require("lib_parser")
local common = require("harness_common")
local reporter = require("lib_reporter")

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

local function promptReady(io)
    common.promptEnter(io, "Arrange materials across the turtle inventory and chests, then press Enter to continue.")
end

local function runMaterialCheckLoop(ctx, io)
    local attempt = 1
    while true do
        if io.print then
            io.print(string.format("\n-- Check attempt %d --", attempt))
        end
        local success, report = reporter.runCheck(ctx, io, {})
        if success then
            reporter.gatherSummary(io, report)
            break
        end
        if io.print then
            io.print("Adjust supplies and press Enter to retry, or type 'cancel' to exit.")
        end
        local response = common.prompt(io, "Continue? (Enter to retry / cancel to stop)", { allowEmpty = true, default = "" })
        if response and response:lower() == "cancel" then
            reporter.gatherSummary(io, report)
            break
        end
        attempt = attempt + 1
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

    reporter.describeMaterials(io, ctx.schemaInfo)
    reporter.detectContainers(io)
    promptReady(io)

    runMaterialCheckLoop(ctx, io)

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
