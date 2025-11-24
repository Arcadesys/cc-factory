--[[
Graphical Schema Designer (Paint-style)
]]

local ui = require("lib_ui")
local json = require("lib_json")
local items = require("lib_items")
local schema_utils = require("lib_schema")

local designer = {}

-- --- Constants & Config ---

local COLORS = {
    bg = colors.gray,
    canvas_bg = colors.black,
    grid = colors.lightGray,
    text = colors.white,
    btn_active = colors.blue,
    btn_inactive = colors.lightGray,
    btn_text = colors.black,
}

local DEFAULT_MATERIALS = {
    { id = "minecraft:stone", color = colors.lightGray, sym = "#" },
    { id = "minecraft:dirt", color = colors.brown, sym = "d" },
    { id = "minecraft:cobblestone", color = colors.gray, sym = "c" },
    { id = "minecraft:planks", color = colors.orange, sym = "p" },
    { id = "minecraft:glass", color = colors.lightBlue, sym = "g" },
    { id = "minecraft:log", color = colors.brown, sym = "L" },
    { id = "minecraft:torch", color = colors.yellow, sym = "i" },
    { id = "minecraft:iron_block", color = colors.white, sym = "I" },
    { id = "minecraft:gold_block", color = colors.yellow, sym = "G" },
    { id = "minecraft:diamond_block", color = colors.cyan, sym = "D" },
}

local TOOLS = {
    PENCIL = "Pencil",
    LINE = "Line",
    RECT = "Rect",
    RECT_FILL = "FillRect",
    CIRCLE = "Circle",
    CIRCLE_FILL = "FillCircle",
    BUCKET = "Bucket",
    PICKER = "Picker"
}

-- --- State ---

local state = {}

local function resetState()
    state.running = true
    state.w = 14
    state.h = 14
    state.d = 5
    state.data = {} -- [x][y][z] = material_index (0 or nil for air)
    state.meta = {} -- [x][y][z] = meta table
    state.palette = {}
    state.paletteEditMode = false
    state.offset = { x = 0, y = 0, z = 0 }

    state.view = {
        layer = 0, -- Current Y level
        offsetX = 4, -- Screen X offset of canvas
        offsetY = 3, -- Screen Y offset of canvas
        scrollX = 0,
        scrollY = 0,
    }

    state.menuOpen = false
    state.inventoryOpen = false
    state.searchOpen = false
    state.searchQuery = ""
    state.searchResults = {}
    state.searchScroll = 0
    state.dragItem = nil -- { id, sym, color }

    state.tool = TOOLS.PENCIL
    state.primaryColor = 1 -- Index in palette
    state.secondaryColor = 0 -- 0 = Air/Eraser

    state.mouse = {
        down = false,
        drag = false,
        startX = 0, startY = 0, -- Canvas coords
        currX = 0, currY = 0,   -- Canvas coords
        btn = 1
    }

    state.status = "Ready"

    for i, m in ipairs(DEFAULT_MATERIALS) do
        state.palette[i] = { id = m.id, color = m.color, sym = m.sym }
    end
end

resetState()

-- --- Helpers ---

local function getMaterial(idx)
    if idx == 0 or not idx then return nil end
    return state.palette[idx]
end

local function getBlock(x, y, z)
    if not state.data[x] then return 0 end
    if not state.data[x][y] then return 0 end
    return state.data[x][y][z] or 0
end

local function setBlock(x, y, z, matIdx, meta)
    if x < 0 or x >= state.w or z < 0 or z >= state.h or y < 0 or y >= state.d then return end

    if not state.data[x] then state.data[x] = {} end
    if not state.data[x][y] then state.data[x][y] = {} end
    if not state.meta[x] then state.meta[x] = {} end
    if not state.meta[x][y] then state.meta[x][y] = {} end

    if matIdx == 0 then
        state.data[x][y][z] = nil
        if state.meta[x] and state.meta[x][y] then
            state.meta[x][y][z] = nil
        end
    else
        state.data[x][y][z] = matIdx
        state.meta[x][y][z] = meta or {}
    end
end

local function getBlockMeta(x, y, z)
    if not state.meta[x] or not state.meta[x][y] then return {} end
    return schema_utils.cloneMeta(state.meta[x][y][z])
end

