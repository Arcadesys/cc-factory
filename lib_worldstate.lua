--[[
Shared world-state + traversal helpers for CC:Tweaked farmers.
Encapsulates reference-frame math, serpentine traversal state, and
walkway-safe navigation so individual farmer scripts can stay focused
on crop-specific logic.
]]

local movement = require("lib_movement")

local worldstate = {}

local CARDINALS = { "north", "east", "south", "west" }
local CARDINAL_INDEX = {
  north = 1,
  east = 2,
  south = 3,
  west = 4,
}

local MOVE_OPTS_CLEAR = { dig = true, attack = true }
local MOVE_OPTS_SOFT = { dig = false, attack = false }
local MOVE_AXIS_FALLBACK = { "z", "x", "y" }

local function cloneTable(source)
  if type(source) ~= "table" then
    return nil
  end
  local copy = {}
  for key, value in pairs(source) do
    if type(value) == "table" then
      copy[key] = cloneTable(value)
    else
      copy[key] = value
    end
  end
  return copy
end

local function canonicalFacing(name)
  if type(name) ~= "string" then
    return nil
  end
  local normalized = name:lower()
  if CARDINAL_INDEX[normalized] then
    return normalized
  end
  return nil
end

local function rotateFacing(facing, steps)
  local canonical = canonicalFacing(facing)
  if not canonical then
    return facing
  end
  local index = CARDINAL_INDEX[canonical]
  local count = #CARDINALS
  local rotated = ((index - 1 + steps) % count) + 1
  return CARDINALS[rotated]
end

local function rotate2D(x, z, steps)
  local normalized = steps % 4
  if normalized < 0 then
    normalized = normalized + 4
  end
  if normalized == 0 then
    return x, z
  elseif normalized == 1 then
    return -z, x
  elseif normalized == 2 then
    return -x, -z
  else
    return z, -x
  end
end

local function mergeTables(target, source)
  if type(target) ~= "table" or type(source) ~= "table" then
    return target
  end
  for key, value in pairs(source) do
    if type(value) == "table" then
      target[key] = target[key] or {}
      mergeTables(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

local function ensureWorld(ctx)
  ctx.world = ctx.world or {}
  local world = ctx.world
  world.origin = world.origin or cloneTable(ctx.origin) or { x = 0, y = 0, z = 0 }
  ctx.origin = ctx.origin or cloneTable(world.origin)
  world.frame = world.frame or {}
  world.grid = world.grid or {}
  world.walkway = world.walkway or {}
  world.traversal = world.traversal or {}
  world.bounds = world.bounds or {}
  return world
end

-- Reference-frame helpers -------------------------------------------------
function worldstate.buildReferenceFrame(ctx, opts)
  local world = ensureWorld(ctx)
  opts = opts or {}
  local desired = canonicalFacing(opts.homeFacing)
    or canonicalFacing(opts.initialFacing)
    or canonicalFacing(ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing))
    or canonicalFacing(world.frame.homeFacing)
    or "east"
  local baseline = canonicalFacing(opts.referenceFacing) or "east"
  local desiredIndex = CARDINAL_INDEX[desired]
  local baselineIndex = CARDINAL_INDEX[baseline]
  local rotationSteps = ((desiredIndex - baselineIndex) % 4)
  world.frame.rotationSteps = rotationSteps
  world.frame.homeFacing = desired
  world.frame.referenceFacing = baseline
  return world.frame
end

function worldstate.referenceToWorld(ctx, refPos)
  if not refPos then
    return nil
  end
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  local x = refPos.x or 0
  local z = refPos.z or 0
  local rotatedX, rotatedZ = rotate2D(x, z, rotationSteps)
  return {
    x = (world.origin.x or 0) + rotatedX,
    y = (world.origin.y or 0) + (refPos.y or 0),
    z = (world.origin.z or 0) + rotatedZ,
  }
end

function worldstate.worldToReference(ctx, worldPos)
  if not worldPos then
    return nil
  end
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  local dx = (worldPos.x or 0) - (world.origin.x or 0)
  local dz = (worldPos.z or 0) - (world.origin.z or 0)
  local refX, refZ = rotate2D(dx, dz, -rotationSteps)
  return {
    x = refX,
    y = (worldPos.y or 0) - (world.origin.y or 0),
    z = refZ,
  }
end

function worldstate.resolveFacing(ctx, facing)
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  return rotateFacing(facing, rotationSteps)
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

function worldstate.goToReference(ctx, refPos, moveOpts)
  if not refPos then
    return false, "invalid_reference_position"
  end
  local worldPos = worldstate.referenceToWorld(ctx, refPos)
  return goToWithFallback(ctx, worldPos, moveOpts)
end

