--[[
Parser library for CC:Tweaked turtles.
Normalises schema sources (JSON, text grids, voxel tables) into the canonical
schema[x][y][z] format used by the build states. All public entry points
return success booleans with optional error messages and metadata tables.
--]]

---@diagnostic disable: undefined-global

local parser = {}
local logger = require("lib_logger")
local table_utils = require("lib_table")
local fs_utils = require("lib_fs")
local json_utils = require("lib_json")
local schema_utils = require("lib_schema")

local function parseLayerRows(schema, bounds, counts, layerDef, legend, opts)
    local rows = layerDef.rows
    if type(rows) ~= "table" then
        return false, "invalid_layer"
    end
    local height = #rows
    if height == 0 then
        return true
    end
    local width = nil
    for rowIndex, row in ipairs(rows) do
        if type(row) ~= "string" then
            return false, "invalid_row"
        end
        if width == nil then
            width = #row
            if width == 0 then
                return false, "empty_row"
            end
        elseif width ~= #row then
            return false, "ragged_row"
        end
        for col = 1, #row do
            local symbol = row:sub(col, col)
            local entry, err = schema_utils.resolveSymbol(symbol, legend, opts)
            if err then
                return false, string.format("legend_error:%s", symbol)
            end
            if entry then
                local x = (layerDef.x or 0) + (col - 1)
                local y = layerDef.y or 0
                local z = (layerDef.z or 0) + (rowIndex - 1)
                local ok, addErr = schema_utils.addBlock(schema, bounds, counts, x, y, z, entry.material, entry.meta)
                if not ok then
                    return false, addErr
                end
            end
        end
    end
    return true
end