local function findItemDef(id)
    for _, item in ipairs(items) do
        if item.id == id then
            return item
        end
    end
    return nil
end

local function ensurePaletteMaterial(material)
    for idx, mat in ipairs(state.palette) do
        if mat.id == material then
            return idx
        end
    end

    local fallback = findItemDef(material)
    local entry = {
        id = material,
        color = fallback and fallback.color or colors.white,
        sym = fallback and fallback.sym or "?",
    }

    table.insert(state.palette, entry)
    return #state.palette
end

local function clearCanvas()
    state.data = {}
    state.meta = {}
end

local function loadCanonical(schema, metadata)
    if type(schema) ~= "table" then
        return false, "invalid_schema"
    end

    clearCanvas()

    local bounds = schema_utils.newBounds()
    local blockCount = 0

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            schema_utils.updateBounds(bounds, x, y, z)
                            blockCount = blockCount + 1
                        end
                    end
                end
            end
        end
    end

    if blockCount == 0 then
        state.status = "Loaded empty schema"
        return true
    end

    state.offset = {
        x = bounds.min.x,
        y = bounds.min.y,
        z = bounds.min.z,
    }

    state.w = math.max(1, (bounds.max.x - bounds.min.x) + 1)
    state.d = math.max(1, (bounds.max.y - bounds.min.y) + 1)
    state.h = math.max(1, (bounds.max.z - bounds.min.z) + 1)

    for xKey, xColumn in pairs(schema) do
        if type(xColumn) == "table" then
            local x = tonumber(xKey) or xKey
            if type(x) ~= "number" then return false, "invalid_coordinate" end
            for yKey, yColumn in pairs(xColumn) do
                if type(yColumn) == "table" then
                    local y = tonumber(yKey) or yKey
                    if type(y) ~= "number" then return false, "invalid_coordinate" end
                    for zKey, block in pairs(yColumn) do
                        if type(block) == "table" and block.material then
                            local z = tonumber(zKey) or zKey
                            if type(z) ~= "number" then return false, "invalid_coordinate" end
                            local matIdx = ensurePaletteMaterial(block.material)
                            local localX = x - state.offset.x
                            local localY = y - state.offset.y
                            local localZ = z - state.offset.z
                            setBlock(localX, localY, localZ, matIdx, schema_utils.cloneMeta(block.meta))
                        end
                    end
                end
            end
        end
    end

    state.status = string.format("Loaded %d blocks", blockCount)
    if metadata and metadata.path then
        state.status = state.status .. " from " .. metadata.path
    end

    return true
end

local function exportCanonical()
    local schema = {}
    local bounds = schema_utils.newBounds()
    local total = 0

    for x, xColumn in pairs(state.data) do
        for y, yColumn in pairs(xColumn) do
            for z, matIdx in pairs(yColumn) do
                local mat = getMaterial(matIdx)
                if mat then
                    local worldX = x + state.offset.x
                    local worldY = y + state.offset.y
                    local worldZ = z + state.offset.z
                    schema[worldX] = schema[worldX] or {}
                    schema[worldX][worldY] = schema[worldX][worldY] or {}
                    schema[worldX][worldY][worldZ] = {
                        material = mat.id,
                        meta = getBlockMeta(x, y, z),
                    }
                    schema_utils.updateBounds(bounds, worldX, worldY, worldZ)
                    total = total + 1
                end
            end
        end
    end

    local info = { totalBlocks = total }
    if total > 0 then
        info.bounds = bounds
    end

    return schema, info
end

local function exportVoxelDefinition()
    local canonical, info = exportCanonical()
    return schema_utils.canonicalToVoxelDefinition(canonical), info
end

-- --- Algorithms ---

