--[[
Simple 3D printer script powered by the cc-factory libraries.
Reads a text-grid or JSON schema, computes a serpentine build order,
then walks the turtle through each placement from a safe overhead
position. Designed as a starter so you can iterate on more advanced
state-machine driven agents later.

Usage (on the turtle):
    3dprinter [schema.txt] [--offset x y z] [--facing dir] [--dry-run] [--verbose]

All offsets are specified in turtle-local coordinates (x = right/left, y = up/down, z = forward/back).

Defaults:
    * If no schema path is supplied, the script lists detected schemas and selects the first entry (the sample file if present).
    * If no offset is provided, you will be prompted to choose an orientation; pressing Enter keeps option 1 (forward + left).
    * Facing defaults to north. Adjust if your turtle starts facing another way.

The script expects to run on a turtle with the cc-factory libraries on its disk.
--]]

---@diagnostic disable: undefined-global

local parser = require("lib_parser")
local movement = require("lib_movement")
local placement = require("lib_placement")
local inventory = require("lib_inventory")
local loggerLib = require("lib_logger")
local initialize = require("lib_initialize")
local fuelLib = require("lib_fuel")
local orientation = require("lib_orientation")

local HELP = [[
3dprinter - quick-start schema builder

Usage:
  3dprinter [schema_path] [options]

Options:
    --offset <x> <y> <z>   Skip the orientation prompt using LOCAL offsets (x=right, y=up, z=forward)
  --facing <dir>         Initial/home facing (north|south|east|west)
  --dry-run              Preview the build order without moving or placing
  --verbose              Enable verbose logging (debug level)
  --park <n>             Extra vertical clearance before parking (default 2)
  --travel-clearance <n> Extra height above target layer when traversing (default 1)
    --min-fuel <n>         Warn if the fuel level is below n before starting (default 80)
    --list-schemas         Show detected schema files and exit
  --help                 Show this message

If schema_path is omitted, the printer lists detected schemas and prompts for a choice.

Example:
  3dprinter schema_printer_sample.txt --offset 0 0 3 --facing south
]]

local START_ORIENTATIONS = {
    [1] = { label = "Forward + Left", key = "forward_left" },
    [2] = { label = "Forward + Right", key = "forward_right" },
}
local DEFAULT_ORIENTATION = 1


local function computeLocalXZ(bounds, x, z, orientationKey)
    -- Map schema coordinates so every build starts one block forward and diagonally offset from the turtle.
    local orientation = orientation.resolveOrientationKey(orientationKey)
    local relativeX = x - bounds.minX
    local relativeZ = z - bounds.minZ
    local localZ = - (relativeZ + 1)
    local localX
    if orientation == "forward_right" then
        localX = relativeX + 1
    else
        localX = - (relativeX + 1)
    end
    return localX, localZ
end

local function promptStartCell(opts, logger)
    if opts.offsetProvided then
        return
    end

    local selection = DEFAULT_ORIENTATION
    if type(read) == "function" then
        print("")
        print("Select build orientation relative to the turtle (arrow = front):")
        print(" 1) Forward + Left (front-left corner)")
        print(" 2) Forward + Right (front-right corner)")
        print("Local axes: x = right/left, z = forward/back, y = up/down")
        print("Reference (top-down):")
        print(" L . R")
        print(" . T C")
        print("T = turtle, C = optional chest")

        while true do
            if type(write) == "function" then
                write("Enter 1-2 (default 1): ")
            else
                print("Enter 1-2 (default 1): ")
            end
            local response = read()
            if not response or response == "" then
                break
            end
            local value = tonumber(response)
            if value and START_ORIENTATIONS[value] then
                selection = value
                break
            end
            print("Please enter a number between 1 and 2.")
        end
    elseif logger then
        logger:info("Input unavailable; defaulting orientation to option 1 (forward + left).")
    end

    local choice = START_ORIENTATIONS[selection] or START_ORIENTATIONS[DEFAULT_ORIENTATION]
    opts.orientation = orientation.resolveOrientationKey(choice.key or opts.orientation)
    opts.offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    opts.offset = orientation.localToWorld(opts.offsetLocal, opts.facing)
    opts.startCell = selection
    if logger then
        logger:info(string.format("Using orientation %s", choice.label))
    end
    opts.orientationLogged = true
end

