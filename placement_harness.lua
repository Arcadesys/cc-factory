--[[
Placement harness for lib_placement.lua.
Run on a CC:Tweaked turtle to exercise placement helpers and build-state logic.
--]]

---@diagnostic disable: undefined-global, undefined-field
local placement = require("lib_placement")
local movement = require("lib_movement")

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

local function prompt(message)
    print(message)
    if _G.read then
        read()
    else
        if _G.sleep then
            sleep(3)
        end
    end
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

local function ensureMaterialPresent(material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if hasMaterial(material) then
        return
    end
    print("Turtle is missing " .. material .. ". Load it, then press Enter.")
    repeat
        prompt("")
    until hasMaterial(material)
end

local function ensureMaterialAbsent(material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if not hasMaterial(material) then
        return
    end
    print("Remove all " .. material .. " from the turtle inventory, then press Enter.")
    repeat
        prompt("")
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

local function printManifest(manifest)
    print("\nRequested manifest (minimum counts):")
    local shown = false
    for material, count in pairs(manifest) do
        print(string.format(" - %s x%d", material, count))
        shown = true
    end
    if not shown then
        print(" - <empty>")
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
        after = function()
            prompt("Break the blocking block before continuing.")
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

local function newContext(def)
    local ctx = {
        origin = { x = 0, y = 0, z = 0 },
        pointer = copyPosition(def.pointer),
        state = "BUILD",
        config = {
            verbose = true,
            allowOverwrite = def.meta and def.meta.overwrite or false,
            defaultPlacementSide = "forward",
            fuelThreshold = 0,
        },
    }

    ctx.logger = makeLogger(ctx)
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

local function runScenario(def)
    print("\n== " .. def.name .. " ==")
    if def.prompt then
        print(def.prompt)
    end

    if def.inventory == "present" then
        ensureMaterialPresent(def.material)
    elseif def.inventory == "absent" then
        ensureMaterialAbsent(def.material)
    end

    prompt("Press Enter to execute placement.")

    local ctx = newContext(def)
    local nextState, detail = placement.executeBuildState(ctx, def.opts or {})

    print("Next state: " .. tostring(nextState))
    if def.expect and def.expect ~= nextState then
        print("[WARN] Expected " .. tostring(def.expect) .. " but observed " .. tostring(nextState))
    end

    if detail then
        print("Detail: " .. detailToString(detail))
    end

    if ctx.placement and ctx.placement.lastPlacement then
        print("Placement summary: " .. detailToString(ctx.placement.lastPlacement))
    end

    if def.after then
        def.after()
    else
        prompt("Press Enter when ready for the next scenario.")
    end
end

local function main()
    if not turtle then
        error("turtle API unavailable. Run this on a CC:Tweaked turtle.")
    end

    print("Placement harness starting.")
    print("Ensure the turtle has fuel, faces north, and sits at the chosen origin before continuing.")

    local manifest = computeManifest(scenarios)
    printManifest(manifest)
    prompt("Gather at least the listed materials before continuing. Press Enter once ready.")

    for _, def in ipairs(scenarios) do
        runScenario(def)
    end

    print("\nHarness complete. Review the results above for any failures.")
end

main()
