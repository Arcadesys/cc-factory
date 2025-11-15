---@diagnostic disable: undefined-global
-- Tree factory program for a crafting turtle running a 3x3 farm.
-- The turtle starts at the south-west corner of the plot, facing east.
-- Service bay layout (when the turtle steps south from home and faces south):
--   front  (south): furnace output chest (charcoal arrives here)
--   right  (west): hopper leading into furnace input (drop logs here)
--   down         : hopper leading into furnace fuel slot (drop charcoal here)
--   left   (east): charcoal overflow chest
--   up            : finished torch chest
--   back  (north): sapling supply chest
-- Adjust the physical setup to match or edit the helper functions below.

local GRID_WIDTH = 3
local GRID_LENGTH = 3

local SAPLING_SLOT = 13
local FUEL_SLOT = 14
local CHARCOAL_BUFFER_SLOT = 15
local TORCH_SLOT = 16

local MIN_FUEL = 300
local FUEL_RESERVE_TARGET = 32
local TORCH_TARGET = 64
local CHARCOAL_BUFFER_TARGET = 32
local SAPLING_MINIMUM = 9

local FURNACE_POLL_INTERVAL = 5
local FURNACE_MAX_POLLS = 120

local SERVICE_Z = -1

local EAST, SOUTH, WEST, NORTH = 0, 1, 2, 3

local posX, posZ = 0, 0
local heading = EAST

local RESERVED_SLOTS = {
    [SAPLING_SLOT] = true,
    [FUEL_SLOT] = true,
    [TORCH_SLOT] = true,
}

local native_read = _G and rawget(_G, "read") or nil
local native_sleep = _G and rawget(_G, "sleep") or function(_) end

local function logEvent(msg)
    if msg then
        print(msg)
    end
end

local function waitForUser(prompt)
    logEvent(prompt or "Waiting for input... Press Enter to continue.")
    if native_read then
        native_read()
    else
        native_sleep(5)
    end
end

local function wrapHeading(value)
    return (value + 4) % 4
end

local function updatePositionForward()
    if heading == EAST then
        posX = posX + 1
    elseif heading == SOUTH then
        posZ = posZ - 1
    elseif heading == WEST then
        posX = posX - 1
    else
        posZ = posZ + 1
    end
end

local function updatePositionBackward()
    if heading == EAST then
        posX = posX - 1
    elseif heading == SOUTH then
        posZ = posZ + 1
    elseif heading == WEST then
        posX = posX + 1
    else
        posZ = posZ - 1
    end
end

local function turnLeft()
    local ok = turtle.turnLeft()
    if ok then
        heading = wrapHeading(heading - 1)
    end
    return ok
end

local function turnRight()
    local ok = turtle.turnRight()
    if ok then
        heading = wrapHeading(heading + 1)
    end
    return ok
end

local function turnAround()
    return turnRight() and turnRight()
end

local function face(target)
    if heading == target then
        return true
    end
    local diff = (target - heading) % 4
    if diff == 1 then
        return turnRight()
    elseif diff == 2 then
        return turnAround()
    else
        return turnLeft()
    end
end

local function ensureFuelAvailable()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end
    if type(fuelLevel) == "number" and fuelLevel > 0 then
        return true
    end
    logEvent("Fuel depleted. Load charcoal and press Enter.")
    waitForUser()
    return type(turtle.getFuelLevel()) == "number" and turtle.getFuelLevel() > 0
end

local function moveSafeForward()
    if not ensureFuelAvailable() then
        return false
    end
    local attempts = 0
    while not turtle.forward() do
        attempts = attempts + 1
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
        end
        if attempts >= 5 then
            logEvent("Unable to move forward. Clear the path and press Enter.")
            waitForUser()
            attempts = 0
        else
            native_sleep(0.4)
        end
    end
    updatePositionForward()
    return true
end

