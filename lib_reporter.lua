local reporter = {}
local initialize = require("lib_initialize")
local movement = require("lib_movement")

function reporter.describeFuel(io, report)
    if not io.print then
        return
    end
    if report.unlimited then
        io.print("Fuel: unlimited")
        return
    end
    local levelText = report.level and tostring(report.level) or "unknown"
    local limitText = report.limit and ("/" .. tostring(report.limit)) or ""
    io.print(string.format("Fuel level: %s%s", levelText, limitText))
    if report.threshold then
        io.print(string.format("Threshold: %d", report.threshold))
    end
    if report.reserve then
        io.print(string.format("Reserve target: %d", report.reserve))
    end
    if report.needsService then
        io.print("Status: below threshold (service required)")
    else
        io.print("Status: sufficient for now")
    end
end

function reporter.describeService(io, report)
    if not io.print then
        return
    end
    if not report then
        io.print("No service report available.")
        return
    end
    if report.returnError then
        io.print("Return-to-origin failed: " .. tostring(report.returnError))
    end
    if report.steps then
        for _, step in ipairs(report.steps) do
            if step.type == "return" then
                io.print("Return to origin: " .. (step.success and "OK" or "FAIL"))
            elseif step.type == "refuel" then
                local info = step.report or {}
                local final = info.finalLevel ~= nil and info.finalLevel or (info.endLevel or "unknown")
                io.print(string.format("Refuel step: %s (final=%s)", step.success and "OK" or "FAIL", tostring(final)))
            end
        end
    end
    if report.finalLevel then
        io.print("Service final fuel level: " .. tostring(report.finalLevel))
    end
end

function reporter.describeMaterials(io, info)
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

function reporter.detectContainers(io)
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

function reporter.runCheck(ctx, io, opts)
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

function reporter.gatherSummary(io, report)
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

function reporter.describeTotals(io, totals)
    totals = totals or {}
    local keys = {}
    for material in pairs(totals) do
        keys[#keys + 1] = material
    end
    table.sort(keys)
    if io.print then
        if #keys == 0 then
            io.print("Inventory totals: <empty>")
        else
            io.print("Inventory totals:")
            for _, material in ipairs(keys) do
                io.print(string.format(" - %s x%d", material, totals[material] or 0))
            end
        end
    end
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
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

function reporter.printMaterials(io, info)
    if not io.print then
        return
    end
    if not info or not info.materials or #info.materials == 0 then
        io.print("Materials: <none>")
        return
    end
    io.print("Materials:")
    for _, entry in ipairs(info.materials) do
        io.print(string.format(" - %s x%d", entry.material, entry.count))
    end
end

function reporter.printBounds(io, info)
    if not io.print then
        return
    end
    if not info or not info.bounds or not info.bounds.min then
        io.print("Bounds: <unknown>")
        return
    end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    local dims = {
        x = (maxB.x - minB.x) + 1,
        y = (maxB.y - minB.y) + 1,
        z = (maxB.z - minB.z) + 1,
    }
    io.print(string.format("Bounds: min(%d,%d,%d) max(%d,%d,%d) dims(%d,%d,%d)",
        minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z, dims.x, dims.y, dims.z))
end

function reporter.detailToString(value, depth)
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
        parts[#parts + 1] = tostring(k) .. "=" .. reporter.detailToString(v, depth)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function reporter.computeManifest(list)
    local totals = {}
    for _, sc in ipairs(list) do
        if sc.material and sc.material ~= "" then
            totals[sc.material] = (totals[sc.material] or 0) + 1
        end
    end
    return totals
end

function reporter.printManifest(io, manifest)
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

return reporter
