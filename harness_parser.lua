--[[
Parser harness for lib_parser.lua.
Run on a CC:Tweaked computer or turtle to exercise schema parsing helpers with
sample JSON, text-grid, and voxel inputs. Prompts allow testing custom files on disk.
--]]

---@diagnostic disable: undefined-global
local parser = require("lib_parser")
local common = require("harness_common")
local reporter = require("lib_reporter")
local fs_utils = require("lib_fs")
local data = require("harness_parser_data")

local function emitParseSummary(io, schema, info)
    if not io.print then
        return
    end
    info = info or {}
    if info.format then
        io.print("Format: " .. tostring(info.format))
    end
    if info.path then
        io.print("Source: " .. tostring(info.path))
    end
    io.print("Total blocks: " .. tostring(info.totalBlocks or (schema and tostring(#schema) or 0)))
    reporter.printBounds(io, info)
    reporter.printMaterials(io, info)
end

local function toMaterialMap(list)
    local map = {}
    if type(list) ~= "table" then
        return map
    end
    for _, entry in ipairs(list) do
        if entry.material then
            map[entry.material] = entry.count or 0
        end
    end
    return map
end

local function checkExpectations(info, expect)
    if not expect then
        return true
    end
    if expect.totalBlocks and (info.totalBlocks or 0) ~= expect.totalBlocks then
        return false, string.format("expected %d blocks but found %d", expect.totalBlocks, info.totalBlocks or 0)
    end
    if expect.materials then
        local actual = toMaterialMap(info.materials)
        for material, expectedCount in pairs(expect.materials) do
            local observed = actual[material] or 0
            if observed ~= expectedCount then
                return false, string.format("material %s expected %d but found %d", material, expectedCount, observed)
            end
        end
        for material, observed in pairs(actual) do
            if expect.materials[material] == nil then
                return false, string.format("unexpected material %s (count %d)", material, observed)
            end
        end
    end
    if expect.bounds then
        local bounds = info.bounds
        if not bounds or not bounds.min or not bounds.max then
            return false, "missing bounds information"
        end
        for axis, value in pairs(expect.bounds.min) do
            if (bounds.min[axis] or 0) ~= value then
                return false, string.format("bounds.min.%s expected %d but found %d", axis, value, bounds.min[axis] or 0)
            end
        end
        for axis, value in pairs(expect.bounds.max) do
            if (bounds.max[axis] or 0) ~= value then
                return false, string.format("bounds.max.%s expected %d but found %d", axis, value, bounds.max[axis] or 0)
            end
        end
    end
    return true
end

local function executeParse(io, parseCall, expect)
    local callOk, resultOk, schemaOrErr, info = pcall(parseCall)
    if not callOk then
        if io.print then
            io.print("Parser invocation errored: " .. tostring(resultOk))
        end
        return false, tostring(resultOk)
    end
    if not resultOk then
        if io.print then
            io.print("Parser returned failure: " .. tostring(schemaOrErr))
        end
        return false, tostring(schemaOrErr)
    end
    emitParseSummary(io, schemaOrErr, info)
    local expectOk, expectErr = checkExpectations(info or {}, expect)
    if expect then
        if expectOk then
            if io.print then
                io.print("[PASS] Expectations met.")
            end
        else
            if io.print then
                io.print("[FAIL] " .. tostring(expectErr))
            end
            return false, expectErr
        end
    end
    return true
end

local function runFileSample(io, ctx, sample)
    return executeParse(io, function()
        local ok, err = fs_utils.writeFile(sample.path, sample.contents)
        if not ok then
            return false, err or "write_failed"
        end
        fs_utils.stageArtifact(sample.path)
        return parser.parseFile(ctx, sample.path, sample.opts)
    end, sample.expect)
end

local function prepareContext(ctxOverrides, io)
    local ctx = common.merge({ config = { verbose = true } }, ctxOverrides or {})
    ctx.logger = ctx.logger or common.makeLogger(ctx, io)
    return ctx
end

local function runCustomPath(io, ctx)
    local path = common.promptInput(io, "Enter path to schema file (JSON or text grid)", "schema.json")
    if not path or path == "" then
        if io.print then
            io.print("Skipping custom file test.")
        end
        return true
    end
    return executeParse(io, function()
        return parser.parseFile(ctx, path, { formatHint = nil })
    end)
end

local function runCustomText(io, ctx)
    local mode = common.promptInput(io, "Enter format for raw text (json/grid)", "grid")
    local promptMessage = mode == "json" and "Paste JSON, end with empty line:" or "Paste text grid, end with empty line:"
    if io.print then
        io.print(promptMessage)
    end
    local lines = {}
    while true do
        local line = common.prompt(io, "", { allowEmpty = true })
        if not line or line == "" then
            break
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        if io.print then
            io.print("No text entered, skipping.")
        end
        return true
    end
    local text = table.concat(lines, "\n")
    return executeParse(io, function()
        return parser.parse(ctx, { text = text, format = mode })
    end)
end

local function run(ctxOverrides, ioOverrides)
    local io = common.resolveIo(ioOverrides)
    local ctx = prepareContext(ctxOverrides, io)

    if io.print then
        io.print("Parser harness starting. Ensure sample schema files are available if you want to test custom paths.")
    end

    local suite = common.createSuite({ name = "Parser Harness", io = io })
    local step = function(name, fn)
        return suite:step(name, fn)
    end

    step("Sample Text Grid", function()
        return executeParse(io, function()
            return parser.parse(ctx, { text = data.SAMPLE_TEXT_GRID, format = "grid" })
        end, data.EXPECT_TEXT_GRID)
    end)

    step("Sample JSON", function()
        return executeParse(io, function()
            return parser.parse(ctx, { text = data.SAMPLE_JSON, format = "json" })
        end, data.EXPECT_JSON)
    end)

    step("Sample Voxel", function()
        return executeParse(io, function()
            return parser.parse(ctx, { text = data.SAMPLE_VOXEL, format = "voxel" })
        end, data.EXPECT_VOXEL)
    end)

    step("Sample Text Grid via parseText", function()
        return executeParse(io, function()
            return parser.parseText(ctx, data.SAMPLE_TEXT_GRID)
        end, data.EXPECT_TEXT_GRID)
    end)

    step("Sample JSON Blocks via parseJson", function()
        return executeParse(io, function()
            return parser.parseJson(ctx, data.SAMPLE_BLOCK_DATA)
        end, data.EXPECT_BLOCK_DATA)
    end)

    step("Sample Voxel via data", function()
        return executeParse(io, function()
            return parser.parse(ctx, { data = data.SAMPLE_VOXEL_DATA, format = "voxel" })
        end, data.EXPECT_VOXEL)
    end)

    step("Sample JSON direct source", function()
        return executeParse(io, function()
            return parser.parse(ctx, data.SAMPLE_JSON)
        end, data.EXPECT_JSON)
    end)

    for _, sample in ipairs(data.FILE_SAMPLES) do
        step(sample.label, function()
            return runFileSample(io, ctx, sample)
        end)
    end

    step("File autodetect via parse", function()
        local sample = data.FILE_SAMPLES[1]
        return executeParse(io, function()
            local ok, err = fs_utils.writeFile(sample.path, sample.contents)
            if not ok then
                return false, err or "write_failed"
            end
            fs_utils.stageArtifact(sample.path)
            return parser.parse(ctx, { source = sample.path })
        end, data.EXPECT_TEXT_GRID)
    end)

    local customFileAnswer = common.promptInput(io, "Run custom file test? (y/n)", "n")
    if customFileAnswer == "y" then
        step("Custom file test", function()
            return runCustomPath(io, ctx)
        end)
    end

    local customTextAnswer = common.promptInput(io, "Run custom raw text test? (y/n)", "n")
    if customTextAnswer == "y" then
        step("Custom raw text", function()
            return runCustomText(io, ctx)
        end)
    end

    suite:summary()

    local passed = 0
    for _, result in ipairs(suite.results) do
        if result.ok then
            passed = passed + 1
        end
    end
    if io.print then
        io.print(string.format("Tests: %d passed / %d total", passed, #suite.results))
        if passed == #suite.results then
            io.print("All parser harness tests passed.")
        else
            io.print("Some parser harness tests failed.")
        end
    end

    fs_utils.cleanupArtifacts()
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
