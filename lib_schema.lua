--[[
Schema library for CC:Tweaked turtles.
Provides helpers for working with build schemas.
--]]

---@diagnostic disable: undefined-global

local schema_utils = {}
local table_utils = require("lib_table")

local function copyTable(tbl)
    if type(tbl) ~= "table" then return {} end
    return table_utils.shallowCopy(tbl)
end

function schema_utils.pushMaterialCount(counts, material)
    counts[material] = (counts[material] or 0) + 1
end

function schema_utils.cloneMeta(meta)
    return copyTable(meta)
end

function schema_utils.newBounds()
    return {
        min = { x = math.huge, y = math.huge, z = math.huge },
        max = { x = -math.huge, y = -math.huge, z = -math.huge },
    }
end

function schema_utils.updateBounds(bounds, x, y, z)
    local minB = bounds.min
    local maxB = bounds.max
    if x < minB.x then minB.x = x end
    if y < minB.y then minB.y = y end
    if z < minB.z then minB.z = z end
    if x > maxB.x then maxB.x = x end
    if y > maxB.y then maxB.y = y end
    if z > maxB.z then maxB.z = z end
end

function schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return false, "invalid_coordinate"
    end
    if type(material) ~= "string" or material == "" then
        return false, "invalid_material"
    end
    meta = schema_utils.cloneMeta(meta)
    schema[x] = schema[x] or {}
    local yLayer = schema[x]
    yLayer[y] = yLayer[y] or {}
    local zLayer = yLayer[y]
    if zLayer[z] ~= nil then
        return false, "duplicate_coordinate"
    end
    zLayer[z] = { material = material, meta = meta }
    schema_utils.updateBounds(bounds, x, y, z)
    schema_utils.pushMaterialCount(counts, material)
    return true
end

function schema_utils.mergeLegend(base, override)
    local result = {}
    if type(base) == "table" then
        for symbol, entry in pairs(base) do
            result[symbol] = entry
        end
    end
    if type(override) == "table" then
        for symbol, entry in pairs(override) do
            result[symbol] = entry
        end
    end
    return result
end

function schema_utils.normaliseLegendEntry(symbol, entry)
    if entry == nil then
        return nil, "unknown_symbol"
    end
    if entry == false or entry == "" then
        return false
    end
    if type(entry) == "string" then
        return { material = entry, meta = {} }
    end
    if type(entry) == "table" then
        if entry.material == nil and entry[1] then
            entry = { material = entry[1], meta = entry[2] }
        end
        local material = entry.material
        if material == nil or material == "" then
            return false
        end
        local meta = entry.meta
        if meta ~= nil and type(meta) ~= "table" then
            return nil, "invalid_meta"
        end
        return { material = material, meta = meta or {} }
    end
    return nil, "invalid_legend_entry"
end

function schema_utils.resolveSymbol(symbol, legend, opts)
    if symbol == "" then
        return nil, "empty_symbol"
    end
    if legend == nil then
        return nil, "missing_legend"
    end
    local entry = legend[symbol]
    if entry == nil then
        if symbol == "." or symbol == " " then
            return false
        end
        if opts and opts.allowImplicitAir and symbol:match("^%p?$") then
            return false
        end
        return nil, "unknown_symbol"
    end
    local normalised, err = schema_utils.normaliseLegendEntry(symbol, entry)
    if err then
        return nil, err
    end
    return normalised
end

function schema_utils.fetchSchemaEntry(schema, pos)
    if type(schema) ~= "table" or type(pos) ~= "table" then
        return nil, "missing_schema"
    end
    local xLayer = schema[pos.x] or schema[tostring(pos.x)]
    if type(xLayer) ~= "table" then
        return nil, "empty"
    end
    local yLayer = xLayer[pos.y] or xLayer[tostring(pos.y)]
    if type(yLayer) ~= "table" then
        return nil, "empty"
    end
    local block = yLayer[pos.z] or yLayer[tostring(pos.z)]
    if block == nil then
        return nil, "empty"
    end
    return block
end

function schema_utils.canonicalToGrid(schema, opts)
    opts = opts or {}
    local grid = {}
    if type(schema) ~= "table" then
        return grid
    end
    for x, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            for y, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    for z, block in pairs(yColumn) do
                        if block and type(block) == "table" then
                            local material = block.material
                            if material and material ~= "" then
                                local gx = tostring(x)
                                local gy = tostring(y)
                                local gz = tostring(z)
                                grid[gx] = grid[gx] or {}
                                grid[gx][gy] = grid[gx][gy] or {}
                                grid[gx][gy][gz] = {
                                    material = material,
                                    meta = copyTable(block.meta),
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return grid
end

function schema_utils.canonicalToVoxelDefinition(schema, opts)
    return { grid = schema_utils.canonicalToGrid(schema, opts) }
end

function schema_utils.printMaterials(io, info)
    if not io.print then
        return
    end
    if not info or not info.materials or #info.materials == 0 then
        io.print("Materials: <none>")
        return
    end
    io.print("Materials:")
    for _, entry in ipairs(info.materials) do
        io.print(string.format(" - %s x%d", entry.material, entry.count))
    end
end

function schema_utils.printBounds(io, info)
    if not io.print then
        return
    end
    if not info or not info.bounds or not info.bounds.min then
        io.print("Bounds: <unknown>")
        return
    end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    local dims = {
        x = (maxB.x - minB.x) + 1,
        y = (maxB.y - minB.y) + 1,
        z = (maxB.z - minB.z) + 1,
    }
    io.print(string.format("Bounds: min(%d,%d,%d) max(%d,%d,%d) dims(%d,%d,%d)",
        minB.x, minB.y, minB.z, maxB.x, maxB.y, maxB.z, dims.x, dims.y, dims.z))
end

return schema_utils
