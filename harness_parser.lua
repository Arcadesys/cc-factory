--[[
Parser harness for lib_parser.lua.
Run on a CC:Tweaked computer or turtle to exercise schema parsing helpers with
sample JSON, text-grid, and voxel inputs. Prompts allow testing custom files on disk.
--]]

---@diagnostic disable: undefined-global
local parser = require("lib_parser")

local createdArtifacts = {}

local function stageArtifact(path)
    for _, existing in ipairs(createdArtifacts) do
        if existing == path then
            return
        end
    end
    createdArtifacts[#createdArtifacts + 1] = path
end

local function writeFile(path, contents)
    if type(path) ~= "string" or path == "" then
        return false, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "w")
        if not handle then
            return false, "open_failed"
        end
        handle.write(contents)
        handle.close()
        return true
    end
    if io and io.open then
        local handle, err = io.open(path, "w")
        if not handle then
            return false, err or "open_failed"
        end
        handle:write(contents)
        handle:close()
        return true
    end
    return false, "fs_unavailable"
end

local function deleteFile(path)
    if fs and fs.delete and fs.exists then
        local ok, exists = pcall(fs.exists, path)
        if ok and exists then
            fs.delete(path)
        end
        return true
    end
    if os and os.remove then
        os.remove(path)
        return true
    end
    return false
end

local function cleanupArtifacts()
    for index = #createdArtifacts, 1, -1 do
        local path = createdArtifacts[index]
        deleteFile(path)
        createdArtifacts[index] = nil
    end
end

local function makeLogger(ctx)
    local logger = {}

    function logger.info(msg)
        print("[INFO] " .. msg)
    end

    function logger.warn(msg)
        print("[WARN] " .. msg)
    end

    function logger.error(msg)
        print("[ERROR] " .. msg)
    end

    function logger.debug(msg)
        if ctx.config and ctx.config.verbose then
            print("[DEBUG] " .. msg)
        end
    end

    return logger
end

local function prompt(message, default)
    local suffix = ""
    if default and default ~= "" then
        suffix = " [" .. default .. "]"
    end
    print(message .. suffix)
    local readFn = _G and _G["read"]
    if type(readFn) == "function" then
        local line = readFn()
        if line and line ~= "" then
            return line
        end
    else
        local sleepFn = _G and _G["sleep"]
        if type(sleepFn) == "function" then
            sleepFn(2)
        end
    end
    return default
end

local function printMaterials(info)
    if not info or not info.materials or #info.materials == 0 then
        print("Materials: <none>")
        return
    end
    print("Materials:")
    for _, entry in ipairs(info.materials) do
        print(string.format(" - %s x%d", entry.material, entry.count))
    end
end

local function printBounds(info)
    if not info or not info.bounds or not info.bounds.min then
        print("Bounds: <unknown>")
        return
    end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    local dims = {
        x = (maxB.x - minB.x) + 1,
        y = (maxB.y - minB.y) + 1,
        z = (maxB.z - minB.z) + 1,
    }
    print(string.format("Bounds: min(%d,%d,%d) max(%d,%d,%d) dims(%d,%d,%d)",
        minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z, dims.x, dims.y, dims.z))
end

