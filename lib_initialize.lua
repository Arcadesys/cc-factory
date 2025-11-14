--[[
Initialization helper for schema-driven builds.
Verifies material availability against a manifest by checking the turtle
inventory plus nearby supply chests. Provides prompting to gather missing
materials before a print begins.
--]]

---@diagnostic disable: undefined-global

local inventory = require("lib_inventory")

local initialize = {}

local DEFAULT_SIDES = { "forward", "down", "up" }

local function log(ctx, level, message)
    if type(ctx) ~= "table" then
        return
    end
    local logger = ctx.logger
    if type(logger) ~= "table" then
        if level == "error" or level == "warn" then
            print(string.format("[%s] %s", level:upper(), message))
        end
        return
    end
    local fn = logger[level]
    if type(fn) == "function" then
        fn(message)
        return
    end
    if type(logger.log) == "function" then
        logger.log(level, message)
    end
end

local function mapSides(opts)
    local sides = {}
    if type(opts) == "table" and type(opts.sides) == "table" then
        for _, side in ipairs(opts.sides) do
            sides[#sides + 1] = side
        end
    end
    if #sides == 0 then
        for _, side in ipairs(DEFAULT_SIDES) do
            sides[#sides + 1] = side
        end
    end
    return sides
end

local function inspectSide(side)
    if side == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif side == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif side == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

local function isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

local function toPeripheralSide(side)
    if side == "forward" then
        return "front"
    elseif side == "up" then
        return "top"
    elseif side == "down" then
        return "bottom"
    end
    return side
end

local function copyTotals(totals)
    local result = {}
    for material, count in pairs(totals or {}) do
        result[material] = count
    end
    return result
end

local function mergeTotals(target, source)
    for material, count in pairs(source or {}) do
        target[material] = (target[material] or 0) + count
    end
end

local function normaliseManifest(manifest)
    local result = {}
    if type(manifest) ~= "table" then
        return result
    end
    local function push(material, count)
        if type(material) ~= "string" or material == "" then
            return
        end
        if material == "minecraft:air" or material == "air" then
            return
        end
        if type(count) ~= "number" or count <= 0 then
            return
        end
        result[material] = math.max(result[material] or 0, math.floor(count))
    end
    local isArray = manifest[1] ~= nil
    if isArray then
        for _, entry in ipairs(manifest) do
            if type(entry) == "table" then
                local count = entry.count or entry.quantity or entry.amount or entry.required
                push(entry.material or entry.name or entry.id, count or entry[2])
            elseif type(entry) == "string" then
                push(entry, 1)
            end
        end
    else
        for material, count in pairs(manifest) do
            push(material, count)
        end
    end
    return result
end

local function listChestTotals(peripheralObj)
    local totals = {}
    if type(peripheralObj) ~= "table" then
        return totals
    end
    local ok, items = pcall(function()
        if type(peripheralObj.list) == "function" then
            return peripheralObj.list()
        end
        return nil
    end)
    if not ok or type(items) ~= "table" then
        return totals
    end
    for _, stack in pairs(items) do
        if type(stack) == "table" then
            local name = stack.name or stack.id
            local count = stack.count or stack.qty or stack.quantity
            if type(name) == "string" and type(count) == "number" and count > 0 then
                totals[name] = (totals[name] or 0) + count
            end
        end
    end
    return totals
end

local function gatherChestData(ctx, opts)
    local entries = {}
    local combined = {}
    if not peripheral then
        return entries, combined
    end
    for _, side in ipairs(mapSides(opts)) do
        local ok, detail = inspectSide(side)
        if ok and isContainer(detail) then
            local periphSide = toPeripheralSide(side)
            local okWrap, wrapped = pcall(peripheral.wrap, periphSide)
            local containerName = "container"
            if type(detail) == "table" and type(detail.name) == "string" and detail.name ~= "" then
                containerName = detail.name
            end
            if okWrap and type(wrapped) == "table" then
                local totals = listChestTotals(wrapped)
                mergeTotals(combined, totals)
                entries[#entries + 1] = {
                    side = side,
                    name = containerName,
                    totals = totals,
                }
            else
                entries[#entries + 1] = {
                    side = side,
                    name = containerName,
                    totals = {},
                    error = "wrap_failed",
                }
            end
        end
    end
    if next(combined) == nil then
        combined = {}
    end
    return entries, combined
end

local function gatherTurtleTotals(ctx)
    local totals = {}
    local ok, err = inventory.scan(ctx, { force = true })
    if not ok then
        return totals, err
    end
    local observed, mapErr = inventory.getTotals(ctx, { force = true })
    if not observed then
        return totals, mapErr
    end
    for material, count in pairs(observed) do
        if type(count) == "number" and count > 0 then
            totals[material] = count
        end
    end
    return totals
end

local function summariseMissing(manifest, totals)
    local missing = {}
    for material, required in pairs(manifest) do
        local have = totals[material] or 0
        if have < required then
            missing[#missing + 1] = {
                material = material,
                required = required,
                have = have,
                missing = required - have,
            }
        end
    end
    table.sort(missing, function(a, b)
        if a.missing == b.missing then
            return a.material < b.material
        end
        return a.missing > b.missing
    end)
    return missing
end

local function promptUser(report, attempt, opts)
    if not read then
        return false
    end
    print("\nMissing materials detected:")
    for _, entry in ipairs(report.missing or {}) do
        print(string.format(" - %s: need %d (have %d, short %d)", entry.material, entry.required, entry.have, entry.missing))
    end
    print("Add materials to the turtle or connected chests, then press Enter to retry.")
    print("Type 'cancel' to abort.")
    if type(write) == "function" then
        write("> ")
    end
    local response = read()
    if response and string.lower(response) == "cancel" then
        return false
    end
    return true
end

function initialize.checkMaterials(ctx, spec, opts)
    opts = opts or {}
    spec = spec or {}
    local manifestSrc = spec.manifest or spec.materials or spec
    if not manifestSrc and type(ctx) == "table" and type(ctx.schemaInfo) == "table" then
        manifestSrc = ctx.schemaInfo.materials
    end
    local manifest = normaliseManifest(manifestSrc)
    local report = {
        manifest = copyTotals(manifest),
    }
    if next(manifest) == nil then
        report.ok = true
        return true, report
    end

    local turtleTotals, invErr = gatherTurtleTotals(ctx)
    if invErr then
        report.inventoryError = invErr
        log(ctx, "warn", "Inventory scan failed: " .. tostring(invErr))
    end
    report.turtleTotals = copyTotals(turtleTotals)

    local chestEntries, chestTotals = gatherChestData(ctx, opts)
    report.chests = chestEntries
    report.chestTotals = copyTotals(chestTotals)

    local combinedTotals = copyTotals(turtleTotals)
    mergeTotals(combinedTotals, chestTotals)
    report.combinedTotals = combinedTotals

    report.missing = summariseMissing(manifest, combinedTotals)
    if #report.missing == 0 then
        report.ok = true
        return true, report
    end

    report.ok = false
    return false, report
end

function initialize.ensureMaterials(ctx, spec, opts)
    opts = opts or {}
    local attempt = 0
    while true do
        local ok, report = initialize.checkMaterials(ctx, spec, opts)
        if ok then
            log(ctx, "info", "Material check passed.")
            return true, report
        end
        log(ctx, "warn", "Materials missing; print halted.")
        if opts.nonInteractive then
            return false, report
        end
        attempt = attempt + 1
        local continue = promptUser(report, attempt, opts)
        if not continue then
            return false, report
        end
    end
end

return initialize
