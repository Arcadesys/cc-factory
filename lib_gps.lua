--[[
GPS library for CC:Tweaked turtles.
Provides helpers for using the GPS API.
--]]

---@diagnostic disable: undefined-global

local gps_utils = {}

function gps_utils.detectFacingWithGps(logger)
    if not gps or type(gps.locate) ~= "function" then
        return nil, "gps_unavailable"
    end
    if not turtle or type(turtle.forward) ~= "function" or type(turtle.back) ~= "function" then
        return nil, "turtle_api_unavailable"
    end

    local function locate(timeout)
        local ok, x, y, z = pcall(gps.locate, timeout)
        if ok and x then
            return x, y, z
        end
        return nil, nil, nil
    end

    local x1, _, z1 = locate(0.5)
    if not x1 then
        x1, _, z1 = locate(1)
        if not x1 then
            return nil, "gps_initial_failed"
        end
    end

    if not turtle.forward() then
        return nil, "forward_blocked"
    end

    local x2, _, z2 = locate(0.5)
    if not x2 then
        x2, _, z2 = locate(1)
    end

    local returned = turtle.back()
    if not returned then
        local attempts = 0
        while attempts < 5 and not returned do
            returned = turtle.back()
            attempts = attempts + 1
            if not returned and sleep then
                sleep(0)
            end
        end
        if not returned then
            if logger then
                logger:warn("Facing detection failed to restore the turtle's start position; adjust the turtle manually and rerun.")
            end
            return nil, "return_failed"
        end
    end

    if not x2 then
        return nil, "gps_second_failed"
    end

    local dx = x2 - x1
    local dz = z2 - z1
    local threshold = 0.2

    if math.abs(dx) < threshold and math.abs(dz) < threshold then
        return nil, "gps_delta_small"
    end

    if math.abs(dx) >= math.abs(dz) then
        if dx > threshold then
            return "east"
        elseif dx < -threshold then
            return "west"
        end
    else
        if dz > threshold then
            return "south"
        elseif dz < -threshold then
            return "north"
        end
    end

    return nil, "gps_delta_small"
end

return gps_utils