local function summariseResult(ok, schema, info, err)
    if not ok then
        print("Result: FAIL - " .. tostring(err))
        return
    end
    print("Result: PASS")
    info = info or {}
    if info.format then
        print("Format: " .. tostring(info.format))
    end
    if info.path then
        print("Source: " .. tostring(info.path))
    end
    print("Total blocks: " .. tostring(info.totalBlocks or (schema and "~" .. tostring(#schema) or 0)))
    printBounds(info)
    printMaterials(info)
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

local SAMPLE_TEXT_GRID = [[
legend:
# = minecraft:cobblestone
~ = minecraft:glass

####
#..#
#..#
####

layer:1
~..~
.##.
~..~
]]

local SAMPLE_JSON = [[
{
  "legend": {
    "A": "minecraft:oak_planks",
    "B": { "material": "minecraft:stone", "meta": { "variant": "smooth" } }
  },
  "layers": [
    {
      "y": 0,
      "rows": ["AA", "BB"]
    },
    {
      "y": 1,
      "rows": ["BB", "AA"]
    }
  ]
}
]]

local SAMPLE_VOXEL = [[
{
  "grid": {
    "0": {
      "0": { "0": "minecraft:oak_log", "1": "minecraft:oak_log" },
      "1": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" }
    },
    "1": {
      "0": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" },
      "1": { "0": "minecraft:air", "1": "minecraft:torch" }
    }
  }
}
]]

local EXPECT_TEXT_GRID = {
    totalBlocks = 18,
    materials = {
        ["minecraft:cobblestone"] = 14,
        ["minecraft:glass"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 3, y = 1, z = 3 },
    },
}

local EXPECT_JSON = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_planks"] = 4,
        ["minecraft:stone"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

local EXPECT_VOXEL = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_log"] = 2,
        ["minecraft:oak_leaves"] = 4,
        ["minecraft:air"] = 1,
        ["minecraft:torch"] = 1,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

local SAMPLE_BLOCK_DATA = {
    blocks = {
        { x = 0, y = 0, z = 0, material = "minecraft:cobblestone" },
        { x = 1, y = 0, z = 0, material = "minecraft:stone" },
        { x = 0, y = 1, z = 0, material = "minecraft:stone" },
    },
}

local SAMPLE_VOXEL_DATA = {
    grid = {
        [0] = {
            [0] = { [0] = "minecraft:oak_log", [1] = "minecraft:oak_log" },
            [1] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
        },
        [1] = {
            [0] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
            [1] = { [0] = "minecraft:air", [1] = "minecraft:torch" },
        },
    },
}

local EXPECT_BLOCK_DATA = {
    totalBlocks = 3,
    materials = {
        ["minecraft:cobblestone"] = 1,
        ["minecraft:stone"] = 2,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 0 },
    },
}

local FILE_SAMPLES = {
    {
        label = "File Text Grid",
        path = "tmp_sample_grid.txt",
        contents = SAMPLE_TEXT_GRID,
        expect = EXPECT_TEXT_GRID,
    },
    {
        label = "File JSON",
        path = "tmp_sample_schema.json",
        contents = SAMPLE_JSON,
        expect = EXPECT_JSON,
    },
    {
        label = "File Voxel",
        path = "tmp_sample_voxel.vox",
        contents = SAMPLE_VOXEL,
        expect = EXPECT_VOXEL,
        opts = { formatHint = "voxel" },
    },
}

local testStats = {
    total = 0,
    passed = 0,
    failures = 0,
    details = {},
}

local function recordResult(name, success, message)
    testStats.total = testStats.total + 1
    if success then
        testStats.passed = testStats.passed + 1
    else
        testStats.failures = testStats.failures + 1
        testStats.details[#testStats.details + 1] = {
            name = name,
            message = message or "unknown error",
        }
    end
end

local function runParseCall(ctx, label, parseCall, expect)
    print("\n== " .. label .. " ==")
    local callOk, resultOk, schemaOrErr, info = pcall(parseCall)
    if not callOk then
        summariseResult(false, nil, nil, resultOk)
        recordResult(label, false, tostring(resultOk))
        return
    end
    if not resultOk then
        summariseResult(false, nil, nil, schemaOrErr)
        recordResult(label, false, tostring(schemaOrErr))
        return
    end
    summariseResult(true, schemaOrErr, info)
    local expectOk, expectErr = checkExpectations(info or {}, expect)
    if expect then
        if expectOk then
            print("[PASS] Expectations met.")
        else
            print("[FAIL] " .. tostring(expectErr))
        end
    end
    recordResult(label, expectOk ~= false, expectErr)
end

local function runSample(ctx, label, spec, expect)
    runParseCall(ctx, label, function()
        return parser.parse(ctx, spec)
    end, expect)
end

local function runFileSample(ctx, label, path, contents, expect, opts)
    runParseCall(ctx, label, function()
        local ok, err = writeFile(path, contents)
        if not ok then
            return false, err or "write_failed"
        end
        stageArtifact(path)
        return parser.parseFile(ctx, path, opts)
    end, expect)
end

local function runParseTextSample(ctx, label, text, expect)
    runParseCall(ctx, label, function()
        return parser.parseText(ctx, text)
    end, expect)
end

local function runParseJsonSample(ctx, label, data, expect)
    runParseCall(ctx, label, function()
        return parser.parseJson(ctx, data)
    end, expect)
end

local function runCustomPath(ctx)
    local path = prompt("Enter path to schema file (JSON or text grid)", "schema.json")
    if not path or path == "" then
        print("Skipping custom file test.")
        return
    end
    print("\n== Parse File: " .. path .. " ==")
    local ok, schemaOrErr, info = parser.parseFile(ctx, path, { formatHint = nil })
    if not ok then
        summariseResult(false, nil, nil, schemaOrErr)
        recordResult("File: " .. path, false, tostring(schemaOrErr))
    else
        summariseResult(true, schemaOrErr, info)
        recordResult("File: " .. path, true)
    end
end

local function runCustomText(ctx)
    local mode = prompt("Enter format for raw text (json/grid)", "grid")
    local text
    if mode == "json" then
        print("Paste JSON, end with empty line:")
    else
        print("Paste text grid, end with empty line:")
    end
    local lines = {}
    while true do
        local line = prompt("")
        if not line or line == "" then
            break
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then
        print("No text entered, skipping.")
        return
    end
    text = table.concat(lines, "\n")
    print("\n== Parse Raw Text ==")
    local ok, schemaOrErr, info = parser.parse(ctx, { text = text, format = mode })
    if not ok then
        summariseResult(false, nil, nil, schemaOrErr)
        recordResult("Raw text", false, tostring(schemaOrErr))
    else
        summariseResult(true, schemaOrErr, info)
        recordResult("Raw text", true)
    end
end

local function prepareContext()
    local ctx = {
        config = {
            verbose = true,
        },
    }
    ctx.logger = makeLogger(ctx)
    return ctx
end

local function main()
    local ctx = prepareContext()

    print("Parser harness starting. Ensure sample schema files are available if you want to test custom paths.")

    runSample(ctx, "Sample Text Grid", { text = SAMPLE_TEXT_GRID, format = "grid" }, EXPECT_TEXT_GRID)
    runSample(ctx, "Sample JSON", { text = SAMPLE_JSON, format = "json" }, EXPECT_JSON)
    runSample(ctx, "Sample Voxel", { text = SAMPLE_VOXEL, format = "voxel" }, EXPECT_VOXEL)
    runParseTextSample(ctx, "Sample Text Grid via parseText", SAMPLE_TEXT_GRID, EXPECT_TEXT_GRID)
    runParseJsonSample(ctx, "Sample JSON Blocks via parseJson", SAMPLE_BLOCK_DATA, EXPECT_BLOCK_DATA)
    runParseCall(ctx, "Sample Voxel via data", function()
        return parser.parse(ctx, { data = SAMPLE_VOXEL_DATA, format = "voxel" })
    end, EXPECT_VOXEL)
    runParseCall(ctx, "Sample JSON direct source", function()
        return parser.parse(ctx, SAMPLE_JSON)
    end, EXPECT_JSON)
    for _, sample in ipairs(FILE_SAMPLES) do
        runFileSample(ctx, sample.label, sample.path, sample.contents, sample.expect, sample.opts)
    end
    runParseCall(ctx, "File autodetect via parse", function()
        local sample = FILE_SAMPLES[1]
        local ok, err = writeFile(sample.path, sample.contents)
        if not ok then
            return false, err or "write_failed"
        end
        stageArtifact(sample.path)
        return parser.parse(ctx, { source = sample.path })
    end, EXPECT_TEXT_GRID)

    if prompt("Run custom file test? (y/n)", "n") == "y" then
        runCustomPath(ctx)
    end
    if prompt("Run custom raw text test? (y/n)", "n") == "y" then
        runCustomText(ctx)
    end

    print("\nHarness complete. Review the results above for details.")
    print(string.format("Tests: %d passed / %d total", testStats.passed, testStats.total))
    cleanupArtifacts()
    if testStats.failures > 0 then
        print("Failures:")
        for _, failure in ipairs(testStats.details) do
            print(string.format(" - %s: %s", failure.name, failure.message))
        end
        error("Parser harness detected failures.")
    else
        print("All parser harness tests passed.")
    end
end

main()
