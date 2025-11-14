--[[
Inventory harness for lib_inventory.lua.
Run on a CC:Tweaked turtle to validate scanning, pulling, pushing, and slot management.
--]]

---@diagnostic disable: undefined-global, undefined-field
local inventory = require("lib_inventory")

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

local function promptEnter(message)
    print(message)
    if _G.read then
        read()
    elseif _G.sleep then
        sleep(3)
    end
end

local function promptInput(message, default)
    local suffix = ""
    if default and default ~= "" then
        suffix = " [" .. default .. "]"
    end
    print(message .. suffix)
    if _G.read then
        local line = read()
        if line and line ~= "" then
            return line
        end
    else
        if _G.sleep then
            sleep(1)
        end
    end
    return default or ""
end

local function getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local function isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = detail.name or ""
    local lowered = string.lower(name)
    if lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) or lowered:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local tagLower = string.lower(tag)
            if tagLower:find("chest", 1, true) or tagLower:find("container", 1, true) or tagLower:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

local function detectContainers()
    local found = {}
    for _, side in ipairs({ "forward", "up", "down" }) do
        local inspect = getInspect(side)
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok and isContainer(detail) then
                found[#found + 1] = {
                    side = side,
                    name = detail.name or "unknown",
                }
            end
        end
    end
    return found
end

local function ensureContainer(side)
    while true do
        local inspect = getInspect(side)
        if type(inspect) ~= "function" then
            return false
        end
        local ok, detail = inspect()
        if ok and isContainer(detail) then
            print(string.format("Detected %s on %s", detail.name or "container", side))
            return true
        end
        promptEnter(string.format("No chest detected %s. Place a chest there and press Enter.", side == "forward" and "in front" or (side == "up" and "above" or "below")))
    end
end

local function describeTotals(totals)
    local keys = {}
    for material in pairs(totals) do
        keys[#keys + 1] = material
    end
    table.sort(keys)
    if #keys == 0 then
        print("Inventory totals: <empty>")
        return
    end
    print("Inventory totals:")
    for _, material in ipairs(keys) do
        print(string.format(" - %s x%d", material, totals[material] or 0))
    end
end

local function firstMaterial(ctx)
    local state = ctx.inventoryState or {}
    if type(state.materialTotals) ~= "table" then
        return nil
    end
    for material in pairs(state.materialTotals) do
        return material
    end
    return nil
end

local function step(name, fn)
    print("\n== " .. name .. " ==")
    local ok, err = fn()
    if ok then
        print("Result: PASS")
    else
        print("Result: FAIL - " .. tostring(err))
    end
end

local function main()
    if not turtle then
        error("turtle API unavailable. Run this on a CC:Tweaked turtle.")
    end

    local ctx = {
        config = {
            verbose = true,
        },
    }
    ctx.logger = makeLogger(ctx)
    inventory.ensureState(ctx)

    print("Inventory harness starting.")
    print("Setup: place a supply chest in front of the turtle. Optionally place an output chest below or above.")

    local containers = detectContainers()
    if #containers == 0 then
        promptEnter("No chests detected. Place at least one chest (front/up/down) and press Enter.")
        containers = detectContainers()
    end

    local supplySide = "forward"
    local dropSide = "forward"
    local seen = {}
    for _, entry in ipairs(containers) do
        seen[entry.side] = entry
    end
    if not seen[supplySide] then
        if seen.up then
            supplySide = "up"
        elseif seen.down then
            supplySide = "down"
        end
    end
    if seen.down and supplySide ~= "down" then
        dropSide = "down"
    elseif seen.up and supplySide ~= "up" then
        dropSide = "up"
    else
        dropSide = supplySide
    end

    ensureContainer(supplySide)
    ensureContainer(dropSide)

    step("Initial scan", function()
        local ok, err = inventory.scan(ctx, { force = true })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx)
        describeTotals(totals or {})
        if inventory.isEmpty(ctx) then
            print("Inventory is empty. Pull step will fetch items from chest.")
        end
        return true
    end)

    local pulledMaterial

    step("Pull items from chest", function()
        local amountStr = promptInput("Enter amount to pull", "4")
        local amount = tonumber(amountStr) or 4
        local ok, err = inventory.pullMaterial(ctx, nil, amount, { side = supplySide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(totals or {})
        pulledMaterial = pulledMaterial or firstMaterial(ctx)
        if not pulledMaterial then
            return false, "nothing pulled"
        end
        print("Primary material detected: " .. pulledMaterial)
        return true
    end)

    step("Select material", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local ok, err = inventory.selectMaterial(ctx, pulledMaterial)
        if not ok then
            return false, err
        end
        print("Selected slot: " .. tostring(turtle.getSelectedSlot and turtle.getSelectedSlot() or "?"))
        return true
    end)

    step("Count and verify", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local count, err = inventory.countMaterial(ctx, pulledMaterial)
        if err then
            return false, err
        end
        print(string.format("Material %s count: %d", pulledMaterial, count))
        if count <= 0 then
            return false, "count did not increase"
        end
        return true
    end)

    step("Push items to output chest", function()
        if not pulledMaterial then
            return false, "no material available"
        end
        local dropAmountStr = promptInput("Enter amount to push", "2")
        local dropAmount = tonumber(dropAmountStr) or 2
        local ok, err = inventory.pushMaterial(ctx, pulledMaterial, dropAmount, { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(totals or {})
        return true
    end)

    step("Clear first slot", function()
        local state = ctx.inventoryState or {}
        if type(state.materialSlots) ~= "table" then
            return true
        end
        local list = state.materialSlots[pulledMaterial]
        if not list or not list[1] then
            return true
        end
        local ok, err = inventory.clearSlot(ctx, list[1], { side = dropSide })
        if not ok then
            return false, err
        end
        local totals = inventory.getTotals(ctx, { force = true })
        describeTotals(totals or {})
        return true
    end)

    step("Snapshot", function()
        local snap, err = inventory.snapshot(ctx, { force = true })
        if not snap then
            return false, err
        end
        print(string.format("Snapshot version %d with %d total items", snap.scanVersion or 0, snap.totalItems or 0))
        return true
    end)

    print("\nHarness complete. Review the results above for any failures.")
end

main()
