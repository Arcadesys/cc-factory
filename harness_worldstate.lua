-- World state harness for lib_worldstate.lua
-- Simulates turtle movement to exercise reference frames, traversal, and
-- walkway logic without needing an actual turtle.

---@diagnostic disable: undefined-global

local common = require("harness_common")

--[[
Mocked movement module --------------------------------------------------------
Provides deterministic movement + logging so worldstate can be tested without
CC:Tweaked. The stub exposes a __test helper for configuring scenarios.
]]
local movementStub = {}

local function copyPosition(pos)
    pos = pos or {}
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

local function serializePosition(pos)
    pos = copyPosition(pos)
    return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

local function ensureState(ctx)
    if type(ctx) ~= "table" then
        error("movement ctx required")
    end
    if not ctx._movementState then
        local origin = copyPosition(ctx.origin)
        local facing = (ctx.config and (ctx.config.initialFacing or ctx.config.homeFacing)) or "east"
        ctx._movementState = {
            position = origin,
            facing = facing,
            log = {},
            failWithoutAxis = {},
        }
    end
    return ctx._movementState
end

local function logEvent(state, event)
    state.log[#state.log + 1] = event
end

function movementStub.goTo(ctx, position, moveOpts)
    local state = ensureState(ctx)
    local target = copyPosition(position)
    local axisOrder = moveOpts and moveOpts.axisOrder
    logEvent(state, {
        action = "goTo",
        position = target,
        axisOrder = axisOrder,
    })
    local key = serializePosition(target)
    if state.failWithoutAxis[key] and not axisOrder then
        return false, "axis_blocked"
    end
    state.failWithoutAxis[key] = nil
    state.position = target
    return true
end

function movementStub.faceDirection(ctx, facing)
    local state = ensureState(ctx)
    state.facing = facing
    logEvent(state, { action = "face", facing = facing })
    return true
end

function movementStub.getPosition(ctx)
    local state = ensureState(ctx)
    return copyPosition(state.position)
end

function movementStub.getFacing(ctx)
    local state = ensureState(ctx)
    return state.facing
end

movementStub.__test = {
    ensureState = ensureState,
    setPosition = function(ctx, pos)
        local state = ensureState(ctx)
        state.position = copyPosition(pos)
    end,
    requireAxisOrder = function(ctx, pos)
        local state = ensureState(ctx)
        local key = serializePosition(pos)
        state.failWithoutAxis[key] = true
    end,
    clearLog = function(ctx)
        ensureState(ctx).log = {}
    end,
    getLog = function(ctx)
        return ensureState(ctx).log
    end,
}

package.loaded["lib_movement"] = movementStub
local worldstate = require("lib_worldstate")

-- Assertion helpers ----------------------------------------------------------
local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s expected %s got %s", label or "value", tostring(expected), tostring(actual)))
    end
end

local function assertVector(actual, expected, label)
    assertEqual(actual.x, expected.x, (label or "vector") .. ".x")
    assertEqual(actual.y, expected.y, (label or "vector") .. ".y")
    assertEqual(actual.z, expected.z, (label or "vector") .. ".z")
end

local DEFAULT_CONTEXT = {
    origin = { x = 0, y = 64, z = 0 },
    config = {
        initialFacing = "east",
        homeFacing = "east",
        treeSpacing = 2,
        treeSpacingX = 2,
        treeSpacingZ = 3,
        gridWidth = 3,
        gridLength = 2,
    },
}

local function freshCtx(overrides)
    local ctx = common.merge(DEFAULT_CONTEXT, overrides or {})
    ctx.world = nil
    ctx.walkwayEntranceX = nil
    ctx.fieldOrigin = nil
    ctx.traverse = nil
    ctx._movementState = nil
    return ctx
end

local function lastLogEntry(ctx)
    local log = movementStub.__test.getLog(ctx)
    return log[#log]
end

local function renderAsciiWorld(ctx, io, radius)
    radius = radius or 5
    if not ctx then
        if io and io.print then
            io.print("No snapshot available")
        end
        return
    end
    local world = ctx.world or {}
    local grid = world.grid or {}
    local walkway = world.walkway or {}
    local spacingX = grid.spacingX or 1
    local spacingZ = grid.spacingZ or 1
    local origin = grid.origin or { x = 0, y = 0, z = 0 }
    local turtleRef = worldstate.worldToReference(ctx, movementStub.getPosition(ctx)) or { x = 0, z = 0 }
    local walkwayX = walkway.selected

    local function isColumn(x)
        local width = grid.width or 0
        for col = 0, math.max(width - 1, 0) do
            if (origin.x or 0) + col * spacingX == x then
                return true
            end
        end
        return false
    end

    local function isRow(z)
        local length = grid.length or 0
        for row = 0, math.max(length - 1, 0) do
            if (origin.z or 0) + row * spacingZ == z then
                return true
            end
        end
        return false
    end

    local lines = {}
    for dz = radius, -radius, -1 do
        local z = turtleRef.z + dz
        local chars = {}
        for dx = -radius, radius do
            local x = turtleRef.x + dx
            local char = "."
            if x == turtleRef.x and z == turtleRef.z then
                char = "T"
            elseif walkwayX and x == walkwayX then
                char = "|"
            elseif isColumn(x) and isRow(z) then
                char = "#"
            elseif isColumn(x) then
                char = "x"
            elseif isRow(z) then
                char = "-"
            end
            chars[#chars + 1] = char
        end
        lines[#lines + 1] = table.concat(chars)
    end

    if io and io.print then
        io.print("\nWorld snapshot around turtle (T):")
        io.print("Legend: # cell center, x column, - row, | walkway")
        io.print(table.concat(lines, "\n"))
    end
end

local function testReferenceFrame()
    local ctx = freshCtx({
        origin = { x = 10, y = 5, z = -4 },
        config = { initialFacing = "south", homeFacing = "west" },
    })
    local frame = worldstate.buildReferenceFrame(ctx, {
        homeFacing = "north",
        referenceFacing = "west",
    })
    assertEqual(frame.rotationSteps, 1, "rotation steps")
    local refPos = { x = 3, y = 2, z = -1 }
    local worldPos = worldstate.referenceToWorld(ctx, refPos)
    assertVector(worldPos, { x = 11, y = 7, z = -1 }, "ref->world")
    local roundTrip = worldstate.worldToReference(ctx, worldPos)
    assertVector(roundTrip, refPos, "world->ref")
    local resolvedFacing = worldstate.resolveFacing(ctx, "north")
    assertEqual(resolvedFacing, "east", "resolved facing")
    return true
end

local function testMovementOps()
    local ctx = freshCtx()
    worldstate.buildReferenceFrame(ctx, { homeFacing = "east" })
    movementStub.__test.clearLog(ctx)
    local refTarget = { x = 6, y = 64, z = -2 }
    local worldTarget = worldstate.referenceToWorld(ctx, refTarget)
    movementStub.__test.requireAxisOrder(ctx, worldTarget)
    local ok = select(1, worldstate.goToReference(ctx, refTarget))
    assertEqual(ok, true, "goToReference result")
    local log = movementStub.__test.getLog(ctx)
    assertEqual(#log, 2, "goTo attempts")
    assertEqual(log[1].axisOrder, nil, "first attempt axis order")
    assertEqual(type(log[2].axisOrder), "table", "fallback axis order")

    local faceOk = select(1, worldstate.goAndFaceReference(ctx, { x = 0, y = 64, z = 0 }, "north"))
    assertEqual(faceOk, true, "goAndFaceReference")
    assertEqual(lastLogEntry(ctx).facing, "north", "facing updated")

    movementStub.__test.setPosition(ctx, { x = 20, y = 64, z = 5 })
    local returnOk = select(1, worldstate.returnHome(ctx))
    assertEqual(returnOk, true, "returnHome result")
    assertVector(movementStub.getPosition(ctx), ctx.origin, "home position")
    assertEqual(movementStub.getFacing(ctx), ctx.config.homeFacing, "home facing")
    return true
end

local function testSafetyBounds()
    local ctx = freshCtx()
    worldstate.buildReferenceFrame(ctx)
    worldstate.configureGrid(ctx, { width = 2, length = 2, spacingX = 2, spacingZ = 3 })
    worldstate.configureNoDigBounds(ctx, { minX = 0, maxX = 4, minZ = 0, maxZ = 6 })
    local insideWorld = worldstate.referenceToWorld(ctx, { x = 2, y = 64, z = 3 })
    local outsideWorld = worldstate.referenceToWorld(ctx, { x = 6, y = 64, z = 9 })
    local insideOpts = worldstate.moveOptsForPosition(ctx, insideWorld)
    local outsideOpts = worldstate.moveOptsForPosition(ctx, outsideWorld)
    assertEqual(insideOpts, worldstate.MOVE_OPTS_SOFT, "inside bounds opts")
    assertEqual(outsideOpts, worldstate.MOVE_OPTS_CLEAR, "outside bounds opts")
    return true
end

local function testWalkway(io)
    local ctx = freshCtx()
    worldstate.buildReferenceFrame(ctx)
    local grid = worldstate.configureGrid(ctx, {
        width = 3,
        length = 3,
        spacingX = 2,
        spacingZ = 3,
        origin = { x = 0, y = 64, z = 0 },
    })
    assertEqual(grid.width, 3, "grid width")
    assertEqual(grid.spacingZ, 3, "grid spacingZ")

    local walkway = worldstate.configureWalkway(ctx, {
        candidates = { grid.origin.x, grid.origin.x + grid.spacingX },
        offset = -2,
    })
    assertEqual(walkway.selected, grid.origin.x + grid.spacingX * grid.width, "fallback walkway")
    local ensured = worldstate.ensureWalkwayAvailability(ctx)
    assertEqual(ensured, walkway.selected, "ensureWalkwayAvailability")

    local entryRef = { x = walkway.selected, y = grid.origin.y, z = grid.origin.z }
    movementStub.__test.setPosition(ctx, worldstate.referenceToWorld(ctx, entryRef))
    movementStub.__test.clearLog(ctx)

    local targetRef = { x = grid.origin.x, y = grid.origin.y, z = grid.origin.z + grid.spacingZ }
    local ok, err = worldstate.moveAlongWalkway(ctx, targetRef)
    assertEqual(ok, true, err or "walkway move")
    local log = movementStub.__test.getLog(ctx)
    assertEqual(#log, 3, "walkway goTo count")
    assertVector(worldstate.worldToReference(ctx, movementStub.getPosition(ctx)), targetRef, "final walkway position")
    return true, ctx
end

local function testTraversal(ctx)
    local traversalCtx = ctx or freshCtx()
    worldstate.configureGrid(traversalCtx, {
        width = 3,
        length = 2,
        spacingX = 2,
        spacingZ = 3,
        origin = { x = 0, y = 64, z = 0 },
    })
    worldstate.configureWalkway(traversalCtx, { offset = -1 })
    local tr = worldstate.resetTraversal(traversalCtx)
    assertEqual(tr.row, 1, "initial row")
    assertEqual(tr.col, 1, "initial col")
    local cellRef = worldstate.currentCellRef(traversalCtx)
    assertVector(cellRef, { x = 0, y = 64, z = 0 }, "first cell")
    local offsetRef = worldstate.offsetFromCell(traversalCtx, { x = 1, z = 2 })
    assertVector(offsetRef, { x = 1, y = 64, z = 2 }, "offset cell")

    worldstate.advanceTraversal(traversalCtx)
    worldstate.advanceTraversal(traversalCtx)
    worldstate.advanceTraversal(traversalCtx)
    assertEqual(tr.col, 2, "serpentine col")
    assertEqual(tr.row, 2, "serpentine row")

    local currentWorld = worldstate.currentCellWorld(traversalCtx)
    assertVector(currentWorld, worldstate.referenceToWorld(traversalCtx, worldstate.currentCellRef(traversalCtx)), "current cell world")

    local walkRef = worldstate.currentWalkPositionRef(traversalCtx)
    local walkWorld = worldstate.currentWalkPositionWorld(traversalCtx)
    assertVector(walkWorld, worldstate.referenceToWorld(traversalCtx, walkRef), "walkway world pos")

    local ensured = worldstate.ensureTraversal(traversalCtx)
    assertEqual(ensured, traversalCtx.world.traversal, "ensureTraversal")
    return true
end

local function run(ioOverrides)
    local io = common.resolveIo(ioOverrides)
    local suite = common.createSuite({ name = "Worldstate Harness", io = io })
    local snapshotCtx

    suite:step("Reference frame math", testReferenceFrame)
    suite:step("Movement and facing", testMovementOps)
    suite:step("Safety bounds", testSafetyBounds)
    suite:step("Walkway planning", function()
        local ok, ctx = testWalkway(io)
        if ok then
            snapshotCtx = ctx
        end
        return ok
    end)
    suite:step("Traversal bookkeeping", function()
        return testTraversal(snapshotCtx)
    end)

    suite:summary()
    renderAsciiWorld(snapshotCtx, io, 6)
    return suite
end

local M = { run = run }

local args = { ... }
if #args == 0 then
    run()
end

return M