local function moveBackward()
    local attempts = 0
    while not turtle.back() do
        attempts = attempts + 1
        turnAround()
        if turtle.detect() then
            turtle.dig()
        else
            turtle.attack()
        end
        turnAround()
        if attempts >= 5 then
            logEvent("Unable to move backward. Clear the path and press Enter.")
            waitForUser()
            attempts = 0
        else
            native_sleep(0.4)
        end
    end
    updatePositionBackward()
    return true
end

local function goTo(targetX, targetZ)
    if posZ < targetZ then
        face(NORTH)
        while posZ < targetZ do
            if not moveSafeForward() then
                return false
            end
        end
    elseif posZ > targetZ then
        face(SOUTH)
        while posZ > targetZ do
            if not moveSafeForward() then
                return false
            end
        end
    end

    if posX < targetX then
        face(EAST)
        while posX < targetX do
            if not moveSafeForward() then
                return false
            end
        end
    elseif posX > targetX then
        face(WEST)
        while posX > targetX do
            if not moveSafeForward() then
                return false
            end
        end
    end

    return true
end

local function returnHome()
    if not goTo(0, 0) then
        return false
    end
    face(EAST)
    return true
end

local function enterServiceBay()
    if not returnHome() then
        return false
    end
    face(SOUTH)
    if posZ ~= SERVICE_Z then
        if not moveSafeForward() then
            return false
        end
    end
    face(SOUTH)
    return true
end

local function leaveServiceBay()
    face(NORTH)
    if posZ ~= 0 then
        if not moveSafeForward() then
            return false
        end
    end
    face(EAST)
    return true
end

local function dropToSide(side, count)
    if side == "front" then
        return turtle.drop(count)
    elseif side == "up" then
        return turtle.dropUp(count)
    elseif side == "down" then
        return turtle.dropDown(count)
    elseif side == "left" then
        turnLeft()
        local ok = turtle.drop(count)
        turnRight()
        return ok
    elseif side == "right" then
        turnRight()
        local ok = turtle.drop(count)
        turnLeft()
        return ok
    elseif side == "back" then
        turnAround()
        local ok = turtle.drop(count)
        turnAround()
        return ok
    end
    return false
end

local function suckFromSide(side, count)
    if side == "front" then
        return turtle.suck(count)
    elseif side == "up" then
        return turtle.suckUp(count)
    elseif side == "down" then
        return turtle.suckDown(count)
    elseif side == "left" then
        turnLeft()
        local ok = turtle.suck(count)
        turnRight()
        return ok
    elseif side == "right" then
        turnRight()
        local ok = turtle.suck(count)
        turnLeft()
        return ok
    elseif side == "back" then
        turnAround()
        local ok = turtle.suck(count)
        turnAround()
        return ok
    end
    return false
end

local function isLog(name)
    return type(name) == "string" and (name:find("_log", 1, true) or name:find("_stem", 1, true) or name:find(":log", 1, true))
end

local function isSaplingItem(name)
    return type(name) == "string" and name:find("sapling", 1, true)
end

local function isCharcoal(name)
    return name == "minecraft:charcoal"
end

local function isPlank(name)
    return type(name) == "string" and name:find("_planks", 1, true)
end

local function isStick(name)
    return name == "minecraft:stick"
end

local function isTorch(name)
    return name == "minecraft:torch"
end

local function countItems(predicate, skipFuel)
    local count = 0
    for slot = 1, 16 do
        if not (skipFuel and slot == FUEL_SLOT) then
            local detail = turtle.getItemDetail(slot)
            if detail and predicate(detail.name) then
                count = count + detail.count
            end
        end
    end
    return count
end

local function findExistingStack(name)
    for slot = 10, 16 do
        if slot ~= FUEL_SLOT and slot ~= TORCH_SLOT then
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name == name and turtle.getItemSpace(slot) > 0 then
                return slot
            end
        end
    end
    return nil
end

local function findEmptyStorageSlot()
    for slot = 10, 16 do
        if not RESERVED_SLOTS[slot] and turtle.getItemCount(slot) == 0 then
            return slot
        end
    end
    return nil
end

