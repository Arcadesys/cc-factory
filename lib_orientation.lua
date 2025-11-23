--[[
Orientation library for CC:Tweaked turtles.
Provides helpers for facing, orientation, and coordinate transformations.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local world = require("lib_world")
local gps_utils = require("lib_gps")

local orientation = {}

local START_ORIENTATIONS = {
    [1] = { label = "Forward + Left", key = "forward_left" },
    [2] = { label = "Forward + Right", key = "forward_right" },
}
local DEFAULT_ORIENTATION = 1

function orientation.resolveOrientationKey(raw)
    if type(raw) == "string" then
        local key = raw:lower()
        if key == "forward_left" or key == "forward-left" or key == "left" or key == "l" then
            return "forward_left"
        elseif key == "forward_right" or key == "forward-right" or key == "right" or key == "r" then
            return "forward_right"
        end
    elseif type(raw) == "number" and START_ORIENTATIONS[raw] then
        return START_ORIENTATIONS[raw].key
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].key
end

function orientation.orientationLabel(key)
    local resolved = orientation.resolveOrientationKey(key)
    for _, entry in pairs(START_ORIENTATIONS) do
        if entry.key == resolved then
            return entry.label
        end
    end
    return START_ORIENTATIONS[DEFAULT_ORIENTATION].label
end

function orientation.normaliseFacing(facing)
    return world.normaliseFacing(facing)
end

function orientation.facingVectors(facing)
    return world.facingVectors(facing)
end

function orientation.rotateLocalOffset(localOffset, facing)
    return world.rotateLocalOffset(localOffset, facing)
end

function orientation.localToWorld(localOffset, facing)
    return world.localToWorld(localOffset, facing)
end

function orientation.detectFacingWithGps(logger)
    return gps_utils.detectFacingWithGps(logger)
end

function orientation.turnLeftOf(facing)
    return movement.turnLeftOf(facing)
end

function orientation.turnRightOf(facing)
    return movement.turnRightOf(facing)
end

function orientation.turnBackOf(facing)
    return movement.turnBackOf(facing)
end

return orientation
