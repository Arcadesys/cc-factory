--[[
Strategy generator for farms.
Generates 3D schemas for Tree, Sugarcane, and Potato farms.
]]

local strategy = {}

local MATERIALS = {
    dirt = "minecraft:dirt",
    sand = "minecraft:sand",
    water = "minecraft:water",
    log = "minecraft:oak_log",
    sapling = "minecraft:oak_sapling",
    cane = "minecraft:sugar_cane",
    potato = "minecraft:potatoes",
    farmland = "minecraft:farmland",
    stone = "minecraft:stone_bricks", -- Border
    torch = "minecraft:torch"
}

local function createBlock(mat)
    return { material = mat }
end

function strategy.generate(farmType, width, length)
    width = tonumber(width) or 9
    length = tonumber(length) or 9
    
    local schema = {}
    
    -- Helper to set block
    local function set(x, y, z, mat)
        schema[x] = schema[x] or {}
        schema[x][y] = schema[x][y] or {}
        schema[x][y][z] = createBlock(mat)
    end

    if farmType == "tree" then
        -- Simple grid of saplings with 2 block spacing
        -- Layer 0: Dirt
        -- Layer 1: Saplings
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                set(x, 0, z, MATERIALS.dirt)
                
                -- Border
                if x == 0 or x == width - 1 or z == 0 or z == length - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    -- Checkerboard or spacing
                    if x % 3 == 1 and z % 3 == 1 then
                        set(x, 1, z, MATERIALS.sapling)
                    elseif (x % 3 == 1 and z % 3 == 0) or (x % 3 == 0 and z % 3 == 1) then
                         -- Space around sapling
                    elseif x % 5 == 0 and z % 5 == 0 then
                        set(x, 1, z, MATERIALS.torch)
                    end
                end
            end
        end

    elseif farmType == "cane" then
        -- Rows: Water, Sand, Sand, Water
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                -- Border
                if z == 0 or z == length - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    local pattern = x % 3
                    if pattern == 0 then
                        set(x, 0, z, MATERIALS.water)
                    else
                        set(x, 0, z, MATERIALS.sand)
                        set(x, 1, z, MATERIALS.cane)
                    end
                end
            end
        end

    elseif farmType == "potato" then
        -- Rows of water every 4 blocks?
        -- Hydration is 4 blocks.
        -- Pattern: W D D D D D D D D W (9 blocks)
        -- Let's do: W D D D W D D D W
        for x = 0, width - 1 do
            for z = 0, length - 1 do
                if z == 0 or z == length - 1 or x == 0 or x == width - 1 then
                    set(x, 0, z, MATERIALS.stone)
                else
                    if x % 4 == 0 then
                        set(x, 0, z, MATERIALS.water)
                        -- Cover water with slab or lily pad? 
                        -- For simplicity, leave open or put trapdoor?
                        -- Let's just leave open for now.
                    else
                        set(x, 0, z, MATERIALS.dirt) -- Turtle will till this later or we place dirt
                        -- We can't place "farmland" item usually. We place dirt.
                        -- The build script places blocks.
                        -- If we want potatoes, we need to till.
                        -- For now, let's just place dirt and plant potatoes (which might fail if not tilled).
                        -- Actually, "potatoes" block can't be placed on dirt.
                        -- So this strategy is "Prepare the land".
                        -- The user might need to till manually or we add a "TILL" state.
                        -- Let's just lay the dirt and water.
                    end
                end
            end
        end
    end

    return schema
end

return strategy