local function ensureSlotEmpty(slot)
    if turtle.getItemCount(slot) == 0 then
        return true
    end
    local detail = turtle.getItemDetail(slot)
    if not detail then
        return true
    end
    local target = findExistingStack(detail.name)
    if not target then
        target = findEmptyStorageSlot()
    end
    if not target then
        return false
    end
    turtle.select(slot)
    turtle.transferTo(target)
    return turtle.getItemCount(slot) == 0
end

local function stashCraftOutputs()
    for slot = 1, 9 do
        local count = turtle.getItemCount(slot)
        if count > 0 then
            local detail = turtle.getItemDetail(slot)
            if detail then
                local target
                if isTorch(detail.name) then
                    target = TORCH_SLOT
                elseif isCharcoal(detail.name) and slot ~= FUEL_SLOT then
                    target = CHARCOAL_BUFFER_SLOT
                else
                    target = findExistingStack(detail.name)
                end
                if not target then
                    target = findEmptyStorageSlot()
                end
                if target and target ~= slot then
                    turtle.select(slot)
                    turtle.transferTo(target)
                end
            end
        end
    end
end

local function ensureCraftGridClear()
    for slot = 1, 9 do
        if turtle.getItemCount(slot) > 0 then
            if not ensureSlotEmpty(slot) then
                return false
            end
        end
    end
    return true
end

local function pullItemsToSlot(targetSlot, predicate, amount, skipFuel)
    if amount <= 0 then
        return 0
    end
    if not ensureSlotEmpty(targetSlot) then
        return 0
    end
    local pulled = 0
    for slot = 1, 16 do
        if slot ~= targetSlot and not RESERVED_SLOTS[slot] and not (skipFuel and slot == FUEL_SLOT) then
            local detail = turtle.getItemDetail(slot)
            if detail and predicate(detail.name) then
                turtle.select(slot)
                local move = math.min(amount - pulled, turtle.getItemCount(slot))
                if move > 0 then
                    turtle.transferTo(targetSlot, move)
                    pulled = pulled + move
                    if pulled >= amount then
                        break
                    end
                end
            end
        end
    end
    return pulled
end

local function craftPlanksFromLogs(requiredLogs)
    local remaining = requiredLogs
    while remaining > 0 do
        if not ensureCraftGridClear() then
            return false
        end
        local moved = pullItemsToSlot(1, isLog, remaining)
        if moved == 0 then
            return true
        end
        turtle.select(1)
        if not turtle.craft(moved) then
            logEvent("Crafting planks failed. Check crafting turtle fuel / space.")
            return false
        end
        stashCraftOutputs()
        remaining = remaining - moved
    end
    return true
end

local function ensurePlanksAvailable(count)
    if count <= 0 then
        return true
    end
    local existing = countItems(isPlank, false)
    if existing >= count then
        return true
    end
    local missing = count - existing
    local neededLogs = math.ceil(missing / 4)
    if neededLogs <= 0 then
        return true
    end
    return craftPlanksFromLogs(neededLogs)
end

local function craftSticks(craftRuns)
    local remaining = craftRuns
    while remaining > 0 do
        if not ensureCraftGridClear() then
            return false
        end
        local batch = math.min(remaining, 64)
        local pulledTop = pullItemsToSlot(2, isPlank, batch)
        local pulledMid = pullItemsToSlot(5, isPlank, batch)
        if pulledTop == 0 or pulledMid == 0 then
            stashCraftOutputs()
            return true
        end
        turtle.select(2)
        if not turtle.craft(batch) then
            logEvent("Crafting sticks failed. Clear crafting grid.")
            return false
        end
        stashCraftOutputs()
        remaining = remaining - batch
    end
    return true
end

local function ensureSticksAvailable(count)
    if count <= 0 then
        return true
    end
    local existing = countItems(isStick, false)
    if existing >= count then
        return true
    end
    local missing = count - existing
    local runs = math.ceil(missing / 4)
    if not ensurePlanksAvailable(runs * 2) then
        logEvent("Not enough planks to craft sticks.")
        return false
    end
    craftSticks(runs)
    return countItems(isStick, false) >= count