local function toLayerRows(layer)
    if type(layer) == "string" then
        local rows = {}
        for line in layer:gmatch("([^\r\n]+)") do
            rows[#rows + 1] = line
        end
        return { rows = rows }
    end
    if type(layer) == "table" then
        if layer.rows then
            local rows = {}
            for i = 1, #layer.rows do
                rows[i] = tostring(layer.rows[i])
            end
            return {
                rows = rows,
                y = layer.y or layer.height or layer.level or 0,
                x = layer.x or layer.offsetX or 0,
                z = layer.z or layer.offsetZ or 0,
            }
        end
        local rows = {}
        local count = 0
        for _, value in ipairs(layer) do
            rows[#rows + 1] = tostring(value)
            count = count + 1
        end
        if count > 0 then
            return { rows = rows, y = layer.y or 0, x = layer.x or 0, z = layer.z or 0 }
        end
    end
    return nil
end

local function parseLayers(schema, bounds, counts, def, legend, opts)
    local layers = def.layers
    if type(layers) ~= "table" then
        return false, "invalid_layers"
    end
    local used = 0
    for index, layer in ipairs(layers) do
        local layerRows = toLayerRows(layer)
        if not layerRows then
            return false, "invalid_layer"
        end
        if not layerRows.y then
            layerRows.y = (def.baseY or 0) + (index - 1)
        else
            layerRows.y = layerRows.y + (def.baseY or 0)
        end
        if def.baseX then
            layerRows.x = (layerRows.x or 0) + def.baseX
        end
        if def.baseZ then
            layerRows.z = (layerRows.z or 0) + def.baseZ
        end
        local ok, err = parseLayerRows(schema, bounds, counts, layerRows, legend, opts)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_layers"
    end
    return true
end

local function parseBlockList(schema, bounds, counts, blocks)
    local used = 0
    for _, block in ipairs(blocks) do
        if type(block) ~= "table" then
            return false, "invalid_block"
        end
        local x = block.x or block[1]
        local y = block.y or block[2]
        local z = block.z or block[3]
        local material = block.material or block.name or block.block
        local meta = block.meta or block.data
        if type(meta) ~= "table" then
            meta = {}
        end
        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
        if not ok then
            return false, err
        end
        used = used + 1
    end
    if used == 0 then
        return false, "empty_blocks"
    end
    return true
end

local function parseVoxelGrid(schema, bounds, counts, grid)
    if type(grid) ~= "table" then
        return false, "invalid_grid"
    end
    local used = 0
    for xKey, xColumn in pairs(grid) do
        local x = tonumber(xKey) or xKey
        if type(x) ~= "number" then
            return false, "invalid_coordinate"
        end
        if type(xColumn) ~= "table" then
            return false, "invalid_grid"
        end
        for yKey, yColumn in pairs(xColumn) do
            local y = tonumber(yKey) or yKey
            if type(y) ~= "number" then
                return false, "invalid_coordinate"
            end
            if type(yColumn) ~= "table" then
                return false, "invalid_grid"
            end
            for zKey, entry in pairs(yColumn) do
                local z = tonumber(zKey) or zKey
                if type(z) ~= "number" then
                    return false, "invalid_coordinate"
                end
                if entry ~= nil then
                    local material
                    local meta = {}
                    if type(entry) == "string" then
                        material = entry
                    elseif type(entry) == "table" then
                        material = entry.material or entry.name or entry.block
                        meta = type(entry.meta) == "table" and entry.meta or {}
                    else
                        return false, "invalid_block"
                    end
                    if material and material ~= "" then
                        local ok, err = schema_utils.addBlock(schema, bounds, counts, x, y, z, material, meta)
                        if not ok then
                            return false, err
                        end
                        used = used + 1
                    end
                end
            end
        end
    end
    if used == 0 then
        return false, "empty_grid"
    end
    return true
end

local function summarise(bounds, counts)
    local materials = {}
    for material, count in pairs(counts) do
        materials[#materials + 1] = { material = material, count = count }
    end
    table.sort(materials, function(a, b)
        if a.count == b.count then
            return a.material < b.material
        end
        return a.count > b.count
    end)
    local total = 0
    for _, entry in ipairs(materials) do
        total = total + entry.count
    end
    return {
        bounds = {
            min = table_utils.shallowCopy(bounds.min),
            max = table_utils.shallowCopy(bounds.max),
        },
        materials = materials,
        totalBlocks = total,
    }
end

local function buildCanonical(def, opts)
    local schema = {}
    local bounds = schema_utils.newBounds()
    local counts = {}
    local ok, err
    if def.blocks then
        ok, err = parseBlockList(schema, bounds, counts, def.blocks)
    elseif def.layers then
        ok, err = parseLayers(schema, bounds, counts, def, def.legend, opts)
    elseif def.grid then
        ok, err = parseVoxelGrid(schema, bounds, counts, def.grid)
    else
        return nil, "unknown_definition"
    end
    if not ok then
        return nil, err
    end
    if bounds.min.x == math.huge then
        return nil, "empty_schema"
    end
    return schema, summarise(bounds, counts)
end

local function detectFormatFromExtension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_%-]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "json" or ext == "schem" then
        return "json"
    end
    if ext == "txt" or ext == "grid" then
        return "grid"
    end
    if ext == "vox" or ext == "voxel" then
        return "voxel"
    end
    return nil
end

local function detectFormatFromText(text)
    if type(text) ~= "string" then
        return nil
    end
    local trimmed = text:match("^%s*(.-)%s*$") or text
    local firstChar = trimmed:sub(1, 1)
    if firstChar == "{" or firstChar == "[" then
        return "json"
    end
    return "grid"
end

local function parseLegendBlock(lines, index)
    local legend = {}
    local pos = index
    while pos <= #lines do
        local line = lines[pos]
        if line == "" then
            break
        end
        if line:match("^layer") then
            break
        end
        local symbol, rest = line:match("^(%S+)%s*[:=]%s*(.+)$")
        if not symbol then
            symbol, rest = line:match("^(%S+)%s+(.+)$")
        end
        if symbol and rest then
            rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
            local value
            if rest:sub(1, 1) == "{" then
                local parsed = json_utils.decodeJson(rest)
                if parsed then
                    value = parsed
                else
                    value = rest
                end
            else
                value = rest
            end
            legend[symbol] = value
        end
        pos = pos + 1
    end
    return legend, pos
end

local function parseTextGridContent(text, opts)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        lines[#lines + 1] = line
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, nil)
    local layers = {}
    local current = {}
    local currentY = nil
    local lineIndex = 1
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "" then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
                currentY = nil
            end
            lineIndex = lineIndex + 1
        elseif trimmed:lower() == "legend:" then
            local legendBlock, nextIndex = parseLegendBlock(lines, lineIndex + 1)
            legend = schema_utils.mergeLegend(legend, legendBlock)
            lineIndex = nextIndex
        elseif trimmed:match("^layer") then
            if #current > 0 then
                layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
                current = {}
            end
            local yValue = trimmed:match("layer%s*[:=]%s*(-?%d+)")
            currentY = yValue and tonumber(yValue) or (#layers)
            lineIndex = lineIndex + 1
        else
            current[#current + 1] = line
            lineIndex = lineIndex + 1
        end
    end
    if #current > 0 then
        layers[#layers + 1] = { rows = current, y = currentY or (#layers) }
    end
    if not legend or next(legend) == nil then
        return nil, "missing_legend"
    end
    if #layers == 0 then
        return nil, "empty_layers"
    end
    return {
        layers = layers,
        legend = legend,
    }
end

local function parseJsonContent(obj, opts)
    if type(obj) ~= "table" then
        return nil, "invalid_json_root"
    end
    local legend = schema_utils.mergeLegend(opts and opts.legend or nil, obj.legend or nil)
    if obj.blocks then
        return {
            blocks = obj.blocks,
            legend = legend,
        }
    end
    if obj.layers then
        return {
            layers = obj.layers,
            legend = legend,
            baseX = obj.baseX,
            baseY = obj.baseY,
            baseZ = obj.baseZ,
        }
    end
    if obj.grid or obj.voxels then
        return {
            grid = obj.grid or obj.voxels,
            legend = legend,
        }
    end
    if #obj > 0 then
        return {
            blocks = obj,
            legend = legend,
        }
    end
    return nil, "unrecognised_json"
end

local function assignToContext(ctx, schema, info)
    if type(ctx) ~= "table" then
        return
    end
    ctx.schema = schema
    ctx.schemaInfo = info
end

local function ensureSpecTable(spec)
    if type(spec) == "table" then
        return table_utils.shallowCopy(spec)
    end
    if type(spec) == "string" then
        return { source = spec }
    end
    return {}
end

function parser.parse(ctx, spec)
    spec = ensureSpecTable(spec)
    local format = spec.format
    local text = spec.text
    local data = spec.data
    local path = spec.path or spec.sourcePath
    local source = spec.source
    if not format and spec.path then
        format = detectFormatFromExtension(spec.path)
    end
    if not format and spec.formatHint then
        format = spec.formatHint
    end
    if not text and not data then
        if spec.textContent then
            text = spec.textContent
        elseif spec.raw then
            text = spec.raw
        elseif spec.sourceText then
            text = spec.sourceText
        end
    end
    if not path and type(source) == "string" and text == nil and data == nil then
        local maybeFormat = detectFormatFromExtension(source)
        if maybeFormat then
            path = source
            format = format or maybeFormat
        else
            text = source
        end
    end
    if text == nil and path then
        local contents, err = fs_utils.readFile(path)
        if not contents then
            return false, err or "read_failed"
        end
        text = contents
        if not format then
            format = detectFormatFromExtension(path) or detectFormatFromText(text)
        end
    end
    if not format then
        if data then
            if data.layers then
                format = "grid"
            elseif data.blocks then
                format = "json"
            elseif data.grid or data.voxels then
                format = "voxel"
            end
        elseif text then
            format = detectFormatFromText(text)
        end
    end
    if not format then
        return false, "unknown_format"
    end
    local definition, err
    if format == "json" then
        if data then
            definition, err = parseJsonContent(data, spec)
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            definition, err = parseJsonContent(obj, spec)
        end
    elseif format == "grid" then
        if data and (data.layers or data.rows) then
            definition = {
                layers = data.layers or { data.rows },
                legend = schema_utils.mergeLegend(spec.legend or nil, data.legend or nil),
            }
        else
            definition, err = parseTextGridContent(text, spec)
        end
    elseif format == "voxel" then
        if data then
            definition = {
                grid = data.grid or data.voxels or data,
            }
        else
            local obj, decodeErr = json_utils.decodeJson(text)
            if not obj then
                return false, decodeErr
            end
            if obj.grid or obj.voxels then
                definition = {
                    grid = obj.grid or obj.voxels,
                }
            else
                definition, err = parseJsonContent(obj, spec)
            end
        end
    else
        return false, "unsupported_format"
    end
    if not definition then
        return false, err or "invalid_definition"
    end
    if spec.legend then
        definition.legend = schema_utils.mergeLegend(definition.legend, spec.legend)
    end
    local schema, metadata = buildCanonical(definition, spec)
    if not schema then
        return false, metadata or "parse_failed"
    end
    if type(metadata) ~= "table" then
        metadata = { note = metadata }
    end
    metadata = metadata or {}
    metadata.format = format
    metadata.path = path
    assignToContext(ctx, schema, metadata)
    logger.log(ctx, "debug", string.format("Parsed schema with %d blocks", metadata.totalBlocks or 0))
    return true, schema, metadata
end

function parser.parseFile(ctx, path, opts)
    opts = opts or {}
    opts.path = path
    return parser.parse(ctx, opts)
end

function parser.parseText(ctx, text, opts)
    opts = opts or {}
    opts.text = text
    opts.format = opts.format or "grid"
    return parser.parse(ctx, opts)
end

function parser.parseJson(ctx, data, opts)
    opts = opts or {}
    opts.data = data
    opts.format = "json"
    return parser.parse(ctx, opts)
end

return parser
