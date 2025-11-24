local reporter = {}
local initialize = require("lib_initialize")
local movement = require("lib_movement")
local fuel = require("lib_fuel")
local inventory = require("lib_inventory")
local world = require("lib_world")
local schema_utils = require("lib_schema")
local string_utils = require("lib_string")

function reporter.describeFuel(io, report)
    fuel.describeFuel(io, report)
end

function reporter.describeService(io, report)
    fuel.describeService(io, report)
end

function reporter.describeMaterials(io, info)
    inventory.describeMaterials(io, info)
end

function reporter.detectContainers(io)
    world.detectContainers(io)
end

function reporter.runCheck(ctx, io, opts)
    inventory.runCheck(ctx, io, opts)
end

function reporter.gatherSummary(io, report)
    inventory.gatherSummary(io, report)
end

function reporter.describeTotals(io, totals)
    inventory.describeTotals(io, totals)
end

function reporter.showHistory(io, entries)
    if not io.print then
        return
    end
    if not entries or #entries == 0 then
        io.print("Captured history: <empty>")
        return
    end
    io.print("Captured history:")
    for _, entry in ipairs(entries) do
        local label = entry.levelLabel or entry.level
        local stamp = entry.timestamp and (entry.timestamp .. " ") or ""
        local tag = entry.tag and (entry.tag .. " ") or ""
        io.print(string.format(" - %s%s%s%s", stamp, tag, label, entry.message and (" " .. entry.message) or ""))
    end
end

function reporter.describePosition(ctx)
    return movement.describePosition(ctx)
end

function reporter.printMaterials(io, info)
    schema_utils.printMaterials(io, info)
end

function reporter.printBounds(io, info)
    schema_utils.printBounds(io, info)
end

function reporter.detailToString(value, depth)
    return string_utils.detailToString(value, depth)
end

function reporter.computeManifest(list)
    return inventory.computeManifest(list)
end

function reporter.printManifest(io, manifest)
    inventory.printManifest(io, manifest)
end

return reporter