function worldstate.goAndFaceReference(ctx, refPos, facing, moveOpts)
  if not refPos then
    return false, "invalid_reference_position"
  end
  local ok, err = worldstate.goToReference(ctx, refPos, moveOpts)
  if not ok then
    return false, err
  end
  if facing then
    return movement.faceDirection(ctx, worldstate.resolveFacing(ctx, facing))
  end
  return true
end

function worldstate.returnHome(ctx, moveOpts)
  local world = ensureWorld(ctx)
  local opts = moveOpts or MOVE_OPTS_SOFT
  local ok, err = goToWithFallback(ctx, world.origin, opts)
  if not ok then
    return false, err
  end
  local facing = world.frame.homeFacing or ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing) or "east"
  ok, err = movement.faceDirection(ctx, facing)
  if not ok then
    return false, err
  end
  return true
end

-- Movement safety ---------------------------------------------------------
function worldstate.configureNoDigBounds(ctx, bounds)
  local world = ensureWorld(ctx)
  world.bounds.noDig = cloneTable(bounds)
  return world.bounds.noDig
end

local function positionWithinBounds(pos, bounds)
  if not pos or not bounds then
    return false
  end
  local x, z = pos.x or 0, pos.z or 0
  if bounds.minX and x < bounds.minX then
    return false
  end
  if bounds.maxX and x > bounds.maxX then
    return false
  end
  if bounds.minZ and z < bounds.minZ then
    return false
  end
  if bounds.maxZ and z > bounds.maxZ then
    return false
  end
  return true
end

function worldstate.moveOptsForPosition(ctx, position)
  local world = ensureWorld(ctx)
  local bounds = world.bounds.noDig
  if not bounds then
    return MOVE_OPTS_CLEAR
  end
  local ref = worldstate.worldToReference(ctx, position) or position
  if positionWithinBounds(ref, bounds) then
    return MOVE_OPTS_SOFT
  end
  return MOVE_OPTS_CLEAR
end

-- Walkway planning --------------------------------------------------------
local function isColumnX(grid, testX)
  if not grid or not grid.origin then
    return false
  end
  local spacing = grid.spacingX or 1
  local width = grid.width or 0
  local baseX = grid.origin.x or 0
  for offset = 0, math.max(width - 1, 0) do
    local columnX = baseX + offset * spacing
    if columnX == testX then
      return true
    end
  end
  return false
end

local function insertUnique(list, value)
  if not list or value == nil then
    return
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return
    end
  end
  table.insert(list, value)
end

function worldstate.configureGrid(ctx, cfg)
  local world = ensureWorld(ctx)
  cfg = cfg or {}
  world.grid.width = cfg.width or world.grid.width or ctx.config and ctx.config.gridWidth or 1
  world.grid.length = cfg.length or world.grid.length or ctx.config and ctx.config.gridLength or 1
  world.grid.spacingX = cfg.spacingX or cfg.spacing or world.grid.spacingX or ctx.config and (ctx.config.treeSpacingX or ctx.config.treeSpacing) or 1
  world.grid.spacingZ = cfg.spacingZ or cfg.spacing or world.grid.spacingZ or ctx.config and (ctx.config.treeSpacingZ or ctx.config.treeSpacing) or 1
  world.grid.origin = cloneTable(cfg.origin) or world.grid.origin or cloneTable(ctx.fieldOrigin) or { x = 0, y = 0, z = 0 }
  ctx.fieldOrigin = cloneTable(world.grid.origin)
  return world.grid
end

function worldstate.configureWalkway(ctx, cfg)
  local world = ensureWorld(ctx)
  cfg = cfg or {}
  local walkway = world.walkway
  walkway.offset = cfg.offset
    or walkway.offset
    or ctx.config and (ctx.config.walkwayOffsetX)
    or -world.grid.spacingX
  walkway.candidates = cloneTable(cfg.candidates) or walkway.candidates or {}
  if #walkway.candidates == 0 then
    insertUnique(walkway.candidates, world.grid.origin.x + (walkway.offset or -1))
    insertUnique(walkway.candidates, world.grid.origin.x)
    insertUnique(walkway.candidates, ctx.origin and ctx.origin.x)
  end
  worldstate.ensureWalkwayAvailability(ctx)
  return walkway
end

function worldstate.ensureWalkwayAvailability(ctx)
  local world = ensureWorld(ctx)
  local walkway = world.walkway
  walkway.candidates = walkway.candidates or {}
  local safe, selected = {}, walkway.selected
  for _, candidate in ipairs(walkway.candidates) do
    if candidate ~= nil and not isColumnX(world.grid, candidate) then
      insertUnique(safe, candidate)
      selected = selected or candidate
    end
  end
  if not selected then
    local spacing = world.grid.spacingX or 1
    local maxX = (world.grid.origin.x or 0) + math.max((world.grid.width or 1) - 1, 0) * spacing
    selected = maxX + spacing
    insertUnique(safe, selected)
  end
  walkway.candidates = safe
  walkway.selected = selected
  ctx.walkwayEntranceX = selected
  return selected