local function drawLine(x0, y0, x1, y1, callback)
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        callback(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

local function drawRect(x0, y0, x1, y1, filled, callback)
    local minX, maxX = math.min(x0, x1), math.max(x0, x1)
    local minY, maxY = math.min(y0, y1), math.max(y0, y1)
    
    for x = minX, maxX do
        for y = minY, maxY do
            if filled or (x == minX or x == maxX or y == minY or y == maxY) then
                callback(x, y)
            end
        end
    end
end

local function drawCircle(x0, y0, x1, y1, filled, callback)
    -- Midpoint circle algorithm adapted for ellipse/bounds
    local r = math.floor(math.min(math.abs(x1 - x0), math.abs(y1 - y0)) / 2)
    local cx = math.floor((x0 + x1) / 2)
    local cy = math.floor((y0 + y1) / 2)
    
    local x = r
    local y = 0
    local err = 0

    while x >= y do
        if filled then
            for i = cx - x, cx + x do callback(i, cy + y); callback(i, cy - y) end
            for i = cx - y, cx + y do callback(i, cy + x); callback(i, cy - x) end
        else
            callback(cx + x, cy + y)
            callback(cx + y, cy + x)
            callback(cx - y, cy + x)
            callback(cx - x, cy + y)
            callback(cx - x, cy - y)
            callback(cx - y, cy - x)
            callback(cx + y, cy - x)
            callback(cx + x, cy - y)
        end

        if err <= 0 then
            y = y + 1
            err = err + 2 * y + 1
        end
        if err > 0 then
            x = x - 1
            err = err - 2 * x + 1
        end
    end
end

local function floodFill(startX, startY, targetColor, replaceColor)
    if targetColor == replaceColor then return end
    
    local queue = { {x = startX, y = startY} }
    local visited = {}
    
    local function key(x, y) return x .. "," .. y end
    
    while #queue > 0 do
        local p = table.remove(queue, 1)
        local k = key(p.x, p.y)
        
        if not visited[k] then
            visited[k] = true
            local curr = getBlock(p.x, state.view.layer, p.y)
            
            if curr == targetColor then
                setBlock(p.x, state.view.layer, p.y, replaceColor)
                
                local neighbors = {
                    {x = p.x + 1, y = p.y},
                    {x = p.x - 1, y = p.y},
                    {x = p.x, y = p.y + 1},
                    {x = p.x, y = p.y - 1}
                }
                
                for _, n in ipairs(neighbors) do
                    if n.x >= 0 and n.x < state.w and n.y >= 0 and n.y < state.h then
                        table.insert(queue, n)
                    end
                end
            end
        end
    end
end

-- --- Rendering ---

local drawSearch

local function drawMenu()
    if not state.menuOpen then return end
    
    local w, h = term.getSize()
    local mx, my = w - 12, 2
    local mw, mh = 12, 8
    
    ui.drawFrame(mx, my, mw, mh, "Menu")
    
    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
    for i, opt in ipairs(options) do
        term.setCursorPos(mx + 1, my + i)
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        if opt == "Inventory" and state.inventoryOpen then
            term.setTextColor(colors.yellow)
        end
        term.write(opt)
    end
end

local function drawInventory()
    if not state.inventoryOpen then return end
    
    local w, h = term.getSize()
    local iw, ih = 18, 6 -- 4x4 grid + border
    local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)
    
    ui.drawFrame(ix, iy, iw, ih, "Inventory")
    
    -- Draw 4x4 grid
    for row = 0, 3 do
        for col = 0, 3 do
            local slot = row * 4 + col + 1
            local item = turtle.getItemDetail(slot)
            
            term.setCursorPos(ix + 1 + (col * 4), iy + 1 + row)
            
            local sym = "."
            local color = colors.gray
            
            if item then
                sym = item.name:sub(11, 11):upper() -- First char of name after minecraft:
                color = colors.white
            end
            
            term.setBackgroundColor(colors.black)
            term.setTextColor(color)
            term.write(" " .. sym .. " ")
        end
    end
    
    term.setCursorPos(ix + 1, iy + ih)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write("Drag to Palette")
end

local function drawDragItem()
    if state.dragItem and state.mouse.screenX then
        term.setCursorPos(state.mouse.screenX, state.mouse.screenY)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(state.dragItem.sym)
    end
end

