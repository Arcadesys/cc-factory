--[[
Strategy generator for tunneling.
Produces a linear list of steps for the turtle to excavate a tunnel of given dimensions.
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

local function forward(x, z, facing)
    if facing == 0 then
        z = z + 1
    elseif facing == 1 then
        x = x + 1
    elseif facing == 2 then
        z = z - 1
    else
        x = x - 1
    end
    return x, z
end

local function turnLeft(facing)
    return (facing + 3) % 4
end

local function turnRight(facing)
    return (facing + 1) % 4
end

--- Generate a tunnel strategy
---@param length number Length of the tunnel
---@param width number Width of the tunnel
---@param height number Height of the tunnel
---@param torchInterval number Distance between torches
---@return table
function strategy.generate(length, width, height, torchInterval)
    length = normalizePositiveInt(length, 16)
    width = normalizePositiveInt(width, 1)
    height = normalizePositiveInt(height, 2)
    torchInterval = normalizePositiveInt(torchInterval, 6)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward (z+), 1: right (x+), 2: back (z-), 3: left (x-)

    -- We assume the turtle starts at bottom-left of the tunnel face, facing into the tunnel.
    -- Actually, let's assume turtle starts at (0,0,0) and that is the bottom-center or bottom-left?
    -- Let's assume standard behavior: Turtle is at start of tunnel.
    -- It will mine forward `length` blocks.
    -- If width > 1, it needs to strafe or turn.
    
    -- Simple implementation: Layer by layer, row by row.
    -- But for a tunnel, we usually want to move forward, clearing the cross-section.
    
    for l = 1, length do
        -- Clear the cross-section at current depth
        -- We are at some (x, y) in the cross section.
        -- Let's say we start at bottom-left (0,0) of the cross section relative to the tunnel axis.
        
        -- Actually, simpler: Just iterate x, y, z loops.
        -- But we want to minimize movement.
        -- Serpentine pattern for the cross section?
        
        -- Let's stick to the `state_mine` logic which expects "move" steps.
        -- `state_mine` is designed for branch mining where it moves forward and mines neighbors.
        -- It might not be suitable for clearing a large room.
        -- `state_mine` supports: move, turn, mine_neighbors, place_torch.
        -- `mine_neighbors` mines up, down, left, right, front.
        
        -- If we use `state_mine`, we are limited to its capabilities.
        -- Maybe we should use `state_build` logic but with "dig" enabled?
        -- Or extend `state_mine`?
        
        -- `state_mine` logic:
        -- if step.type == "move" then movement.goTo(dest, {dig=true})
        
        -- So if we generate a path that covers every block in the tunnel volume, `movement.goTo` with `dig=true` will clear it.
        -- We just need to generate the path.
        
        -- Let's generate a path that visits every block in the volume (0..width-1, 0..height-1, 1..length)
        -- Wait, 1..length because 0 is start?
        -- Let's say turtle starts at 0,0,0.
        -- It needs to clear 0,0,1 to width-1, height-1, length.
        
        -- Actually, let's just do a simple serpentine.
        
        -- Current pos
        -- x, y, z are relative to start.
        
        -- We are at (x,y,z). We want to clear the block at (x,y,z) if it's not 0,0,0?
        -- No, `goTo` moves TO the block.
        
        -- Let's iterate length first (depth), then width/height?
        -- No, usually you want to clear the face then move forward.
        -- But `goTo` is absolute coords.
        
        -- Let's do:
        -- For each slice z = 1 to length:
        --   For each y = 0 to height-1:
        --     For each x = 0 to width-1:
        --       visit(x, y, z)
        
        -- Optimization: Serpentine x and y.
    end
    
    -- Re-thinking: `state_mine` uses `localToWorld` which interprets x,y,z relative to turtle start.
    -- So we just need to generate a list of coordinates to visit.
    
    local currentX, currentY, currentZ = 0, 0, 0
    
    for d = 1, length do
        -- Move forward to next slice
        -- We are at z = d-1. We want to clear z = d.
        -- But we also need to clear x=0..width-1, y=0..height-1 at z=d.
        
        -- Let's assume we are at (currentX, currentY, d-1).
        -- We move to (currentX, currentY, d).
        
        -- Serpentine logic for the face
        -- We are at some x,y.
        -- We want to cover all x in [0, width-1] and y in [0, height-1].
        
        -- If we are just moving forward, we are carving a 1x1 tunnel.
        -- If width/height > 1, we need to visit others.
        
        -- Let's generate points.
        local slicePoints = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                table.insert(slicePoints, {x=x, y=y})
            end
        end
        
        -- Sort slicePoints to be nearest neighbor or serpentine
        -- Simple serpentine:
        -- If y is even, x goes 0 -> width-1
        -- If y is odd, x goes width-1 -> 0
        -- But we also need to minimize y movement.
        
        -- Actually, let's just generate the path directly.
        
        -- We are at z=d.
        -- We iterate y from 0 to height-1.
        -- If y is even: x from 0 to width-1
        -- If y is odd: x from width-1 to 0
        
        -- But wait, between slices, we want to connect the end of slice d to start of slice d+1.
        -- End of slice d is (endX, endY, d).
        -- Start of slice d+1 should be (endX, endY, d+1).
        -- So we should reverse the traversal order for the next slice?
        -- Or just continue?
        
        -- Let's try to keep it simple.
        -- Slice 1:
        --   y=0: x=0->W
        --   y=1: x=W->0
        --   ...
        --   End at (LastX, LastY, 1)
        
        -- Slice 2:
        --   Start at (LastX, LastY, 2)
        --   We should traverse in reverse of Slice 1 to minimize movement?
        --   Or just continue the pattern?
        
        -- Let's just do standard serpentine for every slice, but reverse the whole slice order if d is even?
        
        local yStart, yEnd, yStep
        if d % 2 == 1 then
            yStart, yEnd, yStep = 0, height - 1, 1
        else
            yStart, yEnd, yStep = height - 1, 0, -1
        end
        
        for y = yStart, yEnd, yStep do
            local xStart, xEnd, xStep
            -- If we are on an "even" row relative to the start of this slice...
            -- Let's just say: if y is even, go right. If y is odd, go left.
            -- But we need to match the previous position.
            
            -- If we came from z-1, we are at (currentX, currentY, d-1).
            -- We move to (currentX, currentY, d).
            -- So we should start this slice at currentX, currentY.
            
            -- This implies we shouldn't hardcode loops, but rather "fill" the slice starting from current pos.
            -- But that's pathfinding.
            
            -- Let's stick to a fixed pattern that aligns.
            -- If width=1, height=2.
            -- d=1: (0,0,1) -> (0,1,1). End at (0,1,1).
            -- d=2: (0,1,2) -> (0,0,2). End at (0,0,2).
            -- d=3: (0,0,3) -> (0,1,3).
            -- This works perfectly.
            
            -- So:
            -- If d is odd: y goes 0 -> height-1.
            -- If d is even: y goes height-1 -> 0.
            
            -- Inside y loop:
            -- We need to decide x direction.
            -- If y is even (0, 2...): x goes 0 -> width-1?
            -- Let's trace d=1 (odd). y=0. x=0->W. End x=W-1.
            -- y=1. We are at x=W-1. So x should go W-1 -> 0.
            -- So if y is odd: x goes W-1 -> 0.
            
            -- Now d=2 (even). Start y=height-1.
            -- If height=2. Start y=1.
            -- We ended d=1 at (0, 1, 1).
            -- So we start d=2 at (0, 1, 2).
            -- y=1 is odd. So x goes W-1 -> 0?
            -- Wait, we are at x=0.
            -- So if y is odd, we should go 0 -> W-1?
            -- This depends on where we ended.
            
            -- Let's generalize.
            -- We are at (currentX, currentY, d).
            -- We want to visit all x in row y.
            -- If currentX is 0, go to W-1.
            -- If currentX is W-1, go to 0.
            
            if currentX == 0 then
                xStart, xEnd, xStep = 0, width - 1, 1
            else
                xStart, xEnd, xStep = width - 1, 0, -1
            end
            
            for x = xStart, xEnd, xStep do
                -- We are visiting (x, y, d)
                -- But wait, we need to actually MOVE there.
                -- The loop generates the target coordinates.
                
                -- If this is the very first point (0,0,1), we are at (0,0,0).
                -- We just push the step.
                
                pushStep(steps, x, y, d, 0, "move")
                currentX, currentY, currentZ = x, y, d
                
                -- Place torch?
                -- Only on the floor (y=0) and maybe centered x?
                -- And at interval.
                if y == 0 and x == math.floor((width-1)/2) and d % torchInterval == 0 then
                     pushStep(steps, x, y, d, 0, "place_torch")
                end
            end
        end
    end

    return steps
end

return strategy
