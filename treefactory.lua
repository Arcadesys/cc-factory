--[[
Tree Factory state machine for CC:Tweaked turtles.
Builds a simple factory footprint (furnace + chests), walks a tree grid,
harvests logs, and manages restocking / deposits using the shared lib_ helpers.
]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local placement = require("lib_placement")
local loggerLib = require("lib_logger")
local fuelLib = require("lib_fuel")

local STATE_INITIALIZE = "INITIALIZE"
local STATE_BUILD_FACTORY = "BUILD_FACTORY"
local STATE_VERIFY_FACTORY = "VERIFY_FACTORY"
local STATE_TRAVERSE = "TRAVERSE"
local STATE_INSPECT_CELL = "INSPECT_CELL"
local STATE_CHOP = "CHOP"
local STATE_PLANT = "PLANT"
local STATE_RETURN_HOME = "RETURN_HOME"
local STATE_SMELT = "SMELT"
local STATE_CRAFT = "CRAFT"
local STATE_REFUEL = "REFUEL"
local STATE_RESTOCK = "RESTOCK"
local STATE_DEPOSIT = "DEPOSIT"
local STATE_SLEEP = "SLEEP"
local STATE_ERROR = "ERROR"

local MOVE_OPTS_CLEAR = { dig = true, attack = true }
local MOVE_OPTS_SOFT = { dig = false, attack = false }
local MOVE_OPTS_FACTORY = { dig = true, attack = true }
local MOVE_AXIS_FALLBACK = { "z", "x", "y" }

-- Bounding box around the factory where we must never dig
local FACTORY_BOUNDS = {
  minX = -2,
  maxX = 2,
  minZ = -3,
  maxZ = 3,
}

local DEFAULT_CONFIG = {
  gridWidth = 5,
  gridLength = 6,
  initialFacing = "east",
  homeFacing = "east",
  minFuel = 200,
  smeltBatch = 8,
  furnaceWait = 10,
  sleepSeconds = 10,
  logMaterial = "minecraft:oak_log",
  saplingMaterial = "minecraft:oak_sapling",
  charcoalMaterial = "minecraft:charcoal",
  torchMaterial = "minecraft:torch",
  keepCharcoal = 16,
  keepTorches = 16,
  factorySlots = {
    furnace = 4,
    outputChest = 5,
    saplingChest = 6,
    fuelChest = 7,
    logChest = 8,
  },
  factoryMaterials = {
    furnace = "minecraft:furnace",
    outputChest = "minecraft:chest",
    saplingChest = "minecraft:chest",
    fuelChest = "minecraft:chest",
    logChest = "minecraft:chest",
  },
  saplingSlot = 1,
  fuelSlot = 2,
  torchSlot = 3,
}

local FACTORY_APPROACH = {
  furnace = { position = { x = 0, y = 0, z = 0 }, facing = "north" },
  outputChest = { position = { x = 1, y = 0, z = -2 }, facing = "west" },
  saplingChest = { position = { x = 0, y = 0, z = 0 }, facing = "south" },
  fuelChest = { position = { x = 1, y = 0, z = 2 }, facing = "west" },
  logChest = { position = { x = 0, y = 0, z = 0 }, facing = "west" },
}

local FACTORY_POSITIONS = {
  furnace = { x = 0, y = 0, z = -1 },
  outputChest = { x = 0, y = 0, z = -2 },
  saplingChest = { x = 0, y = 0, z = 1 },
  fuelChest = { x = 0, y = 0, z = 2 },
  logChest = { x = -1, y = 0, z = 0 },
}

local function mergeTables(target, source)
  if type(target) ~= "table" or type(source) ~= "table" then
    return target
  end
  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" then
      mergeTables(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

local function loadConfig()
  local cfg = {}
  mergeTables(cfg, DEFAULT_CONFIG)

  local ok, userCfg = pcall(require, "config")
  if ok and type(userCfg) == "table" then
    if type(userCfg.treefactory) == "table" then
      mergeTables(cfg, userCfg.treefactory)
    elseif type(userCfg.treeFactory) == "table" then
      mergeTables(cfg, userCfg.treeFactory)
    else
      mergeTables(cfg, userCfg)
    end
  end

  cfg.factorySlots = cfg.factorySlots or {}
  mergeTables(cfg.factorySlots, DEFAULT_CONFIG.factorySlots)

  cfg.factoryMaterials = cfg.factoryMaterials or {}
  mergeTables(cfg.factoryMaterials, DEFAULT_CONFIG.factoryMaterials)

  return cfg
end

local function createLogger()
  local logger = loggerLib.new({ tag = "TreeFactory", level = "info" })
  return logger
end

local function cloneTable(source)
  if type(source) ~= "table" then
    return nil
  end
  local copy = {}
  for key, value in pairs(source) do
    copy[key] = value
  end
  return copy
end

local function mergeMoveOpts(baseOpts, extraOpts)
  if not extraOpts then
    if not baseOpts then
      return nil
    end
    return cloneTable(baseOpts)
  end

  local merged = {}
  if baseOpts then
    for key, value in pairs(baseOpts) do
      merged[key] = value
    end
  end
  for key, value in pairs(extraOpts) do
    merged[key] = value
  end
  return merged
end

local function goToWithFallback(ctx, position, moveOpts)
  local ok, err = movement.goTo(ctx, position, moveOpts)
  if ok or (moveOpts and moveOpts.axisOrder) then
    return ok, err
  end
  local fallbackOpts = mergeMoveOpts(moveOpts, { axisOrder = MOVE_AXIS_FALLBACK })
  return movement.goTo(ctx, position, fallbackOpts)
end

local function goAndFace(ctx, position, facing, moveOpts)
  local ok, err = goToWithFallback(ctx, position, moveOpts or MOVE_OPTS_FACTORY)
  if not ok then
    return false, err
  end
  if facing then
    ok, err = movement.faceDirection(ctx, facing)
    if not ok then
      return false, err
    end
  end
  return true
end

local function isInsideFactoryBounds(pos)
  if not pos then
    return false
  end
  local x, z = pos.x or 0, pos.z or 0
  return x >= FACTORY_BOUNDS.minX and x <= FACTORY_BOUNDS.maxX
    and z >= FACTORY_BOUNDS.minZ and z <= FACTORY_BOUNDS.maxZ
end

-- Move softly from current position to a fixed "safe" point outside the factory box.
-- This never digs, so placed chests/furnace cannot be broken.
local function moveSoftOutOfFactory(ctx)
  local safe = { x = 3, y = 0, z = -4 }
  local ok, err = goToWithFallback(ctx, safe, MOVE_OPTS_SOFT)
  if not ok then
    return false, err or "failed_soft_escape"
  end
  return true
end

local function returnHome(ctx)
  local ok, err = goToWithFallback(ctx, ctx.origin, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  local facing = ctx.config.homeFacing or ctx.config.initialFacing or "east"
  ok, err = movement.faceDirection(ctx, facing)
  if not ok then
    return false, err
  end
  ctx.currentX = 0
  ctx.currentZ = 0
  return true
end

local function setError(ctx, message, returnState)
  ctx.errorMessage = message or "unknown error"
  ctx.returnState = returnState or ctx.lastState or STATE_INITIALIZE
  ctx.errorAttempts = (ctx.errorAttempts or 0) + 1
  if ctx.logger then
    ctx.logger:error(ctx.errorMessage)
  end
end

local function resetTraversal(ctx)
  ctx.traverse = {
    row = 1,
    col = 1,
    forward = true,
    done = false,
  }
end

local function advanceTraversal(ctx)
  local tr = ctx.traverse
  if not tr then
    resetTraversal(ctx)
    tr = ctx.traverse
  end

  if tr.done then
    return
  end

  if tr.forward then
    if tr.col < ctx.gridWidth then
      tr.col = tr.col + 1
      return
    end
    tr.forward = false
  else
    if tr.col > 1 then
      tr.col = tr.col - 1
      return
    end
    tr.forward = true
  end

  tr.row = tr.row + 1
  if tr.row > ctx.gridLength then
    tr.done = true
  else
    tr.col = tr.forward and 1 or ctx.gridWidth
  end
end

local function currentWalkPosition(ctx)
  local tr = ctx.traverse
  if not tr then
    resetTraversal(ctx)
    tr = ctx.traverse
  end
  return {
    x = ctx.fieldOrigin.x + (tr.col - 1),
    y = ctx.fieldOrigin.y,
    z = ctx.fieldOrigin.z + (tr.row - 1),
  }
end

local function currentTreePosition(ctx)
  local walk = currentWalkPosition(ctx)
  return {
    x = walk.x,
    y = walk.y,
    z = walk.z + 1,
  }
end

local function isLogBlock(ctx, detail)
  if type(detail) ~= "table" then
    return false
  end
  local name = detail.name or ""
  if name == ctx.config.logMaterial then
    return true
  end
  return name:find("_log", 1, true) ~= nil
end

local function isSaplingBlock(ctx, detail)
  if type(detail) ~= "table" then
    return false
  end
  local name = detail.name or ""
  if name == ctx.config.saplingMaterial then
    return true
  end
  return name:find("sapling", 1, true) ~= nil
end

local function ensureInventory(ctx)
  local ok, err = inventory.scan(ctx, { force = true })
  if not ok then
    return false, err
  end
  return true
end

local function ensureFuelState(ctx)
  local state = fuelLib.ensureState(ctx)
  ctx.minFuel = ctx.config.minFuel or state.threshold or ctx.minFuel or DEFAULT_CONFIG.minFuel
  return state
end

local function queueRestock(ctx, params)
  ctx.restock = params
  ctx.restockReturnState = ctx.state
end

local function clearRestock(ctx)
  ctx.restock = nil
end

local function placeFactoryBlock(ctx, key)
  local approach = FACTORY_APPROACH[key]
  local material = ctx.config.factoryMaterials[key]
  if not approach or not material then
    return false, "missing_factory_definition"
  end

  local ok, err = goAndFace(ctx, approach.position, approach.facing, MOVE_OPTS_FACTORY)
  if not ok then
    return false, err
  end

  local placed, reason = placement.placeMaterial(ctx, material, { block = { material = material }, overwrite = true, side = approach.side })
  if not placed and reason ~= "already_present" then
    return false, reason or "place_failed"
  end

  return true
end

local function verifyFactoryBlock(ctx, key)
  local expected = ctx.config.factoryMaterials[key]
  local target = FACTORY_POSITIONS[key]
  local approach = FACTORY_APPROACH[key]
  if not expected or not target or not approach then
    return false, "missing_factory_definition"
  end

  local ok, err = goAndFace(ctx, approach.position, approach.facing, MOVE_OPTS_FACTORY)
  if not ok then
    return false, err
  end

  local inspectSide = approach.inspect or "forward"
  local hasBlock, detail
  if inspectSide == "forward" then
    hasBlock, detail = turtle.inspect()
  elseif inspectSide == "up" then
    hasBlock, detail = turtle.inspectUp()
  elseif inspectSide == "down" then
    hasBlock, detail = turtle.inspectDown()
  end

  if not hasBlock or type(detail) ~= "table" then
    return false, "missing_block"
  end

  if detail.name ~= expected then
    return false, string.format("expected %s got %s", expected, detail.name or "unknown")
  end

  return true
end

local function ensureFactoryMaterials(ctx)
  local required = {
    { key = "furnace", slotsField = "furnaceSlot", material = ctx.config.factoryMaterials.furnace },
    { key = "outputChest", slotsField = "outputChestSlot", material = ctx.config.factoryMaterials.outputChest },
    { key = "saplingChest", slotsField = "saplingChestSlot", material = ctx.config.factoryMaterials.saplingChest },
    { key = "fuelChest", slotsField = "fuelChestSlot", material = ctx.config.factoryMaterials.fuelChest },
    { key = "logChest", slotsField = "logChestSlot", material = ctx.config.factoryMaterials.logChest },
  }

  for _, entry in ipairs(required) do
    local slot = ctx.factory[entry.slotsField]
    if type(slot) ~= "number" then
      return false, string.format("slot missing for %s", entry.key)
    end
    local detail = turtle.getItemDetail and turtle.getItemDetail(slot)
    if not detail or detail.name ~= entry.material then
      return false, string.format("missing %s in slot %d", entry.material or entry.key, slot)
    end
  end

  return true
end

local function refuelIfNeeded(ctx)
  if not turtle or not turtle.getFuelLevel then
    return true
  end
  local level = turtle.getFuelLevel()
  if level == "unlimited" then
    return true
  end
  if level >= ctx.minFuel then
    return true
  end

  local slot = ctx.fuelSlot
  if not slot then
    return false, "fuel_slot_unassigned"
  end
  if turtle.getItemCount(slot) <= 0 then
    return false, "fuel_slot_empty"
  end
  if not turtle.select(slot) then
    return false, "select_failed"
  end
  if not turtle.refuel(1) then
    return false, "refuel_failed"
  end
  ctx.charcoalBuffer = math.max((ctx.charcoalBuffer or 0) - 1, 0)
  return true
end

local function moveAboveFurnace(ctx)
  local ok, err = goAndFace(ctx, ctx.origin, "north", MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.up(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    movement.down(ctx, MOVE_OPTS_SOFT)
    return false, err
  end
  return true
end

local function leaveAboveFurnace(ctx)
  local ok, err = movement.turnAround(ctx)
  if not ok then
    return false, err
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.turnAround(ctx)
  if not ok then
    return false, err
  end
  ok, err = movement.down(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  return true
end

local function moveToFurnaceFuelSide(ctx)
  local ok, err = goAndFace(ctx, { x = 1, y = 0, z = 0 }, "north", MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.faceDirection(ctx, "west")
  if not ok then
    return false, err
  end
  return true
end

local function leaveFurnaceFuelSide(ctx)
  local ok, err = movement.faceDirection(ctx, "south")
  if not ok then
    return false, err
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  ok, err = movement.faceDirection(ctx, "west")
  if not ok then
    return false, err
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    return false, err
  end
  returnHome(ctx)
  return true
end

local function depositToChest(ctx, key, material, keepCount)
  keepCount = keepCount or 0
  if not material then
    return true
  end
  local ok = ensureInventory(ctx)
  if not ok then
    return false, "inventory_scan_failed"
  end

  local total = inventory.countMaterial(ctx, material, { force = true })
  if not total or total <= keepCount then
    return true
  end
  local toDrop = total - keepCount

  local approach = FACTORY_APPROACH[key]
  ok = goAndFace(ctx, approach.position, approach.facing, MOVE_OPTS_FACTORY)
  if not ok then
    return false, "move_failed"
  end

  local slots = inventory.getMaterialSlots(ctx, material, { force = true }) or {}
  for _, slot in ipairs(slots) do
    if toDrop <= 0 then
      break
    end
    local count = turtle.getItemCount(slot)
    if count and count > 0 then
      local amount = math.min(count, toDrop)
      local success = select(1, inventory.pushSlot(ctx, slot, amount, { side = approach.side or "forward", deferScan = true }))
      if success then
        toDrop = toDrop - amount
      end
    end
  end

  inventory.invalidate(ctx)
  returnHome(ctx)
  return true
end

local function restockFromChest(ctx, chestKey, material, slot, amount)
  amount = amount or 16
  local approach = FACTORY_APPROACH[chestKey]
  if not approach then
    return false, "unknown_chest"
  end

  local ok, err = goAndFace(ctx, approach.position, approach.facing, MOVE_OPTS_FACTORY)
  if not ok then
    return false, err
  end

  ok, err = ensureInventory(ctx)
  if not ok then
    return false, err
  end

  local pulled, pullErr = inventory.pullMaterial(ctx, material, amount, { side = approach.side or "forward", deferScan = false })
  if not pulled then
    return false, pullErr or "pull_failed"
  end

  inventory.invalidate(ctx)
  ensureInventory(ctx)

  if turtle.getItemCount(slot) <= 0 then
    local targetSlot = inventory.getSlotForMaterial(ctx, material, { force = true })
    if targetSlot and targetSlot ~= slot then
      turtle.select(targetSlot)
      turtle.transferTo(slot)
    end
  end

  returnHome(ctx)
  return true
end

local function frontBlockDetail()
  local ok, detail = turtle.inspect()
  if not ok then
    return nil
  end
  return detail
end

-- STATE: INITIALIZE
local function stateInitialize(ctx)
  ctx.config = loadConfig()
  ctx.logger = createLogger()
  ctx.gridWidth = ctx.config.gridWidth
  ctx.gridLength = ctx.config.gridLength
  ctx.saplingSlot = ctx.config.saplingSlot
  ctx.fuelSlot = ctx.config.fuelSlot
  ctx.torchSlot = ctx.config.torchSlot
  ctx.minFuel = ctx.config.minFuel
  ctx.logBuffer = ctx.logBuffer or 0
  ctx.charcoalBuffer = ctx.charcoalBuffer or 0
  ctx.origin = { x = 0, y = 0, z = 0 }
  ctx.currentX = 0
  ctx.currentZ = 0
  ctx.fieldOrigin = { x = 1, y = 0, z = -ctx.gridLength }
  ctx.treeFacing = "south"
  ctx.factory = ctx.factory or {}
  ctx.factory.furnaceSlot = ctx.config.factorySlots.furnace
  ctx.factory.outputChestSlot = ctx.config.factorySlots.outputChest
  ctx.factory.saplingChestSlot = ctx.config.factorySlots.saplingChest
  ctx.factory.fuelChestSlot = ctx.config.factorySlots.fuelChest
  ctx.factory.logChestSlot = ctx.config.factorySlots.logChest

  movement.ensureState(ctx)
  movement.setPosition(ctx, ctx.origin)
  movement.setFacing(ctx, ctx.config.initialFacing or "east")
  local fuelState = ensureFuelState(ctx)
  if ctx.logger and fuelState and turtle and turtle.getFuelLevel then
    local level = turtle.getFuelLevel()
    ctx.logger:info(string.format("Initial fuel level: %s (threshold %d)", tostring(level), ctx.minFuel or 0))
  end
  inventory.invalidate(ctx)
  resetTraversal(ctx)
  clearRestock(ctx)
  if ctx.logger then
    ctx.logger:info("Initialization complete")
  end
  return STATE_BUILD_FACTORY
end

local function stateBuildFactory(ctx)
  -- Pre-flight fuel: delegate to fuelLib service/ensure so we can move before placing
  local ok, fuelReport = fuelLib.ensure(ctx, { threshold = ctx.minFuel, reserve = ctx.minFuel })
  if not ok then
    setError(ctx, "fuel service failed before factory build", STATE_BUILD_FACTORY)
    return STATE_ERROR
  end

  local err
  ok, err = ensureFactoryMaterials(ctx)
  if not ok then
    setError(ctx, err or "missing factory materials", STATE_BUILD_FACTORY)
    return STATE_ERROR
  end

  local order = {
    { key = "furnace", slotField = "furnaceSlot" },
    { key = "outputChest", slotField = "outputChestSlot" },
    { key = "fuelChest", slotField = "fuelChestSlot" },
    { key = "saplingChest", slotField = "saplingChestSlot" },
    { key = "logChest", slotField = "logChestSlot" },
  }

  for _, entry in ipairs(order) do
    local placed, placeErr = placeFactoryBlock(ctx, entry.key)
    if not placed then
      setError(ctx, string.format("failed placing %s: %s", entry.key, placeErr or "unknown"), STATE_BUILD_FACTORY)
      return STATE_ERROR
    end
  end

  returnHome(ctx)
  return STATE_VERIFY_FACTORY
end

-- STATE: VERIFY_FACTORY
local function stateVerifyFactory(ctx)
  for key in pairs(FACTORY_POSITIONS) do
    local ok, err = verifyFactoryBlock(ctx, key)
    if not ok then
      setError(ctx, string.format("factory block %s missing: %s", key, err or "unknown"), STATE_BUILD_FACTORY)
      return STATE_ERROR
    end
  end
  returnHome(ctx)
  return STATE_TRAVERSE
end

-- STATE: TRAVERSE
local function stateTraverse(ctx)
  ensureFuelState(ctx)
  local ok, err = refuelIfNeeded(ctx)
  if not ok then
    queueRestock(ctx, { material = ctx.config.charcoalMaterial, slot = ctx.fuelSlot, chest = "fuelChest", amount = 8 })
    return STATE_REFUEL
  end

  local tr = ctx.traverse
  if not tr or tr.done then
    resetTraversal(ctx)
    tr = ctx.traverse
  end

  local target = currentWalkPosition(ctx)

  -- Ensure we are safely outside the factory bounding box before any digging moves.
  -- This run uses soft movement only, so factory blocks are never broken.
  if isInsideFactoryBounds(ctx.origin) or isInsideFactoryBounds(ctx.position) then
    ok, err = moveSoftOutOfFactory(ctx)
    if not ok then
      setError(ctx, string.format("failed to exit factory zone: %s", err or "unknown"), STATE_TRAVERSE)
      return STATE_ERROR
    end
  end

  -- Now we are outside the factory; it's safe to use clearing moves toward the field.
  ok, err = goToWithFallback(ctx, target, MOVE_OPTS_CLEAR)
  if not ok then
    setError(ctx, string.format("failed to reach farm tile: %s", err or "unknown"), STATE_TRAVERSE)
    return STATE_ERROR
  end

  ctx.currentX = target.x
  ctx.currentZ = target.z

  return STATE_INSPECT_CELL
end

-- STATE: INSPECT_CELL
local function stateInspectCell(ctx)
  local ok, err = movement.faceDirection(ctx, ctx.treeFacing)
  if not ok then
    setError(ctx, err or "cannot face tree", STATE_INSPECT_CELL)
    return STATE_ERROR
  end

  local hasBlock, detail = turtle.inspect()
  if hasBlock and isLogBlock(ctx, detail) then
    return STATE_CHOP
  end

  if not hasBlock then
    return STATE_PLANT
  end

  if isSaplingBlock(ctx, detail) then
    advanceTraversal(ctx)
    if ctx.traverse.done then
      return STATE_RETURN_HOME
    end
    return STATE_TRAVERSE
  end

  advanceTraversal(ctx)
  if ctx.traverse.done then
    return STATE_RETURN_HOME
  end
  return STATE_TRAVERSE
end

-- STATE: CHOP
local function stateChop(ctx)
  local ok, err = movement.faceDirection(ctx, ctx.treeFacing)
  if not ok then
    setError(ctx, err or "cannot face tree", STATE_CHOP)
    return STATE_ERROR
  end

  ensureInventory(ctx)
  local before = inventory.countMaterial(ctx, ctx.config.logMaterial, { force = true }) or 0

  ok, err = movement.forward(ctx, MOVE_OPTS_CLEAR)
  if not ok then
    setError(ctx, err or "failed entering tree", STATE_CHOP)
    return STATE_ERROR
  end
  local ascended = 0
  while true do
    local upOk, upDetail = turtle.inspectUp()
    if not upOk or not isLogBlock(ctx, upDetail) then
      break
    end
    turtle.digUp()
    ok, err = movement.up(ctx, MOVE_OPTS_CLEAR)
    if not ok then
      setError(ctx, err or "failed climbing tree", STATE_CHOP)
      return STATE_ERROR
    end
    ascended = ascended + 1
  end

  while ascended > 0 do
    ok, err = movement.down(ctx, MOVE_OPTS_SOFT)
    if not ok then
      setError(ctx, err or "failed descending", STATE_CHOP)
      return STATE_ERROR
    end
    ascended = ascended - 1
  end

  ok, err = movement.turnAround(ctx)
  if not ok then
    setError(ctx, err or "turnaround failed", STATE_CHOP)
    return STATE_ERROR
  end
  ok, err = movement.forward(ctx, MOVE_OPTS_SOFT)
  if not ok then
    setError(ctx, err or "failed returning", STATE_CHOP)
    return STATE_ERROR
  end
  ok, err = movement.turnAround(ctx)
  if not ok then
    setError(ctx, err or "turnaround failed", STATE_CHOP)
    return STATE_ERROR
  end

  inventory.invalidate(ctx)
  ensureInventory(ctx)
  local after = inventory.countMaterial(ctx, ctx.config.logMaterial, { force = true }) or before
  local gained = math.max(after - before, 0)
  ctx.logBuffer = (ctx.logBuffer or 0) + gained

  advanceTraversal(ctx)
  if ctx.traverse.done then
    return STATE_RETURN_HOME
  end
  return STATE_TRAVERSE
end

-- STATE: PLANT
local function statePlant(ctx)
  local slot = ctx.saplingSlot
  if not slot then
    setError(ctx, "sapling slot not configured", STATE_PLANT)
    return STATE_ERROR
  end

  if turtle.getItemCount(slot) <= 0 then
    queueRestock(ctx, { material = ctx.config.saplingMaterial, slot = slot, chest = "saplingChest", amount = 16 })
    return STATE_RESTOCK
  end

  local ok = turtle.select(slot)
  if not ok then
    setError(ctx, "sapling slot select failed", STATE_PLANT)
    return STATE_ERROR
  end

  ok = movement.faceDirection(ctx, ctx.treeFacing)
  if not ok then
    setError(ctx, "cannot face tree", STATE_PLANT)
    return STATE_ERROR
  end

  if not turtle.place() then
    setError(ctx, "sapling placement failed", STATE_PLANT)
    return STATE_ERROR
  end

  advanceTraversal(ctx)
  if ctx.traverse.done then
    return STATE_RETURN_HOME
  end
  return STATE_TRAVERSE
end

-- STATE: RETURN_HOME
local function stateReturnHome(ctx)
  local ok, err = returnHome(ctx)
  if not ok then
    setError(ctx, err or "return home failed", STATE_RETURN_HOME)
    return STATE_ERROR
  end
  return STATE_SMELT
end

-- STATE: SMELT
local function stateSmelt(ctx)
  ensureInventory(ctx)
  local logMaterial = ctx.config.logMaterial
  local logCount = inventory.countMaterial(ctx, logMaterial, { force = true }) or 0
  if logCount <= 0 then
    ctx.logBuffer = 0
    return STATE_CRAFT
  end

  local batch = math.min(ctx.config.smeltBatch or 8, logCount)
  local slots = inventory.getMaterialSlots(ctx, logMaterial, { force = true }) or {}
  local remaining = batch

  local ok, err = moveAboveFurnace(ctx)
  if not ok then
    setError(ctx, err or "cannot reach furnace", STATE_SMELT)
    return STATE_ERROR
  end

  for _, slot in ipairs(slots) do
    if remaining <= 0 then
      break
    end
    local count = turtle.getItemCount(slot)
    if count and count > 0 then
      local toDrop = math.min(count, remaining)
      turtle.select(slot)
      if not turtle.dropDown(toDrop) then
        leaveAboveFurnace(ctx)
        setError(ctx, "failed dropping logs", STATE_SMELT)
        return STATE_ERROR
      end
      remaining = remaining - toDrop
    end
  end

  leaveAboveFurnace(ctx)
  inventory.invalidate(ctx)
  ctx.logBuffer = math.max((ctx.logBuffer or 0) - (batch - remaining), 0)

  local charcoalMaterial = ctx.config.charcoalMaterial
  if charcoalMaterial then
    ensureInventory(ctx)
    local charcoalSlot = inventory.getSlotForMaterial(ctx, charcoalMaterial, { force = true })
    if charcoalSlot then
      ok, err = moveToFurnaceFuelSide(ctx)
      if ok then
        if turtle.getItemCount(charcoalSlot) > 0 then
          turtle.select(charcoalSlot)
          turtle.drop(1)
          ctx.charcoalBuffer = math.max((ctx.charcoalBuffer or 0) - 1, 0)
        end
        leaveFurnaceFuelSide(ctx)
      end
    end
  end

  returnHome(ctx)
  movement.faceDirection(ctx, "north")
  if sleep then
    sleep(ctx.config.furnaceWait or 8)
  end

  ensureInventory(ctx)
  local before = inventory.countMaterial(ctx, charcoalMaterial, { force = true }) or 0
  for _ = 1, 4 do
    if not turtle.suck() then
      break
    end
  end
  inventory.invalidate(ctx)
  ensureInventory(ctx)
  local after = inventory.countMaterial(ctx, charcoalMaterial, { force = true }) or before
  local produced = math.max(after - before, 0)
  ctx.charcoalBuffer = (ctx.charcoalBuffer or 0) + produced

  returnHome(ctx)
  return STATE_CRAFT
end

-- STATE: CRAFT (placeholder)
local function stateCraft(ctx)
  if ctx.logger then
    ctx.logger:debug("CRAFT state currently a no-op; manual crafting may be required")
  end
  return STATE_REFUEL
end

-- STATE: REFUEL
local function stateRefuel(ctx)
  local ok, err = refuelIfNeeded(ctx)
  if ok then
    return STATE_DEPOSIT
  end

  if not ctx.restock and (err == "fuel_slot_empty" or err == "refuel_failed") then
    queueRestock(ctx, {
      material = ctx.config.charcoalMaterial,
      slot = ctx.fuelSlot,
      chest = "fuelChest",
      amount = 16,
    })
  end

  if ctx.restock then
    return STATE_RESTOCK
  end

  setError(ctx, err or "refuel failed", STATE_REFUEL)
  return STATE_ERROR
end

-- STATE: RESTOCK
local function stateRestock(ctx)
  local request = ctx.restock
  if not request then
    local fallback = ctx.restockReturnState or ctx.returnState or STATE_TRAVERSE
    ctx.restockReturnState = nil
    ctx.returnState = nil
    return fallback
  end

  local ok, err = restockFromChest(ctx, request.chest, request.material, request.slot, request.amount)
  if not ok then
    setError(ctx, err or "restock failed", STATE_RESTOCK)
    return STATE_ERROR
  end

  local resume = ctx.restockReturnState or STATE_TRAVERSE
  clearRestock(ctx)
  ctx.restockReturnState = nil
  ctx.returnState = nil
  return resume
end

-- STATE: DEPOSIT
local function stateDeposit(ctx)
  depositToChest(ctx, "logChest", ctx.config.logMaterial, 0)
  depositToChest(ctx, "outputChest", ctx.config.charcoalMaterial, ctx.config.keepCharcoal or 0)
  depositToChest(ctx, "outputChest", ctx.config.torchMaterial, ctx.config.keepTorches or 0)
  ctx.logBuffer = 0
  ensureInventory(ctx)
  local charcoalCount = inventory.countMaterial(ctx, ctx.config.charcoalMaterial, { force = true }) or 0
  ctx.charcoalBuffer = charcoalCount
  returnHome(ctx)
  return STATE_SLEEP
end

-- STATE: SLEEP
local function stateSleep(ctx)
  if sleep then
    sleep(ctx.config.sleepSeconds or 10)
  end
  resetTraversal(ctx)
  return STATE_TRAVERSE
end

-- STATE: ERROR
local function stateError(ctx)
  local message = ctx.errorMessage or "Unknown error"
  print("[TREEFACTORY] ERROR: " .. message)
  if read then
    print("Press Enter to resume")
    read()
  end
  local resume = ctx.returnState or STATE_INITIALIZE
  if ctx.errorAttempts and ctx.errorAttempts > 3 then
    print("Too many consecutive errors; falling back to INITIALIZE")
    resume = STATE_INITIALIZE
    ctx.errorAttempts = 0
  end
  ctx.errorMessage = nil
  ctx.returnState = nil
  return resume
end

local STATE_HANDLERS = {
  [STATE_INITIALIZE] = stateInitialize,
  [STATE_BUILD_FACTORY] = stateBuildFactory,
  [STATE_VERIFY_FACTORY] = stateVerifyFactory,
  [STATE_TRAVERSE] = stateTraverse,
  [STATE_INSPECT_CELL] = stateInspectCell,
  [STATE_CHOP] = stateChop,
  [STATE_PLANT] = statePlant,
  [STATE_RETURN_HOME] = stateReturnHome,
  [STATE_SMELT] = stateSmelt,
  [STATE_CRAFT] = stateCraft,
  [STATE_REFUEL] = stateRefuel,
  [STATE_RESTOCK] = stateRestock,
  [STATE_DEPOSIT] = stateDeposit,
  [STATE_SLEEP] = stateSleep,
  [STATE_ERROR] = stateError,
}

local function run()
  local ctx = {}
  local state = STATE_INITIALIZE

  while state do
    ctx.state = state
    local handler = STATE_HANDLERS[state]
    if not handler then
      print("[TREEFACTORY] Unknown state: " .. tostring(state))
      break
    end

    local ok, nextStateOrErr = pcall(handler, ctx)
    if not ok then
      setError(ctx, nextStateOrErr, STATE_ERROR)
      state = STATE_ERROR
    else
      ctx.lastState = state
      state = nextStateOrErr
    end
  end
end

run()