local function drawUI()
    ui.clear()
    
    -- Toolbar (Top)
    term.setBackgroundColor(COLORS.bg)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    -- [M] Button
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.write(" M ")
    
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    term.write(string.format(" Designer [%d,%d,%d] Layer: %d/%d", state.w, state.h, state.d, state.view.layer, state.d - 1))
    
    -- Tools (Left Side)
    local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
    for i, t in ipairs(toolsList) do
        term.setCursorPos(1, 2 + i)
        if state.tool == t then
            term.setBackgroundColor(COLORS.btn_active)
            term.setTextColor(colors.white)
            term.write(" " .. t:sub(1,1) .. " ")
        else
            term.setBackgroundColor(COLORS.btn_inactive)
            term.setTextColor(COLORS.btn_text)
            term.write(" " .. t:sub(1,1) .. " ")
        end
    end
    
    -- Palette (Right Side)
    local palX = 2 + state.w + 2
    term.setCursorPos(palX, 2)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.text)
    
    local editLabel = state.paletteEditMode and "[EDITING]" or "[Edit]"
    if state.paletteEditMode then term.setTextColor(colors.red) end
    term.write("Pal " .. editLabel)
    
    -- Search Button
    term.setCursorPos(palX + 14, 2)
    term.setBackgroundColor(COLORS.btn_inactive)
    term.setTextColor(COLORS.btn_text)
    term.write("Find")
    
    for i, mat in ipairs(state.palette) do
        term.setCursorPos(palX, 3 + i)
        
        -- Indicator for selection
        local indicator = " "
        if state.primaryColor == i then indicator = "L" end
        if state.secondaryColor == i then indicator = "R" end
        if state.primaryColor == i and state.secondaryColor == i then indicator = "B" end
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        term.write(indicator)
        
        term.setBackgroundColor(mat.color)
        term.setTextColor(colors.black)
        term.write(" " .. mat.sym .. " ")
        
        term.setBackgroundColor(COLORS.bg)
        term.setTextColor(COLORS.text)
        local name = mat.id:match(":(.+)") or mat.id
        term.write(" " .. name)
    end
    
    -- Status Bar (Bottom)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(COLORS.bg)
    term.clearLine()
    term.write(state.status)
    
    -- Instructions
    term.setCursorPos(1, h-1)
    term.write("S:Save L:Load F:Find R:Resize C:Clear Q:Quit PgUp/Dn:Layer")
    
    drawMenu()
    drawInventory()
    drawSearch()
    drawDragItem()
end

local function drawCanvas()
    local ox, oy = state.view.offsetX, state.view.offsetY
    local sx, sy = state.view.scrollX, state.view.scrollY
    
    -- Draw Border
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(colors.white)
    ui.drawBox(ox - 1, oy - 1, state.w + 2, state.h + 2, COLORS.bg, colors.white)
    
    -- Draw Pixels
    for x = 0, state.w - 1 do
        for z = 0, state.h - 1 do
            -- Apply scroll
            local screenX = ox + x - sx
            local screenY = oy + z - sy
            
            -- Only draw if within canvas view area (roughly)
            -- Actually, we should clip to the border box
            -- For simplicity, let's just draw if it fits on screen
            local w, h = term.getSize()
            if screenX >= ox and screenX < w and screenY >= oy and screenY < h - 2 then
                local matIdx = getBlock(x, state.view.layer, z)
                local mat = getMaterial(matIdx)
                
                local bg = COLORS.canvas_bg
                local char = "."
                local fg = COLORS.grid
                
                if mat then
                    bg = mat.color
                    char = mat.sym
                    fg = colors.black
                    if bg == colors.black then fg = colors.white end
                end
                
                -- Ghost drawing
                if state.mouse.down and state.mouse.drag then
                    local isGhost = false
                    local ghostColor = (state.mouse.btn == 1) and state.primaryColor or state.secondaryColor
                    
                    local function checkGhost(gx, gy)
                        if gx == x and gy == z then isGhost = true end
                    end
                    
                    if state.tool == TOOLS.PENCIL then
                        checkGhost(state.mouse.currX, state.mouse.currY)
                    elseif state.tool == TOOLS.LINE then
                        drawLine(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, checkGhost)
                    elseif state.tool == TOOLS.RECT then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.RECT_FILL then
                        drawRect(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, false, checkGhost)
                    elseif state.tool == TOOLS.CIRCLE_FILL then
                        drawCircle(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, true, checkGhost)
                    end
                    
                    if isGhost then
                        local gMat = getMaterial(ghostColor)
                        if gMat then
                            bg = gMat.color
                            char = gMat.sym
                            fg = colors.black
                        else
                            bg = COLORS.canvas_bg
                            char = "x"
                            fg = colors.red
                        end
                    end
                end
                
                term.setCursorPos(screenX, screenY)
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(char)
            end
        end
    end
end



-- --- Logic ---

