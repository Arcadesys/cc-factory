--[[
Strategy generator for excavation (quarry).
Produces a linear list of steps for the turtle to excavate a hole of given dimensions.
]]

local strategy = {}

local function normalizePositiveInt(value, default)
    local numberValue = tonumber(value)
    if not numberValue or numberValue < 1 then
        return default
    end
    return math.floor(numberValue)
end

local function pushStep(steps, x, y, z, facing, stepType, data)
    steps[#steps + 1] = {
        type = stepType,
        x = x,
        y = y,
        z = z,
        facing = facing,
        data = data,
    }
end

--- Generate an excavation strategy
---@param length number Length (z-axis)
---@param width number Width (x-axis)
---@param depth number Depth (y-axis, downwards)
---@return table
function strategy.generate(length, width, depth)
    length = normalizePositiveInt(length, 8)
    width = normalizePositiveInt(width, 8)
    depth = normalizePositiveInt(depth, 3)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)

    -- We assume turtle starts at (0,0,0) which is the top-left corner of the hole.
    -- It will excavate x=[0, width-1], z=[0, length-1], y=[0, -depth+1].
    
    for d = 0, depth - 1 do
        local currentY = -d
        
        -- Serpentine pattern for the layer
        -- If d is even: start at (0,0), end at (W-1, L-1) or (0, L-1) depending on W.
        -- If d is odd: we should probably reverse to minimize travel.
        
        -- Actually, standard excavate usually returns to start to dump items?
        -- My system handles restocking/refueling via state machine interrupts.
        -- So I just need to generate the path.
        
        -- Layer logic:
        -- Iterate z from 0 to length-1.
        -- For each z, iterate x.
        
        -- To optimize, we alternate x direction every z row.
        -- And we alternate z direction every layer?
        
        -- Let's keep it simple.
        -- Layer 0: z=0..L-1.
        --   z=0: x=0..W-1
        --   z=1: x=W-1..0
        --   ...
        
        -- End of Layer 0 is at z=L-1, x=(depends).
        -- Layer 1 starts at z=L-1, x=(same).
        -- So Layer 1 should go z=L-1..0.
        
        local zStart, zEnd, zStep
        if d % 2 == 0 then
            zStart, zEnd, zStep = 0, length - 1, 1
        else
            zStart, zEnd, zStep = length - 1, 0, -1
        end
        
        for z = zStart, zEnd, zStep do
            local xStart, xEnd, xStep
            -- Determine x direction based on z and layer parity?
            -- If d is even (0):
            --   z=0: x=0..W-1
            --   z=1: x=W-1..0
            --   So if z is even, x=0..W-1.
            
            -- If d is odd (1):
            --   We start at z=L-1.
            --   We want to match the x from previous layer.
            --   Previous layer ended at z=L-1.
            --   If (L-1) was even, it ended at W-1.
            --   If (L-1) was odd, it ended at 0.
            
            -- Let's just use currentX to decide.
            -- But we are generating steps, we don't track currentX easily unless we simulate.
            -- Let's simulate.
            
            -- Wait, I can just use the same logic as tunnel.
            -- If we are at x=0, go to W-1.
            -- If we are at x=W-1, go to 0.
            
            -- But I need to know where I am at the start of the z-loop.
            -- At start of d=0, I am at (0,0,0).
            
            -- Let's track currentX, currentZ.
            if d == 0 and z == zStart then
                x = 0
            end
            
            if x == 0 then
                xStart, xEnd, xStep = 0, width - 1, 1
            else
                xStart, xEnd, xStep = width - 1, 0, -1
            end
            
            for ix = xStart, xEnd, xStep do
                x = ix
                pushStep(steps, x, currentY, z, 0, "move")
            end
        end
    end

    return steps
end

return strategy
