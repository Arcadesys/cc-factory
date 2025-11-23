--[[
Strategy generator for branch mining.
Produces a linear list of steps for the turtle to execute.
]]

local strategy = {}

--- Generate a branch mining strategy
-- @param length number Length of the main spine
-- @param branchInterval number Distance between branches
-- @param branchLength number Length of each branch
-- @param torchInterval number Distance between torches on spine
-- @return table List of steps
function strategy.generate(length, branchInterval, branchLength, torchInterval)
    local steps = {}
    local x, y, z = 0, 0, 0 -- Local coordinates relative to start
    local facing = 0 -- 0: forward, 1: right, 2: back, 3: left

    local function addStep(type, data)
        table.insert(steps, { type = type, x = x, y = y, z = z, facing = facing, data = data })
    end

    -- Helper to move forward in local space
    local function forward()
        if facing == 0 then z = z + 1
        elseif facing == 1 then x = x + 1
        elseif facing == 2 then z = z - 1
        elseif facing == 3 then x = x - 1
        end
        addStep("move")
        addStep("mine_neighbors")
    end

    local function turnRight()
        facing = (facing + 1) % 4
        addStep("turn", "right")
    end

    local function turnLeft()
        facing = (facing - 1) % 4
        addStep("turn", "left")
    end

    -- Initial setup
    addStep("mine_neighbors")

    for i = 1, length do
        forward()

        -- Place torch on spine
        if i % torchInterval == 0 then
            addStep("place_torch")
        end

        -- Dig branches
        if i % branchInterval == 0 then
            -- Left branch
            turnLeft()
            for b = 1, branchLength do
                forward()
            end
            -- Return from left branch
            turnRight()
            turnRight()
            for b = 1, branchLength do
                forward()
            end
            turnRight() -- Back to spine facing

            -- Right branch
            turnRight()
            for b = 1, branchLength do
                forward()
            end
            -- Return from right branch
            turnRight()
            turnRight()
            for b = 1, branchLength do
                forward()
            end
            turnLeft() -- Back to spine facing
        end
        
        -- Periodic trash dump
        if i % 5 == 0 then
            addStep("dump_trash")
        end
    end

    -- Return to start
    turnRight()
    turnRight()
    for i = 1, length do
        forward()
    end
    turnRight()
    turnRight() -- Restore original facing

    addStep("done")

    return steps
end

return strategy