end

local function moveCharcoalToFuel()
    if turtle.getItemCount(FUEL_SLOT) >= FUEL_RESERVE_TARGET then
        return
    end
    for slot = 1, 16 do
        if slot ~= FUEL_SLOT then
            local detail = turtle.getItemDetail(slot)
            if detail and isCharcoal(detail.name) then
                turtle.select(slot)
                local needed = FUEL_RESERVE_TARGET - turtle.getItemCount(FUEL_SLOT)
                turtle.transferTo(FUEL_SLOT, needed)
                if turtle.getItemCount(FUEL_SLOT) >= FUEL_RESERVE_TARGET then
                    return
                end
            end
        end
    end
end

local function consolidateCharcoal()
    moveCharcoalToFuel()
    if turtle.getItemCount(CHARCOAL_BUFFER_SLOT) < CHARCOAL_BUFFER_TARGET then
        for slot = 1, 16 do
            if slot ~= FUEL_SLOT and slot ~= CHARCOAL_BUFFER_SLOT then
                local detail = turtle.getItemDetail(slot)
                if detail and isCharcoal(detail.name) then
                    turtle.select(slot)
                    local needed = CHARCOAL_BUFFER_TARGET - turtle.getItemCount(CHARCOAL_BUFFER_SLOT)
                    if needed > 0 then
                        turtle.transferTo(CHARCOAL_BUFFER_SLOT, needed)
                    end
                end
            end
        end
    end
    for slot = 1, 16 do
        if slot ~= FUEL_SLOT and slot ~= CHARCOAL_BUFFER_SLOT then
            local detail = turtle.getItemDetail(slot)
            if detail and isCharcoal(detail.name) then
                turtle.select(slot)
                if not dropToSide("left") then
                    logEvent("Unable to drop surplus charcoal. Check the overflow chest.")
                    break
                end
            end
        end
    end
end

local function chopTree()
    local ok, data = turtle.inspect()
    if not ok or not data or not isLog(data.name) then
        return false
    end
    logEvent("Chopping tree...")
    turtle.dig()
    native_sleep(0.2)
    if not moveSafeForward() then
        return false
    end
    local climbed = 0
    while true do
        local has, above = turtle.inspectUp()
        if has and above and isLog(above.name) then
            turtle.digUp()
            native_sleep(0.2)
            turtle.up()
            climbed = climbed + 1
        else
            break
        end
    end
    while climbed > 0 do
        turtle.down()
        climbed = climbed - 1
    end
    moveBackward()
    return true
end

local function plantSapling()
    if turtle.getItemCount(SAPLING_SLOT) == 0 then
        waitForUser("Saplings depleted. Load saplings into slot " .. SAPLING_SLOT .. " and press Enter.")
        return false
    end
    turtle.select(SAPLING_SLOT)
    local placed = turtle.place()
    if placed then
        logEvent("Planted sapling.")
        return true
    end
    -- Try clearing tall grass or similar
    turtle.dig()
    native_sleep(0.2)
    placed = turtle.place()
    if not placed then
        logEvent("Failed to plant sapling. Check the plot.")
    end
    return placed
end

local function handlePlot(x, z)
    local hasBlock, detail = turtle.inspect()
    if hasBlock and detail then
        if isLog(detail.name) then
            if chopTree() then
                plantSapling()
            end
            return
        elseif isSaplingItem(detail.name) then
            return
        else
            turtle.dig()
            native_sleep(0.2)
            hasBlock = false
        end
    end
    if not hasBlock then
        plantSapling()
    end
end

local function serpentineWalk(callback)
    for row = 0, GRID_LENGTH - 1 do
        for col = 0, GRID_WIDTH - 1 do
            callback(col, row)
            if col < GRID_WIDTH - 1 then
                moveSafeForward()
            end
        end
        if row < GRID_LENGTH - 1 then
            if row % 2 == 0 then
                turnLeft()
                moveSafeForward()
                turnLeft()
            else
                turnRight()
                moveSafeForward()
                turnRight()
            end
        end
    end
