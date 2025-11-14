--[[
Simple 3D printer script powered by the cc-factory libraries.
Reads a text-grid or JSON schema, computes a serpentine build order,
then walks the turtle through each placement from a safe overhead
position. Designed as a starter so you can iterate on more advanced
state-machine driven agents later.

Usage (on the turtle):
  3dprinter [schema.txt] [--offset x y z] [--facing dir] [--dry-run] [--verbose]

Defaults:
    * If no schema path is supplied, the script lists detected schemas and selects the first entry (the sample file if present).
    * If no offset is provided, you will be prompted to choose a start cell; pressing Enter keeps option 2 (the block in front).
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

local HELP = [[
3dprinter - quick-start schema builder

Usage:
  3dprinter [schema_path] [options]

Options:
    --offset <x> <y> <z>   Skip the start-cell prompt and use these offsets directly
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

local START_CELL_OFFSETS = {
    [1] = { x = -1, z = -1 },
    [2] = { x = 0,  z = -1 },
    [3] = { x = 1,  z = -1 },
    [4] = { x = -1, z = 0 },
    [5] = { x = 1,  z = 0 },
    [6] = { x = -1, z = 1 },
    [7] = { x = 0,  z = 1 },
    [8] = { x = 1,  z = 1 },
}

local function normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

local function facingVectors(facing)
    facing = normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
    end
end

local function rotateLocalOffset(localOffset, facing)
    local vectors = facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * (-dz)),
        z = (right.z * dx) + (forward.z * (-dz)),
    }
end

local function promptStartCell(opts, logger)
    if opts.offsetProvided then
        return
    end

    local selection = 2
    if type(read) == "function" then
        print("")
        print("Select build start location relative to the turtle (arrow = front):")
        print(" [1][2][3]")
        print(" [4][^][5]")
        print(" [6][7][8]")

        while true do
            if type(write) == "function" then
                write("Enter 1-8 (default 2): ")
            else
                print("Enter 1-8 (default 2): ")
            end
            local response = read()
            if not response or response == "" then
                break
            end
            local value = tonumber(response)
            if value and START_CELL_OFFSETS[value] then
                selection = value
                break
            end
            print("Please enter a number between 1 and 8.")
        end
    elseif logger then
        logger:info("Input unavailable; defaulting start location to 2 (front).")
    end

    local offsetLocal = START_CELL_OFFSETS[selection] or START_CELL_OFFSETS[2]
    local rotated = rotateLocalOffset(offsetLocal, opts.facing)
    opts.offset = {
        x = rotated.x,
        y = 0,
        z = rotated.z,
    }
    opts.startCell = selection
    if logger then
        logger:info(string.format("Using start cell %d (offset x=%d, z=%d)", selection, opts.offset.x, opts.offset.z))
    end
end

local function parseArgs(raw)
    local opts = {
        schemaPath = nil,
        offset = nil,
        offsetProvided = false,
        facing = "north",
        dryRun = false,
        verbose = false,
        parkClearance = 2,
        travelClearance = 1,
        minFuel = 80,
        listSchemas = false,
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
            opts.offset = { x = ox, y = oy, z = oz }
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

local function computeApproach(worldPos, side)
    side = side or "down"
    if side == "up" then
        return { x = worldPos.x, y = worldPos.y - 1, z = worldPos.z }, side
    elseif side == "down" then
        return { x = worldPos.x, y = worldPos.y + 1, z = worldPos.z }, side
    else
        -- Treat any other directive as forward placement from the block position.
        return { x = worldPos.x, y = worldPos.y, z = worldPos.z }, side
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

local function buildOrder(schema, info, offset)
    local bounds, err = normaliseBounds(info)
    if not bounds then
        return nil, err or "missing_bounds"
    end
    offset = offset or { x = 0, y = 0, z = 0 }

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
                    local worldPos = {
                        x = x + offset.x,
                        y = y + offset.y,
                        z = z + offset.z,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproach(worldPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        worldPos = worldPos,
                        approach = approach,
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
        safeY = math.max(safeY, (bounds.maxY + opts.offset.y) + opts.parkClearance)
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

local function ensureFacing(ctx, facing, logger)
    if not facing then
        return
    end
    local ok, err = movement.setFacing(ctx, facing)
    if not ok then
        logger:warn(string.format("Unable to set facing to %s: %s", tostring(facing), tostring(err)))
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

    if not opts.offsetProvided then
        promptStartCell(opts, logger)
    else
        opts.offset = opts.offset or { x = 0, y = 0, z = 0 }
        if logger then
            logger:info(string.format("Using CLI offset x=%d y=%d z=%d", opts.offset.x, opts.offset.y, opts.offset.z))
        end
    end

    if not opts.offset then
        -- Fallback for non-interactive environments
        opts.offset = { x = 0, y = 0, z = -1 }
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

    local order, boundsOrErr = buildOrder(schema, info, opts.offset)
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

    local stats = { placed = 0, reused = 0, skipped = 0, failures = 0 }
    for index, step in ipairs(order) do
        ctx.pointer = step.schemaPos
        logger:info(string.format("[%d/%d] %s at (%d,%d,%d)", index, #order, step.block.material, step.worldPos.x, step.worldPos.y, step.worldPos.z))

        if opts.dryRun then
            stats.skipped = stats.skipped + 1
        else
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
                break
            end
            if fuelStatus and fuelStatus.level then
                    threshold = (opts.minFuel and opts.minFuel > 0) and opts.minFuel or nil,
                    lastKnown = nil,
                    reserve = (opts.minFuel and opts.minFuel > 0) and math.max(opts.minFuel * 2, opts.minFuel + 64) or nil,
            local travelOk, travelErr = travelTo(ctx, step.approach, opts.travelClearance)
            if not travelOk then
                local level, limit = readFuel()
                if level then
                    local suffix = limit and string.format("/%d", limit) or ""
            ensureFacing(ctx, opts.facing, logger)
                    logger:error(string.format("Fuel remaining at failure: %d%s", level, suffix))
                    if level <= 0 then
                        logger:error("Turtle is out of fuel; supply fuel and rerun.")

            local fuelOk, fuelLevel = ensureInitialFuel(ctx, logger, opts.minFuel)
            if not fuelOk then
                return
            end
            if ctx.fuelState then
                ctx.fuelState.lastKnown = fuelLevel
            end
            ensureFacing(ctx, opts.facing, logger)
                    end
                end
                logger:error("Movement failed: " .. tostring(travelErr))
                stats.failures = stats.failures + 1
                break
            end

            local placed, placeInfo = placement.placeMaterial(ctx, step.block.material, { side = step.side, block = step.block, dig = true, attack = true })
            if not placed then
                logger:error("Placement failed: " .. tostring(placeInfo))
                stats.failures = stats.failures + 1
                break
            end
            if placeInfo == "already_present" then
                stats.reused = stats.reused + 1
            else
                stats.placed = stats.placed + 1
            end
        end
    end

    local homeOk, homeErr = returnToOrigin(ctx, opts, bounds, logger)
    if not homeOk and homeErr then
        logger:warn("Unable to return to origin: " .. tostring(homeErr))
    end

    logger:info(string.format("Placed: %d, reused: %d, skipped: %d, failures: %d", stats.placed, stats.reused, stats.skipped, stats.failures))
    if stats.failures == 0 then
        logger:info("Print complete.")
    else
        logger:warn("Print halted early; inspect the turtle and environment before retrying.")
    end
end

local rawArgs = { ... }
run(rawArgs)