local function resolveFacing(opts, logger)
    if opts.facingProvided then
        opts.facing = orientation.normaliseFacing(opts.facing)
        if not opts.facing and logger then
            logger:warn("Unknown facing provided; defaulting to north.")
        end
    elseif opts.dryRun then
        if logger then
            logger:info("Dry run requested; skipping automatic facing detection. Using configured facing.")
        end
    else
        local detected, reason = orientation.detectFacingWithGps(logger)
        if detected then
            opts.facing = orientation.normaliseFacing(detected)
            if logger and opts.facing then
                logger:info(string.format("Detected turtle facing: %s (build will extend forward).")
            end
        else
            local manualFacing
            if type(read) == "function" then
                print("Unable to auto-detect facing. Enter north/east/south/west or press Enter to assume north:")
                while true do
                    if type(write) == "function" then
                        write("> ")
                    else
                        print("> ")
                    end
                    local response = read()
                    if not response or response == "" then
                        break
                    end
                    local normalised = orientation.normaliseFacing(response)
                    if normalised then
                        manualFacing = normalised
                        break
                    end
                    print("Please enter north, east, south, or west.")
                end
            end

            if manualFacing then
                opts.facing = manualFacing
                if logger then
                    local message = reason and string.format("Auto facing detection unavailable (%s); using manual input: %s.", reason, manualFacing) or string.format("Auto facing detection unavailable; using manual input: %s.", manualFacing)
                    logger:info(message)
                end
            else
                opts.facing = orientation.normaliseFacing(opts.facing)
                if not opts.facing then
                    opts.facing = "north"
                end

                if logger then
                    local message
                    if reason == "gps_unavailable" then
                        message = "GPS unavailable; defaulting to north. Use --facing to override."
                    elseif reason == "forward_blocked" then
                        message = "Unable to move forward to detect facing; defaulting to north. Clear space or use --facing."
                    elseif reason == "turtle_api_unavailable" then
                        message = "Turtle API unavailable for facing detection; defaulting to north."
                    elseif reason == "return_failed" then
                        message = "Automatic facing detection failed to restore the turtle's position; defaulting to north. Realign and rerun if the build origin shifted."
                    elseif reason == "gps_initial_failed" or reason == "gps_second_failed" then
                        message = "GPS locate did not respond; defaulting to north. Ensure a GPS network is available or use --facing."
                    elseif reason == "gps_delta_small" then
                        message = "GPS delta too small to determine facing; defaulting to north. Retry after improving signal or use --facing."
                    else
                        message = "Unable to detect facing automatically; defaulting to north. Use --facing to override."
                    end
                    logger:warn(message)
                end
            end
        end
    end

    opts.facing = orientation.normaliseFacing(opts.facing) or "north"
end

local function parseArgs(raw)
    local opts = {
        schemaPath = nil,
        offset = nil,
        offsetLocal = nil,
        offsetProvided = false,
        facing = nil,
        facingProvided = false,
        dryRun = false,
        verbose = false,
        parkClearance = 2,
        travelClearance = 1,
        minFuel = 80,
        listSchemas = false,
        orientation = START_ORIENTATIONS[DEFAULT_ORIENTATION].key,
    }

    local i = 1
    while i <= #raw do
        local arg = raw[i]
        if arg == "--help" or arg == "-h" then
            opts.showHelp = true
            return opts
        elseif arg == "--dry-run" then
            opts.dryRun = true
            i = i + 1
        elseif arg == "--verbose" or arg == "-v" then
            opts.verbose = true
            i = i + 1
        elseif arg == "--facing" then
            local value = raw[i + 1]
            if not value then
                opts.parseError = "--facing requires a direction"
                return opts
            end
            opts.facing = value:lower()
            opts.facingProvided = true
            i = i + 2
        elseif arg == "--offset" then
            local ox, oy, oz = raw[i + 1], raw[i + 2], raw[i + 3]
            if not (ox and oy and oz) then
                opts.parseError = "--offset requires three numbers"
                return opts
            end
            ox, oy, oz = tonumber(ox), tonumber(oy), tonumber(oz)
            if not (ox and oy and oz) then
                opts.parseError = "--offset values must be numbers"
                return opts
            end
            opts.offsetLocal = { x = ox, y = oy, z = oz }
            opts.offsetProvided = true
            i = i + 4
        elseif arg == "--park" then
            local value = raw[i + 1]
            if not value then
                opts.parseError = "--park requires a number"
                return opts
            end
            local num = tonumber(value)
            if not num then
                opts.parseError = "--park value must be a number"
                return opts
            end
            opts.parkClearance = math.max(0, num)
            i = i + 2
        elseif arg == "--travel-clearance" then
            local value = raw[i + 1]
            if not value then
                opts.parseError = "--travel-clearance requires a number"
                return opts
            end
            local num = tonumber(value)
            if not num then
                opts.parseError = "--travel-clearance value must be a number"
                return opts
            end
            opts.travelClearance = math.max(0, num)
            i = i + 2
        elseif arg == "--min-fuel" then
            local value = raw[i + 1]
            if not value then
                opts.parseError = "--min-fuel requires a number"
                return opts
            end
            local num = tonumber(value)
            if not num then
                opts.parseError = "--min-fuel value must be a number"
                return opts
            end
            opts.minFuel = math.max(0, math.floor(num))
            i = i + 2
        elseif arg == "--list-schemas" then
            opts.listSchemas = true
            i = i + 1
        else
            if not opts.schemaPath then
                opts.schemaPath = arg
            else
                opts.extraArgs = opts.extraArgs or {}
                opts.extraArgs[#opts.extraArgs + 1] = arg
            end
            i = i + 1
        end
    end

    return opts
end

local SCHEMA_EXTENSIONS = {
    txt = true,
    json = true,
    grid = true,
    vox = true,
    voxel = true,
    schem = true,
    schematic = true,
}

local function collectSchemas(searchDir)
    if not fs or type(fs.list) ~= "function" or type(fs.isDir) ~= "function" then
        return {}
    end
    searchDir = searchDir or ""
    local ok, entries = pcall(fs.list, searchDir)
    if not ok or type(entries) ~= "table" then
        return {}
    end
    local results = {}
    for _, name in ipairs(entries) do
        local path = searchDir ~= "" and fs.combine(searchDir, name) or name
        if not fs.isDir(path) then
            local ext = name:match("%.([%w_%-]+)$")
            if ext then
                ext = ext:lower()
                if SCHEMA_EXTENSIONS[ext] then
                    results[#results + 1] = path
                end
            end
        end
    end
    table.sort(results)
    return results
end

local function printSchemaList(schemaFiles)
    if #schemaFiles == 0 then
        print("No schema files found in the current directory.")
        return
    end
    print("Detected schema files:")
    for index, path in ipairs(schemaFiles) do
        print(string.format("  [%d] %s", index, path))
    end
end

local function resolveSchemaPath(opts, logger)
    local candidates
    if opts.listSchemas then
        candidates = collectSchemas("")
        printSchemaList(candidates)
        return nil, "list_only"
    end
    if opts.schemaPath and opts.schemaPath ~= "" then
        return opts.schemaPath
    end
    candidates = candidates or collectSchemas("")
    if #candidates == 0 then
        if logger then
            logger:error("No schema files found; supply a path or add a schema_*.txt/json file.")
        end
        return nil, "no_schemas"
    end
    printSchemaList(candidates)
    if #candidates == 1 then
        local choice = candidates[1]
        if logger then
            logger:info(string.format("Only one schema detected; defaulting to %s", choice))
        end
        return choice
    end
    if type(read) ~= "function" then
        local choice = candidates[1]
        if logger then
            logger:warn("Input unavailable; defaulting to first schema in list.")
        end
        return choice
    end
    while true do
        local prompt = string.format("Select schema [1-%d] or enter a path (blank for 1): ", #candidates)
        if type(write) == "function" then
            write(prompt)
        else
            print(prompt)
        end
        local response = read()
        if not response or response == "" then
            return candidates[1]
        end
        local index = tonumber(response)
        if index and candidates[index] then
            return candidates[index]
        end
        if fs and type(fs.exists) == "function" and fs.exists(response) and not fs.isDir(response) then
            return response
        end
        print("Invalid selection; try again.")
    end
end

local function getBlock(schema, x, y, z)
    local xLayer = schema[x] or schema[tostring(x)]
    if not xLayer then
        return nil
    end
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if not yLayer then
        return nil
    end
    return yLayer[z] or yLayer[tostring(z)]
end

local function isPlaceable(block)
    if not block then
        return false
    end
    local name = block.material
    if not name or name == "" then
        return false
    end
    if name == "minecraft:air" or name == "air" then
        return false
    end
    return true
end

local function computeApproachLocal(localPos, side)
    side = side or "down"
    if side == "up" then
        return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
    elseif side == "down" then
        return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
    else
        -- Treat any other directive as forward placement from the block position.
        return { x = localPos.x, y = localPos.y, z = localPos.z }, side
    end
end

local function toNumber(value)
    local num = tonumber(value)
    if not num then
        return nil
    end
    return num
end

local function normaliseBounds(info)
    if not info or not info.bounds then
        return nil, "missing_bounds"
    end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    if not (minB and maxB) then
        return nil, "missing_bounds"
    end
    local function norm(axisTable, axis)
        local raw = axisTable and axisTable[axis]
        return toNumber(raw)
    end
    local minX = norm(minB, "x") or 0
    local minY = norm(minB, "y") or 0
    local minZ = norm(minB, "z") or 0
    local maxX = norm(maxB, "x") or minX
    local maxY = norm(maxB, "y") or minY
    local maxZ = norm(maxB, "z") or minZ
    return {
        minX = minX,
        minY = minY,
        minZ = minZ,
        maxX = maxX,
        maxY = maxY,
        maxZ = maxZ,
    }
end

local function buildOrder(schema, info, opts)
    local bounds, err = normaliseBounds(info)
    if not bounds then
        return nil, err or "missing_bounds"
    end
    opts = opts or {}
    local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    local offsetXLocal = offsetLocal.x or 0
    local offsetYLocal = offsetLocal.y or 0
    local offsetZLocal = offsetLocal.z or 0
    orientation.resolveOrientationKey(opts.orientation)

    local order = {}
    for y = bounds.minY, bounds.maxY do
        for row = 0, bounds.maxZ - bounds.minZ do
            local z = bounds.minZ + row
            local forward = (row % 2) == 0
            local xStart = forward and bounds.minX or bounds.maxX
            local xEnd = forward and bounds.maxX or bounds.minX
            local step = forward and 1 or -1
            local x = xStart
            while true do
                local block = getBlock(schema, x, y, z)
                if isPlaceable(block) then
                    local baseX, baseZ = computeLocalXZ(bounds, x, z, orientation)
                    local localPos = {
                        x = baseX + offsetXLocal,
                        y = y + offsetYLocal,
                        z = baseZ + offsetZLocal,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproachLocal(localPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        localPos = localPos,
                        approachLocal = approach,
                        block = block,
                        side = resolvedSide,
                    }
                end
                if x == xEnd then
                    break
                end
                x = x + step
            end
        end
    end
    return order, bounds
end

local function registerPlannedBlock(plan, pos, material)
    if not material or material == "" then
        return
    end

    local x = pos.x or 0
    local y = pos.y or 0
    local z = pos.z or 0

    plan[x] = plan[x] or {}
    local xLayer = plan[x]
    xLayer[y] = xLayer[y] or {}
    xLayer[y][z] = material
end

local function prepareBuildPlan(ctx, order, opts)
    if type(ctx) ~= "table" or type(order) ~= "table" then
        return
    end

    opts = opts or {}
    local plan = {}
    local origin = ctx.origin or { x = 0, y = 0, z = 0 }

    for _, step in ipairs(order) do
        local block = step.block
        if isPlaceable(block) and step.localPos then
            local worldOffset = localToWorld(step.localPos, opts.facing)
            local pos = {
                x = (origin.x or 0) + (worldOffset.x or 0),
                y = (origin.y or 0) + (worldOffset.y or 0),
                z = (origin.z or 0) + (worldOffset.z or 0),
            }
            registerPlannedBlock(plan, pos, block.material)
        end
    end

    ctx.buildPlan = plan
end

local function travelTo(ctx, target, travelClearance)
    -- Move via an elevated waypoint to minimise collisions with the freshly printed build.
    local current = movement.getPosition(ctx)
    travelClearance = travelClearance or 0
    local midY = math.max(current.y, target.y + travelClearance)

    if current.y < midY then
        local ok, err = movement.goTo(ctx, { x = current.x, y = midY, z = current.z }, { axisOrder = { "y", "x", "z" } })
        if not ok then
            return false, err
        end
        current = movement.getPosition(ctx)
    end

    if current.x ~= target.x or current.z ~= target.z then
        local ok, err = movement.goTo(ctx, { x = target.x, y = current.y, z = target.z }, { axisOrder = { "x", "z", "y" } })
        if not ok then
            return false, err
        end
        current = movement.getPosition(ctx)
    end

    if current.y ~= target.y then
        local ok, err = movement.goTo(ctx, target, { axisOrder = { "y", "x", "z" } })
        if not ok then
            return false, err
        end
    end

    return true
end

local function ensureFacing(ctx, facing, logger)
    if not facing then
        return
    end
    local ok, err = movement.faceDirection(ctx, facing)
    if not ok and logger then
        logger:warn(string.format("Unable to set facing to %s: %s", tostring(facing), tostring(err)))
    end
end

local function returnToOrigin(ctx, opts, bounds, logger)
    -- Route the turtle home via a safe overhead waypoint to avoid freshly placed blocks.
    if opts.dryRun then
        ensureFacing(ctx, opts.facing, logger)
        return true
    end

    local current = movement.getPosition(ctx)
    if not current then
        return false, "unknown_position"
    end

    local origin = ctx.origin or { x = 0, y = 0, z = 0 }
    local safeY = math.max(current.y, origin.y)
    if bounds then
        local offsetLocalY = (opts.offsetLocal and opts.offsetLocal.y) or 0
        safeY = math.max(safeY, (bounds.maxY + offsetLocalY) + opts.parkClearance)
    else
        safeY = safeY + math.max(0, opts.parkClearance)
    end

    if current.y < safeY then
        local ok, err = travelTo(ctx, { x = current.x, y = safeY, z = current.z }, opts.travelClearance)
        if not ok then
            return false, err
        end
        current = movement.getPosition(ctx)
        if not current then
            return false, "position_update_failed"
        end
    end

    if current.x ~= origin.x or current.z ~= origin.z then
        local ok, err = travelTo(ctx, { x = origin.x, y = current.y, z = origin.z }, opts.travelClearance)
        if not ok then
            return false, err
        end
        current = movement.getPosition(ctx)
        if not current then
            return false, "position_update_failed"
        end
    end

    if current.y ~= origin.y then
        local ok, err = travelTo(ctx, origin, opts.travelClearance)
        if not ok then
            return false, err
        end
    end

    ensureFacing(ctx, opts.facing, logger)
    return true
end

local restockMaterial

local function attemptAutoRestock(ctx, opts, bounds, step, logger)
    if not ctx or (opts and opts.dryRun) then
        return false
    end
    if not ctx.hasSupplyChest then
        return false
    end
    if not step or not step.block or not step.block.material then
        return false
    end

    local material = step.block.material

    local homeOk, homeErr = returnToOrigin(ctx, opts, bounds, logger)
    if not homeOk then
        if logger and logger.warn then
            logger:warn(string.format("Unable to reach supply chest for %s: %s", material, tostring(homeErr)))
        end
        return false
    end

    inventory.invalidate(ctx)

    local targets = ctx.materialTargets or {}
    local target = targets[material] or 64

    local before, beforeErr = inventory.countMaterial(ctx, material, { force = true })
    if beforeErr then
        if logger and logger.debug then
            logger:debug(string.format("Inventory scan failed before restock: %s", tostring(beforeErr)))
        end
        before = 0
    end

    local count, metTarget, restockErr = restockMaterial(ctx, material, target, logger)
    if restockErr then
        if logger and logger.debug then
            logger:debug(string.format("Automatic restock for %s failed: %s", material, tostring(restockErr)))
        end
        return count > before
    end

    if count > before then
        local gained = count - before
        if logger then
            if metTarget and logger.info then
                logger:info(string.format("Restocked %s (+%d, now %d)", material, gained, count))
            elseif logger.debug then
                logger:debug(string.format("Restocked %s (+%d, now %d/%d)", material, gained, count, target))
            end
        end
        return true
    end

    if count > 0 then
        return true
    end

    if logger and logger.warn then
        logger:warn(string.format("Supply chest is out of %s; awaiting manual refill.", material))
    end
    return false
end

local function awaitMaterialRefill(ctx, opts, bounds, step, logger)
    if not step or not step.block or not step.block.material then
        return false
    end

    local material = step.block.material
    if logger then
        logger:error(string.format("Out of %s; pausing print until restocked.", material))
    end

    if not opts.dryRun then
        local homeOk, homeErr = returnToOrigin(ctx, opts, bounds, logger)
        if not homeOk and logger then
            logger:warn(string.format("Unable to return home while waiting for %s: %s", material, tostring(homeErr)))
        end
    end

    if type(read) ~= "function" then
        if logger then
            logger:error("Input unavailable; cannot await manual restock. Aborting print.")
        end
        return false
    end

    print("")
    print(string.format("Refill %s, then press Enter to resume. Type 'abort' to cancel the print.", material))

    while true do
        if type(write) == "function" then
            write("> ")
        else
            print("> ")
        end
        local response = read()
        local trimmed = response and response:gsub("^%s+", ""):gsub("%s+$", "") or ""

        if trimmed == "" then
            inventory.invalidate(ctx)
            local total, err = inventory.countMaterial(ctx, material, { force = true })
            if err then
                if logger then
                    logger:warn(string.format("Inventory scan failed while waiting for %s: %s", material, tostring(err)))
                end
            elseif total and total > 0 then
                if logger then
                    logger:info(string.format("Detected %d x %s; resuming print.", total, material))
                end
                return true
            else
                print(string.format("Still missing %s. Restock and press Enter to retry, or type 'abort' to stop.", material))
            end
        else
            local lower = trimmed:lower()
            if lower == "abort" or lower == "stop" or lower == "quit" or lower == "exit" then
                if logger then
                    logger:warn("Print aborted by user during restock pause.")
                end
                return false
            else
                print("Press Enter to retry once materials are available, or type 'abort' to cancel.")
            end
        end
    end
end

local function awaitObstacleClear(ctx, opts, step, reason, logger)
    if type(read) ~= "function" then
        if logger then
            logger:error("Placement blocked and no input available; aborting print.")
        end
        return false
    end

    local blockingName
    if ctx and ctx.placement and ctx.placement.lastPlacement then
        blockingName = ctx.placement.lastPlacement.blocking
    end

    local pos = step and step.localPos or nil
    local posText = pos and string.format("(%d,%d,%d)", pos.x or 0, pos.y or 0, pos.z or 0) or "unknown"
    local material = step and step.block and step.block.material or "unknown"

    print("")
    print(string.format("Placement blocked at local %s while placing %s.", posText, material))
    if blockingName then
        print(string.format("Detected blocking block: %s", blockingName))
    end
    if reason == "mismatched_block" then
        print("Clear the conflicting block, then press Enter to retry. Type 'cancel' to abort.")
    else
        print("Resolve the obstruction, then press Enter to retry. Type 'cancel' to abort.")
    end

    while true do
        if type(write) == "function" then
            write("> ")
        else
            print("> ")
        end
        local response = read()
        local trimmed = response and response:gsub("^%s+", ""):gsub("%s+$", "") or ""

        if trimmed == "" or trimmed:lower() == "retry" or trimmed:lower() == "continue" then
            return true
        end

        local lower = trimmed:lower()
        if lower == "cancel" or lower == "abort" or lower == "stop" or lower == "quit" or lower == "exit" then
            if logger then
                logger:warn("Print aborted by user after blockage notification.")
            end
            return false
        end

        print("Press Enter to retry once the path is clear, or type 'cancel' to abort.")
    end
end

local function handlePlacementFailure(ctx, opts, bounds, step, reason, logger)
    reason = reason or "unknown"
    if reason == "missing_material" then
        if attemptAutoRestock(ctx, opts, bounds, step, logger) then
            return "retry"
        end
        local resumed = awaitMaterialRefill(ctx, opts, bounds, step, logger)
        if resumed then
            return "retry"
        end
        return "abort"
    end

    if reason == "mismatched_block" or reason == "blocked" then
        local blockingName
        if ctx and ctx.placement and ctx.placement.lastPlacement then
            blockingName = ctx.placement.lastPlacement.blocking
        end
        if logger then
            if step and step.localPos then
                logger:warn(string.format("Placement blocked at local (%d,%d,%d) by %s; awaiting manual clear.", step.localPos.x or 0, step.localPos.y or 0, step.localPos.z or 0, blockingName or "unknown block"))
            else
                logger:warn(string.format("Placement blocked by %s; awaiting manual clear.", blockingName or "unknown block"))
            end
        end
        local resumed = awaitObstacleClear(ctx, opts, step, reason, logger)
        if resumed then
            return "retry"
        end
        return "abort"
    end

    if logger then
        if step and step.localPos then
            logger:error(string.format("Placement failed at local (%d,%d,%d) with reason '%s'; aborting print.", step.localPos.x or 0, step.localPos.y or 0, step.localPos.z or 0, tostring(reason)))
        else
            logger:error(string.format("Placement failed with reason '%s'; aborting print.", tostring(reason)))
        end
    end
    return "abort"
end

local function readFuel()
    if not turtle or not turtle.getFuelLevel then
        return nil, nil, false
    end
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit and turtle.getFuelLimit() or nil
    if level == "unlimited" or limit == "unlimited" then
        return nil, nil, true
    end
    if level == math.huge or limit == math.huge then
        return nil, nil, true
    end
    if type(level) ~= "number" then
        return nil, nil, false
    end
    if type(limit) ~= "number" then
        limit = nil
    end
    return level, limit, false
end

local function logFuel(logger, prefix)
    local level, limit, unlimited = readFuel()
    if unlimited then
        logger:debug((prefix or "") .. "Fuel is unlimited; skipping fuel tracking.")
        return
    end
    if not level then
        return
    end
    local suffix = limit and string.format("/%d", limit) or ""
    logger:info(string.format("%sFuel level: %d%s", prefix or "", level, suffix))
end

local function ensureInitialFuel(ctx, logger, minFuel)
    local level, limit, unlimited = readFuel()
    if unlimited then
        logger:debug("Fuel reported as unlimited; continuing without checks.")
        return true, nil
    end
    if not level then
        logger:debug("Fuel API unavailable or unreadable; continuing without checks.")
        return true, nil
    end

    if level <= 0 then
        logger:warn("Fuel depleted; attempting automatic refuel before starting.")
        if ctx then
            local threshold = (minFuel and minFuel > 0) and minFuel or 1
            local reserve = (ctx.fuelState and ctx.fuelState.reserve) or nil
            if not reserve or reserve <= threshold then
                reserve = math.max(threshold * 2, threshold + 64)
            end
            local refuelOk, refuelReport = fuelLib.ensure(ctx, {
                threshold = threshold,
                reserve = reserve,
                target = reserve,
                rounds = 4,
            })
            if not refuelOk then
                logger:error("Automatic refuel failed; supply fuel manually and retry.")
                if refuelReport and refuelReport.note then
                    logger:warn(tostring(refuelReport.note))
                end
                if refuelReport and refuelReport.service then
                    local service = refuelReport.service
                    if service.returnError then
                        logger:error("SERVICE return failed: " .. tostring(service.returnError))
                    elseif service.error then
                        logger:error("SERVICE error: " .. tostring(service.error))
                    end
                end
                return false, level
            end
            level = refuelReport and refuelReport.level or select(1, readFuel()) or level
            limit = refuelReport and refuelReport.limit or select(2, readFuel()) or limit
            if not level or level <= 0 then
                logger:error("Refuel reported success but fuel level remains empty.")
                return false, level or 0
            end
            logger:info("Refuel complete; continuing startup checks.")
        else
            logger:error("Fuel depleted and no context available for refuel.")
            return false, level
        end
    end

    local suffix = limit and string.format("/%d", limit) or ""
    logger:info(string.format("Starting fuel: %d%s", level, suffix))
    if minFuel and minFuel > 0 and level < minFuel then
        logger:warn(string.format("Fuel %d is below the requested minimum (%d). Refuel or lower --min-fuel.", level, minFuel))
    end
    return true, level
end

local function logMaterials(logger, info)
    if not info or not info.materials then
        return
    end
    for _, entry in ipairs(info.materials) do
        if entry.material ~= "minecraft:air" and entry.material ~= "air" then
            logger:info(string.format("Requires %d x %s", entry.count or 0, entry.material))
        end
    end
end

local function sortedKeys(map)
    local keys = {}
    if type(map) ~= "table" then
        return keys
    end
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function logMaterialAvailability(logger, report, verbose)
    if type(report) ~= "table" then
        return
    end
    if report.inventoryError then
        logger:warn(string.format("Inventory scan issue: %s", tostring(report.inventoryError)))
    end
    if type(report.chests) == "table" then
        for _, entry in ipairs(report.chests) do
            if entry.error == "wrap_failed" then
                logger:warn(string.format("Unable to query container on %s: peripheral wrap failed", tostring(entry.side or "unknown")))
            elseif verbose then
                local totals = entry.totals or {}
                local materials = sortedKeys(totals)
                if #materials > 0 then
                    logger:debug(string.format("Chest %s (%s) inventory:", tostring(entry.side or "unknown"), tostring(entry.name or "container")))
                    for _, material in ipairs(materials) do
                        logger:debug(string.format("  %s x%d", material, totals[material] or 0))
                    end
                end
            end
        end
    end
    if verbose and report.combinedTotals then
        local materials = sortedKeys(report.combinedTotals)
        if #materials > 0 then
            logger:debug("Combined turtle + chest totals:")
            for _, material in ipairs(materials) do
                logger:debug(string.format("  %s x%d", material, report.combinedTotals[material] or 0))
            end
        end
    end
end

local function hasSupplyAccess(report)
    if type(report) ~= "table" then
        return false
    end
    if type(report.chests) ~= "table" then
        return false
    end
    for _, entry in ipairs(report.chests) do
        if type(entry) == "table" and not entry.error then
            return true
        end
    end
    return false
end

local function computeTargetStacks(report)
    local targets = {}
    local manifest = report and report.manifest
    if type(manifest) ~= "table" then
        return targets
    end
    for material, _ in pairs(manifest) do
        if type(material) == "string" and material ~= "minecraft:air" and material ~= "air" then
            targets[material] = 64
        end
    end
    return targets
end

function restockMaterial(ctx, material, target, logger)
    target = (target and target > 0) and target or 64
    local attempts = 0
    local lastCount = -1
    while attempts < 4 do
        local count, countErr = inventory.countMaterial(ctx, material, { force = true })
        if countErr then
            return 0, false, countErr
        end
        if count >= target then
            return count, true, nil
        end
        if count <= lastCount then
            break
        end
        lastCount = count
        local request = math.max(target - count, 1)
        local ok, pullErr = inventory.pullMaterial(ctx, material, request, { side = "forward" })
        if not ok then
            return count, false, pullErr
        end
        inventory.invalidate(ctx)
        attempts = attempts + 1
    end

    local finalCount, finalErr = inventory.countMaterial(ctx, material, { force = true })
    if finalErr then
        return 0, false, finalErr
    end
    return finalCount, finalCount >= target, nil
end

local function primeManifestInventory(ctx, logger)
    if not ctx.materialReport then
        return
    end

    ctx.materialTargets = computeTargetStacks(ctx.materialReport)
    ctx.hasSupplyChest = hasSupplyAccess(ctx.materialReport)

    local targets = ctx.materialTargets
    if not ctx.hasSupplyChest or not targets or next(targets) == nil then
        if logger and logger.debug then
            logger:debug("Supply chests unavailable; skipping manifest priming.")
        end
        return
    end

    inventory.invalidate(ctx)

    local materials = {}
    for material in pairs(targets) do
        materials[#materials + 1] = material
    end
    table.sort(materials)

    for _, material in ipairs(materials) do
        local target = targets[material]
        local before, beforeErr = inventory.countMaterial(ctx, material, { force = true })
        if beforeErr then
            if logger and logger.debug then
                logger:debug(string.format("Unable to read inventory for %s: %s", material, tostring(beforeErr)))
            end
        elseif before < target then
            local count, metTarget, restockErr = restockMaterial(ctx, material, target, logger)
            if restockErr then
                if logger and logger.debug then
                    logger:debug(string.format("Priming %s failed: %s", material, tostring(restockErr)))
                end
            else
                local gained = count - before
                if gained > 0 then
                    if logger and logger.info then
                        logger:info(string.format("Primed %s (+%d, now %d)", material, gained, count))
                    end
                elseif not metTarget and logger and logger.warn then
                    logger:warn(string.format("Supply chest lacks enough %s; have %d", material, count))
                end
            end
        end
    end
end

local function run(rawArgs)
    local opts = parseArgs(rawArgs)
    if opts.showHelp then
        print(HELP)
        return
    end
    if opts.parseError then
        print("Argument error: " .. opts.parseError)
        return
    end

    if not turtle then
        error("3dprinter.lua must be run on a turtle.")
    end

    local logger = loggerLib.new({ level = opts.verbose and "debug" or "info", tag = "3dprinter", timestamps = false })

    local selectedSchema, schemaErr = resolveSchemaPath(opts, logger)
    if not selectedSchema then
        if schemaErr == "list_only" then
            return
        end
        return
    end
    opts.schemaPath = selectedSchema

    resolveFacing(opts, logger)

    if not opts.offsetProvided then
        promptStartCell(opts, logger)
    else
        opts.offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
        opts.offset = localToWorld(opts.offsetLocal, opts.facing)
        if logger then
            logger:info(string.format("Using CLI local offset x=%d y=%d z=%d", opts.offsetLocal.x, opts.offsetLocal.y, opts.offsetLocal.z))
        end
    end

    if not opts.offsetLocal then
        -- Fallback for non-interactive environments: zero offset with default orientation
        opts.offsetLocal = { x = 0, y = 0, z = 0 }
    else
        opts.offsetLocal.x = opts.offsetLocal.x or 0
        opts.offsetLocal.y = opts.offsetLocal.y or 0
        opts.offsetLocal.z = opts.offsetLocal.z or 0
    end
    opts.offset = localToWorld(opts.offsetLocal, opts.facing)
    if logger and not opts.orientationLogged then
        logger:info(string.format("Orientation set to %s.", orientation.orientationLabel(opts.orientation)))
    end

    local ctx = {
        origin = { x = 0, y = 0, z = 0 },
        config = {
            verbose = opts.verbose,
            initialFacing = opts.facing,
            homeFacing = opts.facing,
            defaultPlacementSide = "down",
            maxMoveRetries = 8,
            moveRetryDelay = 0.4,
            digOnMove = true,
            attackOnMove = true,
            minFuel = opts.minFuel,
        },
        logger = logger,
        fuelState = {
            threshold = (opts.minFuel and opts.minFuel > 0) and opts.minFuel or nil,
            lastKnown = nil,
            reserve = (opts.minFuel and opts.minFuel > 0) and math.max(opts.minFuel * 2, opts.minFuel + 64) or nil,
        },
    }

    movement.ensureState(ctx)
    movement.setPosition(ctx, ctx.origin)
    ensureFacing(ctx, opts.facing, logger)
    placement.ensureState(ctx)
    inventory.ensureState(ctx)
    fuelLib.ensureState(ctx)

    local fuelOk, fuelLevel = ensureInitialFuel(ctx, logger, opts.minFuel)
    if not fuelOk then
        return
    end
    if ctx.fuelState then
        ctx.fuelState.lastKnown = fuelLevel
    end
    ensureFacing(ctx, opts.facing, logger)

    logger:info(string.format("Loading schema: %s", opts.schemaPath))
    local ok, schemaOrErr, info = parser.parseFile(ctx, opts.schemaPath, { formatHint = nil })
    if not ok then
        logger:error("Failed to parse schema: " .. tostring(schemaOrErr))
        return
    end
    local schema = schemaOrErr
    ctx.schema = schema
    ctx.schemaInfo = info

    logMaterials(logger, info)

    local manifestSpec = { manifest = info and info.materials or nil }
    local materialsOk, materialReport = initialize.ensureMaterials(ctx, manifestSpec, { sides = opts.chestSides })
    ctx.materialReport = materialReport
    logMaterialAvailability(logger, materialReport, opts.verbose)
    if not materialsOk then
        if materialReport and materialReport.missing then
            for _, entry in ipairs(materialReport.missing) do
                logger:error(string.format("Missing %s: need %d, have %d", entry.material, entry.required, entry.have))
            end
        end
        logger:error("Aborting print due to insufficient materials.")
        return
    end

    if opts.dryRun then
        ctx.materialTargets = computeTargetStacks(ctx.materialReport)
        ctx.hasSupplyChest = hasSupplyAccess(ctx.materialReport)
    else
        primeManifestInventory(ctx, logger)
    end

    local order, boundsOrErr = buildOrder(schema, info, opts)
    if not order then
        logger:error("Unable to derive build order: " .. tostring(boundsOrErr))
        return
    end
    local bounds = boundsOrErr

    if #order == 0 then
        logger:warn("Schema contains no placeable blocks.")
        return
    end

    logger:info(string.format("Planned %d placements across %d layers.", #order, (bounds.maxY - bounds.minY) + 1))
    prepareBuildPlan(ctx, order, opts)
    if opts.dryRun then
        logger:info("Dry run enabled; skipping movement and placement.")
    end

    if not opts.dryRun then
        local scanOk, scanErr = inventory.scan(ctx)
        if not scanOk and scanErr ~= "turtle API unavailable" then
            logger:warn("Inventory scan issue: " .. tostring(scanErr))
        end
        local threshold = (ctx.fuelState and ctx.fuelState.threshold) or opts.minFuel or 0
        local computedReserve = (ctx.fuelState and ctx.fuelState.reserve) or math.max(threshold * 2, threshold + 64)
        local reserve = (computedReserve and computedReserve > 0) and computedReserve or nil
        local fuelOk, fuelReport = fuelLib.ensure(ctx, {
            threshold = threshold,
            reserve = reserve,
            target = reserve,
            rounds = 4,
        })
        ctx.fuelStatus = fuelReport
        if not fuelOk then
            logger:error("Unable to ensure fuel readiness before printing.")
            if fuelReport and fuelReport.service then
                local service = fuelReport.service
                if service.returnError then
                    logger:error("SERVICE return failed: " .. tostring(service.returnError))
                elseif service.error then
                    logger:error("SERVICE error: " .. tostring(service.error))
                end
            end
            if fuelReport and fuelReport.depleted then
                logger:error("Turtle is out of fuel; refuel manually and retry.")
            end
            return
        end
        if fuelReport and fuelReport.level then
            local suffix = fuelReport.limit and string.format("/%d", fuelReport.limit) or ""
            logger:info(string.format("Fuel level ready: %d%s", fuelReport.level, suffix))
        end
    end

    local stats = { placed = 0, reused = 0, skipped = 0, failures = 0, pauses = 0 }
    local aborted = false
    local index = 1
    while index <= #order do
        local step = order[index]
        ctx.pointer = step.schemaPos
        local localPos = step.localPos or { x = 0, y = 0, z = 0 }
        logger:info(string.format("[%d/%d] %s local (%d,%d,%d)", index, #order, step.block.material, localPos.x, localPos.y, localPos.z))
        if opts.verbose then
            local worldPreview = localToWorld(localPos, opts.facing)
            logger:debug(string.format("  world approx (%d,%d,%d)", worldPreview.x, worldPreview.y, worldPreview.z))
        end

        if opts.dryRun then
            stats.skipped = stats.skipped + 1
            index = index + 1
        else
            local retryStep = true
            while retryStep do
                retryStep = false

                local threshold = (ctx.fuelState and ctx.fuelState.threshold) or opts.minFuel or 0
                local computedReserve = (ctx.fuelState and ctx.fuelState.reserve) or math.max(threshold * 2, threshold + 64)
                local reserve = (computedReserve and computedReserve > 0) and computedReserve or nil
                local fuelOk, fuelStatus = fuelLib.ensure(ctx, {
                    threshold = threshold,
                    reserve = reserve,
                    target = reserve,
                    rounds = 2,
                })
                ctx.fuelStatus = fuelStatus
                if not fuelOk then
                    logger:error("Fuel check failed; stopping print.")
                    if fuelStatus and fuelStatus.service then
                        local service = fuelStatus.service
                        if service.returnError then
                            logger:error("SERVICE return failed: " .. tostring(service.returnError))
                        elseif service.error then
                            logger:error("SERVICE error: " .. tostring(service.error))
                        end
                    elseif fuelStatus and fuelStatus.note then
                        logger:warn(tostring(fuelStatus.note))
                    end
                    stats.failures = stats.failures + 1
                    aborted = true
                    break
                end
                if fuelStatus and fuelStatus.level then
                    ctx.fuelState = ctx.fuelState or {}
                    ctx.fuelState.lastKnown = fuelStatus.level
                end

                local approachLocal = step.approachLocal or localPos
                local approachWorld = localToWorld(approachLocal, opts.facing)
                local travelOk, travelErr = travelTo(ctx, approachWorld, opts.travelClearance)
                if not travelOk then
                    local level, limit = readFuel()
                    if level then
                        local suffix = limit and string.format("/%d", limit) or ""
                        logger:error(string.format("Fuel remaining at failure: %d%s", level, suffix))
                        if level <= 0 then
                            logger:error("Turtle is out of fuel; supply fuel and rerun.")
                        end
                    end
                    logger:error("Movement failed: " .. tostring(travelErr))
                    stats.failures = stats.failures + 1
                    aborted = true
                    break
                end

                ensureFacing(ctx, opts.facing, logger)
                local placed, placeInfo = placement.placeMaterial(ctx, step.block.material, { side = step.side, block = step.block, dig = true, attack = true })
                if not placed then
                    local action = handlePlacementFailure(ctx, opts, bounds, step, placeInfo, logger)
                    if action == "retry" then
                        stats.pauses = stats.pauses + 1
                        retryStep = true
                    else
                        stats.failures = stats.failures + 1
                        aborted = true
                    end
                else
                    if placeInfo == "already_present" then
                        stats.reused = stats.reused + 1
                    else
                        stats.placed = stats.placed + 1
                    end
                    index = index + 1
                end

                if aborted then
                    break
                end
            end

            if aborted then
                break
            end
        end
    end

    local homeOk, homeErr = returnToOrigin(ctx, opts, bounds, logger)
    if not homeOk and homeErr then
        logger:warn("Unable to return to origin: " .. tostring(homeErr))
    end

    logger:info(string.format("Placed: %d, reused: %d, skipped: %d, failures: %d", stats.placed, stats.reused, stats.skipped, stats.failures))
    if stats.pauses and stats.pauses > 0 then
        logger:info(string.format("Manual restock pauses: %d", stats.pauses))
    end
    if stats.failures == 0 then
        logger:info("Print complete.")
    else
        logger:warn("Print halted early; inspect the turtle and environment before retrying.")
    end
end

local rawArgs = { ... }
run(rawArgs)