end

local function refuelIfNeeded()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end
    if type(fuelLevel) ~= "number" then
        return true
    end
    if fuelLevel >= MIN_FUEL then
        return true
    end
    moveCharcoalToFuel()
    if turtle.getItemCount(FUEL_SLOT) == 0 then
        local logs = countItems(isLog, false)
        if logs == 0 then
            logEvent("Out of fuel and no logs available. Load charcoal and press Enter.")
            waitForUser()
            return turtle.getFuelLevel() >= MIN_FUEL
        end
        logEvent("Fuel low. Smelting logs into charcoal.")
        return false
    end
    turtle.select(FUEL_SLOT)
    while turtle.getFuelLevel() < MIN_FUEL and turtle.getItemCount(FUEL_SLOT) > 0 do
        if not turtle.refuel(1) then
            break
        end
    end
    if turtle.getFuelLevel() < MIN_FUEL then
        logEvent("Unable to refuel to target. Add more charcoal and press Enter.")
        waitForUser()
    else
        logEvent("Refueled to " .. turtle.getFuelLevel() .. ".")
    end
    return turtle.getFuelLevel() >= MIN_FUEL
end

local function depositLogsIntoFurnace()
    local total = 0
    for slot = 1, 16 do
        if not RESERVED_SLOTS[slot] then
            local detail = turtle.getItemDetail(slot)
            if detail and isLog(detail.name) then
                turtle.select(slot)
                local dropped = turtle.getItemCount(slot)
                if dropped > 0 then
                    if not dropToSide("right") then
                        logEvent("Furnace input blocked. Clear hopper and press Enter.")
                        waitForUser()
                        return total
                    end
                    total = total + dropped
                end
            end
        end
    end
    return total
end

local function dropFuelCharcoal()
    moveCharcoalToFuel()
    if turtle.getItemCount(FUEL_SLOT) == 0 then
        logEvent("No charcoal in fuel slot. Add charcoal and press Enter.")
        waitForUser()
    end
    if turtle.getItemCount(FUEL_SLOT) == 0 then
        return false
    end
    turtle.select(FUEL_SLOT)
    return dropToSide("down", 1)
end

local function pullCharcoalFromFurnace(expected)
    local received = 0
    local polls = 0
    local prevSlot = turtle.getSelectedSlot()
    if CHARCOAL_BUFFER_SLOT then
        turtle.select(CHARCOAL_BUFFER_SLOT)
    end
    while received < expected do
        while turtle.suck() do
            local detail = turtle.getItemDetail()
            if detail and isCharcoal(detail.name) then
                received = received + detail.count
            end
            stashCraftOutputs()
            moveCharcoalToFuel()
        end
        if received >= expected then
            break
        end
        polls = polls + 1
        if polls > FURNACE_MAX_POLLS then
            logEvent("Furnace timeout. Check furnace and press Enter.")
            waitForUser()
            polls = 0
        else
            native_sleep(FURNACE_POLL_INTERVAL)
        end
    end
    if prevSlot then
        turtle.select(prevSlot)
    end
end

local function smeltCharcoal()
    local logs = countItems(isLog, false)
    if logs == 0 then
        return
    end
    logEvent("Smelting " .. logs .. " logs into charcoal...")
    if not dropFuelCharcoal() then
        return
    end
    local fed = depositLogsIntoFurnace()
    if fed == 0 then
        return
    end
    pullCharcoalFromFurnace(fed)
    consolidateCharcoal()
end

