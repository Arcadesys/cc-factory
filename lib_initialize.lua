--[[
Initialization helper for schema-driven builds.
Verifies material availability against a manifest by checking the turtle
inventory plus nearby supply chests. Provides prompting to gather missing
materials before a print begins.
--]]

---@diagnostic disable: undefined-global

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local world = require("lib_world")
local table_utils = require("lib_table")

local initialize = {}

local DEFAULT_SIDES = { "forward", "down", "up", "left", "right", "back" }

local function mapSides(opts)
    local sides = {}
    local seen = {}
    if type(opts) == "table" and type(opts.sides) == "table" then
        for _, side in ipairs(opts.sides) do
            local normalised = world.normaliseSide(side)
            if normalised and not seen[normalised] then
                sides[#sides + 1] = normalised
                seen[normalised] = true
            end
        end
    end
    if #sides == 0 then
        for _, side in ipairs(DEFAULT_SIDES) do
            local normalised = world.normaliseSide(side)
            if normalised and not seen[normalised] then
                sides[#sides + 1] = normalised
                seen[normalised] = true
            end
        end
    end
    return sides
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

local function gatherChestDataForSide(side, entries, combined)
    local periphSide = world.toPeripheralSide(side) or side
    local inspectOk, inspectDetail = world.inspectSide(side)
    local inspectIsContainer = inspectOk and world.isContainer(inspectDetail)
    local inspectName = nil
    if inspectIsContainer and type(inspectDetail) == "table" and type(inspectDetail.name) == "string" and inspectDetail.name ~= "" then
        inspectName = inspectDetail.name
    end

    local wrapOk, wrapped = pcall(peripheral.wrap, periphSide)
    if not wrapOk then
        wrapped = nil
    end

    local metaName, metaTags
    if wrapped then
        if type(peripheral.call) == "function" then
            local metaOk, metadata = pcall(peripheral.call, periphSide, "getMetadata")
            if metaOk and type(metadata) == "table" then
                metaName = metadata.name or metadata.displayName or metaName
                metaTags = metadata.tags
            end
        end
        if not metaName and type(peripheral.getType) == "function" then
            local typeOk, perType = pcall(peripheral.getType, periphSide)
            if typeOk then
                if type(perType) == "string" then
                    metaName = perType
                elseif type(perType) == "table" and type(perType[1]) == "string" then
                    metaName = perType[1]
                end
            end
        end
    end

    local metaIsContainer = false
    if metaName then
        metaIsContainer = world.isContainer({ name = metaName, tags = metaTags })
    end

    local hasInventoryMethods = wrapped and (type(wrapped.list) == "function" or type(wrapped.size) == "function")
    local containerDetected = inspectIsContainer or metaIsContainer or hasInventoryMethods

    if containerDetected then
        local containerName = inspectName or metaName or "container"
        if wrapped and hasInventoryMethods then
            local totals = listChestTotals(wrapped)
            table_utils.mergeTotals(combined, totals)
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

local function gatherChestData(ctx, opts)
    local entries = {}
    local combined = {}
    if not peripheral then
        return entries, combined
    end
    for _, side in ipairs(mapSides(opts)) do
        gatherChestDataForSide(side, entries, combined)
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

local function checkMaterialsInternal(ctx, manifest, opts)
    local report = {
        manifest = table_utils.copyTotals(manifest),
    }
    if next(manifest) == nil then
        report.ok = true
        return true, report
    end

    local turtleTotals, invErr = gatherTurtleTotals(ctx)
    if invErr then
        report.inventoryError = invErr
        logger.log(ctx, "warn", "Inventory scan failed: " .. tostring(invErr))
    end
    report.turtleTotals = table_utils.copyTotals(turtleTotals)

    local chestEntries, chestTotals = gatherChestData(ctx, opts)
    report.chests = chestEntries
    report.chestTotals = table_utils.copyTotals(chestTotals)

    local combinedTotals = table_utils.copyTotals(turtleTotals)
    table_utils.mergeTotals(combinedTotals, chestTotals)
    report.combinedTotals = combinedTotals

    report.missing = summariseMissing(manifest, combinedTotals)
    if #report.missing == 0 then
        report.ok = true
        return true, report
    end

    report.ok = false
    return false, report
end

function initialize.checkMaterials(ctx, spec, opts)
    opts = opts or {}
    spec = spec or {}
    local manifestSrc = spec.manifest or spec.materials or spec
    if not manifestSrc and type(ctx) == "table" and type(ctx.schemaInfo) == "table" then
        manifestSrc = ctx.schemaInfo.materials
    end
    local manifest = normaliseManifest(manifestSrc)
    return checkMaterialsInternal(ctx, manifest, opts)
end

function initialize.ensureMaterials(ctx, spec, opts)
    opts = opts or {}
    local attempt = 0
    while true do
        local ok, report = initialize.checkMaterials(ctx, spec, opts)
        if ok then
            logger.log(ctx, "info", "Material check passed.")
            return true, report
        end
        logger.log(ctx, "warn", "Materials missing; print halted.")
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