end

local function moveToAvailableWalkway(ctx, yLevel, targetZ)
  local world = ensureWorld(ctx)
  local walkway = world.walkway
  local candidates = walkway.candidates or { walkway.selected }
  local lastErr
  for _, safeX in ipairs(candidates) do
    if safeX then
      local currentWorld = movement.getPosition(ctx)
      local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
      local stageOne = { x = safeX, y = yLevel, z = currentRef.z }
      local ok, err = worldstate.goToReference(ctx, stageOne, MOVE_OPTS_SOFT)
      if not ok then
        lastErr = err
        goto next_candidate
      end
      local stageTwo = { x = safeX, y = yLevel, z = targetZ }
      ok, err = worldstate.goToReference(ctx, stageTwo, MOVE_OPTS_SOFT)
      if not ok then
        lastErr = err
        goto next_candidate
      end
      walkway.selected = safeX
      ctx.walkwayEntranceX = safeX
      return true
    end
    ::next_candidate::
  end
  return false, lastErr or "walkway_blocked"
end

function worldstate.moveAlongWalkway(ctx, targetRef)
  if not ctx or not targetRef then
    return false, "invalid_target"
  end
  local world = ensureWorld(ctx)
  local currentWorld = movement.getPosition(ctx)
  local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
  local yLevel = targetRef.y or world.grid.origin.y or 0
  if currentRef.z ~= targetRef.z then
    local ok, err = moveToAvailableWalkway(ctx, yLevel, targetRef.z)
    if not ok then
      return false, err
    end
    currentRef = { x = world.walkway.selected or currentRef.x, y = yLevel, z = targetRef.z }
  end
  if currentRef.x ~= targetRef.x then
    local ok, err = worldstate.goToReference(ctx, { x = targetRef.x, y = yLevel, z = targetRef.z }, MOVE_OPTS_SOFT)
    if not ok then
      return false, err
    end
  end
  return true
end

-- Traversal bookkeeping ---------------------------------------------------
function worldstate.resetTraversal(ctx, overrides)
  local world = ensureWorld(ctx)
  world.traversal = {
    row = 1,
    col = 1,
    forward = true,
    done = false,
  }
  if type(overrides) == "table" then
    mergeTables(world.traversal, overrides)
  end
  ctx.traverse = world.traversal
  return world.traversal
end

function worldstate.advanceTraversal(ctx)
  local world = ensureWorld(ctx)
  local tr = world.traversal
  if not tr then
    tr = worldstate.resetTraversal(ctx)
  end
  if tr.done then
    return tr
  end
  if tr.forward then
    if tr.col < (world.grid.width or 1) then
      tr.col = tr.col + 1
      return tr
    end
    tr.forward = false
  else
    if tr.col > 1 then
      tr.col = tr.col - 1
      return tr
    end
    tr.forward = true
  end
  tr.row = tr.row + 1
  if tr.row > (world.grid.length or 1) then
    tr.done = true
  else
    tr.col = tr.forward and 1 or (world.grid.width or 1)
  end
  return tr
end

function worldstate.currentCellRef(ctx)
  local world = ensureWorld(ctx)
  local tr = world.traversal or worldstate.resetTraversal(ctx)
  return {
    x = (world.grid.origin.x or 0) + (tr.col - 1) * (world.grid.spacingX or 1),
    y = world.grid.origin.y or 0,
    z = (world.grid.origin.z or 0) + (tr.row - 1) * (world.grid.spacingZ or 1),
  }
end

function worldstate.currentCellWorld(ctx)
  return worldstate.referenceToWorld(ctx, worldstate.currentCellRef(ctx))
end

function worldstate.offsetFromCell(ctx, offset)
  offset = offset or {}
  local base = worldstate.currentCellRef(ctx)
  return {
    x = base.x + (offset.x or 0),
    y = base.y + (offset.y or 0),
    z = base.z + (offset.z or 0),
  }
end

function worldstate.currentWalkPositionRef(ctx)
  local world = ensureWorld(ctx)
  local ref = worldstate.currentCellRef(ctx)
  return {
    x = (ref.x or 0) + (world.walkway.offset or -1),
    y = ref.y,
    z = ref.z,
  }
end

function worldstate.currentWalkPositionWorld(ctx)
  return worldstate.referenceToWorld(ctx, worldstate.currentWalkPositionRef(ctx))
end

function worldstate.ensureTraversal(ctx)
  local world = ensureWorld(ctx)
  if not world.traversal then
    worldstate.resetTraversal(ctx)
  end
  return world.traversal
end

-- Convenience exports -----------------------------------------------------
worldstate.MOVE_OPTS_CLEAR = MOVE_OPTS_CLEAR
worldstate.MOVE_OPTS_SOFT = MOVE_OPTS_SOFT

return worldstate