local function applyTool(x, y, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    if state.tool == TOOLS.PENCIL then
        setBlock(x, state.view.layer, y, color)
    elseif state.tool == TOOLS.BUCKET then
        local target = getBlock(x, state.view.layer, y)
        floodFill(x, y, target, color)
    elseif state.tool == TOOLS.PICKER then
        local picked = getBlock(x, state.view.layer, y)
        if btn == 1 then state.primaryColor = picked else state.secondaryColor = picked end
        state.tool = TOOLS.PENCIL -- Auto switch back
    end
end

local function applyShape(x0, y0, x1, y1, btn)
    local color = (btn == 1) and state.primaryColor or state.secondaryColor
    
    local function plot(x, y)
        setBlock(x, state.view.layer, y, color)
    end
    
    if state.tool == TOOLS.LINE then
        drawLine(x0, y0, x1, y1, plot)
    elseif state.tool == TOOLS.RECT then
        drawRect(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.RECT_FILL then
        drawRect(x0, y0, x1, y1, true, plot)
    elseif state.tool == TOOLS.CIRCLE then
        drawCircle(x0, y0, x1, y1, false, plot)
    elseif state.tool == TOOLS.CIRCLE_FILL then
        drawCircle(x0, y0, x1, y1, true, plot)
    end
end

local function saveSchema()
    ui.clear()
    term.setCursorPos(1, 1)
    print("Save Schema")
    write("Filename: ")
    local name = read()
    if name == "" then return end
    if not name:find("%.json$") then name = name .. ".json" end
    
    local exportDef = exportVoxelDefinition()

    local f = fs.open(name, "w")
    f.write(json.encode(exportDef))
    f.close()
    state.status = "Saved to " .. name
end

local function resizeCanvas()
    ui.clear()
    print("Resize Canvas")
    write("Width (" .. state.w .. "): ")
    local w = tonumber(read()) or state.w
    write("Height/Depth (" .. state.h .. "): ")
    local h = tonumber(read()) or state.h
    write("Layers (" .. state.d .. "): ")
    local d = tonumber(read()) or state.d
    
    state.w = w
    state.h = h
    state.d = d
end

local function editPaletteItem(idx)
    ui.clear()
    term.setCursorPos(1, 1)
    print("Edit Palette Item #" .. idx)
    
    local current = state.palette[idx]
    
    write("ID (" .. current.id .. "): ")
    local newId = read()
    if newId == "" then newId = current.id end
    
    write("Symbol (" .. current.sym .. "): ")
    local newSym = read()
    if newSym == "" then newSym = current.sym end
    newSym = newSym:sub(1, 1)
    
    -- Color selection is tricky in text mode, let's skip for now or cycle
    -- For now, keep color
    
    state.palette[idx].id = newId
    state.palette[idx].sym = newSym
    state.status = "Updated Item #" .. idx
end

local function updateSearchResults()
    state.searchResults = {}
    local query = state.searchQuery:lower()
    for _, item in ipairs(items) do
        if item.name:lower():find(query, 1, true) or item.id:lower():find(query, 1, true) then
            table.insert(state.searchResults, item)
        end
    end
    state.searchScroll = 0
end

drawSearch = function()
    if not state.searchOpen then return end
    
    local w, h = term.getSize()
    local sw, sh = 24, 14
    local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)
    
    ui.drawFrame(sx, sy, sw, sh, "Item Search")
    
    -- Search Box
    term.setCursorPos(sx + 1, sy + 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(state.searchQuery .. "_")
    local padding = sw - 2 - #state.searchQuery - 1
    if padding > 0 then term.write(string.rep(" ", padding)) end
    
    -- Results List
    local maxLines = sh - 3
    for i = 1, maxLines do
        local idx = state.searchScroll + i
        local item = state.searchResults[idx]
        
        term.setCursorPos(sx + 1, sy + 2 + i)
        if item then
            term.setBackgroundColor(colors.black)
            term.setTextColor(item.color or colors.white)
            local label = item.name or item.id
            if #label > sw - 4 then label = label:sub(1, sw - 4) end
            term.write(" " .. item.sym .. " " .. label)
            local pad = sw - 2 - 3 - #label
            if pad > 0 then term.write(string.rep(" ", pad)) end
        else
            term.setBackgroundColor(COLORS.bg)
            term.write(string.rep(" ", sw - 2))
        end
    end
end

-- --- Main ---

function designer.run(opts)
    opts = opts or {}
    resetState()

    if opts.schema then
        local ok, err = loadCanonical(opts.schema, opts.metadata)
        if not ok then
            return false, err
        end
    end

    state.running = true

    while state.running do
        drawUI()
        drawCanvas()
        drawMenu()
        drawInventory()
        drawSearch()
        drawDragItem()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "char" and state.searchOpen then
            state.searchQuery = state.searchQuery .. p1
            updateSearchResults()

        elseif event == "mouse_scroll" and state.searchOpen then
            local dir = p1
            state.searchScroll = math.max(0, state.searchScroll + dir)

        elseif event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local handled = false

            -- 0. Check Search (Topmost)
            if state.searchOpen then
                local w, h = term.getSize()
                local sw, sh = 24, 14
                local sx, sy = math.floor((w - sw)/2), math.floor((h - sh)/2)

                if mx >= sx and mx < sx + sw and my >= sy and my < sy + sh then
                    -- Inside Search Window
                    if my >= sy + 3 then
                        local idx = state.searchScroll + (my - (sy + 2))
                        local item = state.searchResults[idx]
                        if item then
                            state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                            state.searchOpen = false
                        end
                    end
                    handled = true
                else
                    state.searchOpen = false
                    handled = true
                end
            end

            -- 1. Check Menu (Topmost)
            if not handled and state.menuOpen then
                local w, h = term.getSize()
                local menuX, menuY = w - 12, 2
                if mx >= menuX and mx < menuX + 12 and my >= menuY and my < menuY + 8 then
                    local idx = my - menuY
                    local options = { "Resize", "Save", "Load", "Clear", "Inventory", "Quit" }
                    if options[idx] then
                        if options[idx] == "Quit" then state.running = false
                        elseif options[idx] == "Inventory" then state.inventoryOpen = not state.inventoryOpen
                        elseif options[idx] == "Resize" then resizeCanvas()
                        elseif options[idx] == "Save" then saveSchema()
                        elseif options[idx] == "Clear" then clearCanvas()
                        -- Load logic...
                        end
                        if options[idx] ~= "Inventory" then state.menuOpen = false end
                    end
                    handled = true
                else
                    -- Click outside menu closes it
                    state.menuOpen = false
                    handled = true -- Consume click
                end
            end

            -- 2. Check Inventory (Topmost)
            if not handled and state.inventoryOpen then
                local w, h = term.getSize()
                local iw, ih = 18, 6
                local ix, iy = math.floor((w - iw)/2), math.floor((h - ih)/2)

                if mx >= ix and mx < ix + iw and my >= iy and my < iy + ih then
                    -- Check slot click
                    local relX, relY = mx - ix - 1, my - iy - 1
                    if relX >= 0 and relY >= 0 then
                        local col = math.floor(relX / 4)
                        local row = relY
                        if col >= 0 and col <= 3 and row >= 0 and row <= 3 then
                            local slot = row * 4 + col + 1
                            local item = turtle.getItemDetail(slot)
                            if item then
                                state.dragItem = {
                                    id = item.name,
                                    sym = item.name:sub(11, 11):upper(),
                                    color = colors.white
                                }
                            end
                        end
                    end
                    handled = true
                end
            end

            -- 3. Check [M] Button
            if not handled and mx >= 1 and mx <= 3 and my == 1 then
                state.menuOpen = not state.menuOpen
                handled = true
            end

            -- 4. Check Palette (Drop Target & Selection)
            local palX = 2 + state.w + 2
            if not handled and mx >= palX and mx <= palX + 18 then -- Expanded for Search button
                if my == 2 then
                    -- Check Edit vs Search
                    if mx >= palX + 14 and mx <= palX + 17 then
                        state.searchOpen = not state.searchOpen
                        if state.searchOpen then
                            state.searchQuery = ""
                            updateSearchResults()
                        end
                    elseif mx <= palX + 13 then
                        state.paletteEditMode = not state.paletteEditMode
                    end
                    handled = true
                elseif my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    if state.paletteEditMode then
                        editPaletteItem(idx)
                    else
                        if btn == 1 then state.primaryColor = idx
                        elseif btn == 2 then state.secondaryColor = idx end
                    end
                    handled = true
                end
            end

            -- 5. Check Tools
            if not handled and mx >= 1 and mx <= 3 and my >= 3 and my < 3 + 8 then
                local idx = my - 2
                local toolsList = { TOOLS.PENCIL, TOOLS.LINE, TOOLS.RECT, TOOLS.RECT_FILL, TOOLS.CIRCLE, TOOLS.CIRCLE_FILL, TOOLS.BUCKET, TOOLS.PICKER }
                if toolsList[idx] then state.tool = toolsList[idx] end
                handled = true
            end

            -- 6. Check Canvas
            if not handled then
                local cx = mx - state.view.offsetX
                local cy = my - state.view.offsetY

                if cx >= 0 and cx < state.w and cy >= 0 and cy < state.h then
                    state.mouse.down = true
                    state.mouse.btn = btn
                    state.mouse.startX = cx
                    state.mouse.startY = cy
                    state.mouse.currX = cx
                    state.mouse.currY = cy

                    if state.tool == TOOLS.PENCIL or state.tool == TOOLS.BUCKET or state.tool == TOOLS.PICKER then
                        applyTool(cx, cy, btn)
                    end
                end
            end

        elseif event == "mouse_drag" then
            local btn, mx, my = p1, p2, p3
            state.mouse.screenX = mx
            state.mouse.screenY = my
            local cx = mx - state.view.offsetX
            local cy = my - state.view.offsetY

            if state.mouse.down then
                -- Clamp to canvas
                cx = math.max(0, math.min(state.w - 1, cx))
                cy = math.max(0, math.min(state.h - 1, cy))

                state.mouse.currX = cx
                state.mouse.currY = cy
                state.mouse.drag = true

                if state.tool == TOOLS.PENCIL then
                    applyTool(cx, cy, state.mouse.btn)
                end
            end

        elseif event == "mouse_up" then
            local btn, mx, my = p1, p2, p3

            -- Handle Drag Drop to Palette
            if state.dragItem then
                local palX = 2 + state.w + 2
                if mx >= palX and mx <= palX + 15 and my >= 4 and my < 4 + #state.palette then
                    local idx = my - 3
                    state.palette[idx].id = state.dragItem.id
                    state.palette[idx].sym = state.dragItem.sym
                    state.status = "Assigned " .. state.dragItem.id .. " to slot " .. idx
                end
                state.dragItem = nil
            end

            if state.mouse.down and state.mouse.drag then
                -- Commit shape
                if state.tool == TOOLS.LINE or state.tool == TOOLS.RECT or state.tool == TOOLS.RECT_FILL or state.tool == TOOLS.CIRCLE then
                    applyShape(state.mouse.startX, state.mouse.startY, state.mouse.currX, state.mouse.currY, state.mouse.btn)
                end
            end
            state.mouse.down = false
            state.mouse.drag = false

        elseif event == "key" then
            local key = p1

            if state.searchOpen then
                if key == keys.backspace then
                    state.searchQuery = state.searchQuery:sub(1, -2)
                    updateSearchResults()
                elseif key == keys.enter then
                    if #state.searchResults > 0 then
                        local item = state.searchResults[1]
                        state.dragItem = { id = item.id, sym = item.sym, color = item.color }
                        state.searchOpen = false
                    end
                elseif key == keys.up then
                    state.searchScroll = math.max(0, state.searchScroll - 1)
                elseif key == keys.down then
                    state.searchScroll = state.searchScroll + 1
                end
            else
                if key == keys.q then state.running = false end
                if key == keys.f then 
                    state.searchOpen = not state.searchOpen 
                    if state.searchOpen then 
                        state.searchQuery = "" 
                        updateSearchResults()
                    end
                end
                if key == keys.s then saveSchema() end
                if key == keys.r then resizeCanvas() end
                if key == keys.c then clearCanvas() end -- Clear all
                if key == keys.pageUp then state.view.layer = math.min(state.d - 1, state.view.layer + 1) end
                if key == keys.pageDown then state.view.layer = math.max(0, state.view.layer - 1) end
            end
        end
    end

    if opts.returnSchema then
        return exportCanonical()
    end
end

designer.loadCanonical = loadCanonical
designer.exportCanonical = exportCanonical
designer.exportVoxelDefinition = exportVoxelDefinition

return designer