local function craftTorches()
    local currentTorches = turtle.getItemCount(TORCH_SLOT)
    if currentTorches >= TORCH_TARGET then
        local extra = currentTorches - TORCH_TARGET
        if extra > 0 then
            turtle.select(TORCH_SLOT)
            if dropToSide("up", extra) then
                logEvent("Deposited " .. extra .. " torches.")
            else
                logEvent("Torch chest full. Unable to deposit surplus torches.")
            end
        end
        return
    end
    local neededTorches = TORCH_TARGET - currentTorches
    local neededCrafts = math.ceil(neededTorches / 4)
    local availableCharcoal = countItems(isCharcoal, true)
    if availableCharcoal <= 0 then
        logEvent("No charcoal available for torch crafting.")
        return
    end
    local crafts = math.min(neededCrafts, availableCharcoal)
    if crafts <= 0 then
        return
    end
    if not ensureSticksAvailable(crafts) then
        logEvent("Unable to craft sticks for torches.")
        return
    end
    local produced = 0
    local remaining = crafts
    while remaining > 0 do
        if not ensureCraftGridClear() then
            logEvent("Craft grid jammed. Clear inventory and retry.")
            return
        end
        local batch = math.min(remaining, 64)
        local pulledChar = pullItemsToSlot(2, isCharcoal, batch, true)
        local pulledStick = pullItemsToSlot(5, isStick, batch, false)
        if pulledChar == 0 or pulledStick == 0 then
            stashCraftOutputs()
            break
        end
        turtle.select(2)
        if not turtle.craft(batch) then
            logEvent("Torch crafting failed. Check inputs.")
            stashCraftOutputs()
            return
        end
        stashCraftOutputs()
        produced = produced + batch * 4
        remaining = remaining - batch
    end
    local after = turtle.getItemCount(TORCH_SLOT)
    if after > TORCH_TARGET then
        local extra = after - TORCH_TARGET
        turtle.select(TORCH_SLOT)
        if dropToSide("up", extra) then
            logEvent("Deposited " .. extra .. " surplus torches.")
        else
            logEvent("Torch chest full. Carrying extra torches for now.")
        end
    end
    logEvent("Crafted torches. Slot " .. TORCH_SLOT .. " now holds " .. turtle.getItemCount(TORCH_SLOT) .. ".")
end

local function restockFromChests()
    -- Saplings from chest behind (north)
    if turtle.getItemCount(SAPLING_SLOT) < SAPLING_MINIMUM then
        local originalSlot = turtle.getSelectedSlot()
        turtle.select(SAPLING_SLOT)
        turnAround()
        while turtle.getItemCount(SAPLING_SLOT) < SAPLING_MINIMUM do
            if not turtle.suck(SAPLING_MINIMUM - turtle.getItemCount(SAPLING_SLOT)) then
                break
            end
        end
        turnAround()
        turtle.select(originalSlot)
        if turtle.getItemCount(SAPLING_SLOT) < SAPLING_MINIMUM then
            waitForUser("Sapling chest empty. Restock and press Enter.")
        else
            logEvent("Saplings restocked to slot " .. SAPLING_SLOT .. ".")
        end
    end

    -- Charcoal top-up from left chest if needed
    moveCharcoalToFuel()
    if turtle.getItemCount(FUEL_SLOT) < FUEL_RESERVE_TARGET then
        local prevSlot = turtle.getSelectedSlot()
        turtle.select(FUEL_SLOT)
        turnLeft()
        suckFromSide("front", FUEL_RESERVE_TARGET - turtle.getItemCount(FUEL_SLOT))
        turnRight()
        moveCharcoalToFuel()
        if prevSlot then
            turtle.select(prevSlot)
        end
    end
end

local function runFarmCycle()
    serpentineWalk(handlePlot)
    returnHome()
    enterServiceBay()
    smeltCharcoal()
    consolidateCharcoal()
    craftTorches()
    restockFromChests()
    refuelIfNeeded()
    leaveServiceBay()
end

local function main()
    logEvent("Tree factory active. Ctrl+T to stop.")
    while true do
        if not enterServiceBay() then
            break
        end
        restockFromChests()
        if not refuelIfNeeded() then
            smeltCharcoal()
            consolidateCharcoal()
            refuelIfNeeded()
        end
        leaveServiceBay()
        runFarmCycle()
    end
end

main()
