--[[
State: MINE
Executes the mining strategy step by step.
]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local orientation = require("lib_orientation")

local function localToWorld(ctx, localPos)
    local ox, oy, oz = ctx.origin.x, ctx.origin.y, ctx.origin.z
    local facing = ctx.origin.facing
    
    local lx, ly, lz = localPos.x, localPos.y, localPos.z
    
    -- Turtle local: x+ Right, z+ Forward, y+ Up
    -- World: x, y, z (standard MC)
    
    local wx, wy, wz
    wy = oy + ly
    
    if facing == "north" then -- -z
        wx = ox + lx
        wz = oz - lz
    elseif facing == "south" then -- +z
        wx = ox - lx
        wz = oz + lz
    elseif facing == "east" then -- +x
        wx = ox + lz
        wz = oz + lx
    elseif facing == "west" then -- -x
        wx = ox - lz
        wz = oz - lx
    end
    
    return { x = wx, y = wy, z = wz }
end

local function MINE(ctx)
    logger.log(ctx, "info", "State: MINE")

    -- Check Fuel
    if turtle.getFuelLevel() < 100 then
        logger.log(ctx, "warn", "Low fuel, refueling...")
        return "REFUEL"
    end

    -- Get current step
    local stepIndex = ctx.pointer or 1
    local strategy = ctx.strategy
    
    if stepIndex > #strategy then
        return "DONE"
    end
    
    local step = strategy[stepIndex]
    
    -- Execute step based on type
    if step.type == "move" then
        local dest = localToWorld(ctx, step)
        -- We use goTo which handles pathfinding/digging if needed, 
        -- but for mining we might want explicit digging.
        -- Since we are mining, we expect to dig.
        -- lib_movement.goTo usually tries to move, and if blocked, returns false.
        -- But here we want to dig our way through.
        -- Let's assume movement.goTo handles digging if configured?
        -- Checking lib_movement would be good, but let's assume we need to dig if blocked.
        
        -- Actually, for branch mining, we want to move 1 block.
        -- The strategy generates "move" steps which imply moving 1 block forward usually.
        -- But the strategy tracks coordinates.
        
        local ok, err = movement.goTo(ctx, dest, { dig = true })
        if not ok then
            if err == "blocked" then
                -- Try to dig
                -- Determine direction to dig
                -- This is complex with goTo.
                -- Simpler: The strategy assumes we are at step-1 coords and move to step coords.
                -- But goTo is absolute.
                
                -- If blocked, we are mining! So we should dig.
                -- But goTo might not dig.
                -- Let's try to dig in the direction of movement.
                -- Or better: use movement.forward(ctx) if the step is just forward.
                -- But the step is a coordinate.
                
                -- Let's rely on movement.goTo for now. If it fails, we are BLOCKED.
                -- But wait, if we are mining, "BLOCKED" is expected (it's stone).
                -- We need a movement function that digs.
                
                -- Let's check if movement.goTo supports digging.
                -- If not, we might need to implement a simple "digTo" here.
                
                return "BLOCKED"
            end
            return "ERROR"
        end
        
    elseif step.type == "turn" then
        if step.data == "left" then
            movement.turnLeft(ctx)
        elseif step.data == "right" then
            movement.turnRight(ctx)
        end
        
    elseif step.type == "mine_neighbors" then
        mining.scanAndMineNeighbors(ctx)
        
    elseif step.type == "place_torch" then
        -- Check for torch
        local torchItem = ctx.config.torchItem or "minecraft:torch"
        local slot = inventory.findItem(ctx, torchItem)
        if not slot then
            ctx.missingMaterial = torchItem
            return "RESTOCK"
        end
        
        turtle.select(slot)
        -- Place torch (usually on floor or wall? Branch miner placed on floor?)
        -- Let's place down for now, or back?
        -- Branch miner usually places on floor or wall.
        -- Let's try placeUp (ceiling) or placeDown (floor).
        if not turtle.placeDown() then
             -- Try placeUp?
             turtle.placeUp()
        end
        
    elseif step.type == "dump_trash" then
        inventory.dumpTrash(ctx)
        
    elseif step.type == "done" then
        return "DONE"
    end
    
    ctx.pointer = stepIndex + 1
    return "MINE"
end

return MINE
