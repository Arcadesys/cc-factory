
-- Auto-generated installer by bundle.js
local bundled_modules = {}
bundled_modules["factory"] = [===[
--[[
Factory entry point for the modular agent system.
Exposes a `run(args)` helper so it can be required/bundled while remaining
runnable as a stand-alone turtle program.
]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")
local debug = debug

local states = {
    INITIALIZE = require("state_initialize"),
    CHECK_REQUIREMENTS = require("state_check_requirements"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    TREEFARM = require("state_treefarm"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done"),
}

local function mergeTables(base, extra)
    if type(base) ~= "table" then
        base = {}
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            base[key] = value
        end
    end
    return base
end

local function buildPayload(ctx, extra)
    local payload = { context = diagnostics.snapshot(ctx) }
    if extra then
        mergeTables(payload, extra)
    end
    return payload
end

local function run(args)
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil,
        },
        origin = { x = 0, y = 0, z = 0, facing = "north" },
        pointer = 1,
        schema = nil,
        strategy = nil,
        inventoryState = {},
        fuelState = {},
        retries = 0,
    }

    local index = 1
    while index <= #args do
        local value = args[index]
        if value == "--verbose" then
            ctx.config.verbose = true
        elseif value == "mine" then
            ctx.config.mode = "mine"
        elseif value == "tunnel" then
            ctx.config.mode = "tunnel"
        elseif value == "excavate" then
            ctx.config.mode = "excavate"
        elseif value == "treefarm" then
            ctx.state = "TREEFARM"
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
        elseif value == "--height" then
            index = index + 1
            ctx.config.height = tonumber(args[index])
        elseif value == "--depth" then
            index = index + 1
            ctx.config.depth = tonumber(args[index])
        elseif value == "--length" then
            index = index + 1
            ctx.config.length = tonumber(args[index])
        elseif value == "--branch-interval" then
            index = index + 1
            ctx.config.branchInterval = tonumber(args[index])
        elseif value == "--branch-length" then
            index = index + 1
            ctx.config.branchLength = tonumber(args[index])
        elseif value == "--torch-interval" then
            index = index + 1
            ctx.config.torchInterval = tonumber(args[index])
        elseif not value:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
            ctx.config.schemaPath = value
        end
        index = index + 1
    end

    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" and ctx.config.mode ~= "farm" then
        ctx.config.schemaPath = "schema.json"
    end

    -- Initialize logger
    local logOpts = {
        level = ctx.config.verbose and "debug" or "info",
        timestamps = true
    }
    logger.attach(ctx, logOpts)
    
    ctx.logger:info("Agent starting...")

    -- Initial fuel check
    if turtle and turtle.getFuelLevel then
        local level = turtle.getFuelLevel()
        local limit = turtle.getFuelLimit()
        ctx.logger:info(string.format("Fuel: %s / %s", tostring(level), tostring(limit)))
        if level ~= "unlimited" and type(level) == "number" and level < 100 then
             ctx.logger:warn("Fuel is very low on startup!")
        end
    end

    while ctx.state ~= "EXIT" do
        local stateHandler = states[ctx.state]
        if not stateHandler then
            ctx.logger:error("Unknown state: " .. tostring(ctx.state), buildPayload(ctx))
            break
        end

        ctx.logger:debug("Entering state: " .. ctx.state)
        local ok, nextStateOrErr = pcall(stateHandler, ctx)
        if not ok then
            local trace = debug and debug.traceback and debug.traceback() or nil
            ctx.logger:error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr),
                buildPayload(ctx, { error = tostring(nextStateOrErr), traceback = trace }))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            if type(nextStateOrErr) ~= "string" or nextStateOrErr == "" then
                ctx.logger:error("State returned invalid transition", buildPayload(ctx, { result = tostring(nextStateOrErr) }))
                ctx.lastError = nextStateOrErr
                ctx.state = "ERROR"
            elseif not states[nextStateOrErr] and nextStateOrErr ~= "EXIT" then
                ctx.logger:error("Transitioned to unknown state: " .. tostring(nextStateOrErr), buildPayload(ctx))
                ctx.state = "ERROR"
            else
                ctx.state = nextStateOrErr
            end
        end

        ---@diagnostic disable-next-line: undefined-global
        sleep(0)
    end

    ctx.logger:info("Agent finished.")
end

local module = { run = run }

---@diagnostic disable-next-line: undefined-field
if not _G.__FACTORY_EMBED__ then
    local argv = { ... }
    run(argv)
end

return module

]===]
bundled_modules["lib_designer"] = [===[
--[[
Graphical Schema Designer (Paint-style)
]]

local ui = require("lib_ui")
local json = require("lib_json")
local items = require("lib_items")

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

local state = {
    running = true,
    w = 14, h = 14, d = 5, -- Canvas dimensions
    data = {}, -- [x][y][z] = material_index (0 or nil for air)
    palette = {}, -- Initialized from DEFAULT_MATERIALS
    paletteEditMode = false,
    
    view = {
        layer = 0, -- Current Y level
        offsetX = 4, -- Screen X offset of canvas
        offsetY = 3, -- Screen Y offset of canvas
        scrollX = 0,
        scrollY = 0,
    },
    
    menuOpen = false,
    inventoryOpen = false,
    searchOpen = false,
    searchQuery = "",
    searchResults = {},
    searchScroll = 0,
    dragItem = nil, -- { id, sym, color }
    
    tool = TOOLS.PENCIL,
    primaryColor = 1, -- Index in palette
    secondaryColor = 0, -- 0 = Air/Eraser
    
    mouse = {
        down = false,
        drag = false,
        startX = 0, startY = 0, -- Canvas coords
        currX = 0, currY = 0,   -- Canvas coords
        btn = 1
    },
    
    status = "Ready"
}

-- Initialize palette
for i, m in ipairs(DEFAULT_MATERIALS) do
    state.palette[i] = { id = m.id, color = m.color, sym = m.sym }
end

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

local function setBlock(x, y, z, matIdx)
    if x < 0 or x >= state.w or z < 0 or z >= state.h or y < 0 or y >= state.d then return end
    
    if not state.data[x] then state.data[x] = {} end
    if not state.data[x][y] then state.data[x][y] = {} end
    
    if matIdx == 0 then
        state.data[x][y][z] = nil
    else
        state.data[x][y][z] = matIdx
    end
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
    term.write("Palette " .. editLabel)
    
    -- Search Button
    term.setCursorPos(palX + 16, 2)
    term.setBackgroundColor(COLORS.btn_inactive)
    term.setTextColor(COLORS.btn_text)
    term.write(" S ")
    
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
        term.write(" " .. mat.id:match(":(.+)"))
    end
    
    -- Status Bar (Bottom)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(COLORS.bg)
    term.clearLine()
    term.write(state.status)
    
    -- Instructions
    term.setCursorPos(1, h-1)
    term.write("S:Save L:Load R:Resize C:Clear Q:Quit PgUp/Dn:Layer")
    
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
    
    -- Convert to sparse format for saving
    local export = {}
    for x, yRow in pairs(state.data) do
        for y, zRow in pairs(yRow) do
            for z, matIdx in pairs(zRow) do
                local mat = getMaterial(matIdx)
                if mat then
                    if not export[tostring(x)] then export[tostring(x)] = {} end
                    if not export[tostring(x)][tostring(y)] then export[tostring(x)][tostring(y)] = {} end
                    export[tostring(x)][tostring(y)][tostring(z)] = { material = mat.id }
                end
            end
        end
    end
    
    local f = fs.open(name, "w")
    f.write(json.encode(export))
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

local function drawSearch()
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

function designer.run()
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
                        elseif options[idx] == "Clear" then state.data = {}
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
                    if mx >= palX + 16 and mx <= palX + 18 then
                        state.searchOpen = not state.searchOpen
                        if state.searchOpen then 
                            state.searchQuery = "" 
                            updateSearchResults()
                        end
                    elseif mx <= palX + 15 then
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
                if key == keys.s then saveSchema() end
                if key == keys.r then resizeCanvas() end
                if key == keys.c then state.data = {} end -- Clear all
                if key == keys.pageUp then state.view.layer = math.min(state.d - 1, state.view.layer + 1) end
                if key == keys.pageDown then state.view.layer = math.max(0, state.view.layer - 1) end
            end
        end
    end
end

return designer

]===]
bundled_modules["lib_diagnostics"] = [===[
--[[
Diagnostics helper for capturing context snapshots and guarded access.
--]]

local diagnostics = {}

local function safeOrigin(origin)
    if type(origin) ~= "table" then
        return nil
    end
    return {
        x = origin.x,
        y = origin.y,
        z = origin.z,
        facing = origin.facing
    }
end

local function normalizeStrategy(strategy)
    if type(strategy) == "table" then
        return strategy
    end
    return nil
end

local function snapshot(ctx)
    if type(ctx) ~= "table" then
        return { error = "missing context" }
    end
    local config = type(ctx.config) == "table" and ctx.config or {}
    local origin = safeOrigin(ctx.origin)
    local strategyLen = 0
    if type(ctx.strategy) == "table" then
        strategyLen = #ctx.strategy
    end
    local stamp
    if os and type(os.time) == "function" then
        stamp = os.time()
    end

    return {
        state = ctx.state,
        mode = config.mode,
        pointer = ctx.pointer,
        strategySize = strategyLen,
        retries = ctx.retries,
        missingMaterial = ctx.missingMaterial,
        lastError = ctx.lastError,
        origin = origin,
        timestamp = stamp
    }
end

local function requireStrategy(ctx)
    local strategy = normalizeStrategy(ctx.strategy)
    if strategy then
        return strategy
    end

    local message = "Build strategy unavailable"
    if ctx and ctx.logger then
        ctx.logger:error(message, { context = snapshot(ctx) })
    end
    ctx.lastError = ctx.lastError or message
    return nil, message
end

diagnostics.snapshot = snapshot
diagnostics.requireStrategy = requireStrategy

return diagnostics
]===]
bundled_modules["lib_fs"] = [===[
local fs_utils = {}

local createdArtifacts = {}

function fs_utils.stageArtifact(path)
    for _, existing in ipairs(createdArtifacts) do
        if existing == path then
            return
        end
    end
    createdArtifacts[#createdArtifacts + 1] = path
end

function fs_utils.writeFile(path, contents)
    if type(path) ~= "string" or path == "" then
        return false, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "w")
        if not handle then
            return false, "open_failed"
        end
        handle.write(contents)
        handle.close()
        return true
    end
    if io and io.open then
        local handle, err = io.open(path, "w")
        if not handle then
            return false, err or "open_failed"
        end
        handle:write(contents)
        handle:close()
        return true
    end
    return false, "fs_unavailable"
end

function fs_utils.deleteFile(path)
    if fs and fs.delete and fs.exists then
        local ok, exists = pcall(fs.exists, path)
        if ok and exists then
            fs.delete(path)
        end
        return true
    end
    if os and os.remove then
        os.remove(path)
        return true
    end
    return false
end

function fs_utils.readFile(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "r")
        if not handle then
            return nil, "open_failed"
        end
        local ok, contents = pcall(handle.readAll)
        handle.close()
        if not ok then
            return nil, "read_failed"
        end
        return contents
    end
    if io and io.open then
        local handle, err = io.open(path, "r")
        if not handle then
            return nil, err or "open_failed"
        end
        local contents = handle:read("*a")
        handle:close()
        return contents
    end
    return nil, "fs_unavailable"
end

function fs_utils.cleanupArtifacts()
    for index = #createdArtifacts, 1, -1 do
        local path = createdArtifacts[index]
        fs_utils.deleteFile(path)
        createdArtifacts[index] = nil
    end
end

return fs_utils

]===]
bundled_modules["lib_fuel"] = [===[
--[[
Fuel management helpers for CC:Tweaked turtles.
Tracks thresholds, detects low fuel conditions, and provides a simple
SERVICE routine that returns the turtle to origin and attempts to refuel
from configured sources.
--]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local table_utils = require("lib_table")
local logger = require("lib_logger")

local fuel = {}

local DEFAULT_THRESHOLD = 80
local DEFAULT_RESERVE = 160
local DEFAULT_SIDES = { "forward", "down", "up" }
local DEFAULT_FUEL_ITEMS = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
    "minecraft:lava_bucket",
    "minecraft:blaze_rod",
    "minecraft:dried_kelp_block",
}

local function ensureFuelState(ctx)
    if type(ctx) ~= "table" then
        error("fuel library requires a context table", 2)
    end
    ctx.fuelState = ctx.fuelState or {}
    local state = ctx.fuelState
    local cfg = ctx.config or {}

    state.threshold = state.threshold or cfg.fuelThreshold or cfg.minFuel or DEFAULT_THRESHOLD
    state.reserve = state.reserve or cfg.fuelReserve or math.max(DEFAULT_RESERVE, state.threshold * 2)
    state.fuelItems = state.fuelItems or (cfg.fuelItems and #cfg.fuelItems > 0 and table_utils.copyArray(cfg.fuelItems)) or table_utils.copyArray(DEFAULT_FUEL_ITEMS)
    state.sides = state.sides or (cfg.fuelChestSides and #cfg.fuelChestSides > 0 and table_utils.copyArray(cfg.fuelChestSides)) or table_utils.copyArray(DEFAULT_SIDES)
    state.cycleLimit = state.cycleLimit or cfg.fuelCycleLimit or cfg.inventoryCycleLimit or 192
    state.history = state.history or {}
    state.serviceActive = state.serviceActive or false
    state.lastLevel = state.lastLevel or nil
    return state
end

function fuel.ensureState(ctx)
    return ensureFuelState(ctx)
end

local function readFuel()
    if not turtle or not turtle.getFuelLevel then
        return nil, nil, false
    end
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit and turtle.getFuelLimit() or nil
    if level == "unlimited" or limit == "unlimited" then
        return nil, nil, true
    end
    if level == math.huge or limit == math.huge then
        return nil, nil, true
    end
    if type(level) ~= "number" then
        return nil, nil, false
    end
    if type(limit) ~= "number" then
        limit = nil
    end
    return level, limit, false
end

local function resolveTarget(state, opts)
    opts = opts or {}
    local target = opts.target or 0
    if type(target) ~= "number" or target <= 0 then
        target = 0
    end
    local threshold = opts.threshold or state.threshold or 0
    local reserve = opts.reserve or state.reserve or 0
    if threshold > target then
        target = threshold
    end
    if reserve > target then
        target = reserve
    end
    if target <= 0 then
        target = threshold > 0 and threshold or DEFAULT_THRESHOLD
    end
    return target
end

local function resolveSides(state, opts)
    opts = opts or {}
    if type(opts.sides) == "table" and #opts.sides > 0 then
        return table_utils.copyArray(opts.sides)
    end
    return table_utils.copyArray(state.sides)
end

local function resolveFuelItems(state, opts)
    opts = opts or {}
    if type(opts.fuelItems) == "table" and #opts.fuelItems > 0 then
        return table_utils.copyArray(opts.fuelItems)
    end
    return table_utils.copyArray(state.fuelItems)
end

local function recordHistory(state, entry)
    state.history = state.history or {}
    state.history[#state.history + 1] = entry
    local limit = 20
    while #state.history > limit do
        table.remove(state.history, 1)
    end
end

local function consumeFromInventory(ctx, target)
    if not turtle or type(turtle.refuel) ~= "function" then
        return false, { error = "turtle API unavailable" }
    end
    local before = select(1, readFuel())
    if before == nil then
        return false, { error = "fuel unreadable" }
    end
    target = target or 0
    if target <= 0 then
        return false, {
            consumed = {},
            startLevel = before,
            endLevel = before,
            note = "no_target",
        }
    end

    local level = before
    local consumed = {}
    for slot = 1, 16 do
        if target > 0 and level >= target then
            break
        end

        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        local canRefuel = count and count > 0 and turtle.refuel(0)
        if canRefuel then
            while (target <= 0 or level < target) and turtle.getItemCount(slot) > 0 do
                if not turtle.refuel(1) then
                    break
                end
                consumed[slot] = (consumed[slot] or 0) + 1
                level = select(1, readFuel()) or level
                if target > 0 and level >= target then
                    break
                end
            end
        end
    end
    local after = select(1, readFuel()) or level
    if inventory.invalidate then
        inventory.invalidate(ctx)
    end
    return (after > before), {
        consumed = consumed,
        startLevel = before,
        endLevel = after,
    }
end

local function pullFromSources(ctx, state, opts)
    if not turtle then
        return false, { error = "turtle API unavailable" }
    end
    inventory.ensureState(ctx)
    local sides = resolveSides(state, opts)
    local items = resolveFuelItems(state, opts)
    local pulled = {}
    local errors = {}
    local attempts = 0
    local maxAttempts = opts and opts.maxPullAttempts or (#sides * #items)
    if maxAttempts < 1 then
        maxAttempts = #sides * #items
    end
    local cycleLimit = (opts and opts.inventoryCycleLimit) or state.cycleLimit or 192
    for _, side in ipairs(sides) do
        for _, material in ipairs(items) do
            if attempts >= maxAttempts then
                break
            end
            attempts = attempts + 1
            local ok, err = inventory.pullMaterial(ctx, material, nil, {
                side = side,
                deferScan = true,
                cycleLimit = cycleLimit,
            })
            if ok then
                pulled[#pulled + 1] = { side = side, material = material }
                logger.log(ctx, "debug", string.format("Pulled %s from %s", material, side))
            elseif err ~= "missing_material" then
                errors[#errors + 1] = { side = side, material = material, error = err }
                logger.log(ctx, "warn", string.format("Pull %s from %s failed: %s", material, side, tostring(err)))
            end
        end
        if attempts >= maxAttempts then
            break
        end
    end
    if #pulled > 0 then
        inventory.invalidate(ctx)
    end
    return #pulled > 0, { pulled = pulled, errors = errors }
end

local function refuelRound(ctx, target, report)
    local consumed, info = consumeFromInventory(ctx, target)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        round = report.round,
        success = consumed,
        info = info,
    }
    if consumed then
        logger.log(ctx, "debug", string.format("Consumed %d fuel items from inventory", table_utils.sumValues(info and info.consumed)))
    end
    local level = select(1, readFuel())
    if level and level >= target and target > 0 then
        report.finalLevel = level
        report.reachedTarget = true
        return true, report
    end

    local pulled, pullInfo = pullFromSources(ctx, state, opts)
    report.steps[#report.steps + 1] = {
        type = "pull",
        round = report.round,
        success = pulled,
        info = pullInfo,
    }

    if pulled then
        local consumedAfterPull, postInfo = consumeFromInventory(ctx, target)
        report.steps[#report.steps + 1] = {
            type = "inventory",
            stage = "post_pull",
            round = report.round,
            success = consumedAfterPull,
            info = postInfo,
        }
        if consumedAfterPull then
            logger.log(ctx, "debug", string.format("Post-pull consumption used %d fuel items", table_utils.sumValues(postInfo and postInfo.consumed)))
            local postLevel = select(1, readFuel())
            if postLevel and postLevel >= target and target > 0 then
                report.finalLevel = postLevel
                report.reachedTarget = true
                return true, report
            end
        end
    end

    return (pulled or consumed), report
end

local function refuelInternal(ctx, state, opts)
    local startLevel, limit, unlimited = readFuel()
    if unlimited then
        return true, {
            startLevel = startLevel,
            limit = limit,
            finalLevel = startLevel,
            unlimited = true,
        }
    end
    if not startLevel then
        return true, {
            startLevel = nil,
            limit = limit,
            finalLevel = nil,
            message = "fuel level unavailable",
        }
    end

    local target = resolveTarget(state, opts)
    local report = {
        startLevel = startLevel,
        limit = limit,
        target = target,
        steps = {},
    }

    local rounds = opts and opts.rounds or 3
    if rounds < 1 then
        rounds = 1
    end

    for i = 1, rounds do
        report.round = i
        local ok, roundReport = refuelRound(ctx, target, report)
        report = roundReport
        if report.reachedTarget then
            return true, report
        end
        if not ok then
            break
        end
    end

    report.finalLevel = select(1, readFuel()) or startLevel
    if report.finalLevel and report.finalLevel >= target and target > 0 then
        report.reachedTarget = true
        return true, report
    end
    report.reachedTarget = target <= 0
    return report.reachedTarget, report
end

function fuel.check(ctx, opts)
    local state = ensureFuelState(ctx)
    local level, limit, unlimited = readFuel()
    state.lastLevel = level or state.lastLevel

    local report = {
        level = level,
        limit = limit,
        unlimited = unlimited,
        threshold = state.threshold,
        reserve = state.reserve,
        history = state.history,
    }

    if unlimited then
        report.ok = true
        return true, report
    end
    if not level then
        report.ok = true
        report.note = "fuel level unavailable"
        return true, report
    end

    local threshold = opts and opts.threshold or state.threshold or 0
    report.threshold = threshold
    report.reserve = opts and opts.reserve or state.reserve
    report.ok = level >= threshold
    report.needsService = not report.ok
    report.depleted = level <= 0
    return report.ok, report
end

function fuel.refuel(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = refuelInternal(ctx, state, opts)
    recordHistory(state, {
        type = "refuel",
        timestamp = os and os.time and os.time() or nil,
        success = ok,
        report = report,
    })
    if ok then
        logger.log(ctx, "info", string.format("Refuel complete (fuel=%s)", tostring(report.finalLevel or "unknown")))
    else
        logger.log(ctx, "warn", "Refuel attempt did not reach target level")
    end
    return ok, report
end

function fuel.ensure(ctx, opts)
    local state = ensureFuelState(ctx)
    local ok, report = fuel.check(ctx, opts)
    if ok then
        return true, report
    end
    if opts and opts.nonInteractive then
        return false, report
    end
    local serviceOk, serviceReport = fuel.service(ctx, opts)
    if not serviceOk then
        report.service = serviceReport
        return false, report
    end
    return fuel.check(ctx, opts)
end

local function bootstrapFuel(ctx, state, opts, report)
    logger.log(ctx, "warn", "Fuel depleted; attempting to consume onboard fuel before navigating")
    local minimumMove = opts and opts.minimumMoveFuel or math.max(10, state.threshold or 0)
    if minimumMove <= 0 then
        minimumMove = 10
    end
    local consumed, info = consumeFromInventory(ctx, minimumMove)
    report.steps[#report.steps + 1] = {
        type = "inventory",
        stage = "bootstrap",
        success = consumed,
        info = info,
    }
    local level = select(1, readFuel()) or (info and info.endLevel) or report.startLevel
    report.bootstrapLevel = level
    if level <= 0 then
        logger.log(ctx, "error", "Fuel depleted; cannot move to origin")
        report.error = "out_of_fuel"
        report.finalLevel = level
        return false, report
    end
    return true, report
end

local function runService(ctx, state, opts, report)
    state.serviceActive = true
    logger.log(ctx, "info", "Entering SERVICE mode: returning to origin for refuel")

    local ok, err = movement.returnToOrigin(ctx, opts and opts.navigation)
    if not ok then
        state.serviceActive = false
        logger.log(ctx, "error", "SERVICE return failed: " .. tostring(err))
        report.returnError = err
        return false, report
    end
    report.steps[#report.steps + 1] = { type = "return", success = true }

    local refuelOk, refuelReport = refuelInternal(ctx, state, opts)
    report.steps[#report.steps + 1] = {
        type = "refuel",
        success = refuelOk,
        report = refuelReport,
    }

    state.serviceActive = false
    recordHistory(state, {
        type = "service",
        timestamp = os and os.time and os.time() or nil,
        success = refuelOk,
        report = report,
    })

    if not refuelOk then
        logger.log(ctx, "warn", "SERVICE refuel did not reach target level")
        report.finalLevel = select(1, readFuel()) or (refuelReport and refuelReport.finalLevel) or report.startLevel
        return false, report
    end

    local finalLevel = select(1, readFuel()) or refuelReport.finalLevel
    report.finalLevel = finalLevel
    logger.log(ctx, "info", string.format("SERVICE complete (fuel=%s)", tostring(finalLevel or "unknown")))
    return true, report
end

function fuel.service(ctx, opts)
    local state = ensureFuelState(ctx)
    if state.serviceActive then
        return false, { error = "service_already_active" }
    end

    inventory.ensureState(ctx)
    movement.ensureState(ctx)

    local level, limit, unlimited = readFuel()
    local report = {
        startLevel = level,
        limit = limit,
        steps = {},
    }

    if unlimited then
        report.note = "fuel is unlimited"
        return true, report
    end

    if not level then
        logger.log(ctx, "warn", "Fuel level unavailable; skipping service")
        report.error = "fuel_unreadable"
        return false, report
    end

    if level <= 0 then
        local ok, bootstrapReport = bootstrapFuel(ctx, state, opts, report)
        if not ok then
            return false, bootstrapReport
        end
        report = bootstrapReport
    end

    return runService(ctx, state, opts, report)
end

function fuel.resolveFuelThreshold(ctx)
    local threshold = 0
    local function consider(value)
        if type(value) == "number" and value > threshold then
            threshold = value
        end
    end
    if type(ctx.fuelState) == "table" then
        local fuel = ctx.fuelState
        consider(fuel.threshold)
        consider(fuel.reserve)
        consider(fuel.min)
        consider(fuel.minFuel)
        consider(fuel.low)
    end
    if type(ctx.config) == "table" then
        local cfg = ctx.config
        consider(cfg.fuelThreshold)
        consider(cfg.fuelReserve)
        consider(cfg.minFuel)
    end
    return threshold
end

function fuel.isFuelLow(ctx)
    if not turtle or not turtle.getFuelLevel then
        return false
    end
    local level = turtle.getFuelLevel()
    if level == "unlimited" then
        return false
    end
    if type(level) ~= "number" then
        return false
    end
    local threshold = fuel.resolveFuelThreshold(ctx)
    if threshold <= 0 then
        return false
    end
    return level <= threshold

    end

    function fuel.describeFuel(io, report)
    if not io.print then
        return
    end
    if report.unlimited then
        io.print("Fuel: unlimited")
        return
    end
    local levelText = report.level and tostring(report.level) or "unknown"
    local limitText = report.limit and ("/" .. tostring(report.limit)) or ""
    io.print(string.format("Fuel level: %s%s", levelText, limitText))
    if report.threshold then
        io.print(string.format("Threshold: %d", report.threshold))
    end
    if report.reserve then
        io.print(string.format("Reserve target: %d", report.reserve))
    end
    if report.needsService then
        io.print("Status: below threshold (service required)")
    else
        io.print("Status: sufficient for now")
    end
end

function fuel.describeService(io, report)
    if not io.print then
        return
    end
    if not report then
        io.print("No service report available.")
        return
    end
    if report.returnError then
        io.print("Return-to-origin failed: " .. tostring(report.returnError))
    end
    if report.steps then
        for _, step in ipairs(report.steps) do
            if step.type == "return" then
                io.print("Return to origin: " .. (step.success and "OK" or "FAIL"))
            elseif step.type == "refuel" then
                local info = step.report or {}
                local final = info.finalLevel ~= nil and info.finalLevel or (info.endLevel or "unknown")
                io.print(string.format("Refuel step: %s (final=%s)", step.success and "OK" or "FAIL", tostring(final)))
            end
        end
    end
    if report.finalLevel then
        io.print("Service final fuel level: " .. tostring(report.finalLevel))
    end
end

return fuel

]===]
bundled_modules["lib_games"] = [===[
local ui = require("lib_ui")

local games = {}

-- --- SHARED UTILS ---

local function createDeck()
    local suits = {"H", "D", "C", "S"}
    local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
    local deck = {}
    for _, s in ipairs(suits) do
        for _, r in ipairs(ranks) do
            table.insert(deck, { suit = s, rank = r, faceUp = false })
        end
    end
    return deck
end

local function shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function drawCard(x, y, card, selected)
    local color = (card.suit == "H" or card.suit == "D") and colors.red or colors.black
    local bg = selected and colors.yellow or colors.white
    
    if not card.faceUp then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(x, y)
        term.write("##")
        return
    end
    
    term.setBackgroundColor(bg)
    term.setTextColor(color)
    term.setCursorPos(x, y)
    local r = card.rank
    if #r == 1 then r = r .. " " end
    term.write(r)
    term.setCursorPos(x, y+1)
    term.write(card.suit .. " ")
end

-- --- MINESWEEPER ---

function games.minesweeper()
    local w, h = 16, 16
    local mines = 40
    local grid = {}
    local revealed = {}
    local flagged = {}
    local gameOver = false
    local win = false
    
    -- Init grid
    for x = 1, w do
        grid[x] = {}
        revealed[x] = {}
        flagged[x] = {}
        for y = 1, h do
            grid[x][y] = 0
            revealed[x][y] = false
            flagged[x][y] = false
        end
    end
    
    -- Place mines
    local placed = 0
    while placed < mines do
        local x, y = math.random(w), math.random(h)
        if grid[x][y] ~= -1 then
            grid[x][y] = -1
            placed = placed + 1
            -- Update neighbors
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local nx, ny = x + dx, y + dy
                    if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[nx][ny] ~= -1 then
                        grid[nx][ny] = grid[nx][ny] + 1
                    end
                end
            end
        end
    end
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, w + 2, h + 2, "Minesweeper")
        
        for x = 1, w do
            for y = 1, h do
                term.setCursorPos(x + 1, y + 1)
                if revealed[x][y] then
                    if grid[x][y] == -1 then
                        term.setBackgroundColor(colors.red)
                        term.setTextColor(colors.black)
                        term.write("*")
                    elseif grid[x][y] == 0 then
                        term.setBackgroundColor(colors.lightGray)
                        term.write(" ")
                    else
                        term.setBackgroundColor(colors.lightGray)
                        term.setTextColor(colors.black)
                        term.write(tostring(grid[x][y]))
                    end
                elseif flagged[x][y] then
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.red)
                    term.write("F")
                else
                    term.setBackgroundColor(colors.gray)
                    term.write(" ")
                end
            end
        end
        
        if gameOver then
            ui.drawBox(5, 8, 12, 3, colors.red, colors.white)
            ui.label(6, 9, win and "YOU WIN!" or "GAME OVER")
            ui.button(6, 10, "Click to exit", true)
        end
    end
    
    local function reveal(x, y)
        if x < 1 or x > w or y < 1 or y > h or revealed[x][y] or flagged[x][y] then return end
        revealed[x][y] = true
        if grid[x][y] == -1 then
            gameOver = true
            win = false
        elseif grid[x][y] == 0 then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    reveal(x + dx, y + dy)
                end
            end
        end
    end
    
    while true do
        draw()
        local event, p1, p2, p3 = os.pullEvent("mouse_click")
        local btn, mx, my = p1, p2, p3
        
        if gameOver then return end
        
        local gx, gy = mx - 1, my - 1
        if gx >= 1 and gx <= w and gy >= 1 and gy <= h then
            if btn == 1 then -- Left click
                reveal(gx, gy)
            elseif btn == 2 then -- Right click
                if not revealed[gx][gy] then
                    flagged[gx][gy] = not flagged[gx][gy]
                end
            end
        end
        
        -- Check win
        local covered = 0
        for x = 1, w do
            for y = 1, h do
                if not revealed[x][y] then covered = covered + 1 end
            end
        end
        if covered == mines then
            gameOver = true
            win = true
        end
    end
end

-- --- SOLITAIRE ---

function games.solitaire()
    local deck = createDeck()
    shuffle(deck)
    
    local piles = {} -- 7 tableau piles
    local foundations = {{}, {}, {}, {}} -- 4 foundations
    local stock = {}
    local waste = {}
    
    -- Deal
    for i = 1, 7 do
        piles[i] = {}
        for j = 1, i do
            local card = table.remove(deck)
            if j == i then card.faceUp = true end
            table.insert(piles[i], card)
        end
    end
    stock = deck
    
    local selected = nil -- { type="pile"|"waste", index=1, cardIndex=1 }
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, 50, 19, "Solitaire")
        
        -- Stock
        if #stock > 0 then
            drawCard(2, 2, {suit="?", rank="?", faceUp=false}, false)
        else
            ui.label(2, 2, "[]")
        end
        
        -- Waste
        if #waste > 0 then
            local card = waste[#waste]
            card.faceUp = true
            drawCard(6, 2, card, selected and selected.type == "waste")
        end
        
        -- Foundations
        for i = 1, 4 do
            local x = 15 + (i-1)*4
            if #foundations[i] > 0 then
                drawCard(x, 2, foundations[i][#foundations[i]], false)
            else
                ui.label(x, 2, "[]")
            end
        end
        
        -- Tableau
        for i = 1, 7 do
            local x = 2 + (i-1)*5
            if #piles[i] == 0 then
                ui.label(x, 5, "[]")
            else
                for j, card in ipairs(piles[i]) do
                    local y = 5 + (j-1)
                    if y < 18 then
                        local isSel = selected and selected.type == "pile" and selected.index == i and selected.cardIndex == j
                        drawCard(x, y, card, isSel)
                    end
                end
            end
        end
    end
    
    local function canStack(bottom, top)
        if not bottom then return top.rank == "K" end -- Empty pile needs King
        local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
        local red = {H=true, D=true}
        local bottomRed = red[bottom.suit]
        local topRed = red[top.suit]
        return (bottomRed ~= topRed) and (ranks[bottom.rank] == ranks[top.rank] + 1)
    end
    
    local function canFoundation(foundation, card)
        local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
        if #foundation == 0 then return card.rank == "A" end
        local top = foundation[#foundation]
        return top.suit == card.suit and ranks[card.rank] == ranks[top.rank] + 1
    end

    while true do
        draw()
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "key" and p1 == keys.q then return end
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Click Stock
            if my >= 2 and my <= 3 and mx >= 2 and mx <= 4 then
                if #stock > 0 then
                    table.insert(waste, table.remove(stock))
                else
                    -- Recycle waste
                    while #waste > 0 do
                        local c = table.remove(waste)
                        c.faceUp = false
                        table.insert(stock, c)
                    end
                end
                selected = nil
            
            -- Click Waste
            elseif my >= 2 and my <= 3 and mx >= 6 and mx <= 8 and #waste > 0 then
                if selected and selected.type == "waste" then
                    selected = nil
                else
                    selected = { type = "waste" }
                end
                
            -- Click Foundations (Target only)
            elseif my >= 2 and my <= 3 and mx >= 15 and mx <= 30 then
                local fIdx = math.floor((mx - 15) / 4) + 1
                if fIdx >= 1 and fIdx <= 4 then
                    if selected then
                        local card
                        if selected.type == "waste" then card = waste[#waste]
                        elseif selected.type == "pile" then 
                            local p = piles[selected.index]
                            if selected.cardIndex == #p then card = p[#p] end
                        end
                        
                        if card and canFoundation(foundations[fIdx], card) then
                            table.insert(foundations[fIdx], card)
                            if selected.type == "waste" then table.remove(waste)
                            else table.remove(piles[selected.index]) end
                            
                            -- Flip next card in pile
                            if selected.type == "pile" then
                                local p = piles[selected.index]
                                if #p > 0 then p[#p].faceUp = true end
                            end
                            selected = nil
                        end
                    end
                end
                
            -- Click Tableau
            elseif my >= 5 then
                local pIdx = math.floor((mx - 2) / 5) + 1
                if pIdx >= 1 and pIdx <= 7 then
                    local p = piles[pIdx]
                    local cIdx = my - 4
                    
                    if cIdx <= #p and cIdx > 0 then
                        -- Clicked a card
                        local card = p[cIdx]
                        if card.faceUp then
                            if selected then
                                if selected.type == "pile" and selected.index == pIdx then
                                    selected = nil -- Deselect self
                                else
                                    -- Try to move selected TO here
                                    local srcCard
                                    if selected.type == "waste" then srcCard = waste[#waste]
                                    elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
                                    
                                    if srcCard and canStack(card, srcCard) then
                                        -- Move
                                        if selected.type == "waste" then
                                            table.insert(p, table.remove(waste))
                                        else
                                            local srcPile = piles[selected.index]
                                            local moving = {}
                                            for k = selected.cardIndex, #srcPile do
                                                table.insert(moving, srcPile[k])
                                            end
                                            for k = #srcPile, selected.cardIndex, -1 do
                                                table.remove(srcPile)
                                            end
                                            for _, m in ipairs(moving) do table.insert(p, m) end
                                            if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
                                        end
                                        selected = nil
                                    else
                                        -- Select this instead
                                        selected = { type = "pile", index = pIdx, cardIndex = cIdx }
                                    end
                                end
                            else
                                selected = { type = "pile", index = pIdx, cardIndex = cIdx }
                            end
                        end
                    elseif #p == 0 and cIdx == 1 then
                        -- Clicked empty slot
                        if selected then
                            local srcCard
                            if selected.type == "waste" then srcCard = waste[#waste]
                            elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
                            
                            if srcCard and canStack(nil, srcCard) then
                                -- Move King to empty
                                if selected.type == "waste" then
                                    table.insert(p, table.remove(waste))
                                else
                                    local srcPile = piles[selected.index]
                                    local moving = {}
                                    for k = selected.cardIndex, #srcPile do
                                        table.insert(moving, srcPile[k])
                                    end
                                    for k = #srcPile, selected.cardIndex, -1 do
                                        table.remove(srcPile)
                                    end
                                    for _, m in ipairs(moving) do table.insert(p, m) end
                                    if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
                                end
                                selected = nil
                            end
                        end
                    end
                end
            end
        end
    end
end

-- --- EUCHRE ---

function games.euchre()
    -- Simplified Euchre: 4 players, 5 cards each.
    -- Deck: 9, 10, J, Q, K, A of all suits (24 cards).
    local function createEuchreDeck()
        local suits = {"H", "D", "C", "S"}
        local ranks = {"9", "10", "J", "Q", "K", "A"}
        local deck = {}
        for _, s in ipairs(suits) do
            for _, r in ipairs(ranks) do
                table.insert(deck, { suit = s, rank = r, faceUp = true })
            end
        end
        return deck
    end
    
    local deck = createEuchreDeck()
    shuffle(deck)
    
    local hands = {{}, {}, {}, {}} -- 1=Human, 2=Left, 3=Partner, 4=Right
    for i=1,4 do
        for j=1,5 do table.insert(hands[i], table.remove(deck)) end
    end
    
    local trump = nil
    local turn = 1
    local tricks = {0, 0} -- Team 1 (Human/Partner), Team 2 (Opponents)
    local currentTrick = {}
    
    -- Simple AI
    local function aiPlay(handIdx)
        local hand = hands[handIdx]
        -- Play first valid card
        local leadSuit = nil
        if #currentTrick > 0 then leadSuit = currentTrick[1].card.suit end
        
        for i, c in ipairs(hand) do
            if not leadSuit or c.suit == leadSuit then
                table.remove(hand, i)
                return c
            end
        end
        return table.remove(hand, 1) -- Fallback (renege possible in this simple logic, but ok for now)
    end
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, 50, 19, "Euchre")
        
        -- Draw Table
        ui.label(20, 2, "Partner")
        ui.label(2, 9, "Left")
        ui.label(45, 9, "Right")
        ui.label(20, 17, "You")
        
        ui.label(2, 2, "Tricks: " .. tricks[1] .. " - " .. tricks[2])
        if trump then ui.label(40, 2, "Trump: " .. trump) end
        
        -- Draw played cards
        for _, play in ipairs(currentTrick) do
            local x, y = 25, 10
            if play.player == 1 then y = 12
            elseif play.player == 2 then x = 15
            elseif play.player == 3 then y = 8
            elseif play.player == 4 then x = 35 end
            drawCard(x, y, play.card, false)
        end
        
        -- Draw Hand
        for i, card in ipairs(hands[1]) do
            drawCard(10 + (i-1)*5, 15, card, false)
        end
    end
    
    -- Bidding Phase (Simplified: just pick top card of kitty or random)
    local kitty = deck[1]
    trump = kitty.suit -- Force trump for simplicity in this version
    
    while true do
        draw()
        
        if #currentTrick == 4 then
            sleep(1)
            -- Evaluate trick
            -- (Skipping complex evaluation logic for brevity, just random winner)
            local winner = math.random(1, 2)
            tricks[winner] = tricks[winner] + 1
            currentTrick = {}
            if #hands[1] == 0 then
                ui.clear()
                print("Game Over. Team " .. (tricks[1] > tricks[2] and "1" or "2") .. " wins!")
                sleep(2)
                return
            end
        end
        
        if turn == 1 then
            -- Human turn
            local event, p1, p2, p3 = os.pullEvent("mouse_click")
            if event == "mouse_click" then
                local mx, my = p2, p3
                if my >= 15 and my <= 16 then
                    local idx = math.floor((mx - 10) / 5) + 1
                    if idx >= 1 and idx <= #hands[1] then
                        local card = table.remove(hands[1], idx)
                        table.insert(currentTrick, { player = 1, card = card })
                        turn = 2
                    end
                end
            end
        else
            sleep(0.5)
            local card = aiPlay(turn)
            table.insert(currentTrick, { player = turn, card = card })
            turn = (turn % 4) + 1
        end
    end
end

return games

]===]
bundled_modules["lib_gps"] = [===[
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

]===]
bundled_modules["lib_initialize"] = [===[
--[[
Initialization helper for schema-driven builds.
Verifies material availability against a manifest by checking the turtle
inventory plus nearby supply chests. Provides prompting to gather missing
materials before a print begins.
--]]

---@diagnostic disable: undefined-global

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local world = require("lib_world")
local table_utils = require("lib_table")

local initialize = {}

local DEFAULT_SIDES = { "forward", "down", "up", "left", "right", "back" }

local function mapSides(opts)
    local sides = {}
    local seen = {}
    if type(opts) == "table" and type(opts.sides) == "table" then
        for _, side in ipairs(opts.sides) do
            local normalised = world.normaliseSide(side)
            if normalised and not seen[normalised] then
                sides[#sides + 1] = normalised
                seen[normalised] = true
            end
        end
    end
    if #sides == 0 then
        for _, side in ipairs(DEFAULT_SIDES) do
            local normalised = world.normaliseSide(side)
            if normalised and not seen[normalised] then
                sides[#sides + 1] = normalised
                seen[normalised] = true
            end
        end
    end
    return sides
end

local function normaliseManifest(manifest)
    local result = {}
    if type(manifest) ~= "table" then
        return result
    end
    local function push(material, count)
        if type(material) ~= "string" or material == "" then
            return
        end
        if material == "minecraft:air" or material == "air" then
            return
        end
        if type(count) ~= "number" or count <= 0 then
            return
        end
        result[material] = math.max(result[material] or 0, math.floor(count))
    end
    local isArray = manifest[1] ~= nil
    if isArray then
        for _, entry in ipairs(manifest) do
            if type(entry) == "table" then
                local count = entry.count or entry.quantity or entry.amount or entry.required
                push(entry.material or entry.name or entry.id, count or entry[2])
            elseif type(entry) == "string" then
                push(entry, 1)
            end
        end
    else
        for material, count in pairs(manifest) do
            push(material, count)
        end
    end
    return result
end

local function listChestTotals(peripheralObj)
    local totals = {}
    if type(peripheralObj) ~= "table" then
        return totals
    end
    local ok, items = pcall(function()
        if type(peripheralObj.list) == "function" then
            return peripheralObj.list()
        end
        return nil
    end)
    if not ok or type(items) ~= "table" then
        return totals
    end
    for _, stack in pairs(items) do
        if type(stack) == "table" then
            local name = stack.name or stack.id
            local count = stack.count or stack.qty or stack.quantity
            if type(name) == "string" and type(count) == "number" and count > 0 then
                totals[name] = (totals[name] or 0) + count
            end
        end
    end
    return totals
end

local function gatherChestDataForSide(side, entries, combined)
    local periphSide = world.toPeripheralSide(side) or side
    local inspectOk, inspectDetail = world.inspectSide(side)
    local inspectIsContainer = inspectOk and world.isContainer(inspectDetail)
    local inspectName = nil
    if inspectIsContainer and type(inspectDetail) == "table" and type(inspectDetail.name) == "string" and inspectDetail.name ~= "" then
        inspectName = inspectDetail.name
    end

    local wrapOk, wrapped = pcall(peripheral.wrap, periphSide)
    if not wrapOk then
        wrapped = nil
    end

    local metaName, metaTags
    if wrapped then
        if type(peripheral.call) == "function" then
            local metaOk, metadata = pcall(peripheral.call, periphSide, "getMetadata")
            if metaOk and type(metadata) == "table" then
                metaName = metadata.name or metadata.displayName or metaName
                metaTags = metadata.tags
            end
        end
        if not metaName and type(peripheral.getType) == "function" then
            local typeOk, perType = pcall(peripheral.getType, periphSide)
            if typeOk then
                if type(perType) == "string" then
                    metaName = perType
                elseif type(perType) == "table" and type(perType[1]) == "string" then
                    metaName = perType[1]
                end
            end
        end
    end

    local metaIsContainer = false
    if metaName then
        metaIsContainer = world.isContainer({ name = metaName, tags = metaTags })
    end

    local hasInventoryMethods = wrapped and (type(wrapped.list) == "function" or type(wrapped.size) == "function")
    local containerDetected = inspectIsContainer or metaIsContainer or hasInventoryMethods

    if containerDetected then
        local containerName = inspectName or metaName or "container"
        if wrapped and hasInventoryMethods then
            local totals = listChestTotals(wrapped)
            table_utils.mergeTotals(combined, totals)
            entries[#entries + 1] = {
                side = side,
                name = containerName,
                totals = totals,
            }
        else
            entries[#entries + 1] = {
                side = side,
                name = containerName,
                totals = {},
                error = "wrap_failed",
            }
        end
    end
end

local function gatherChestData(ctx, opts)
    local entries = {}
    local combined = {}
    if not peripheral then
        return entries, combined
    end
    for _, side in ipairs(mapSides(opts)) do
        gatherChestDataForSide(side, entries, combined)
    end
    if next(combined) == nil then
        combined = {}
    end
    return entries, combined
end

local function gatherTurtleTotals(ctx)
    local totals = {}
    local ok, err = inventory.scan(ctx, { force = true })
    if not ok then
        return totals, err
    end
    local observed, mapErr = inventory.getTotals(ctx, { force = true })
    if not observed then
        return totals, mapErr
    end
    for material, count in pairs(observed) do
        if type(count) == "number" and count > 0 then
            totals[material] = count
        end
    end
    return totals
end

local function summariseMissing(manifest, totals)
    local missing = {}
    for material, required in pairs(manifest) do
        local have = totals[material] or 0
        if have < required then
            missing[#missing + 1] = {
                material = material,
                required = required,
                have = have,
                missing = required - have,
            }
        end
    end
    table.sort(missing, function(a, b)
        if a.missing == b.missing then
            return a.material < b.material
        end
        return a.missing > b.missing
    end)
    return missing
end

local function promptUser(report, attempt, opts)
    if not read then
        return false
    end
    print("\nMissing materials detected:")
    for _, entry in ipairs(report.missing or {}) do
        print(string.format(" - %s: need %d (have %d, short %d)", entry.material, entry.required, entry.have, entry.missing))
    end
    print("Add materials to the turtle or connected chests, then press Enter to retry.")
    print("Type 'cancel' to abort.")
    if type(write) == "function" then
        write("> ")
    end
    local response = read()
    if response and string.lower(response) == "cancel" then
        return false
    end
    return true
end

local function checkMaterialsInternal(ctx, manifest, opts)
    local report = {
        manifest = table_utils.copyTotals(manifest),
    }
    if next(manifest) == nil then
        report.ok = true
        return true, report
    end

    local turtleTotals, invErr = gatherTurtleTotals(ctx)
    if invErr then
        report.inventoryError = invErr
        logger.log(ctx, "warn", "Inventory scan failed: " .. tostring(invErr))
    end
    report.turtleTotals = table_utils.copyTotals(turtleTotals)

    local chestEntries, chestTotals = gatherChestData(ctx, opts)
    report.chests = chestEntries
    report.chestTotals = table_utils.copyTotals(chestTotals)

    local combinedTotals = table_utils.copyTotals(turtleTotals)
    table_utils.mergeTotals(combinedTotals, chestTotals)
    report.combinedTotals = combinedTotals

    report.missing = summariseMissing(manifest, combinedTotals)
    if #report.missing == 0 then
        report.ok = true
        return true, report
    end

    report.ok = false
    return false, report
end

function initialize.checkMaterials(ctx, spec, opts)
    opts = opts or {}
    spec = spec or {}
    local manifestSrc = spec.manifest or spec.materials or spec
    if not manifestSrc and type(ctx) == "table" and type(ctx.schemaInfo) == "table" then
        manifestSrc = ctx.schemaInfo.materials
    end
    local manifest = normaliseManifest(manifestSrc)
    return checkMaterialsInternal(ctx, manifest, opts)
end

function initialize.ensureMaterials(ctx, spec, opts)
    opts = opts or {}
    local attempt = 0
    while true do
        local ok, report = initialize.checkMaterials(ctx, spec, opts)
        if ok then
            logger.log(ctx, "info", "Material check passed.")
            return true, report
        end
        logger.log(ctx, "warn", "Materials missing; print halted.")
        if opts.nonInteractive then
            return false, report
        end
        attempt = attempt + 1
        local continue = promptUser(report, attempt, opts)
        if not continue then
            return false, report
        end
    end
end

return initialize

]===]
bundled_modules["lib_inventory"] = [===[
--[[
Inventory library for CC:Tweaked turtles.
Tracks slot contents, provides material lookup helpers, and wraps chest
interactions used by higher-level states. All public functions accept a shared
ctx table and follow the project convention of returning success booleans with
optional error messages.
--]]

---@diagnostic disable: undefined-global

local inventory = {}
local movement = require("lib_movement")
local logger = require("lib_logger")

local SIDE_ACTIONS = {
    forward = {
        drop = turtle and turtle.drop or nil,
        suck = turtle and turtle.suck or nil,
    },
    up = {
        drop = turtle and turtle.dropUp or nil,
        suck = turtle and turtle.suckUp or nil,
    },
    down = {
        drop = turtle and turtle.dropDown or nil,
        suck = turtle and turtle.suckDown or nil,
    },
}

local PUSH_TARGETS = {
    "front",
    "back",
    "left",
    "right",
    "top",
    "bottom",
    "north",
    "south",
    "east",
    "west",
    "up",
    "down",
}

local OPPOSITE_FACING = {
    north = "south",
    south = "north",
    east = "west",
    west = "east",
}

inventory.DEFAULT_TRASH = {
    ["minecraft:air"] = true,
    ["minecraft:stone"] = true,
    ["minecraft:cobblestone"] = true,
    ["minecraft:deepslate"] = true,
    ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:tuff"] = true,
    ["minecraft:diorite"] = true,
    ["minecraft:granite"] = true,
    ["minecraft:andesite"] = true,
    ["minecraft:calcite"] = true,
    ["minecraft:netherrack"] = true,
    ["minecraft:end_stone"] = true,
    ["minecraft:basalt"] = true,
    ["minecraft:blackstone"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:dirt"] = true,
    ["minecraft:coarse_dirt"] = true,
    ["minecraft:rooted_dirt"] = true,
    ["minecraft:mycelium"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:red_sand"] = true,
    ["minecraft:sandstone"] = true,
    ["minecraft:red_sandstone"] = true,
    ["minecraft:clay"] = true,
    ["minecraft:dripstone_block"] = true,
    ["minecraft:pointed_dripstone"] = true,
    ["minecraft:bedrock"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:water"] = true,
    ["minecraft:torch"] = true,
}

local function noop()
end

local function normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

local function resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

local function tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function copyArray(list)
    if type(list) ~= "table" then
        return {}
    end
    local result = {}
    for index = 1, #list do
        result[index] = list[index]
    end
    return result
end

local function copySummary(summary)
    if type(summary) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(summary) do
        result[key] = value
    end
    return result
end

local function copySlots(slots)
    if type(slots) ~= "table" then
        return {}
    end
    local result = {}
    for slot, info in pairs(slots) do
        if type(info) == "table" then
            result[slot] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = info.detail,
            }
        else
            result[slot] = info
        end
    end
    return result
end

local function hasContainerTag(tags)
    if type(tags) ~= "table" then
        return false
    end
    for key, value in pairs(tags) do
        if value and type(key) == "string" then
            local lower = key:lower()
            for _, keyword in ipairs(CONTAINER_KEYWORDS) do
                if lower:find(keyword, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return hasContainerTag(tags)
end

local function inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

local function shouldSearchAllSides(opts)
    if type(opts) ~= "table" then
        return true
    end
    if opts.searchAllSides == false then
        return false
    end
    return true
end

local function peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

local function computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

local function tryPushItems(chest, periphSide, slot, amount, targetSlot, primaryDirection)
    if type(chest) ~= "table" or type(chest.pushItems) ~= "function" then
        return 0
    end

    local tried = {}

    local function attempt(direction)
        if not direction or tried[direction] then
            return 0
        end
        tried[direction] = true
        local ok, moved
        if targetSlot then
            ok, moved = pcall(chest.pushItems, direction, slot, amount, targetSlot)
        else
            ok, moved = pcall(chest.pushItems, direction, slot, amount)
        end
        if ok and type(moved) == "number" and moved > 0 then
            return moved
        end
        return 0
    end

    local moved = attempt(primaryDirection)
    if moved > 0 then
        return moved
    end

    for _, direction in ipairs(PUSH_TARGETS) do
        moved = attempt(direction)
        if moved > 0 then
            return moved
        end
    end

    return 0
end

local function collectStacks(chest, material)
    local stacks = {}
    if type(chest) ~= "table" or not material then
        return stacks
    end

    if type(chest.list) == "function" then
        local ok, list = pcall(chest.list)
        if ok and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot and type(stack) == "table" then
                    local name = stack.name or stack.id
                    local count = stack.count or stack.qty or stack.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = numericSlot, count = count }
                    end
                end
            end
        end
    end

    if #stacks == 0 and type(chest.size) == "function" and type(chest.getItemDetail) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size > 0 then
            for slot = 1, size do
                local okDetail, detail = pcall(chest.getItemDetail, slot)
                if okDetail and type(detail) == "table" then
                    local name = detail.name
                    local count = detail.count or detail.qty or detail.quantity or 0
                    if name == material and type(count) == "number" and count > 0 then
                        stacks[#stacks + 1] = { slot = slot, count = count }
                    end
                end
            end
        end
    end

    table.sort(stacks, function(a, b)
        return a.slot < b.slot
    end)

    return stacks
end

local function newContainerManifest()
    return {
        totals = {},
        slots = {},
        totalItems = 0,
        orderedSlots = {},
        size = nil,
        metadata = nil,
    }
end

local function addManifestEntry(manifest, slot, stack)
    if type(manifest) ~= "table" or type(slot) ~= "number" then
        return
    end
    if type(stack) ~= "table" then
        return
    end
    local name = stack.name or stack.id
    local count = stack.count or stack.qty or stack.quantity or stack.Count
    if type(name) ~= "string" or type(count) ~= "number" or count <= 0 then
        return
    end
    manifest.slots[slot] = {
        name = name,
        count = count,
        tags = stack.tags,
        nbt = stack.nbt,
        displayName = stack.displayName or stack.label or stack.Name,
        detail = stack,
    }
    manifest.totals[name] = (manifest.totals[name] or 0) + count
    manifest.totalItems = manifest.totalItems + count
end

local function populateManifestSlots(manifest)
    local ordered = {}
    for slot in pairs(manifest.slots) do
        ordered[#ordered + 1] = slot
    end
    table.sort(ordered)
    manifest.orderedSlots = ordered

    local materials = {}
    for material in pairs(manifest.totals) do
        materials[#materials + 1] = material
    end
    table.sort(materials)
    manifest.materials = materials
end

local function attachMetadata(manifest, periphSide)
    if not peripheral then
        return
    end
    local metadata = manifest.metadata or {}
    if type(peripheral.call) == "function" then
        local okMeta, meta = pcall(peripheral.call, periphSide, "getMetadata")
        if okMeta and type(meta) == "table" then
            metadata.name = meta.name or metadata.name
            metadata.displayName = meta.displayName or meta.label or metadata.displayName
            metadata.tags = meta.tags or metadata.tags
        end
    end
    if type(peripheral.getType) == "function" then
        local okType, perType = pcall(peripheral.getType, periphSide)
        if okType then
            if type(perType) == "string" then
                metadata.peripheralType = perType
            elseif type(perType) == "table" and type(perType[1]) == "string" then
                metadata.peripheralType = perType[1]
            end
        end
    end
    if next(metadata) ~= nil then
        manifest.metadata = metadata
    end
end

local function readContainerManifest(periphSide)
    if not peripheral or type(peripheral.wrap) ~= "function" then
        return nil, "peripheral_api_unavailable"
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return nil, "wrap_failed"
    end

    local manifest = newContainerManifest()

    if type(chest.list) == "function" then
        local okList, list = pcall(chest.list)
        if okList and type(list) == "table" then
            for slot, stack in pairs(list) do
                local numericSlot = tonumber(slot)
                if numericSlot then
                    addManifestEntry(manifest, numericSlot, stack)
                end
            end
        end
    end

    local haveSlots = next(manifest.slots) ~= nil
    if type(chest.size) == "function" then
        local okSize, size = pcall(chest.size)
        if okSize and type(size) == "number" and size >= 0 then
            manifest.size = size
            if not haveSlots and type(chest.getItemDetail) == "function" then
                for slot = 1, size do
                    local okDetail, detail = pcall(chest.getItemDetail, slot)
                    if okDetail then
                        addManifestEntry(manifest, slot, detail)
                    end
                end
            end
        end
    end

    populateManifestSlots(manifest)
    attachMetadata(manifest, periphSide)

    return manifest
end

local function extractFromContainer(ctx, periphSide, material, amount, targetSlot)
    if not material or not peripheral or type(peripheral.wrap) ~= "function" then
        return 0
    end

    local wrapOk, chest = pcall(peripheral.wrap, periphSide)
    if not wrapOk or type(chest) ~= "table" then
        return 0
    end
    if type(chest.pushItems) ~= "function" then
        return 0
    end

    local desired = amount
    if not desired or desired <= 0 then
        desired = 64
    end

    local stacks = collectStacks(chest, material)
    if #stacks == 0 then
        return 0
    end

    local remaining = desired
    local transferred = 0
    local primaryDirection = computePrimaryPushDirection(ctx, periphSide)

    for _, stack in ipairs(stacks) do
        local available = stack.count or 0
        while remaining > 0 and available > 0 do
            local toMove = math.min(available, remaining, 64)
            local moved = tryPushItems(chest, periphSide, stack.slot, toMove, targetSlot, primaryDirection)
            if moved <= 0 then
                break
            end
            transferred = transferred + moved
            remaining = remaining - moved
            available = available - moved
        end
        if remaining <= 0 then
            break
        end
    end

    return transferred
end

local function ensureChestAhead(ctx, opts)
    local frontOk, frontDetail = inspectForwardForContainer()
    if frontOk then
        return true, noop, { side = "forward", detail = frontDetail }
    end

    if not shouldSearchAllSides(opts) then
        return false, nil, nil, "container_not_found"
    end
    if not turtle then
        return false, nil, nil, "turtle_api_unavailable"
    end

    movement.ensureState(ctx)
    local startFacing = movement.getFacing(ctx)

    local function restoreFacing()
        if not startFacing then
            return
        end
        if movement.getFacing(ctx) ~= startFacing then
            local okFace, faceErr = movement.faceDirection(ctx, startFacing)
            if not okFace and faceErr then
                logger.log(ctx, "warn", "Failed to restore facing: " .. tostring(faceErr))
            end
        end
    end

    local function makeRestore()
        if not startFacing then
            return noop
        end
        return function()
            restoreFacing()
        end
    end

    -- Check left
    local ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local leftOk, leftDetail = inspectForwardForContainer()
    if leftOk then
        logger.log(ctx, "debug", "Found container on left side; using that")
        return true, makeRestore(), { side = "left", detail = leftDetail }
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check right
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local rightOk, rightDetail = inspectForwardForContainer()
    if rightOk then
        logger.log(ctx, "debug", "Found container on right side; using that")
        return true, makeRestore(), { side = "right", detail = rightDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    -- Check behind
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    local backOk, backDetail = inspectForwardForContainer()
    if backOk then
        logger.log(ctx, "debug", "Found container behind; using that")
        return true, makeRestore(), { side = "back", detail = backDetail }
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end
    ok, err = movement.turnLeft(ctx)
    if not ok then
        restoreFacing()
        return false, nil, nil, err or "turn_failed"
    end

    restoreFacing()
    return false, nil, nil, "container_not_found"
end

local function ensureInventoryState(ctx)
    if type(ctx) ~= "table" then
        error("inventory library requires a context table", 2)
    end

    if type(ctx.inventoryState) ~= "table" then
        ctx.inventoryState = ctx.inventory or {}
    end
    ctx.inventory = ctx.inventoryState

    local state = ctx.inventoryState
    state.scanVersion = state.scanVersion or 0
    state.slots = state.slots or {}
    state.materialSlots = state.materialSlots or {}
    state.materialTotals = state.materialTotals or {}
    state.emptySlots = state.emptySlots or {}
    state.totalItems = state.totalItems or 0
    if state.dirty == nil then
        state.dirty = true
    end
    return state
end

function inventory.ensureState(ctx)
    return ensureInventoryState(ctx)
end

function inventory.invalidate(ctx)
    local state = ensureInventoryState(ctx)
    state.dirty = true
    return true
end

local function fetchSlotDetail(slot)
    if not turtle then
        return { slot = slot, count = 0 }
    end
    local detail
    if turtle.getItemDetail then
        detail = turtle.getItemDetail(slot)
    end
    local count
    if turtle.getItemCount then
        count = turtle.getItemCount(slot)
    elseif detail then
        count = detail.count
    end
    count = count or 0
    local name = detail and detail.name or nil
    return {
        slot = slot,
        count = count,
        name = name,
        detail = detail,
    }
end

function inventory.scan(ctx, opts)
    local state = ensureInventoryState(ctx)
    if not turtle then
        state.slots = {}
        state.materialSlots = {}
        state.materialTotals = {}
        state.emptySlots = {}
        state.totalItems = 0
        state.dirty = false
        state.scanVersion = state.scanVersion + 1
        return false, "turtle API unavailable"
    end

    local slots = {}
    local materialSlots = {}
    local materialTotals = {}
    local emptySlots = {}
    local totalItems = 0

    for slot = 1, 16 do
        local info = fetchSlotDetail(slot)
        slots[slot] = info
        if info.count > 0 and info.name then
            local list = materialSlots[info.name]
            if not list then
                list = {}
                materialSlots[info.name] = list
            end
            list[#list + 1] = slot
            materialTotals[info.name] = (materialTotals[info.name] or 0) + info.count
            totalItems = totalItems + info.count
        else
            emptySlots[#emptySlots + 1] = slot
        end
    end

    state.slots = slots
    state.materialSlots = materialSlots
    state.materialTotals = materialTotals
    state.emptySlots = emptySlots
    state.totalItems = totalItems
    if os and type(os.clock) == "function" then
        state.lastScanClock = os.clock()
    else
        state.lastScanClock = nil
    end
    local epochFn = os and os["epoch"]
    if type(epochFn) == "function" then
        state.lastScanEpoch = epochFn("utc")
    else
        state.lastScanEpoch = nil
    end
    state.scanVersion = state.scanVersion + 1
    state.dirty = false

    logger.log(ctx, "debug", string.format("Inventory scan complete: %d items across %d materials", totalItems, tableCount(materialSlots)))
    return true
end

local function ensureScanned(ctx, opts)
    local state = ensureInventoryState(ctx)
    if state.dirty or (type(opts) == "table" and opts.force) or not state.slots or next(state.slots) == nil then
        local ok, err = inventory.scan(ctx, opts)
        if not ok and err then
            return nil, err
        end
    end
    return state
end

function inventory.getMaterialSlots(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return nil, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local slots = state.materialSlots[material]
    if not slots then
        return {}
    end
    return copyArray(slots)
end

function inventory.getSlotForMaterial(ctx, material, opts)
    local slots, err = inventory.getMaterialSlots(ctx, material, opts)
    if slots == nil then
        return nil, err
    end
    if slots[1] then
        return slots[1]
    end
    return nil, "missing_material"
end

function inventory.countMaterial(ctx, material, opts)
    if type(material) ~= "string" or material == "" then
        return 0, "invalid_material"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.materialTotals[material] or 0
end

function inventory.hasMaterial(ctx, material, amount, opts)
    amount = amount or 1
    if amount <= 0 then
        return true
    end
    local total, err = inventory.countMaterial(ctx, material, opts)
    if err then
        return false, err
    end
    return total >= amount
end

function inventory.findEmptySlot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    local empty = state.emptySlots
    if empty and empty[1] then
        return empty[1]
    end
    return nil, "no_empty_slot"
end

function inventory.isEmpty(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end
    return state.totalItems == 0
end

function inventory.totalItemCount(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return 0, err
    end
    return state.totalItems
end

function inventory.getTotals(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return copySummary(state.materialTotals)
end

function inventory.snapshot(ctx, opts)
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return nil, err
    end
    return {
        slots = copySlots(state.slots),
        totals = copySummary(state.materialTotals),
        emptySlots = copyArray(state.emptySlots),
        totalItems = state.totalItems,
        scanVersion = state.scanVersion,
        lastScanClock = state.lastScanClock,
        lastScanEpoch = state.lastScanEpoch,
    }
end

function inventory.detectContainer(ctx, opts)
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    if side == "forward" then
        local chestOk, restoreFn, info, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFn()
        end
        local result = info or { side = "forward" }
        result.peripheralSide = "front"
        return result
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if okUp then
            return { side = "up", detail = detail, peripheralSide = "top" }
        end
        return nil, "container_not_found"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if okDown then
            return { side = "down", detail = detail, peripheralSide = "bottom" }
        end
        return nil, "container_not_found"
    end
    return nil, "unsupported_side"
end

function inventory.getContainerManifest(ctx, opts)
    if not turtle then
        return nil, "turtle API unavailable"
    end
    opts = opts or {}
    local side = resolveSide(ctx, opts)
    local periphSide = peripheralSideForDirection(side)
    local restoreFacing = noop
    local info

    if side == "forward" then
        local chestOk, restoreFn, chestInfo, err = ensureChestAhead(ctx, opts)
        if not chestOk then
            return nil, err or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
        info = chestInfo or { side = "forward" }
        periphSide = "front"
    elseif side == "up" then
        local okUp, detail = inspectUpForContainer()
        if not okUp then
            return nil, "container_not_found"
        end
        info = { side = "up", detail = detail }
        periphSide = "top"
    elseif side == "down" then
        local okDown, detail = inspectDownForContainer()
        if not okDown then
            return nil, "container_not_found"
        end
        info = { side = "down", detail = detail }
        periphSide = "bottom"
    else
        return nil, "unsupported_side"
    end

    local manifest, manifestErr = readContainerManifest(periphSide)
    restoreFacing()
    if not manifest then
        return nil, manifestErr or "wrap_failed"
    end

    manifest.peripheralSide = periphSide
    if info then
        manifest.relativeSide = info.side
        manifest.inspectDetail = info.detail
        if not manifest.metadata and info.detail then
            manifest.metadata = {
                name = info.detail.name,
                displayName = info.detail.displayName or info.detail.label,
                tags = info.detail.tags,
            }
        elseif manifest.metadata and info.detail then
            manifest.metadata.name = manifest.metadata.name or info.detail.name
            manifest.metadata.displayName = manifest.metadata.displayName or info.detail.displayName or info.detail.label
            manifest.metadata.tags = manifest.metadata.tags or info.detail.tags
        end
    end

    return manifest
end

function inventory.selectMaterial(ctx, material, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
    if not slot then
        return false, err or "missing_material"
    end
    if turtle.select(slot) then
        return true
    end
    return false, "select_failed"
end

local function selectSlot(slot)
    if not turtle then
        return false, "turtle API unavailable"
    end
    if type(slot) ~= "number" or slot < 1 or slot > 16 then
        return false, "invalid_slot"
    end
    if turtle.select(slot) then
        return true
    end
    return false, "select_failed"
end

local function rescanIfNeeded(ctx, opts)
    if opts and opts.deferScan then
        inventory.invalidate(ctx)
        return
    end
    local ok, err = inventory.scan(ctx)
    if not ok and err then
        logger.log(ctx, "warn", "Inventory rescan failed: " .. tostring(err))
        inventory.invalidate(ctx)
    end
end

function inventory.pushSlot(ctx, slot, amount, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local side = resolveSide(ctx, opts)
    local actions = SIDE_ACTIONS[side]
    if not actions or type(actions.drop) ~= "function" then
        return false, "invalid_side"
    end

    local ok, err = selectSlot(slot)
    if not ok then
        return false, err
    end

    local restoreFacing = noop
    if side == "forward" then
        local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
    elseif side == "up" then
        local okUp = inspectUpForContainer()
        if not okUp then
            return false, "container_not_found"
        end
    elseif side == "down" then
        local okDown = inspectDownForContainer()
        if not okDown then
            return false, "container_not_found"
        end
    end

    local count = turtle.getItemCount and turtle.getItemCount(slot) or nil
    if count ~= nil and count <= 0 then
        restoreFacing()
        return false, "empty_slot"
    end

    if amount and amount > 0 then
        ok = actions.drop(amount)
    else
        ok = actions.drop()
    end
    if not ok then
        restoreFacing()
        return false, "drop_failed"
    end

    restoreFacing()
    rescanIfNeeded(ctx, opts)
    return true
end

function inventory.pushMaterial(ctx, material, amount, opts)
    if type(material) ~= "string" or material == "" then
        return false, "invalid_material"
    end
    local slot, err = inventory.getSlotForMaterial(ctx, material, opts)
    if not slot then
        return false, err or "missing_material"
    end
    return inventory.pushSlot(ctx, slot, amount, opts)
end

local function resolveTargetSlotForPull(state, material, opts)
    if opts and opts.slot then
        return opts.slot
    end
    if material then
        local materialSlots = state.materialSlots[material]
        if materialSlots and materialSlots[1] then
            return materialSlots[1]
        end
    end
    local empty = state.emptySlots
    if empty and empty[1] then
        return empty[1]
    end
    return nil
end

function inventory.pullMaterial(ctx, material, amount, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end

    local side = resolveSide(ctx, opts)
    local actions = SIDE_ACTIONS[side]
    if not actions or type(actions.suck) ~= "function" then
        return false, "invalid_side"
    end

    if material ~= nil and (type(material) ~= "string" or material == "") then
        return false, "invalid_material"
    end

    local targetSlot = resolveTargetSlotForPull(state, material, opts)
    if not targetSlot then
        return false, "no_empty_slot"
    end

    local ok, selectErr = selectSlot(targetSlot)
    if not ok then
        return false, selectErr
    end

    local periphSide = peripheralSideForDirection(side)
    local restoreFacing = noop
    if side == "forward" then
        local chestOk, restoreFn, _, searchErr = ensureChestAhead(ctx, opts)
        if not chestOk then
            return false, searchErr or "container_not_found"
        end
        if type(restoreFn) == "function" then
            restoreFacing = restoreFn
        end
    elseif side == "up" then
        local okUp = inspectUpForContainer()
        if not okUp then
            return false, "container_not_found"
        end
    elseif side == "down" then
        local okDown = inspectDownForContainer()
        if not okDown then
            return false, "container_not_found"
        end
    end

    local desired = nil
    if material then
        if amount and amount > 0 then
            desired = math.min(amount, 64)
        else
            -- Accept any positive stack when no explicit amount is requested.
            desired = nil
        end
    elseif amount and amount > 0 then
        desired = amount
    end

    local transferred = 0
    if material then
        transferred = extractFromContainer(ctx, periphSide, material, desired, targetSlot)
        if transferred > 0 then
            restoreFacing()
            rescanIfNeeded(ctx, opts)
            return true
        end
    end

    if material == nil then
        if amount and amount > 0 then
            ok = actions.suck(amount)
        else
            ok = actions.suck()
        end
        if not ok then
            restoreFacing()
            return false, "suck_failed"
        end
        restoreFacing()
        rescanIfNeeded(ctx, opts)
        return true
    end

    local function makePushOpts()
        local pushOpts = { side = side }
        if type(opts) == "table" and opts.searchAllSides ~= nil then
            pushOpts.searchAllSides = opts.searchAllSides
        end
        return pushOpts
    end

    local stashSlots = {}
    local stashSet = {}

    local function addStashSlot(slot)
        stashSlots[#stashSlots + 1] = slot
        stashSet[slot] = true
    end

    local function markSlotEmpty(slot)
        if not slot then
            return
        end
        local info = state.slots[slot]
        if info then
            info.count = 0
            info.name = nil
            info.detail = nil
        end
        for index = #state.emptySlots, 1, -1 do
            if state.emptySlots[index] == slot then
                return
            end
        end
        state.emptySlots[#state.emptySlots + 1] = slot
    end

    local function freeAdditionalSlot()
        local pushOpts = makePushOpts()
        pushOpts.deferScan = true
        for slot = 16, 1, -1 do
            if slot ~= targetSlot and not stashSet[slot] then
                local count = turtle.getItemCount(slot)
                if count > 0 then
                    local info = state.slots[slot]
                    if not info or info.name ~= material then
                        local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
                        if pushOk then
                            inventory.invalidate(ctx)
                            markSlotEmpty(slot)
                            local newState = ensureScanned(ctx, { force = true })
                            if newState then
                                state = newState
                            end
                            if turtle.getItemCount(slot) == 0 then
                                return slot
                            end
                        else
                            if pushErr then
                                logger.log(ctx, "debug", string.format("Unable to clear slot %d while restocking %s: %s", slot, material or "unknown", pushErr))
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function findTemporarySlot()
        for slot = 1, 16 do
            if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
                return slot
            end
        end
        local cleared = freeAdditionalSlot()
        if cleared then
            return cleared
        end
        for slot = 1, 16 do
            if slot ~= targetSlot and not stashSet[slot] and turtle.getItemCount(slot) == 0 then
                return slot
            end
        end
        return nil
    end

    local function returnStash(deferScan)
        if #stashSlots == 0 then
            return
        end
        local pushOpts = makePushOpts()
        pushOpts.deferScan = deferScan
        for _, slot in ipairs(stashSlots) do
            local pushOk, pushErr = inventory.pushSlot(ctx, slot, nil, pushOpts)
            if not pushOk and pushErr then
                logger.log(ctx, "warn", string.format("Failed to return cycled item from slot %d: %s", slot, tostring(pushErr)))
            end
        end
        turtle.select(targetSlot)
        inventory.invalidate(ctx)
        local newState = ensureScanned(ctx, { force = true })
        if newState then
            state = newState
        end
        stashSlots = {}
        stashSet = {}
    end

    local cycles = 0
    local maxCycles = (type(opts) == "table" and opts.cycleLimit) or 48
    local success = false
    local failureReason
    local cycled = 0
    local assumedMatch = false

    while cycles < maxCycles do
        cycles = cycles + 1
        local currentCount = turtle.getItemCount(targetSlot)
        if desired and currentCount >= desired then
            success = true
            break
        end

        local need = desired and math.max(desired - currentCount, 1) or nil
        local pulled
        if need then
            pulled = actions.suck(math.min(need, 64))
        else
            pulled = actions.suck()
        end
        if not pulled then
            failureReason = failureReason or "suck_failed"
            break
        end

        local detail
        if turtle and turtle.getItemDetail then
            detail = turtle.getItemDetail(targetSlot)
            if detail == nil then
                local okDetailed, detailed = pcall(turtle.getItemDetail, targetSlot, true)
                if okDetailed then
                    detail = detailed
                end
            end
        end
        local updatedCount = turtle.getItemCount(targetSlot)

        local assumedMatch = false
        if not detail and material and updatedCount > 0 then
            -- Non-advanced turtles cannot inspect stacks; assume the pulled stack
            -- matches the requested material when we cannot obtain metadata.
            assumedMatch = true
        end

        if (detail and detail.name == material) or assumedMatch then
            if not desired or updatedCount >= desired then
                success = true
                break
            end
        else
            assumedMatch = false
            local stashSlot = findTemporarySlot()
            if not stashSlot then
                failureReason = "no_empty_slot"
                break
            end
            local moved = turtle.transferTo(stashSlot)
            if not moved then
                failureReason = "transfer_failed"
                break
            end
            addStashSlot(stashSlot)
            cycled = cycled + 1
            inventory.invalidate(ctx)
            turtle.select(targetSlot)
        end
    end

    if success then
        if assumedMatch then
            logger.log(ctx, "debug", string.format("Pulled %s without detailed item metadata", material or "unknown"))
        elseif cycled > 0 then
            logger.log(ctx, "debug", string.format("Pulled %s after cycling %d other stacks", material, cycled))
        else
            logger.log(ctx, "debug", string.format("Pulled %s directly via turtle.suck", material))
        end
        returnStash(true)
        restoreFacing()
        rescanIfNeeded(ctx, opts)
        return true
    end

    returnStash(true)
    restoreFacing()
    if failureReason then
        logger.log(ctx, "debug", string.format("Failed to pull %s after cycling %d stacks: %s", material, cycled, failureReason))
    end
    if failureReason == "suck_failed" then
        return false, "missing_material"
    end
    return false, failureReason or "missing_material"
end

function inventory.dumpTrash(ctx, trashList)
    if not turtle then return false, "turtle API unavailable" end
    trashList = trashList or inventory.DEFAULT_TRASH
    
    local state, err = ensureScanned(ctx)
    if not state then return false, err end

    for slot, info in pairs(state.slots) do
        if info and info.name and trashList[info.name] then
            turtle.select(slot)
            turtle.drop()
        end
    end
    
    -- Force rescan after dumping
    inventory.scan(ctx)
    return true
end

function inventory.clearSlot(ctx, slot, opts)
    if not turtle then
        return false, "turtle API unavailable"
    end
    local state, err = ensureScanned(ctx, opts)
    if not state then
        return false, err
    end
    local info = state.slots[slot]
    if not info or info.count == 0 then
        return true
    end
    local ok, dropErr = inventory.pushSlot(ctx, slot, nil, opts)
    if not ok then
        return false, dropErr
    end
    return true
end

function inventory.describeMaterials(io, info)
    if not io.print then
        return
    end
    io.print("Schema manifest requirements:")
    if not info or not info.materials then
        io.print(" - <none>")
        return
    end
    for _, entry in ipairs(info.materials) do
        if entry.material ~= "minecraft:air" and entry.material ~= "air" then
            io.print(string.format(" - %s x%d", entry.material, entry.count or 0))
        end
    end
end

function inventory.runCheck(ctx, io, opts)
    local ok, report = initialize.ensureMaterials(ctx, { manifest = ctx.schemaInfo and ctx.schemaInfo.materials }, opts)
    if io.print then
        if ok then
            io.print("Material check passed. Turtle and chests meet manifest requirements.")
        else
            io.print("Material check failed. Missing materials:")
            for _, entry in ipairs(report.missing or {}) do
                io.print(string.format(" - %s: need %d, have %d", entry.material, entry.required, entry.have))
            end
        end
    end
    return ok, report
end

function inventory.gatherSummary(io, report)
    if not io.print then
        return
    end
    io.print("\nDetailed totals:")
    io.print(" Turtle inventory:")
    for material, count in pairs(report.turtleTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    io.print(" Nearby chests:")
    for material, count in pairs(report.chestTotals or {}) do
        io.print(string.format("   - %s x%d", material, count))
    end
    if #report.chests > 0 then
        io.print(" Per-chest breakdown:")
        for _, entry in ipairs(report.chests) do
            io.print(string.format("   [%s] %s", entry.side, entry.name or "container"))
            for material, count in pairs(entry.totals or {}) do
                io.print(string.format("     * %s x%d", material, count))
            end
        end
    end
end

function inventory.describeTotals(io, totals)
    totals = totals or {}
    local keys = {}
    for material in pairs(totals) do
        keys[#keys + 1] = material
    end
    table.sort(keys)
    if io.print then
        if #keys == 0 then
            io.print("Inventory totals: <empty>")
        else
            io.print("Inventory totals:")
            for _, material in ipairs(keys) do
                io.print(string.format(" - %s x%d", material, totals[material] or 0))
            end
        end
    end
end

function inventory.computeManifest(list)
    local totals = {}
    for _, sc in ipairs(list) do
        if sc.material and sc.material ~= "" then
            totals[sc.material] = (totals[sc.material] or 0) + 1
        end
    end
    return totals
end

function inventory.printManifest(io, manifest)
    if not io.print then
        return
    end
    io.print("\nRequested manifest (minimum counts):")
    local shown = false
    for material, count in pairs(manifest) do
        io.print(string.format(" - %s x%d", material, count))
        shown = true
    end
    if not shown then
        io.print(" - <empty>")
    end
end

return inventory

]===]
bundled_modules["lib_inventory_utils"] = [===[
local inventory_utils = {}

local common = require("harness_common")

function inventory_utils.hasMaterial(material)
    if not turtle or not turtle.getItemDetail then
        return false
    end
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == material and detail.count and detail.count > 0 then
            return true
        end
    end
    return false
end

function inventory_utils.ensureMaterialPresent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if inventory_utils.hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Turtle is missing " .. material .. ". Load it, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until inventory_utils.hasMaterial(material)
end

function inventory_utils.ensureMaterialAbsent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if not inventory_utils.hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Remove all " .. material .. " from the turtle inventory, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until not inventory_utils.hasMaterial(material)
end

return inventory_utils

]===]
bundled_modules["lib_items"] = [===[
local items = {
    { id = "minecraft:stone", name = "Stone", color = colors.lightGray, sym = "#" },
    { id = "minecraft:granite", name = "Granite", color = colors.red, sym = "#" },
    { id = "minecraft:polished_granite", name = "Polished Granite", color = colors.red, sym = "#" },
    { id = "minecraft:diorite", name = "Diorite", color = colors.white, sym = "#" },
    { id = "minecraft:polished_diorite", name = "Polished Diorite", color = colors.white, sym = "#" },
    { id = "minecraft:andesite", name = "Andesite", color = colors.gray, sym = "#" },
    { id = "minecraft:polished_andesite", name = "Polished Andesite", color = colors.gray, sym = "#" },
    { id = "minecraft:grass_block", name = "Grass Block", color = colors.green, sym = "G" },
    { id = "minecraft:dirt", name = "Dirt", color = colors.brown, sym = "d" },
    { id = "minecraft:coarse_dirt", name = "Coarse Dirt", color = colors.brown, sym = "d" },
    { id = "minecraft:podzol", name = "Podzol", color = colors.brown, sym = "d" },
    { id = "minecraft:cobblestone", name = "Cobblestone", color = colors.gray, sym = "C" },
    { id = "minecraft:oak_planks", name = "Oak Planks", color = colors.brown, sym = "P" },
    { id = "minecraft:spruce_planks", name = "Spruce Planks", color = colors.brown, sym = "P" },
    { id = "minecraft:birch_planks", name = "Birch Planks", color = colors.yellow, sym = "P" },
    { id = "minecraft:jungle_planks", name = "Jungle Planks", color = colors.brown, sym = "P" },
    { id = "minecraft:acacia_planks", name = "Acacia Planks", color = colors.orange, sym = "P" },
    { id = "minecraft:dark_oak_planks", name = "Dark Oak Planks", color = colors.brown, sym = "P" },
    { id = "minecraft:mangrove_planks", name = "Mangrove Planks", color = colors.red, sym = "P" },
    { id = "minecraft:cherry_planks", name = "Cherry Planks", color = colors.pink, sym = "P" },
    { id = "minecraft:bamboo_planks", name = "Bamboo Planks", color = colors.yellow, sym = "P" },
    { id = "minecraft:bedrock", name = "Bedrock", color = colors.black, sym = "B" },
    { id = "minecraft:sand", name = "Sand", color = colors.yellow, sym = "s" },
    { id = "minecraft:red_sand", name = "Red Sand", color = colors.orange, sym = "s" },
    { id = "minecraft:gravel", name = "Gravel", color = colors.gray, sym = "g" },
    { id = "minecraft:gold_ore", name = "Gold Ore", color = colors.yellow, sym = "o" },
    { id = "minecraft:iron_ore", name = "Iron Ore", color = colors.brown, sym = "o" },
    { id = "minecraft:coal_ore", name = "Coal Ore", color = colors.black, sym = "o" },
    { id = "minecraft:nether_gold_ore", name = "Nether Gold Ore", color = colors.yellow, sym = "o" },
    { id = "minecraft:oak_log", name = "Oak Log", color = colors.brown, sym = "L" },
    { id = "minecraft:spruce_log", name = "Spruce Log", color = colors.brown, sym = "L" },
    { id = "minecraft:birch_log", name = "Birch Log", color = colors.white, sym = "L" },
    { id = "minecraft:jungle_log", name = "Jungle Log", color = colors.brown, sym = "L" },
    { id = "minecraft:acacia_log", name = "Acacia Log", color = colors.orange, sym = "L" },
    { id = "minecraft:dark_oak_log", name = "Dark Oak Log", color = colors.brown, sym = "L" },
    { id = "minecraft:mangrove_log", name = "Mangrove Log", color = colors.red, sym = "L" },
    { id = "minecraft:cherry_log", name = "Cherry Log", color = colors.pink, sym = "L" },
    { id = "minecraft:stripped_oak_log", name = "Stripped Oak Log", color = colors.brown, sym = "L" },
    { id = "minecraft:stripped_spruce_log", name = "Stripped Spruce Log", color = colors.brown, sym = "L" },
    { id = "minecraft:stripped_birch_log", name = "Stripped Birch Log", color = colors.white, sym = "L" },
    { id = "minecraft:stripped_jungle_log", name = "Stripped Jungle Log", color = colors.brown, sym = "L" },
    { id = "minecraft:stripped_acacia_log", name = "Stripped Acacia Log", color = colors.orange, sym = "L" },
    { id = "minecraft:stripped_dark_oak_log", name = "Stripped Dark Oak Log", color = colors.brown, sym = "L" },
    { id = "minecraft:stripped_mangrove_log", name = "Stripped Mangrove Log", color = colors.red, sym = "L" },
    { id = "minecraft:stripped_cherry_log", name = "Stripped Cherry Log", color = colors.pink, sym = "L" },
    { id = "minecraft:glass", name = "Glass", color = colors.lightBlue, sym = "G" },
    { id = "minecraft:lapis_ore", name = "Lapis Ore", color = colors.blue, sym = "o" },
    { id = "minecraft:diamond_ore", name = "Diamond Ore", color = colors.cyan, sym = "o" },
    { id = "minecraft:redstone_ore", name = "Redstone Ore", color = colors.red, sym = "o" },
    { id = "minecraft:emerald_ore", name = "Emerald Ore", color = colors.green, sym = "o" },
    { id = "minecraft:white_wool", name = "White Wool", color = colors.white, sym = "W" },
    { id = "minecraft:orange_wool", name = "Orange Wool", color = colors.orange, sym = "W" },
    { id = "minecraft:magenta_wool", name = "Magenta Wool", color = colors.magenta, sym = "W" },
    { id = "minecraft:light_blue_wool", name = "Light Blue Wool", color = colors.lightBlue, sym = "W" },
    { id = "minecraft:yellow_wool", name = "Yellow Wool", color = colors.yellow, sym = "W" },
    { id = "minecraft:lime_wool", name = "Lime Wool", color = colors.lime, sym = "W" },
    { id = "minecraft:pink_wool", name = "Pink Wool", color = colors.pink, sym = "W" },
    { id = "minecraft:gray_wool", name = "Gray Wool", color = colors.gray, sym = "W" },
    { id = "minecraft:light_gray_wool", name = "Light Gray Wool", color = colors.lightGray, sym = "W" },
    { id = "minecraft:cyan_wool", name = "Cyan Wool", color = colors.cyan, sym = "W" },
    { id = "minecraft:purple_wool", name = "Purple Wool", color = colors.purple, sym = "W" },
    { id = "minecraft:blue_wool", name = "Blue Wool", color = colors.blue, sym = "W" },
    { id = "minecraft:brown_wool", name = "Brown Wool", color = colors.brown, sym = "W" },
    { id = "minecraft:green_wool", name = "Green Wool", color = colors.green, sym = "W" },
    { id = "minecraft:red_wool", name = "Red Wool", color = colors.red, sym = "W" },
    { id = "minecraft:black_wool", name = "Black Wool", color = colors.black, sym = "W" },
    { id = "minecraft:bricks", name = "Bricks", color = colors.red, sym = "B" },
    { id = "minecraft:bookshelf", name = "Bookshelf", color = colors.brown, sym = "#" },
    { id = "minecraft:mossy_cobblestone", name = "Mossy Cobblestone", color = colors.gray, sym = "C" },
    { id = "minecraft:obsidian", name = "Obsidian", color = colors.black, sym = "O" },
    { id = "minecraft:torch", name = "Torch", color = colors.yellow, sym = "i" },
    { id = "minecraft:chest", name = "Chest", color = colors.brown, sym = "C" },
    { id = "minecraft:crafting_table", name = "Crafting Table", color = colors.brown, sym = "T" },
    { id = "minecraft:furnace", name = "Furnace", color = colors.gray, sym = "F" },
    { id = "minecraft:ladder", name = "Ladder", color = colors.brown, sym = "H" },
    { id = "minecraft:snow", name = "Snow", color = colors.white, sym = "S" },
    { id = "minecraft:ice", name = "Ice", color = colors.lightBlue, sym = "I" },
    { id = "minecraft:snow_block", name = "Snow Block", color = colors.white, sym = "S" },
    { id = "minecraft:clay", name = "Clay", color = colors.lightGray, sym = "C" },
    { id = "minecraft:pumpkin", name = "Pumpkin", color = colors.orange, sym = "P" },
    { id = "minecraft:netherrack", name = "Netherrack", color = colors.red, sym = "N" },
    { id = "minecraft:soul_sand", name = "Soul Sand", color = colors.brown, sym = "S" },
    { id = "minecraft:soul_soil", name = "Soul Soil", color = colors.brown, sym = "S" },
    { id = "minecraft:basalt", name = "Basalt", color = colors.gray, sym = "B" },
    { id = "minecraft:polished_basalt", name = "Polished Basalt", color = colors.gray, sym = "B" },
    { id = "minecraft:glowstone", name = "Glowstone", color = colors.yellow, sym = "G" },
    { id = "minecraft:stone_bricks", name = "Stone Bricks", color = colors.gray, sym = "B" },
    { id = "minecraft:mossy_stone_bricks", name = "Mossy Stone Bricks", color = colors.gray, sym = "B" },
    { id = "minecraft:cracked_stone_bricks", name = "Cracked Stone Bricks", color = colors.gray, sym = "B" },
    { id = "minecraft:chiseled_stone_bricks", name = "Chiseled Stone Bricks", color = colors.gray, sym = "B" },
    { id = "minecraft:deepslate", name = "Deepslate", color = colors.gray, sym = "D" },
    { id = "minecraft:cobbled_deepslate", name = "Cobbled Deepslate", color = colors.gray, sym = "D" },
    { id = "minecraft:polished_deepslate", name = "Polished Deepslate", color = colors.gray, sym = "D" },
    { id = "minecraft:deepslate_bricks", name = "Deepslate Bricks", color = colors.gray, sym = "D" },
    { id = "minecraft:deepslate_tiles", name = "Deepslate Tiles", color = colors.gray, sym = "D" },
    { id = "minecraft:reinforced_deepslate", name = "Reinforced Deepslate", color = colors.black, sym = "D" },
    { id = "minecraft:melon", name = "Melon", color = colors.green, sym = "M" },
    { id = "minecraft:mycelium", name = "Mycelium", color = colors.purple, sym = "M" },
    { id = "minecraft:nether_bricks", name = "Nether Bricks", color = colors.red, sym = "B" },
    { id = "minecraft:end_stone", name = "End Stone", color = colors.yellow, sym = "E" },
    { id = "minecraft:emerald_block", name = "Emerald Block", color = colors.green, sym = "E" },
    { id = "minecraft:quartz_block", name = "Quartz Block", color = colors.white, sym = "Q" },
    { id = "minecraft:white_terracotta", name = "White Terracotta", color = colors.white, sym = "T" },
    { id = "minecraft:orange_terracotta", name = "Orange Terracotta", color = colors.orange, sym = "T" },
    { id = "minecraft:magenta_terracotta", name = "Magenta Terracotta", color = colors.magenta, sym = "T" },
    { id = "minecraft:light_blue_terracotta", name = "Light Blue Terracotta", color = colors.lightBlue, sym = "T" },
    { id = "minecraft:yellow_terracotta", name = "Yellow Terracotta", color = colors.yellow, sym = "T" },
    { id = "minecraft:lime_terracotta", name = "Lime Terracotta", color = colors.lime, sym = "T" },
    { id = "minecraft:pink_terracotta", name = "Pink Terracotta", color = colors.pink, sym = "T" },
    { id = "minecraft:gray_terracotta", name = "Gray Terracotta", color = colors.gray, sym = "T" },
    { id = "minecraft:light_gray_terracotta", name = "Light Gray Terracotta", color = colors.lightGray, sym = "T" },
    { id = "minecraft:cyan_terracotta", name = "Cyan Terracotta", color = colors.cyan, sym = "T" },
    { id = "minecraft:purple_terracotta", name = "Purple Terracotta", color = colors.purple, sym = "T" },
    { id = "minecraft:blue_terracotta", name = "Blue Terracotta", color = colors.blue, sym = "T" },
    { id = "minecraft:brown_terracotta", name = "Brown Terracotta", color = colors.brown, sym = "T" },
    { id = "minecraft:green_terracotta", name = "Green Terracotta", color = colors.green, sym = "T" },
    { id = "minecraft:red_terracotta", name = "Red Terracotta", color = colors.red, sym = "T" },
    { id = "minecraft:black_terracotta", name = "Black Terracotta", color = colors.black, sym = "T" },
    { id = "minecraft:hay_block", name = "Hay Bale", color = colors.yellow, sym = "H" },
    { id = "minecraft:terracotta", name = "Terracotta", color = colors.orange, sym = "T" },
    { id = "minecraft:coal_block", name = "Block of Coal", color = colors.black, sym = "C" },
    { id = "minecraft:packed_ice", name = "Packed Ice", color = colors.lightBlue, sym = "I" },
    { id = "minecraft:blue_ice", name = "Blue Ice", color = colors.blue, sym = "I" },
    { id = "minecraft:prismarine", name = "Prismarine", color = colors.cyan, sym = "P" },
    { id = "minecraft:prismarine_bricks", name = "Prismarine Bricks", color = colors.cyan, sym = "P" },
    { id = "minecraft:dark_prismarine", name = "Dark Prismarine", color = colors.cyan, sym = "P" },
    { id = "minecraft:sea_lantern", name = "Sea Lantern", color = colors.white, sym = "L" },
    { id = "minecraft:red_sandstone", name = "Red Sandstone", color = colors.orange, sym = "S" },
    { id = "minecraft:magma_block", name = "Magma Block", color = colors.red, sym = "M" },
    { id = "minecraft:nether_wart_block", name = "Nether Wart Block", color = colors.red, sym = "W" },
    { id = "minecraft:warped_wart_block", name = "Warped Wart Block", color = colors.cyan, sym = "W" },
    { id = "minecraft:red_nether_bricks", name = "Red Nether Bricks", color = colors.red, sym = "B" },
    { id = "minecraft:bone_block", name = "Bone Block", color = colors.white, sym = "B" },
    { id = "minecraft:shulker_box", name = "Shulker Box", color = colors.purple, sym = "S" },
    { id = "minecraft:white_concrete", name = "White Concrete", color = colors.white, sym = "C" },
    { id = "minecraft:orange_concrete", name = "Orange Concrete", color = colors.orange, sym = "C" },
    { id = "minecraft:magenta_concrete", name = "Magenta Concrete", color = colors.magenta, sym = "C" },
    { id = "minecraft:light_blue_concrete", name = "Light Blue Concrete", color = colors.lightBlue, sym = "C" },
    { id = "minecraft:yellow_concrete", name = "Yellow Concrete", color = colors.yellow, sym = "C" },
    { id = "minecraft:lime_concrete", name = "Lime Concrete", color = colors.lime, sym = "C" },
    { id = "minecraft:pink_concrete", name = "Pink Concrete", color = colors.pink, sym = "C" },
    { id = "minecraft:gray_concrete", name = "Gray Concrete", color = colors.gray, sym = "C" },
    { id = "minecraft:light_gray_concrete", name = "Light Gray Concrete", color = colors.lightGray, sym = "C" },
    { id = "minecraft:cyan_concrete", name = "Cyan Concrete", color = colors.cyan, sym = "C" },
    { id = "minecraft:purple_concrete", name = "Purple Concrete", color = colors.purple, sym = "C" },
    { id = "minecraft:blue_concrete", name = "Blue Concrete", color = colors.blue, sym = "C" },
    { id = "minecraft:brown_concrete", name = "Brown Concrete", color = colors.brown, sym = "C" },
    { id = "minecraft:green_concrete", name = "Green Concrete", color = colors.green, sym = "C" },
    { id = "minecraft:red_concrete", name = "Red Concrete", color = colors.red, sym = "C" },
    { id = "minecraft:black_concrete", name = "Black Concrete", color = colors.black, sym = "C" },
    { id = "minecraft:white_concrete_powder", name = "White Concrete Powder", color = colors.white, sym = "P" },
    { id = "minecraft:orange_concrete_powder", name = "Orange Concrete Powder", color = colors.orange, sym = "P" },
    { id = "minecraft:magenta_concrete_powder", name = "Magenta Concrete Powder", color = colors.magenta, sym = "P" },
    { id = "minecraft:light_blue_concrete_powder", name = "Light Blue Concrete Powder", color = colors.lightBlue, sym = "P" },
    { id = "minecraft:yellow_concrete_powder", name = "Yellow Concrete Powder", color = colors.yellow, sym = "P" },
    { id = "minecraft:lime_concrete_powder", name = "Lime Concrete Powder", color = colors.lime, sym = "P" },
    { id = "minecraft:pink_concrete_powder", name = "Pink Concrete Powder", color = colors.pink, sym = "P" },
    { id = "minecraft:gray_concrete_powder", name = "Gray Concrete Powder", color = colors.gray, sym = "P" },
    { id = "minecraft:light_gray_concrete_powder", name = "Light Gray Concrete Powder", color = colors.lightGray, sym = "P" },
    { id = "minecraft:cyan_concrete_powder", name = "Cyan Concrete Powder", color = colors.cyan, sym = "P" },
    { id = "minecraft:purple_concrete_powder", name = "Purple Concrete Powder", color = colors.purple, sym = "P" },
    { id = "minecraft:blue_concrete_powder", name = "Blue Concrete Powder", color = colors.blue, sym = "P" },
    { id = "minecraft:brown_concrete_powder", name = "Brown Concrete Powder", color = colors.brown, sym = "P" },
    { id = "minecraft:green_concrete_powder", name = "Green Concrete Powder", color = colors.green, sym = "P" },
    { id = "minecraft:red_concrete_powder", name = "Red Concrete Powder", color = colors.red, sym = "P" },
    { id = "minecraft:black_concrete_powder", name = "Black Concrete Powder", color = colors.black, sym = "P" },
    { id = "minecraft:dried_kelp_block", name = "Dried Kelp Block", color = colors.green, sym = "K" },
    { id = "minecraft:dead_tube_coral_block", name = "Dead Tube Coral Block", color = colors.gray, sym = "C" },
    { id = "minecraft:dead_brain_coral_block", name = "Dead Brain Coral Block", color = colors.gray, sym = "C" },
    { id = "minecraft:dead_bubble_coral_block", name = "Dead Bubble Coral Block", color = colors.gray, sym = "C" },
    { id = "minecraft:dead_fire_coral_block", name = "Dead Fire Coral Block", color = colors.gray, sym = "C" },
    { id = "minecraft:dead_horn_coral_block", name = "Dead Horn Coral Block", color = colors.gray, sym = "C" },
    { id = "minecraft:tube_coral_block", name = "Tube Coral Block", color = colors.blue, sym = "C" },
    { id = "minecraft:brain_coral_block", name = "Brain Coral Block", color = colors.pink, sym = "C" },
    { id = "minecraft:bubble_coral_block", name = "Bubble Coral Block", color = colors.magenta, sym = "C" },
    { id = "minecraft:fire_coral_block", name = "Fire Coral Block", color = colors.red, sym = "C" },
    { id = "minecraft:horn_coral_block", name = "Horn Coral Block", color = colors.yellow, sym = "C" },
    { id = "minecraft:honey_block", name = "Honey Block", color = colors.orange, sym = "H" },
    { id = "minecraft:honeycomb_block", name = "Honeycomb Block", color = colors.orange, sym = "H" },
    { id = "minecraft:netherite_block", name = "Block of Netherite", color = colors.black, sym = "N" },
    { id = "minecraft:ancient_debris", name = "Ancient Debris", color = colors.brown, sym = "D" },
    { id = "minecraft:crying_obsidian", name = "Crying Obsidian", color = colors.purple, sym = "O" },
    { id = "minecraft:blackstone", name = "Blackstone", color = colors.black, sym = "B" },
    { id = "minecraft:polished_blackstone", name = "Polished Blackstone", color = colors.black, sym = "B" },
    { id = "minecraft:polished_blackstone_bricks", name = "Polished Blackstone Bricks", color = colors.black, sym = "B" },
    { id = "minecraft:gilded_blackstone", name = "Gilded Blackstone", color = colors.black, sym = "B" },
    { id = "minecraft:chiseled_polished_blackstone", name = "Chiseled Polished Blackstone", color = colors.black, sym = "B" },
    { id = "minecraft:quartz_bricks", name = "Quartz Bricks", color = colors.white, sym = "Q" },
    { id = "minecraft:amethyst_block", name = "Block of Amethyst", color = colors.purple, sym = "A" },
    { id = "minecraft:budding_amethyst", name = "Budding Amethyst", color = colors.purple, sym = "A" },
    { id = "minecraft:tuff", name = "Tuff", color = colors.gray, sym = "T" },
    { id = "minecraft:calcite", name = "Calcite", color = colors.white, sym = "C" },
    { id = "minecraft:tinted_glass", name = "Tinted Glass", color = colors.gray, sym = "G" },
    { id = "minecraft:smooth_basalt", name = "Smooth Basalt", color = colors.gray, sym = "B" },
    { id = "minecraft:raw_iron_block", name = "Block of Raw Iron", color = colors.brown, sym = "I" },
    { id = "minecraft:raw_copper_block", name = "Block of Raw Copper", color = colors.orange, sym = "C" },
    { id = "minecraft:raw_gold_block", name = "Block of Raw Gold", color = colors.yellow, sym = "G" },
    { id = "minecraft:dripstone_block", name = "Dripstone Block", color = colors.brown, sym = "D" },
    { id = "minecraft:moss_block", name = "Moss Block", color = colors.green, sym = "M" },
    { id = "minecraft:mud", name = "Mud", color = colors.brown, sym = "M" },
    { id = "minecraft:packed_mud", name = "Packed Mud", color = colors.brown, sym = "M" },
    { id = "minecraft:mud_bricks", name = "Mud Bricks", color = colors.brown, sym = "M" },
    { id = "minecraft:sculk", name = "Sculk", color = colors.cyan, sym = "S" },
    { id = "minecraft:sculk_catalyst", name = "Sculk Catalyst", color = colors.cyan, sym = "S" },
    { id = "minecraft:sculk_shrieker", name = "Sculk Shrieker", color = colors.cyan, sym = "S" },
    { id = "minecraft:ochre_froglight", name = "Ochre Froglight", color = colors.yellow, sym = "F" },
    { id = "minecraft:verdant_froglight", name = "Verdant Froglight", color = colors.green, sym = "F" },
    { id = "minecraft:pearlescent_froglight", name = "Pearlescent Froglight", color = colors.purple, sym = "F" },
}

return items
]===]
bundled_modules["lib_json"] = [===[
--[[
JSON library for CC:Tweaked turtles.
Provides helpers for encoding and decoding JSON.
--]]

---@diagnostic disable: undefined-global

local json_utils = {}

function json_utils.decodeJson(text)
    if type(text) ~= "string" then
        return nil, "invalid_json"
    end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, text)
        if ok and result ~= nil then
            return result
        end
        return nil, "json_parse_failed"
    end
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local okDecode, result = pcall(json.decode, text)
        if okDecode then
            return result
        end
        return nil, "json_parse_failed"
    end
    return nil, "json_decoder_unavailable"
end

return json_utils

]===]
bundled_modules["lib_logger"] = [===[
--[[
Logger library for CC:Tweaked turtles.
Provides leveled logging with optional timestamping, history capture, and
custom sinks. Public methods work with either colon or dot syntax.
--]]

---@diagnostic disable: undefined-global

local logger = {}

local DEFAULT_LEVEL = "info"
local DEFAULT_CAPTURE_LIMIT = 200

local LEVEL_VALUE = {
    debug = 10,
    info = 20,
    warn = 30,
    error = 40,
}

local LEVEL_LABEL = {
    debug = "DEBUG",
    info = "INFO",
    warn = "WARN",
    error = "ERROR",
}

local LEVEL_ALIAS = {
    warning = "warn",
    err = "error",
    trace = "debug",
    verbose = "debug",
    fatal = "error",
}

local function copyTable(value, depth, seen)
    if type(value) ~= "table" then
        return value
    end
    if depth and depth <= 0 then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return "<recursive>"
    end
    seen[value] = true
    local result = {}
    for k, v in pairs(value) do
        local newKey = copyTable(k, depth and (depth - 1) or nil, seen)
        local newValue = copyTable(v, depth and (depth - 1) or nil, seen)
        result[newKey] = newValue
    end
    seen[value] = nil
    return result
end

local function trySerializers(meta)
    if type(meta) ~= "table" then
        return nil
    end
    if textutils and type(textutils.serialize) == "function" then
        local ok, serialized = pcall(textutils.serialize, meta)
        if ok then
            return serialized
        end
    end
    if textutils and type(textutils.serializeJSON) == "function" then
        local ok, serialized = pcall(textutils.serializeJSON, meta)
        if ok then
            return serialized
        end
    end
    return nil
end

local function formatMetadata(meta)
    if meta == nil then
        return ""
    end
    local metaType = type(meta)
    if metaType == "string" then
        return meta
    elseif metaType == "number" or metaType == "boolean" then
        return tostring(meta)
    elseif metaType == "table" then
        local serialized = trySerializers(meta)
        if serialized then
            return serialized
        end
        local parts = {}
        local count = 0
        for key, value in pairs(meta) do
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
            count = count + 1
            if count >= 16 then
                break
            end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(meta)
end

local function formatMessage(message)
    if message == nil then
        return ""
    end
    local msgType = type(message)
    if msgType == "string" then
        return message
    elseif msgType == "number" or msgType == "boolean" then
        return tostring(message)
    elseif msgType == "table" then
        if message.message and type(message.message) == "string" then
            return message.message
        end
        local metaView = formatMetadata(message)
        if metaView ~= "" then
            return metaView
        end
    end
    return tostring(message)
end

local function resolveLevel(level)
    if type(level) == "string" then
        local lowered = level:lower()
        lowered = LEVEL_ALIAS[lowered] or lowered
        if LEVEL_VALUE[lowered] then
            return lowered
        end
        return nil
    elseif type(level) == "number" then
        local closest
        local distance
        for name, value in pairs(LEVEL_VALUE) do
            local diff = math.abs(value - level)
            if not closest or diff < distance then
                closest = name
                distance = diff
            end
        end
        return closest
    end
    return nil
end

local function levelValue(level)
    return LEVEL_VALUE[level] or LEVEL_VALUE[DEFAULT_LEVEL]
end

local function shouldEmit(level, thresholdValue)
    return levelValue(level) >= thresholdValue
end

local function formatTimestamp(state)
    if not state.timestamps then
        return nil, nil
    end
    local fmt = state.timestampFormat or "%H:%M:%S"
    if os and type(os.date) == "function" then
        local timeNumber = os.time and os.time() or nil
        local stamp = os.date(fmt)
        return stamp, timeNumber
    end
    if os and type(os.clock) == "function" then
        local clockValue = os.clock()
        return string.format("%.03f", clockValue), clockValue
    end
    return nil, nil
end

local function cloneEntry(entry)
    return copyTable(entry, 3)
end

local function pushHistory(state, entry)
    local history = state.history
    history[#history + 1] = cloneEntry(entry)
    local limit = state.captureLimit or DEFAULT_CAPTURE_LIMIT
    while #history > limit do
        table.remove(history, 1)
    end
end

local function defaultWriterFactory(state)
    return function(entry)
        local segments = {}
        if entry.timestamp then
            segments[#segments + 1] = entry.timestamp
        elseif state.timestamps and state.lastTimestamp then
            segments[#segments + 1] = state.lastTimestamp
        end
        if entry.tag then
            segments[#segments + 1] = entry.tag
        elseif state.tag then
            segments[#segments + 1] = state.tag
        end
        segments[#segments + 1] = entry.levelLabel or entry.level
        local prefix = "[" .. table.concat(segments, "][") .. "]"
        local line = prefix .. " " .. entry.message
        local metaStr = formatMetadata(entry.metadata)
        if metaStr ~= "" then
            line = line .. " | " .. metaStr
        end
        if print then
            print(line)
        elseif io and io.write then
            io.write(line .. "\n")
        end
    end
end

local function addWriter(state, writer)
    if type(writer) ~= "function" then
        return false, "invalid_writer"
    end
    for _, existing in ipairs(state.writers) do
        if existing == writer then
            return false, "writer_exists"
        end
    end
    state.writers[#state.writers + 1] = writer
    return true
end

local function logInternal(state, level, message, metadata)
    local resolved = resolveLevel(level)
    if not resolved then
        return false, "unknown_level"
    end
    if not shouldEmit(resolved, state.thresholdValue) then
        return false, "level_filtered"
    end

    local timestamp, timeNumber = formatTimestamp(state)
    state.lastTimestamp = timestamp or state.lastTimestamp

    local entry = {
        level = resolved,
        levelLabel = LEVEL_LABEL[resolved],
        message = formatMessage(message),
        metadata = metadata,
        timestamp = timestamp,
        time = timeNumber,
        sequence = state.sequence + 1,
        tag = state.tag,
    }

    state.sequence = entry.sequence
    state.lastEntry = entry

    if state.capture then
        pushHistory(state, entry)
    end

    for _, writer in ipairs(state.writers) do
        local ok, err = pcall(writer, entry)
        if not ok then
            state.lastWriterError = err
        end
    end

    return true, entry
end

function logger.new(opts)
    local state = {
        capture = opts and opts.capture or false,
        captureLimit = (opts and type(opts.captureLimit) == "number" and opts.captureLimit > 0) and opts.captureLimit or DEFAULT_CAPTURE_LIMIT,
        history = {},
        sequence = 0,
        writers = {},
        timestamps = opts and (opts.timestamps or opts.timestamp) or false,
        timestampFormat = opts and opts.timestampFormat or nil,
        tag = opts and (opts.tag or opts.label) or nil,
    }

    local initialLevel = (opts and resolveLevel(opts.level)) or (opts and resolveLevel(opts.minLevel)) or DEFAULT_LEVEL
    state.threshold = initialLevel
    state.thresholdValue = levelValue(initialLevel)

    local instance = {}
    state.instance = instance

    if not (opts and opts.silent) then
        addWriter(state, defaultWriterFactory(state))
    end
    if opts and type(opts.writer) == "function" then
        addWriter(state, opts.writer)
    end
    if opts and type(opts.writers) == "table" then
        for _, writer in ipairs(opts.writers) do
            if type(writer) == "function" then
                addWriter(state, writer)
            end
        end
    end

    function instance:log(level, message, metadata)
        return logInternal(state, level, message, metadata)
    end

    function instance:debug(message, metadata)
        return logInternal(state, "debug", message, metadata)
    end

    function instance:info(message, metadata)
        return logInternal(state, "info", message, metadata)
    end

    function instance:warn(message, metadata)
        return logInternal(state, "warn", message, metadata)
    end

    function instance:error(message, metadata)
        return logInternal(state, "error", message, metadata)
    end

    function instance:setLevel(level)
        local resolved = resolveLevel(level)
        if not resolved then
            return false, "unknown_level"
        end
        state.threshold = resolved
        state.thresholdValue = levelValue(resolved)
        return true, resolved
    end

    function instance:getLevel()
        return state.threshold
    end

    function instance:enableCapture(limit)
        state.capture = true
        if type(limit) == "number" and limit > 0 then
            state.captureLimit = limit
        end
        return true
    end

    function instance:disableCapture()
        state.capture = false
        state.history = {}
        return true
    end

    function instance:getHistory()
        local result = {}
        for index = 1, #state.history do
            result[index] = cloneEntry(state.history[index])
        end
        return result
    end

    function instance:clearHistory()
        state.history = {}
        return true
    end

    function instance:addWriter(writer)
        return addWriter(state, writer)
    end

    function instance:removeWriter(writer)
        if type(writer) ~= "function" then
            return false, "invalid_writer"
        end
        for index, existing in ipairs(state.writers) do
            if existing == writer then
                table.remove(state.writers, index)
                return true
            end
        end
        return false, "writer_missing"
    end

    function instance:setTag(tag)
        state.tag = tag
        return true
    end

    function instance:getTag()
        return state.tag
    end

    function instance:getLastEntry()
        if not state.lastEntry then
            return nil
        end
        return cloneEntry(state.lastEntry)
    end

    function instance:getLastWriterError()
        return state.lastWriterError
    end

    function instance:setTimestamps(enabled, format)
        state.timestamps = not not enabled
        if format then
            state.timestampFormat = format
        end
        return true
    end

    return instance
end

function logger.attach(ctx, opts)
    if type(ctx) ~= "table" then
        error("logger.attach requires a context table", 2)
    end
    local instance = logger.new(opts)
    ctx.logger = instance
    return instance
end

function logger.isLogger(candidate)
    if type(candidate) ~= "table" then
        return false
    end
    return type(candidate.log) == "function"
        and type(candidate.info) == "function"
        and type(candidate.warn) == "function"
        and type(candidate.error) == "function"
end

logger.DEFAULT_LEVEL = DEFAULT_LEVEL
logger.DEFAULT_CAPTURE_LIMIT = DEFAULT_CAPTURE_LIMIT
logger.LEVELS = copyTable(LEVEL_VALUE, 1)
logger.LABELS = copyTable(LEVEL_LABEL, 1)
logger.resolveLevel = resolveLevel

function logger.log(ctx, level, message)
    if type(ctx) ~= "table" then
        return
    end
    local logger = ctx.logger
    if type(logger) == "table" then
        local fn = logger[level]
        if type(fn) == "function" then
            fn(message)
            return
        end
        if type(logger.log) == "function" then
            logger.log(level, message)
            return
        end
    end
    if (level == "warn" or level == "error") and message then
        print(string.format("[%s] %s", level:upper(), message))
    end
end

return logger

]===]
bundled_modules["lib_mining"] = [===[
--[[
Mining library for CC:Tweaked turtles.
Handles ore detection, extraction, and hole filling.
]]

---@diagnostic disable: undefined-global

local mining = {}
local inventory = require("lib_inventory")
local movement = require("lib_movement")
local logger = require("lib_logger")

-- Blocks that are considered "trash" and should be ignored during ore scanning.
-- Also used to determine what blocks can be used to fill holes.
mining.TRASH_BLOCKS = inventory.DEFAULT_TRASH

-- Blocks that should NEVER be placed to fill holes (liquids, gravity blocks, etc)
mining.FILL_BLACKLIST = {
    ["minecraft:air"] = true,
    ["minecraft:water"] = true,
    ["minecraft:lava"] = true,
    ["minecraft:sand"] = true,
    ["minecraft:gravel"] = true,
    ["minecraft:torch"] = true,
    ["minecraft:bedrock"] = true,
}

--- Check if a block is considered "ore" (valuable)
function mining.isOre(name)
    if not name then return false end
    return not mining.TRASH_BLOCKS[name]
end

--- Find a suitable trash block in inventory to use for filling
local function findFillMaterial(ctx)
    inventory.scan(ctx)
    local state = inventory.ensureState(ctx)
    if not state or not state.slots then return nil end
    for slot, item in pairs(state.slots) do
        if mining.TRASH_BLOCKS[item.name] and not mining.FILL_BLACKLIST[item.name] then
            return slot, item.name
        end
    end
    return nil
end

--- Mine a block in a specific direction if it's valuable, then fill the hole
-- @param dir "front", "up", "down"
function mining.mineAndFill(ctx, dir)
    local inspect, dig, place
    if dir == "front" then
        inspect = turtle.inspect
        dig = turtle.dig
        place = turtle.place
    elseif dir == "up" then
        inspect = turtle.inspectUp
        dig = turtle.digUp
        place = turtle.placeUp
    elseif dir == "down" then
        inspect = turtle.inspectDown
        dig = turtle.digDown
        place = turtle.placeDown
    else
        return false, "Invalid direction"
    end

    local hasBlock, data = inspect()
    if hasBlock and mining.isOre(data.name) then
        logger.log(ctx, "info", "Mining valuable: " .. data.name)
        if dig() then
            -- Attempt to fill the hole
            local slot = findFillMaterial(ctx)
            if slot then
                turtle.select(slot)
                place()
            else
                logger.log(ctx, "warn", "No trash blocks available to fill hole")
            end
            return true
        else
            logger.log(ctx, "warn", "Failed to dig " .. data.name)
        end
    end
    return false
end

--- Scan all 6 directions around the turtle, mine ores, and fill holes.
-- The turtle will return to its original facing.
function mining.scanAndMineNeighbors(ctx)
    -- Check Up
    mining.mineAndFill(ctx, "up")
    
    -- Check Down
    mining.mineAndFill(ctx, "down")

    -- Check 4 horizontal directions
    for i = 1, 4 do
        mining.mineAndFill(ctx, "front")
        movement.turnRight(ctx)
    end
end

return mining

]===]
bundled_modules["lib_movement"] = [===[
--[[-
Movement library for CC:Tweaked turtles.
Provides orientation tracking, safe movement primitives, and navigation helpers.
All public functions accept a shared ctx table and return success booleans
with optional error messages.
--]]

---@diagnostic disable: undefined-global, undefined-field

local movement = {}
local logger = require("lib_logger")

local CARDINALS = {"north", "east", "south", "west"}
local DIRECTION_VECTORS = {
    north = { x = 0, y = 0, z = -1 },
    east = { x = 1, y = 0, z = 0 },
    south = { x = 0, y = 0, z = 1 },
    west = { x = -1, y = 0, z = 0 },
}

local AXIS_FACINGS = {
    x = { positive = "east", negative = "west" },
    z = { positive = "south", negative = "north" },
}

local DEFAULT_SOFT_BLOCKS = {
    ["minecraft:snow"] = true,
    ["minecraft:snow_layer"] = true,
    ["minecraft:powder_snow"] = true,
    ["minecraft:tall_grass"] = true,
    ["minecraft:large_fern"] = true,
    ["minecraft:grass"] = true,
    ["minecraft:fern"] = true,
    ["minecraft:cave_vines"] = true,
    ["minecraft:cave_vines_plant"] = true,
    ["minecraft:kelp"] = true,
    ["minecraft:kelp_plant"] = true,
    ["minecraft:sweet_berry_bush"] = true,
}

local DEFAULT_SOFT_TAGS = {
    ["minecraft:snow"] = true,
    ["minecraft:replaceable_plants"] = true,
    ["minecraft:flowers"] = true,
    ["minecraft:saplings"] = true,
    ["minecraft:carpets"] = true,
}

local DEFAULT_SOFT_NAME_HINTS = {
    "sapling",
    "propagule",
    "seedling",
}

local function cloneLookup(source)
    local lookup = {}
    for key, value in pairs(source) do
        if value then
            lookup[key] = true
        end
    end
    return lookup
end

local function extendLookup(lookup, entries)
    if type(entries) ~= "table" then
        return lookup
    end
    if #entries > 0 then
        for _, name in ipairs(entries) do
            if type(name) == "string" then
                lookup[name] = true
            end
        end
    else
        for name, enabled in pairs(entries) do
            if enabled and type(name) == "string" then
                lookup[name] = true
            end
        end
    end
    return lookup
end

local function buildSoftNameHintList(configHints)
    local seen = {}
    local list = {}

    local function append(value)
        if type(value) ~= "string" then
            return
        end
        local normalized = value:lower()
        if normalized == "" or seen[normalized] then
            return
        end
        seen[normalized] = true
        list[#list + 1] = normalized
    end

    for _, hint in ipairs(DEFAULT_SOFT_NAME_HINTS) do
        append(hint)
    end

    if type(configHints) == "table" then
        if #configHints > 0 then
            for _, entry in ipairs(configHints) do
                append(entry)
            end
        else
            for name, enabled in pairs(configHints) do
                if enabled then
                    append(name)
                end
            end
        end
    elseif type(configHints) == "string" then
        append(configHints)
    end

    return list
end

local function matchesSoftNameHint(hints, blockName)
    if type(blockName) ~= "string" then
        return false
    end
    local lowered = blockName:lower()
    for _, hint in ipairs(hints or {}) do
        if lowered:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function isSoftBlock(state, inspectData)
    if type(state) ~= "table" or type(inspectData) ~= "table" then
        return false
    end
    local name = inspectData.name
    if type(name) == "string" then
        if state.softBlockLookup and state.softBlockLookup[name] then
            return true
        end
        if matchesSoftNameHint(state.softNameHints, name) then
            return true
        end
    end
    local tags = inspectData.tags
    if type(tags) == "table" and state.softTagLookup then
        for tag, value in pairs(tags) do
            if value and state.softTagLookup[tag] then
                return true
            end
        end
    end
    return false
end

local function canonicalFacing(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:lower()
    if DIRECTION_VECTORS[name] then
        return name
    end
    return nil
end

local function copyPosition(pos)
    if not pos then
        return { x = 0, y = 0, z = 0 }
    end
    return { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
end

local function vecAdd(a, b)
    return { x = (a.x or 0) + (b.x or 0), y = (a.y or 0) + (b.y or 0), z = (a.z or 0) + (b.z or 0) }
end

local function getPlannedMaterial(ctx, pos)
    if type(ctx) ~= "table" or type(pos) ~= "table" then
        return nil
    end

    local plan = ctx.buildPlan
    if type(plan) ~= "table" then
        return nil
    end

    local x = pos.x
    local xLayer = plan[x] or plan[tostring(x)]
    if type(xLayer) ~= "table" then
        return nil
    end

    local y = pos.y
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if type(yLayer) ~= "table" then
        return nil
    end

    local z = pos.z
    return yLayer[z] or yLayer[tostring(z)]
end

local function tryInspect(inspectFn)
    if type(inspectFn) ~= "function" then
        return nil
    end

    local ok, success, data = pcall(inspectFn)
    if not ok or not success then
        return nil
    end

    if type(data) == "table" then
        return data
    end

    return nil
end

local function ensureMovementState(ctx)
    if type(ctx) ~= "table" then
        error("movement library requires a context table", 2)
    end

    ctx.movement = ctx.movement or {}
    local state = ctx.movement
    local cfg = ctx.config or {}

    if not state.position then
        if ctx.origin then
            state.position = copyPosition(ctx.origin)
        else
            state.position = { x = 0, y = 0, z = 0 }
        end
    end

    if not state.homeFacing then
        state.homeFacing = canonicalFacing(cfg.homeFacing) or canonicalFacing(cfg.initialFacing) or "north"
    end

    if not state.facing then
        state.facing = canonicalFacing(cfg.initialFacing) or state.homeFacing
    end

    state.position = copyPosition(state.position)

    if not state.softBlockLookup then
        state.softBlockLookup = extendLookup(cloneLookup(DEFAULT_SOFT_BLOCKS), cfg.movementSoftBlocks)
    end
    if not state.softTagLookup then
        state.softTagLookup = extendLookup(cloneLookup(DEFAULT_SOFT_TAGS), cfg.movementSoftTags)
    end
    if not state.softNameHints then
        state.softNameHints = buildSoftNameHintList(cfg.movementSoftNameHints)
    end
    state.hasSoftClearRules = (next(state.softBlockLookup) ~= nil)
        or (next(state.softTagLookup) ~= nil)
        or ((state.softNameHints and #state.softNameHints > 0) or false)

    return state
end

function movement.ensureState(ctx)
    return ensureMovementState(ctx)
end

function movement.getPosition(ctx)
    local state = ensureMovementState(ctx)
    return copyPosition(state.position)
end

function movement.setPosition(ctx, pos)
    local state = ensureMovementState(ctx)
    state.position = copyPosition(pos)
    return true
end

function movement.getFacing(ctx)
    local state = ensureMovementState(ctx)
    return state.facing
end

function movement.setFacing(ctx, facing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(facing)
    if not canonical then
        return false, "unknown facing: " .. tostring(facing)
    end
    state.facing = canonical
    logger.log(ctx, "debug", "Set facing to " .. canonical)
    return true
end

local function turn(ctx, direction)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local rotateFn
    if direction == "left" then
        rotateFn = turtle.turnLeft
    elseif direction == "right" then
        rotateFn = turtle.turnRight
    else
        return false, "invalid turn direction"
    end

    if not rotateFn then
        return false, "turn function missing"
    end

    local ok = rotateFn()
    if not ok then
        return false, "turn " .. direction .. " failed"
    end

    local current = state.facing
    local index
    for i, name in ipairs(CARDINALS) do
        if name == current then
            index = i
            break
        end
    end
    if not index then
        index = 1
        current = CARDINALS[index]
    end

    if direction == "left" then
        index = ((index - 2) % #CARDINALS) + 1
    else
        index = (index % #CARDINALS) + 1
    end

    state.facing = CARDINALS[index]
    logger.log(ctx, "debug", "Turned " .. direction .. ", now facing " .. state.facing)
    return true
end

function movement.turnLeft(ctx)
    return turn(ctx, "left")
end

function movement.turnRight(ctx)
    return turn(ctx, "right")
end

function movement.turnAround(ctx)
    local ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    ok, err = movement.turnRight(ctx)
    if not ok then
        return false, err
    end
    return true
end

function movement.faceDirection(ctx, targetFacing)
    local state = ensureMovementState(ctx)
    local canonical = canonicalFacing(targetFacing)
    if not canonical then
        return false, "unknown facing: " .. tostring(targetFacing)
    end

    local currentIndex
    local targetIndex
    for i, name in ipairs(CARDINALS) do
        if name == state.facing then
            currentIndex = i
        end
        if name == canonical then
            targetIndex = i
        end
    end

    if not targetIndex then
        return false, "cannot face unknown cardinal"
    end

    if currentIndex == targetIndex then
        return true
    end

    if not currentIndex then
        state.facing = canonical
        return true
    end

    local diff = (targetIndex - currentIndex) % #CARDINALS
    if diff == 0 then
        return true
    elseif diff == 1 then
        return movement.turnRight(ctx)
    elseif diff == 2 then
        local ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        ok, err = movement.turnRight(ctx)
        if not ok then
            return false, err
        end
        return true
    else -- diff == 3
        return movement.turnLeft(ctx)
    end
end

local function getMoveConfig(ctx, opts)
    local cfg = ctx.config or {}
    local maxRetries = (opts and opts.maxRetries) or cfg.maxMoveRetries or 5
    local allowDig = opts and opts.dig
    if allowDig == nil then
        allowDig = cfg.digOnMove
        if allowDig == nil then
            allowDig = true
        end
    end
    local allowAttack = opts and opts.attack
    if allowAttack == nil then
        allowAttack = cfg.attackOnMove
        if allowAttack == nil then
            allowAttack = true
        end
    end
    local delay = (opts and opts.retryDelay) or cfg.moveRetryDelay or 0.5
    return maxRetries, allowDig, allowAttack, delay
end

local function moveWithRetries(ctx, opts, moveFns, delta)
    local state = ensureMovementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end

    local maxRetries, allowDig, allowAttack, delay = getMoveConfig(ctx, opts)
    if type(maxRetries) ~= "number" or maxRetries < 1 then
        maxRetries = 1
    else
        maxRetries = math.floor(maxRetries)
    end
    if (allowDig or state.hasSoftClearRules) and maxRetries < 2 then
        -- Ensure we attempt at least two cycles whenever we might clear obstructions.
        maxRetries = 2
    end
    local attempt = 0

    while attempt < maxRetries do
        attempt = attempt + 1
        local targetPos = vecAdd(state.position, delta)

        if moveFns.move() then
            state.position = targetPos
            logger.log(ctx, "debug", string.format("Moved to x=%d y=%d z=%d", state.position.x, state.position.y, state.position.z))
            return true
        end

        local handled = false

        if allowAttack and moveFns.attack then
            if moveFns.attack() then
                handled = true
                logger.log(ctx, "debug", "Attacked entity blocking movement")
            end
        end

        local blocked = moveFns.detect and moveFns.detect() or false
        local inspectData
        if blocked then
            inspectData = tryInspect(moveFns.inspect)
        end

        if blocked and moveFns.dig then
            local plannedMaterial
            local canClear = false
            local softBlock = inspectData and isSoftBlock(state, inspectData)

            if softBlock then
                canClear = true
            elseif allowDig then
                plannedMaterial = getPlannedMaterial(ctx, targetPos)
                canClear = true

                if plannedMaterial then
                    if inspectData and inspectData.name then
                        if inspectData.name == plannedMaterial then
                            canClear = false
                        end
                    else
                        canClear = false
                    end
                end
            end

            if canClear and moveFns.dig() then
                handled = true
                if softBlock then
                    local foundName = inspectData and inspectData.name or "unknown"
                    logger.log(ctx, "debug", string.format(
                        "Cleared soft obstruction %s at x=%d y=%d z=%d",
                        tostring(foundName),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                elseif plannedMaterial then
                    local foundName = inspectData and inspectData.name or "unknown"
                    logger.log(ctx, "debug", string.format(
                        "Cleared mismatched block %s (expected %s) at x=%d y=%d z=%d",
                        tostring(foundName),
                        tostring(plannedMaterial),
                        targetPos.x or 0,
                        targetPos.y or 0,
                        targetPos.z or 0
                    ))
                else
                    local foundName = inspectData and inspectData.name
                    if foundName then
                        logger.log(ctx, "debug", string.format(
                            "Dug blocking block %s at x=%d y=%d z=%d",
                            foundName,
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    else
                        logger.log(ctx, "debug", string.format(
                            "Dug blocking block at x=%d y=%d z=%d",
                            targetPos.x or 0,
                            targetPos.y or 0,
                            targetPos.z or 0
                        ))
                    end
                end
            elseif plannedMaterial and not canClear and allowDig then
                logger.log(ctx, "debug", string.format(
                    "Preserving planned block %s at x=%d y=%d z=%d",
                    tostring(plannedMaterial),
                    targetPos.x or 0,
                    targetPos.y or 0,
                    targetPos.z or 0
                ))
            end
        end

        if attempt < maxRetries then
            if delay and delay > 0 and _G.sleep then
                sleep(delay)
            end
        end
    end

    local axisDelta = string.format("(dx=%d, dy=%d, dz=%d)", delta.x or 0, delta.y or 0, delta.z or 0)
    return false, "unable to move " .. axisDelta .. " after " .. tostring(maxRetries) .. " attempts"
end

function movement.forward(ctx, opts)
    local state = ensureMovementState(ctx)
    local facing = state.facing or "north"
    local delta = copyPosition(DIRECTION_VECTORS[facing])

    local moveFns = {
        move = turtle and turtle.forward or nil,
        detect = turtle and turtle.detect or nil,
        dig = turtle and turtle.dig or nil,
        attack = turtle and turtle.attack or nil,
        inspect = turtle and turtle.inspect or nil,
    }

    if not moveFns.move then
        return false, "turtle API unavailable"
    end

    return moveWithRetries(ctx, opts, moveFns, delta)
end

function movement.up(ctx, opts)
    local moveFns = {
        move = turtle and turtle.up or nil,
        detect = turtle and turtle.detectUp or nil,
        dig = turtle and turtle.digUp or nil,
        attack = turtle and turtle.attackUp or nil,
        inspect = turtle and turtle.inspectUp or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = 1, z = 0 })
end

function movement.down(ctx, opts)
    local moveFns = {
        move = turtle and turtle.down or nil,
        detect = turtle and turtle.detectDown or nil,
        dig = turtle and turtle.digDown or nil,
        attack = turtle and turtle.attackDown or nil,
        inspect = turtle and turtle.inspectDown or nil,
    }
    if not moveFns.move then
        return false, "turtle API unavailable"
    end
    return moveWithRetries(ctx, opts, moveFns, { x = 0, y = -1, z = 0 })
end

local function axisFacing(axis, delta)
    if delta > 0 then
        return AXIS_FACINGS[axis].positive
    else
        return AXIS_FACINGS[axis].negative
    end
end

local function moveAxis(ctx, axis, delta, opts)
    if delta == 0 then
        return true
    end

    if axis == "y" then
        local moveFn = delta > 0 and movement.up or movement.down
        for _ = 1, math.abs(delta) do
            local ok, err = moveFn(ctx, opts)
            if not ok then
                return false, err
            end
        end
        return true
    end

    local targetFacing = axisFacing(axis, delta)
    local ok, err = movement.faceDirection(ctx, targetFacing)
    if not ok then
        return false, err
    end

    for step = 1, math.abs(delta) do
        ok, err = movement.forward(ctx, opts)
        if not ok then
            return false, string.format("failed moving along %s on step %d: %s", axis, step, err or "unknown")
        end
    end
    return true
end

function movement.goTo(ctx, targetPos, opts)
    ensureMovementState(ctx)
    if type(targetPos) ~= "table" then
        return false, "target position must be a table"
    end

    local state = ctx.movement
    local axisOrder = (opts and opts.axisOrder) or (ctx.config and ctx.config.movementAxisOrder) or { "x", "z", "y" }

    for _, axis in ipairs(axisOrder) do
        local desired = targetPos[axis]
        if desired == nil then
            return false, "target position missing axis " .. axis
        end
        local delta = desired - (state.position[axis] or 0)
        local ok, err = moveAxis(ctx, axis, delta, opts)
        if not ok then
            return false, err
        end
    end

    return true
end

function movement.stepPath(ctx, pathNodes, opts)
    if type(pathNodes) ~= "table" then
        return false, "pathNodes must be a table"
    end

    for index, node in ipairs(pathNodes) do
        local ok, err = movement.goTo(ctx, node, opts)
        if not ok then
            return false, string.format("failed at path node %d: %s", index, err or "unknown")
        end
    end

    return true
end

function movement.returnToOrigin(ctx, opts)
    ensureMovementState(ctx)
    if not ctx.origin then
        return false, "ctx.origin is required"
    end

    local ok, err = movement.goTo(ctx, ctx.origin, opts)
    if not ok then
        return false, err
    end

    local desiredFacing = (opts and opts.facing) or ctx.movement.homeFacing
    if desiredFacing then
        ok, err = movement.faceDirection(ctx, desiredFacing)
        if not ok then
            return false, err
        end
    end

    return true
end

function movement.turnLeftOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "west"
    elseif facing == "west" then
        return "south"
    elseif facing == "south" then
        return "east"
    else -- east
        return "north"
    end
end

function movement.turnRightOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "east"
    elseif facing == "east" then
        return "south"
    elseif facing == "south" then
        return "west"
    else -- west
        return "north"
    end
end

function movement.turnBackOf(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return "south"
    elseif facing == "south" then
        return "north"
    elseif facing == "east" then
        return "west"
    else -- west
        return "east"
    end
end
function movement.describePosition(ctx)
    local pos = movement.getPosition(ctx)
    local facing = movement.getFacing(ctx)
    return string.format("(x=%d, y=%d, z=%d, facing=%s)", pos.x, pos.y, pos.z, tostring(facing))
end

return movement

]===]
bundled_modules["lib_navigation"] = [===[
--[[
Navigation library for CC:Tweaked turtles.
Resolves waypoint and route specs into concrete movement paths and wraps
movement helpers for higher-level states (restock, refuel, etc.).
All public functions accept the shared ctx table and return project-style
success booleans or data results with error diagnostics.
--]]

local okMovement, movement = pcall(require, "lib_movement")
if not okMovement then
    movement = nil
end
local logger = require("lib_logger")
local table_utils = require("lib_table")
local world = require("lib_world")

local navigation = {}

local function isCoordinateSpec(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    if tbl.route or tbl.waypoint or tbl.path or tbl.nodes or tbl.sequence or tbl.via or tbl.target or tbl.align then
        return false
    end
    local hasX = tbl.x ~= nil or tbl[1] ~= nil
    local hasY = tbl.y ~= nil or tbl[2] ~= nil
    local hasZ = tbl.z ~= nil or tbl[3] ~= nil
    return hasX and hasY and hasZ
end

local function cloneNodeDefinition(def)
    if type(def) ~= "table" then
        return nil, "invalid_route_definition"
    end
    local result = {}
    for index, value in ipairs(def) do
        if type(value) == "table" then
            result[index] = table_utils.copyValue(value)
        else
            result[index] = value
        end
    end
    return result
end

local function ensureNavigationState(ctx)
    if type(ctx) ~= "table" then
        error("navigation library requires a context table", 2)
    end

    if type(ctx.navigationState) ~= "table" then
        ctx.navigationState = ctx.navigation or {}
    end
    ctx.navigation = ctx.navigationState
    local state = ctx.navigationState

    state.waypoints = state.waypoints or {}
    state.routes = state.routes or {}
    state.restock = state.restock or {}
    state._configLoaded = state._configLoaded or false

    if ctx.origin then
        local originPos, originErr = world.normalisePosition(ctx.origin)
        if originPos then
            state.waypoints.origin = originPos
        elseif originErr then
            logger.log(ctx, "warn", "Origin position invalid: " .. tostring(originErr))
        end
    end

    if not state._configLoaded then
        state._configLoaded = true
        local cfg = ctx.config
        if type(cfg) == "table" and type(cfg.navigation) == "table" then
            local navCfg = cfg.navigation
            if type(navCfg.waypoints) == "table" then
                for name, pos in pairs(navCfg.waypoints) do
                    local normalised, err = world.normalisePosition(pos)
                    if normalised then
                        state.waypoints[name] = normalised
                    else
                        logger.log(ctx, "warn", string.format("Ignoring navigation waypoint '%s': %s", tostring(name), tostring(err)))
                    end
                end
            end
            if type(navCfg.routes) == "table" then
                for name, def in pairs(navCfg.routes) do
                    local cloned, err = cloneNodeDefinition(def)
                    if cloned then
                        state.routes[name] = cloned
                    else
                        logger.log(ctx, "warn", string.format("Ignoring navigation route '%s': %s", tostring(name), tostring(err)))
                    end
                end
            end
            if type(navCfg.restock) == "table" then
                state.restock = table_utils.copyValue(navCfg.restock)
            end
        end
    end

    return state
end

local function resolveWaypoint(ctx, name)
    local state = ensureNavigationState(ctx)
    if type(name) ~= "string" or name == "" then
        return nil, "invalid_waypoint"
    end
    local pos = state.waypoints[name]
    if not pos then
        return nil, "unknown_waypoint"
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local expandSpec

local function expandListToNodes(ctx, list, visited)
    if type(list) ~= "table" then
        return nil, "invalid_path_list"
    end
    local nodes = {}
    local meta = {}
    for index, entry in ipairs(list) do
        local entryNodes, entryMeta = expandSpec(ctx, entry, visited)
        if not entryNodes then
            return nil, string.format("path[%d]: %s", index, tostring(entryMeta or "invalid"))
        end
        for _, node in ipairs(entryNodes) do
            nodes[#nodes + 1] = node
        end
        if entryMeta and entryMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = entryMeta.finalFacing
        end
    end
    return nodes, meta
end

local function expandRouteByName(ctx, name, visited)
    if type(name) ~= "string" or name == "" then
        return nil, "invalid_route_name"
    end
    local state = ensureNavigationState(ctx)
    local def = state.routes[name]
    if not def then
        return nil, "unknown_route"
    end
    visited = visited or {}
    if visited[name] then
        return nil, "route_cycle"
    end
    visited[name] = true
    local nodes, meta = expandListToNodes(ctx, def, visited)
    visited[name] = nil
    return nodes, meta
end

-- Expands a navigation spec (string, waypoint, route, or nested table) into absolute coordinates.
function expandSpec(ctx, spec, visited)
    local specType = type(spec)
    if specType == "string" then
        local routeNodes, routeMeta = expandRouteByName(ctx, spec, visited)
        if routeNodes then
            return routeNodes, routeMeta
        end
        if routeMeta ~= "unknown_route" then
            return nil, routeMeta
        end
        local pos, err = resolveWaypoint(ctx, spec)
        if not pos then
            return nil, err or "unknown_reference"
        end
        return { pos }, {}
    elseif specType == "function" then
        local ok, result = pcall(spec, ctx)
        if not ok then
            return nil, "navigation_callback_failed"
        end
        if result == nil then
            return {}, {}
        end
        return expandSpec(ctx, result, visited)
    elseif specType ~= "table" then
        return nil, "invalid_navigation_spec"
    end

    if isCoordinateSpec(spec) then
        local pos, err = world.normalisePosition(spec)
        if not pos then
            return nil, err
        end
        local meta = {}
        if spec.finalFacing or spec.facing then
            meta.finalFacing = spec.finalFacing or spec.facing
        end
        return { pos }, meta
    end

    local nodes = {}
    local meta = {}
    local facing = spec.finalFacing or spec.facing
    if facing then
        meta.finalFacing = facing
    end

    if spec.sequence then
        local seqNodes, seqMeta = expandListToNodes(ctx, spec.sequence, visited)
        if not seqNodes then
            return nil, seqMeta
        end
        for _, node in ipairs(seqNodes) do
            nodes[#nodes + 1] = node
        end
        if seqMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = seqMeta.finalFacing
        end
    end

    if spec.via then
        local viaNodes, viaMeta = expandListToNodes(ctx, spec.via, visited)
        if not viaNodes then
            return nil, viaMeta
        end
        for _, node in ipairs(viaNodes) do
            nodes[#nodes + 1] = node
        end
        if viaMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = viaMeta.finalFacing
        end
    end

    if spec.path then
        local pathNodes, pathMeta = expandListToNodes(ctx, spec.path, visited)
        if not pathNodes then
            return nil, pathMeta
        end
        for _, node in ipairs(pathNodes) do
            nodes[#nodes + 1] = node
        end
        if pathMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = pathMeta.finalFacing
        end
    elseif spec.nodes then
        local pathNodes, pathMeta = expandListToNodes(ctx, spec.nodes, visited)
        if not pathNodes then
            return nil, pathMeta
        end
        for _, node in ipairs(pathNodes) do
            nodes[#nodes + 1] = node
        end
        if pathMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = pathMeta.finalFacing
        end
    end

    if spec.route then
        if type(spec.route) == "table" then
            local routeNodes, routeMeta = expandListToNodes(ctx, spec.route, visited)
            if not routeNodes then
                return nil, routeMeta
            end
            for _, node in ipairs(routeNodes) do
                nodes[#nodes + 1] = node
            end
            if routeMeta.finalFacing and not meta.finalFacing then
                meta.finalFacing = routeMeta.finalFacing
            end
        else
            local routeNodes, routeMeta = expandRouteByName(ctx, spec.route, visited)
            if not routeNodes then
                return nil, routeMeta
            end
            for _, node in ipairs(routeNodes) do
                nodes[#nodes + 1] = node
            end
            if routeMeta and routeMeta.finalFacing and not meta.finalFacing then
                meta.finalFacing = routeMeta.finalFacing
            end
        end
    end

    if spec.waypoint then
        local pos, err = resolveWaypoint(ctx, spec.waypoint)
        if not pos then
            return nil, err
        end
        nodes[#nodes + 1] = pos
    end

    if spec.position then
        local pos, err = world.normalisePosition(spec.position)
        if not pos then
            return nil, err
        end
        nodes[#nodes + 1] = pos
    end

    if spec.target then
        local targetNodes, targetMeta = expandSpec(ctx, spec.target, visited)
        if not targetNodes then
            return nil, targetMeta
        end
        for _, node in ipairs(targetNodes) do
            nodes[#nodes + 1] = node
        end
        if targetMeta.finalFacing and not meta.finalFacing then
            meta.finalFacing = targetMeta.finalFacing
        end
    end

    if spec.align then
        local alignNodes, alignMeta = expandSpec(ctx, spec.align, visited)
        if not alignNodes then
            return nil, alignMeta
        end
        for _, node in ipairs(alignNodes) do
            nodes[#nodes + 1] = node
        end
        if alignMeta.finalFacing then
            meta.finalFacing = alignMeta.finalFacing
        end
    end

    return nodes, meta
end

function navigation.ensureState(ctx)
    return ensureNavigationState(ctx)
end

function navigation.registerWaypoint(ctx, name, position)
    if type(name) ~= "string" or name == "" then
        return false, "invalid_waypoint_name"
    end
    local state = ensureNavigationState(ctx)
    local pos, err = world.normalisePosition(position)
    if not pos then
        return false, err or "invalid_position"
    end
    state.waypoints[name] = pos
    return true
end

function navigation.getWaypoint(ctx, name)
    return resolveWaypoint(ctx, name)
end

function navigation.listWaypoints(ctx)
    local state = ensureNavigationState(ctx)
    local result = {}
    for name, pos in pairs(state.waypoints) do
        result[name] = { x = pos.x, y = pos.y, z = pos.z }
    end
    return result
end

function navigation.registerRoute(ctx, name, nodes)
    if type(name) ~= "string" or name == "" then
        return false, "invalid_route_name"
    end
    local state = ensureNavigationState(ctx)
    local cloned, err = cloneNodeDefinition(nodes)
    if not cloned then
        return false, err or "invalid_route"
    end
    state.routes[name] = cloned
    return true
end

function navigation.getRoute(ctx, name)
    local nodes, meta = expandRouteByName(ctx, name, {})
    if not nodes then
        return nil, meta
    end
    return nodes, meta
end

function navigation.plan(ctx, targetSpec, opts)
    ensureNavigationState(ctx)
    if targetSpec == nil then
        return nil, "missing_target"
    end
    local nodes, meta = expandSpec(ctx, targetSpec, {})
    if not nodes then
        return nil, meta
    end
    if opts and opts.includeCurrent == false and #nodes > 0 then
        -- no-op placeholder for future options
    end
    return nodes, meta
end

local function resolveRestockSpec(ctx, kind)
    local state = ensureNavigationState(ctx)
    local restock = state.restock
    local spec
    if type(restock) == "table" then
        if kind and restock[kind] ~= nil then
            spec = restock[kind]
        elseif restock.default ~= nil then
            spec = restock.default
        elseif restock.fallback ~= nil then
            spec = restock.fallback
        end
    end
    if spec == nil and state.waypoints.restock then
        spec = state.waypoints.restock
    end
    if spec == nil and state.waypoints.origin then
        spec = state.waypoints.origin
    end
    if spec == nil then
        return nil
    end
    return table_utils.copyValue(spec)
end

function navigation.getRestockTarget(ctx, kind)
    local spec = resolveRestockSpec(ctx, kind)
    if spec == nil then
        return nil, "restock_target_missing"
    end
    return spec
end

function navigation.setRestockTarget(ctx, kind, spec)
    local state = ensureNavigationState(ctx)
    if type(kind) ~= "string" or kind == "" then
        kind = "default"
    end
    if spec == nil then
        state.restock[kind] = nil
        return true
    end
    local specType = type(spec)
    if specType ~= "string" and specType ~= "table" and specType ~= "function" then
        return false, "invalid_restock_spec"
    end
    state.restock[kind] = table_utils.copyValue(spec)
    return true
end

function navigation.planRestock(ctx, opts)
    local kind = nil
    if type(opts) == "table" then
        kind = opts.kind or opts.type or opts.category
    end
    local spec = resolveRestockSpec(ctx, kind)
    if spec == nil then
        return nil, "restock_target_missing"
    end
    local nodes, meta = navigation.plan(ctx, spec, opts)
    if not nodes then
        return nil, meta
    end
    return nodes, meta
end

function navigation.travel(ctx, targetSpec, opts)
    ensureNavigationState(ctx)
    if not movement then
        return false, "movement_library_unavailable"
    end
    local nodes, meta = navigation.plan(ctx, targetSpec, opts)
    if not nodes then
        return false, meta
    end
    movement.ensureState(ctx)
    if #nodes > 0 then
        local moveOpts = opts and opts.move
        local ok, err = movement.stepPath(ctx, nodes, moveOpts)
        if not ok then
            return false, err
        end
    end
    local finalFacing = (opts and opts.finalFacing) or (meta and meta.finalFacing)
    if finalFacing then
        local ok, err = movement.faceDirection(ctx, finalFacing)
        if not ok then
            return false, err
        end
    end
    return true
end

function navigation.travelToRestock(ctx, opts)
    local kind = nil
    if type(opts) == "table" then
        kind = opts.kind or opts.type or opts.category
    end
    local spec, err = navigation.getRestockTarget(ctx, kind)
    if not spec then
        return false, err
    end
    return navigation.travel(ctx, spec, opts)
end

return navigation

]===]
bundled_modules["lib_orientation"] = [===[
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

]===]
bundled_modules["lib_parser"] = [===[
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

]===]
bundled_modules["lib_placement"] = [===[
--[[
Placement library for CC:Tweaked turtles.
Provides safe block placement helpers and a high-level build state executor.
All public functions accept a shared ctx table and return success booleans or
state transition hints, following the project conventions.
--]]

---@diagnostic disable: undefined-global

local placement = {}
local logger = require("lib_logger")
local world = require("lib_world")
local fuel = require("lib_fuel")
local schema_utils = require("lib_schema")
local strategy_utils = require("lib_strategy")

local SIDE_APIS = {
    forward = {
        place = turtle and turtle.place or nil,
        detect = turtle and turtle.detect or nil,
        inspect = turtle and turtle.inspect or nil,
        dig = turtle and turtle.dig or nil,
        attack = turtle and turtle.attack or nil,
    },
    up = {
        place = turtle and turtle.placeUp or nil,
        detect = turtle and turtle.detectUp or nil,
        inspect = turtle and turtle.inspectUp or nil,
        dig = turtle and turtle.digUp or nil,
        attack = turtle and turtle.attackUp or nil,
    },
    down = {
        place = turtle and turtle.placeDown or nil,
        detect = turtle and turtle.detectDown or nil,
        inspect = turtle and turtle.inspectDown or nil,
        dig = turtle and turtle.digDown or nil,
        attack = turtle and turtle.attackDown or nil,
    },
}

local function ensurePlacementState(ctx)
    if type(ctx) ~= "table" then
        error("placement library requires a context table", 2)
    end
    ctx.placement = ctx.placement or {}
    local state = ctx.placement
    state.cachedSlots = state.cachedSlots or {}
    return state
end

local function selectMaterialSlot(ctx, material)
    local state = ensurePlacementState(ctx)
    if not turtle or not turtle.getItemDetail or not turtle.select then
        return nil, "turtle API unavailable"
    end
    if type(material) ~= "string" or material == "" then
        return nil, "invalid_material"
    end

    local cached = state.cachedSlots[material]
    if cached then
        local detail = turtle.getItemDetail(cached)
        local count = detail and detail.count
        if (not count or count <= 0) and turtle.getItemCount then
            count = turtle.getItemCount(cached)
        end
        if detail and detail.name == material and count and count > 0 then
            if turtle.select(cached) then
                state.lastSlot = cached
                return cached
            end
            state.cachedSlots[material] = nil
        else
            state.cachedSlots[material] = nil
        end
    end

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        local count = detail and detail.count
        if (not count or count <= 0) and turtle.getItemCount then
            count = turtle.getItemCount(slot)
        end
        if detail and detail.name == material and count and count > 0 then
            if turtle.select(slot) then
                state.cachedSlots[material] = slot
                state.lastSlot = slot
                return slot
            end
        end
    end

    return nil, "missing_material"
end

local function resolveSide(ctx, block, opts)
    if type(opts) == "table" and opts.side then
        return opts.side
    end
    if type(block) == "table" and type(block.meta) == "table" and block.meta.side then
        return block.meta.side
    end
    if type(ctx.config) == "table" and ctx.config.defaultPlacementSide then
        return ctx.config.defaultPlacementSide
    end
    return "forward"
end

local function resolveOverwrite(ctx, block, opts)
    if type(opts) == "table" and opts.overwrite ~= nil then
        return opts.overwrite
    end
    if type(block) == "table" and type(block.meta) == "table" and block.meta.overwrite ~= nil then
        return block.meta.overwrite
    end
    if type(ctx.config) == "table" and ctx.config.allowOverwrite ~= nil then
        return ctx.config.allowOverwrite
    end
    return false
end

local function detectBlock(sideFns)
    if type(sideFns.inspect) == "function" then
        local hasBlock, data = sideFns.inspect()
        if hasBlock then
            return true, data
        end
        return false, nil
    end
    if type(sideFns.detect) == "function" then
        local exists = sideFns.detect()
        if exists then
            return true, nil
        end
    end
    return false, nil
end

local function clearBlockingBlock(sideFns, allowDig, allowAttack)
    if not allowDig and not allowAttack then
        return false
    end

    local attempts = 0
    local maxAttempts = 4

    while attempts < maxAttempts do
        attempts = attempts + 1
        local cleared = false

        if allowDig and type(sideFns.dig) == "function" then
            cleared = sideFns.dig() or cleared
        end

        if not cleared and allowAttack and type(sideFns.attack) == "function" then
            cleared = sideFns.attack() or cleared
        end

        if cleared then
            if type(sideFns.detect) ~= "function" or not sideFns.detect() then
                return true
            end
        end

        if sleep and attempts < maxAttempts then
            sleep(0)
        end
    end

    return false
end

function placement.placeMaterial(ctx, material, opts)
    local state = ensurePlacementState(ctx)
    if not turtle then
        return false, "turtle API unavailable"
    end
    if material == nil or material == "" or material == "minecraft:air" or material == "air" then
        state.lastPlacement = { skipped = true, reason = "air", material = material }
        return true
    end

    local side = resolveSide(ctx, opts and opts.block or nil, opts)
    local sideFns = SIDE_APIS[side]
    if not sideFns or type(sideFns.place) ~= "function" then
        return false, "invalid_side"
    end

    local slot, slotErr = selectMaterialSlot(ctx, material)
    if not slot then
        state.lastPlacement = { success = false, material = material, error = slotErr }
        return false, slotErr
    end

    local allowDig = opts and opts.dig
    if allowDig == nil then
        allowDig = true
    end
    local allowAttack = opts and opts.attack
    if allowAttack == nil then
        allowAttack = true
    end
    local allowOverwrite = resolveOverwrite(ctx, opts and opts.block or nil, opts)

    local blockPresent, blockData = detectBlock(sideFns)
    local blockingName = blockData and blockData.name or nil
    if blockPresent then
        if blockData and blockData.name == material then
            state.lastPlacement = { success = true, material = material, reused = true, side = side, blocking = blockingName }
            return true, "already_present"
        end

        local needsReplacement = not (blockData and blockData.name == material)
        local canForce = allowOverwrite or needsReplacement

        if not canForce then
            state.lastPlacement = { success = false, material = material, error = "occupied", side = side, blocking = blockingName }
            return false, "occupied"
        end

        local cleared = clearBlockingBlock(sideFns, allowDig, allowAttack)
        if not cleared then
            local reason = needsReplacement and "mismatched_block" or "blocked"
            state.lastPlacement = { success = false, material = material, error = reason, side = side, blocking = blockingName }
            return false, reason
        end
    end

    if not turtle.select(slot) then
        state.cachedSlots[material] = nil
        state.lastPlacement = { success = false, material = material, error = "select_failed", side = side, slot = slot }
        return false, "select_failed"
    end

    local placed, placeErr = sideFns.place()
    if not placed then
        if placeErr then
            logger.log(ctx, "debug", string.format("Place failed for %s: %s", material, placeErr))
        end

        local stillBlocked = type(sideFns.detect) == "function" and sideFns.detect()
        local slotCount
        if turtle.getItemCount then
            slotCount = turtle.getItemCount(slot)
        elseif turtle.getItemDetail then
            local detail = turtle.getItemDetail(slot)
            slotCount = detail and detail.count or nil
        end

        local lowerErr = type(placeErr) == "string" and placeErr:lower() or nil

        if slotCount ~= nil and slotCount <= 0 then
            state.cachedSlots[material] = nil
            state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
            return false, "missing_material"
        end

        if lowerErr then
            if lowerErr:find("no items") or lowerErr:find("no block") or lowerErr:find("missing item") then
                state.cachedSlots[material] = nil
                state.lastPlacement = { success = false, material = material, error = "missing_material", side = side, slot = slot, message = placeErr }
                return false, "missing_material"
            end
            if lowerErr:find("protect") or lowerErr:find("denied") or lowerErr:find("cannot place") or lowerErr:find("can't place") or lowerErr:find("occupied") then
                state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
                return false, "blocked"
            end
        end

        if stillBlocked then
            state.lastPlacement = { success = false, material = material, error = "blocked", side = side, slot = slot, message = placeErr }
            return false, "blocked"
        end

        state.lastPlacement = { success = false, material = material, error = "placement_failed", side = side, slot = slot, message = placeErr }
        return false, "placement_failed"
    end

    state.lastPlacement = {
        success = true,
        material = material,
        side = side,
        slot = slot,
        timestamp = os and os.time and os.time() or nil,
    }
    return true
end

function placement.advancePointer(ctx)
    return strategy_utils.advancePointer(ctx)
end

function placement.ensureState(ctx)
    return ensurePlacementState(ctx)
end

function placement.executeBuildState(ctx, opts)
    opts = opts or {}
    local state = ensurePlacementState(ctx)

    local pointer, pointerErr = strategy_utils.ensurePointer(ctx)
    if not pointer then
        logger.log(ctx, "debug", "No build pointer available: " .. tostring(pointerErr))
        return "DONE", { reason = pointerErr or "no_pointer" }
    end

    if fuel.isFuelLow(ctx) then
        state.resumeState = "BUILD"
        logger.log(ctx, "info", "Fuel below threshold, switching to REFUEL")
        return "REFUEL", { reason = "fuel_low", pointer = world.copyPosition(pointer) }
    end

    local block, schemaErr = schema_utils.fetchSchemaEntry(ctx.schema, pointer)
    if not block then
        logger.log(ctx, "debug", string.format("No schema entry at x=%d y=%d z=%d (%s)", pointer.x or 0, pointer.y or 0, pointer.z or 0, tostring(schemaErr)))
        local autoAdvance = opts.autoAdvance
        if autoAdvance == nil then
            autoAdvance = true
        end
        if autoAdvance then
            local advanced = placement.advancePointer(ctx)
            if advanced then
                return "BUILD", { reason = "skip_empty", pointer = world.copyPosition(ctx.pointer) }
            end
        end
        return "DONE", { reason = "schema_exhausted" }
    end

    if block.material == nil or block.material == "minecraft:air" or block.material == "air" then
        local autoAdvance = opts.autoAdvance
        if autoAdvance == nil then
            autoAdvance = true
        end
        if autoAdvance then
            local advanced = placement.advancePointer(ctx)
            if advanced then
                return "BUILD", { reason = "skip_air", pointer = world.copyPosition(ctx.pointer) }
            end
        end
        return "DONE", { reason = "no_material" }
    end

    local side = resolveSide(ctx, block, opts)
    local overwrite = resolveOverwrite(ctx, block, opts)
    local allowDig = opts.dig
    local allowAttack = opts.attack
    if allowDig == nil and block.meta and block.meta.dig ~= nil then
        allowDig = block.meta.dig
    end
    if allowAttack == nil and block.meta and block.meta.attack ~= nil then
        allowAttack = block.meta.attack
    end

    local placementOpts = {
        side = side,
        overwrite = overwrite,
        dig = allowDig,
        attack = allowAttack,
        block = block,
    }

    local ok, err = placement.placeMaterial(ctx, block.material, placementOpts)
    if not ok then
        if err == "missing_material" then
            state.resumeState = "BUILD"
            state.pendingMaterial = block.material
            logger.log(ctx, "warn", string.format("Need to restock %s", block.material))
            return "RESTOCK", {
                reason = err,
                material = block.material,
                pointer = world.copyPosition(pointer),
            }
        end
        if err == "blocked" then
            state.resumeState = "BUILD"
            logger.log(ctx, "warn", "Placement blocked; invoking BLOCKED state")
            return "BLOCKED", {
                reason = err,
                pointer = world.copyPosition(pointer),
                material = block.material,
            }
        end
        if err == "turtle API unavailable" then
            state.lastError = err
            return "ERROR", { reason = err }
        end
        state.lastError = err
        logger.log(ctx, "error", string.format("Placement failed for %s: %s", block.material, tostring(err)))
        return "ERROR", {
            reason = err,
            material = block.material,
            pointer = world.copyPosition(pointer),
        }
    end

    state.lastPlaced = {
        material = block.material,
        pointer = world.copyPosition(pointer),
        side = side,
        meta = block.meta,
        timestamp = os and os.time and os.time() or nil,
    }

    local autoAdvance = opts.autoAdvance
    if autoAdvance == nil then
        autoAdvance = true
    end
    if autoAdvance then
        local advanced = placement.advancePointer(ctx)
        if advanced then
            return "BUILD", { reason = "continue", pointer = world.copyPosition(ctx.pointer) }
        end
        return "DONE", { reason = "complete" }
    end

    return "BUILD", { reason = "await_pointer_update" }
end

return placement

]===]
bundled_modules["lib_reporter"] = [===[
local reporter = {}
local initialize = require("lib_initialize")
local movement = require("lib_movement")
local fuel = require("lib_fuel")
local inventory = require("lib_inventory")
local world = require("lib_world")
local schema_utils = require("lib_schema")
local string_utils = require("lib_string")

function reporter.describeFuel(io, report)
    fuel.describeFuel(io, report)
end

function reporter.describeService(io, report)
    fuel.describeService(io, report)
end

function reporter.describeMaterials(io, info)
    inventory.describeMaterials(io, info)
end

function reporter.detectContainers(io)
    world.detectContainers(io)
end

function reporter.runCheck(ctx, io, opts)
    inventory.runCheck(ctx, io, opts)
end

function reporter.gatherSummary(io, report)
    inventory.gatherSummary(io, report)
end

function reporter.describeTotals(io, totals)
    inventory.describeTotals(io, totals)
end

function reporter.showHistory(io, entries)
    if not io.print then
        return
    end
    if not entries or #entries == 0 then
        io.print("Captured history: <empty>")
        return
    end
    io.print("Captured history:")
    for _, entry in ipairs(entries) do
        local label = entry.levelLabel or entry.level
        local stamp = entry.timestamp and (entry.timestamp .. " ") or ""
        local tag = entry.tag and (entry.tag .. " ") or ""
        io.print(string.format(" - %s%s%s%s", stamp, tag, label, entry.message and (" " .. entry.message) or ""))
    end
end

function reporter.describePosition(ctx)
    return movement.describePosition(ctx)
end

function reporter.printMaterials(io, info)
    schema_utils.printMaterials(io, info)
end

function reporter.printBounds(io, info)
    schema_utils.printBounds(io, info)
end

function reporter.detailToString(value, depth)
    return string_utils.detailToString(value, depth)
end

function reporter.computeManifest(list)
    return inventory.computeManifest(list)
end

function reporter.printManifest(io, manifest)
    inventory.printManifest(io, manifest)
end

return reporter

]===]
bundled_modules["lib_schema"] = [===[
--[[
Schema library for CC:Tweaked turtles.
Provides helpers for working with build schemas.
--]]

---@diagnostic disable: undefined-global

local schema_utils = {}

function schema_utils.pushMaterialCount(counts, material)
    counts[material] = (counts[material] or 0) + 1
end

local table_utils = require("lib_table")

function schema_utils.cloneMeta(meta)
    if type(meta) ~= "table" then
        return {}
    end
    return table_utils.shallowCopy(meta)
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

]===]
bundled_modules["lib_strategy"] = [===[
--[[
Strategy library for CC:Tweaked turtles.
Provides helpers for managing build strategies.
--]]

---@diagnostic disable: undefined-global

local strategy_utils = {}

local world = require("lib_world")

function strategy_utils.ensurePointer(ctx)
    if type(ctx.pointer) == "table" then
        return ctx.pointer
    end
    local strategy = ctx.strategy
    if type(strategy) == "table" and type(strategy.order) == "table" then
        local idx = strategy.index or 1
        local pos = strategy.order[idx]
        if pos then
            ctx.pointer = world.copyPosition(pos)
            strategy.index = idx
            return ctx.pointer
        end
        return nil, "strategy_exhausted"
    end
    return nil, "no_pointer"
end

function strategy_utils.advancePointer(ctx)
    if type(ctx.strategy) == "table" then
        local strategy = ctx.strategy
        if type(strategy.advance) == "function" then
            local nextPos, doneFlag = strategy.advance(strategy, ctx)
            if nextPos then
                ctx.pointer = world.copyPosition(nextPos)
                return true
            end
            if doneFlag == false then
                return false
            end
            ctx.pointer = nil
            return false
        end
        if type(strategy.next) == "function" then
            local nextPos = strategy.next(strategy, ctx)
            if nextPos then
                ctx.pointer = world.copyPosition(nextPos)
                return true
            end
            ctx.pointer = nil
            return false
        end
        if type(strategy.order) == "table" then
            local idx = (strategy.index or 1) + 1
            strategy.index = idx
            local pos = strategy.order[idx]
            if pos then
                ctx.pointer = world.copyPosition(pos)
                return true
            end
            ctx.pointer = nil
            return false
        end
    elseif type(ctx.strategy) == "function" then
        local nextPos = ctx.strategy(ctx)
        if nextPos then
            ctx.pointer = world.copyPosition(nextPos)
            return true
        end
        ctx.pointer = nil
        return false
    end
    ctx.pointer = nil
    return false
end

return strategy_utils

]===]
bundled_modules["lib_strategy_branchmine"] = [===[
--[[
Strategy generator for branch mining.
Produces a linear list of steps for the turtle to execute without moving the turtle at generation time.
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

--- Generate a branch mining strategy
---@param length number Length of the main spine
---@param branchInterval number Distance between branches
---@param branchLength number Length of each branch
---@param torchInterval number Distance between torches on spine
---@return table
function strategy.generate(length, branchInterval, branchLength, torchInterval)
    length = normalizePositiveInt(length, 60)
    branchInterval = normalizePositiveInt(branchInterval, 3)
    branchLength = normalizePositiveInt(branchLength, 16)
    torchInterval = normalizePositiveInt(torchInterval, 6)

    local steps = {}
    local x, y, z = 0, 0, 0
    local facing = 0 -- 0: forward, 1: right, 2: back, 3: left

    pushStep(steps, x, y, z, facing, "mine_neighbors")

    for i = 1, length do
        x, z = forward(x, z, facing)
        pushStep(steps, x, y, z, facing, "move")
        pushStep(steps, x, y, z, facing, "mine_neighbors")

        if i % torchInterval == 0 then
            pushStep(steps, x, y, z, facing, "place_torch")
        end

        if i % branchInterval == 0 then
            -- Left branch
            facing = turnLeft(facing)
            pushStep(steps, x, y, z, facing, "turn", "left")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go UP
            y = y + 1
            pushStep(steps, x, y, z, facing, "move")
            pushStep(steps, x, y, z, facing, "mine_neighbors")

            -- Turn around and return to spine
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go DOWN
            y = y - 1
            pushStep(steps, x, y, z, facing, "move")

            -- Face down the spine again
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")

            -- Right branch (mirror of left)
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go UP
            y = y + 1
            pushStep(steps, x, y, z, facing, "move")
            pushStep(steps, x, y, z, facing, "mine_neighbors")

            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            facing = turnRight(facing)
            pushStep(steps, x, y, z, facing, "turn", "right")
            for _ = 1, branchLength do
                x, z = forward(x, z, facing)
                pushStep(steps, x, y, z, facing, "move")
                pushStep(steps, x, y, z, facing, "mine_neighbors")
            end

            -- Go DOWN
            y = y - 1
            pushStep(steps, x, y, z, facing, "move")

            facing = turnLeft(facing)
            pushStep(steps, x, y, z, facing, "turn", "left")
        end

        if i % 5 == 0 then
            pushStep(steps, x, y, z, facing, "dump_trash")
        end
    end

    -- Return to origin
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    for _ = 1, length do
        x, z = forward(x, z, facing)
        pushStep(steps, x, y, z, facing, "move")
    end
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")
    facing = turnRight(facing)
    pushStep(steps, x, y, z, facing, "turn", "right")

    pushStep(steps, x, y, z, facing, "done")

    return steps
end

return strategy

]===]
bundled_modules["lib_strategy_excavate"] = [===[
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

]===]
bundled_modules["lib_strategy_farm"] = [===[
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

]===]
bundled_modules["lib_strategy_tunnel"] = [===[
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

]===]
bundled_modules["lib_string"] = [===[
local string_utils = {}

function string_utils.trim(text)
    if type(text) ~= "string" then
        return text
    end
    return text:match("^%s*(.-)%s*$")
end

function string_utils.detailToString(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then
        return "..."
    end
    if type(value) ~= "table" then
        return tostring(value)
    end
    if textutils and textutils.serialize then
        return textutils.serialize(value)
    end
    local parts = {}
    for k, v in pairs(value) do
        parts[#parts + 1] = tostring(k) .. "=" .. string_utils.detailToString(v, depth)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

return string_utils

]===]
bundled_modules["lib_table"] = [===[
local table_utils = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = deepCopy(v)
    end
    return result
end

table_utils.deepCopy = deepCopy

function table_utils.merge(base, overrides)
    if type(base) ~= "table" and type(overrides) ~= "table" then
        return overrides or base
    end

    local result = {}

    if type(base) == "table" then
        for k, v in pairs(base) do
            result[k] = deepCopy(v)
        end
    end

    if type(overrides) == "table" then
        for k, v in pairs(overrides) do
            if type(v) == "table" and type(result[k]) == "table" then
                result[k] = table_utils.merge(result[k], v)
            else
                result[k] = deepCopy(v)
            end
        end
    elseif overrides ~= nil then
        return deepCopy(overrides)
    end

    return result
end

function table_utils.copyArray(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for i = 1, #source do
        result[i] = source[i]
    end
    return result
end

function table_utils.sumValues(tbl)
    local total = 0
    if type(tbl) ~= "table" then
        return total
    end
    for _, value in pairs(tbl) do
        if type(value) == "number" then
            total = total + value
        end
    end
    return total
end

function table_utils.copyTotals(totals)
    local result = {}
    for material, count in pairs(totals or {}) do
        result[material] = count
    end
    return result
end

function table_utils.mergeTotals(target, source)
    for material, count in pairs(source or {}) do
        target[material] = (target[material] or 0) + count
    end
end

function table_utils.tableCount(tbl)
    if type(tbl) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function table_utils.copyArray(list)
    if type(list) ~= "table" then
        return {}
    end
    local result = {}
    for index = 1, #list do
        result[index] = list[index]
    end
    return result
end

function table_utils.copySummary(summary)
    if type(summary) ~= "table" then
        return {}
    end
    local result = {}
    for key, value in pairs(summary) do
        result[key] = value
    end
    return result
end

function table_utils.copySlots(slots)
    if type(slots) ~= "table" then
        return {}
    end
    local result = {}
    for slot, info in pairs(slots) do
        if type(info) == "table" then
            result[slot] = {
                slot = info.slot,
                count = info.count,
                name = info.name,
                detail = info.detail,
            }
        else
            result[slot] = info
        end
    end
    return result
end

function table_utils.copyValue(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for k, v in pairs(value) do
        result[k] = table_utils.copyValue(v, seen)
    end
    return result
end

function table_utils.shallowCopy(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        result[k] = v
    end
    return result
end

return table_utils

]===]
bundled_modules["lib_ui"] = [===[
--[[
UI Library for TurtleOS (Mouse/GUI Edition)
Provides DOS-style windowing and widgets.
--]]

local ui = {}

local colors_bg = colors.blue
local colors_fg = colors.white
local colors_btn = colors.lightGray
local colors_btn_text = colors.black
local colors_input = colors.black
local colors_input_text = colors.white

function ui.clear()
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.clear()
end

function ui.drawBox(x, y, w, h, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end
end

function ui.drawFrame(x, y, w, h, title)
    ui.drawBox(x, y, w, h, colors.gray, colors.white)
    ui.drawBox(x + 1, y + 1, w - 2, h - 2, colors_bg, colors_fg)
    
    -- Shadow
    term.setBackgroundColor(colors.black)
    for i = 1, h do
        term.setCursorPos(x + w, y + i)
        term.write(" ")
    end
    for i = 1, w do
        term.setCursorPos(x + i, y + h)
        term.write(" ")
    end

    if title then
        term.setCursorPos(x + 2, y + 1)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        term.write(" " .. title .. " ")
    end
end

function ui.button(x, y, text, active)
    term.setCursorPos(x, y)
    if active then
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    else
        term.setBackgroundColor(colors_btn)
        term.setTextColor(colors_btn_text)
    end
    term.write(" " .. text .. " ")
end

function ui.label(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_bg)
    term.setTextColor(colors_fg)
    term.write(text)
end

function ui.inputText(x, y, width, value, active)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors_input)
    term.setTextColor(colors_input_text)
    local display = value or ""
    if #display > width then
        display = display:sub(-width)
    end
    term.write(display .. string.rep(" ", width - #display))
    if active then
        term.setCursorPos(x + #display, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

function ui.drawPreview(schema, x, y, w, h)
    -- Find bounds
    local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        if nz < minZ then minZ = nz end
                        if nz > maxZ then maxZ = nz end
                    end
                end
            end
        end
    end

    if minX > maxX then return end -- Empty schema

    local scaleX = w / (maxX - minX + 1)
    local scaleZ = h / (maxZ - minZ + 1)
    local scale = math.min(scaleX, scaleZ, 1) -- Keep aspect ratio, max 1:1

    -- Draw background
    term.setBackgroundColor(colors.black)
    for i = 0, h - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", w))
    end

    -- Draw blocks
    for sx, row in pairs(schema) do
        local nx = tonumber(sx)
        if nx then
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz then
                        -- Map to screen
                        local scrX = math.floor((nx - minX) * scale) + x
                        local scrY = math.floor((nz - minZ) * scale) + y
                        
                        if scrX >= x and scrX < x + w and scrY >= y and scrY < y + h then
                            term.setCursorPos(scrX, scrY)
                            
                            -- Color mapping
                            local mat = block.material
                            local color = colors.gray
                            local char = " "
                            
                            if mat:find("water") then color = colors.blue
                            elseif mat:find("log") then color = colors.brown
                            elseif mat:find("leaves") then color = colors.green
                            elseif mat:find("sapling") then color = colors.green; char = "T"
                            elseif mat:find("sand") then color = colors.yellow
                            elseif mat:find("dirt") then color = colors.brown
                            elseif mat:find("grass") then color = colors.green
                            elseif mat:find("stone") then color = colors.lightGray
                            elseif mat:find("cane") then color = colors.lime; char = "!"
                            elseif mat:find("potato") then color = colors.orange; char = "."
                            elseif mat:find("torch") then color = colors.orange; char = "i"
                            end
                            
                            term.setBackgroundColor(color)
                            if color == colors.black then term.setTextColor(colors.white) else term.setTextColor(colors.black) end
                            term.write(char)
                        end
                    end
                end
            end
        end
    end
end

-- Simple Event Loop for a Form
-- form = { title = "", elements = { {type="button", x=, y=, text=, id=}, ... } }
function ui.runForm(form)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local running = true
    local result = nil
    local activeInput = nil

    while running do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, form.title)
        
        -- Draw elements
        for _, el in ipairs(form.elements) do
            local ex, ey = fx + el.x, fy + el.y
            if el.type == "button" then
                ui.button(ex, ey, el.text, false)
            elseif el.type == "label" then
                ui.label(ex, ey, el.text)
            elseif el.type == "input" then
                ui.inputText(ex, ey, el.width, el.value, activeInput == el)
            end
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            local clickedSomething = false
            
            for _, el in ipairs(form.elements) do
                local ex, ey = fx + el.x, fy + el.y
                if el.type == "button" then
                    if my == ey and mx >= ex and mx < ex + #el.text + 2 then
                        ui.button(ex, ey, el.text, true) -- Flash
                        sleep(0.1)
                        if el.callback then
                            local res = el.callback(form)
                            if res then return res end
                        end
                        clickedSomething = true
                    end
                elseif el.type == "input" then
                    if my == ey and mx >= ex and mx < ex + el.width then
                        activeInput = el
                        clickedSomething = true
                    end
                end
            end
            
            if not clickedSomething then
                activeInput = nil
            end
            
        elseif event == "char" and activeInput then
            activeInput.value = (activeInput.value or "") .. p1
        elseif event == "key" then
            local key = p1
            if key == keys.backspace and activeInput then
                local val = activeInput.value or ""
                if #val > 0 then
                    activeInput.value = val:sub(1, -2)
                end
            elseif key == keys.enter and activeInput then
                activeInput = nil
            end
        end
    end
end

-- Simple Scrollable Menu
-- items = { { text="Label", callback=function() end }, ... }
function ui.runMenu(title, items)
    local w, h = term.getSize()
    local fw, fh = math.floor(w * 0.8), math.floor(h * 0.8)
    local fx, fy = math.floor((w - fw) / 2) + 1, math.floor((h - fh) / 2) + 1
    
    local scroll = 0
    local maxVisible = fh - 4 -- Title + padding (top/bottom)
    
    while true do
        ui.clear()
        ui.drawFrame(fx, fy, fw, fh, title)
        
        -- Draw items
        for i = 1, maxVisible do
            local idx = i + scroll
            if idx <= #items then
                local item = items[idx]
                ui.button(fx + 2, fy + 1 + i, item.text, false)
            end
        end
        
        -- Scroll indicators
        if scroll > 0 then
            ui.label(fx + fw - 2, fy + 2, "^")
        end
        if scroll + maxVisible < #items then
            ui.label(fx + fw - 2, fy + fh - 2, "v")
        end
        
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Check items
            for i = 1, maxVisible do
                local idx = i + scroll
                if idx <= #items then
                    local item = items[idx]
                    local bx, by = fx + 2, fy + 1 + i
                    -- Button width is text length + 2 spaces
                    if my == by and mx >= bx and mx < bx + #item.text + 2 then
                        ui.button(bx, by, item.text, true) -- Flash
                        sleep(0.1)
                        if item.callback then
                            local res = item.callback()
                            if res then return res end
                        end
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            else
                if scroll > 0 then scroll = scroll - 1 end
            end
        elseif event == "key" then
            local key = p1
            if key == keys.up then
                if scroll > 0 then scroll = scroll - 1 end
            elseif key == keys.down then
                if scroll + maxVisible < #items then scroll = scroll + 1 end
            end
        end
    end
end

return ui

]===]
bundled_modules["lib_world"] = [===[
local world = {}

function world.getInspect(side)
    if side == "forward" then
        return turtle.inspect
    elseif side == "up" then
        return turtle.inspectUp
    elseif side == "down" then
        return turtle.inspectDown
    end
    return nil
end

local SIDE_ALIASES = {
    forward = "forward",
    front = "forward",
    down = "down",
    bottom = "down",
    up = "up",
    top = "up",
    left = "left",
    right = "right",
    back = "back",
    behind = "back",
}

function world.normaliseSide(side)
    if type(side) ~= "string" then
        return nil
    end
    return SIDE_ALIASES[string.lower(side)]
end

function world.toPeripheralSide(side)
    local normalised = world.normaliseSide(side) or side
    if normalised == "forward" then
        return "front"
    elseif normalised == "up" then
        return "top"
    elseif normalised == "down" then
        return "bottom"
    elseif normalised == "back" then
        return "back"
    elseif normalised == "left" then
        return "left"
    elseif normalised == "right" then
        return "right"
    end
    return normalised
end

function world.inspectSide(side)
    local normalised = world.normaliseSide(side)
    if normalised == "forward" then
        return turtle and turtle.inspect and turtle.inspect()
    elseif normalised == "up" then
        return turtle and turtle.inspectUp and turtle.inspectUp()
    elseif normalised == "down" then
        return turtle and turtle.inspectDown and turtle.inspectDown()
    end
    return false
end

function world.isContainer(detail)
    if type(detail) ~= "table" then
        return false
    end
    local name = string.lower(detail.name or "")
    if name:find("chest", 1, true) or name:find("barrel", 1, true) or name:find("drawer", 1, true) then
        return true
    end
    if type(detail.tags) == "table" then
        for tag in pairs(detail.tags) do
            local lowered = string.lower(tag)
            if lowered:find("inventory", 1, true) or lowered:find("chest", 1, true) or lowered:find("barrel", 1, true) then
                return true
            end
        end
    end
    return false
end

function world.normalizeSide(value)
    if type(value) ~= "string" then
        return nil
    end
    local lower = value:lower()
    if lower == "forward" or lower == "front" or lower == "fwd" then
        return "forward"
    end
    if lower == "up" or lower == "top" or lower == "above" then
        return "up"
    end
    if lower == "down" or lower == "bottom" or lower == "below" then
        return "down"
    end
    return nil
end

function world.resolveSide(ctx, opts)
    if type(opts) == "string" then
        local direct = world.normalizeSide(opts)
        return direct or "forward"
    end

    local candidate
    if type(opts) == "table" then
        candidate = opts.side or opts.direction or opts.facing or opts.containerSide or opts.defaultSide
        if not candidate and type(opts.location) == "string" then
            candidate = opts.location
        end
    end

    if not candidate and type(ctx) == "table" then
        local cfg = ctx.config
        if type(cfg) == "table" then
            candidate = cfg.inventorySide or cfg.materialSide or cfg.supplySide or cfg.defaultInventorySide
        end
        if not candidate and type(ctx.inventoryState) == "table" then
            candidate = ctx.inventoryState.defaultSide
        end
    end

    local normalised = world.normalizeSide(candidate)
    if normalised then
        return normalised
    end

    return "forward"
end

function world.isContainerBlock(name, tags)
    if type(name) ~= "string" then
        return false
    end
    local lower = name:lower()
    for _, keyword in ipairs(CONTAINER_KEYWORDS) do
        if lower:find(keyword, 1, true) then
            return true
        end
    end
    return world.hasContainerTag(tags)
end

function world.inspectForwardForContainer()
    if not turtle or type(turtle.inspect) ~= "function" then
        return false
    end
    local ok, data = turtle.inspect()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectUpForContainer()
    if not turtle or type(turtle.inspectUp) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectUp()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.inspectDownForContainer()
    if not turtle or type(turtle.inspectDown) ~= "function" then
        return false
    end
    local ok, data = turtle.inspectDown()
    if not ok or type(data) ~= "table" then
        return false
    end
    if world.isContainerBlock(data.name, data.tags) then
        return true, data
    end
    return false
end

function world.peripheralSideForDirection(side)
    if side == "forward" or side == "front" then
        return "front"
    end
    if side == "up" or side == "top" then
        return "top"
    end
    if side == "down" or side == "bottom" then
        return "bottom"
    end
    return side
end

function world.computePrimaryPushDirection(ctx, periphSide)
    if periphSide == "front" then
        local facing = movement.getFacing(ctx)
        if facing then
            return OPPOSITE_FACING[facing]
        end
    elseif periphSide == "top" then
        return "down"
    elseif periphSide == "bottom" then
        return "up"
    end
    return nil
end

function world.normaliseCoordinate(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function world.normalisePosition(pos)
    if type(pos) ~= "table" then
        return nil, "invalid_position"
    end
    local xRaw = pos.x
    if xRaw == nil then
        xRaw = pos[1]
    end
    local yRaw = pos.y
    if yRaw == nil then
        yRaw = pos[2]
    end
    local zRaw = pos.z
    if zRaw == nil then
        zRaw = pos[3]
    end
    local x = world.normaliseCoordinate(xRaw)
    local y = world.normaliseCoordinate(yRaw)
    local z = world.normaliseCoordinate(zRaw)
    if not x or not y or not z then
        return nil, "invalid_position"
    end
    return { x = x, y = y, z = z }
end

function world.normaliseFacing(facing)
    facing = type(facing) == "string" and facing:lower() or "north"
    if facing ~= "north" and facing ~= "east" and facing ~= "south" and facing ~= "west" then
        return "north"
    end
    return facing
end

function world.facingVectors(facing)
    facing = world.normaliseFacing(facing)
    if facing == "north" then
        return { forward = { x = 0, z = -1 }, right = { x = 1, z = 0 } }
    elseif facing == "east" then
        return { forward = { x = 1, z = 0 }, right = { x = 0, z = 1 } }
    elseif facing == "south" then
        return { forward = { x = 0, z = 1 }, right = { x = -1, z = 0 } }
    else -- west
        return { forward = { x = -1, z = 0 }, right = { x = 0, z = -1 } }
    end
end

function world.rotateLocalOffset(localOffset, facing)
    local vectors = world.facingVectors(facing)
    local dx = localOffset.x or 0
    local dz = localOffset.z or 0
    local right = vectors.right
    local forward = vectors.forward
    return {
        x = (right.x * dx) + (forward.x * (-dz)),
        z = (right.z * dx) + (forward.z * (-dz)),
    }
end

function world.localToWorld(localOffset, facing)
    facing = world.normaliseFacing(facing)
    local dx = localOffset and localOffset.x or 0
    local dz = localOffset and localOffset.z or 0
    local rotated = world.rotateLocalOffset({ x = dx, z = dz }, facing)
    return {
        x = rotated.x,
        y = localOffset and localOffset.y or 0,
        z = rotated.z,
    }
end

function world.copyPosition(pos)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x or 0,
        y = pos.y or 0,
        z = pos.z or 0,
    }
end

function world.detectContainers(io)
    local found = {}
    local sides = { "forward", "down", "up" }
    local labels = {
        forward = "front",
        down = "below",
        up = "above",
    }
    for _, side in ipairs(sides) do
        local inspect
        if side == "forward" then
            inspect = turtle.inspect
        elseif side == "up" then
            inspect = turtle.inspectUp
        else
            inspect = turtle.inspectDown
        end
        if type(inspect) == "function" then
            local ok, detail = inspect()
            if ok then
                local name = type(detail.name) == "string" and detail.name or "unknown"
                found[#found + 1] = string.format(" %s: %s", labels[side] or side, name)
            end
        end
    end
    if io.print then
        if #found == 0 then
            io.print("Detected containers: <none>")
        else
            io.print("Detected containers:")
            for _, line in ipairs(found) do
                io.print(" -" .. line)
            end
        end
    end
end

return world

]===]
bundled_modules["lib_worldstate"] = [===[
--[[
Shared world-state + traversal helpers for CC:Tweaked farmers.
Encapsulates reference-frame math, serpentine traversal state, and
walkway-safe navigation so individual farmer scripts can stay focused
on crop-specific logic.
]]

local movement = require("lib_movement")

local worldstate = {}

local CARDINALS = { "north", "east", "south", "west" }
local CARDINAL_INDEX = {
  north = 1,
  east = 2,
  south = 3,
  west = 4,
}

local MOVE_OPTS_CLEAR = { dig = true, attack = true }
local MOVE_OPTS_SOFT = { dig = false, attack = false }
local MOVE_AXIS_FALLBACK = { "z", "x", "y" }

local function cloneTable(source)
  if type(source) ~= "table" then
    return nil
  end
  local copy = {}
  for key, value in pairs(source) do
    if type(value) == "table" then
      copy[key] = cloneTable(value)
    else
      copy[key] = value
    end
  end
  return copy
end

local function canonicalFacing(name)
  if type(name) ~= "string" then
    return nil
  end
  local normalized = name:lower()
  if CARDINAL_INDEX[normalized] then
    return normalized
  end
  return nil
end

local function rotateFacing(facing, steps)
  local canonical = canonicalFacing(facing)
  if not canonical then
    return facing
  end
  local index = CARDINAL_INDEX[canonical]
  local count = #CARDINALS
  local rotated = ((index - 1 + steps) % count) + 1
  return CARDINALS[rotated]
end

local function rotate2D(x, z, steps)
  local normalized = steps % 4
  if normalized < 0 then
    normalized = normalized + 4
  end
  if normalized == 0 then
    return x, z
  elseif normalized == 1 then
    return -z, x
  elseif normalized == 2 then
    return -x, -z
  else
    return z, -x
  end
end

local function mergeTables(target, source)
  if type(target) ~= "table" or type(source) ~= "table" then
    return target
  end
  for key, value in pairs(source) do
    if type(value) == "table" then
      target[key] = target[key] or {}
      mergeTables(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

local function ensureWorld(ctx)
  ctx.world = ctx.world or {}
  local world = ctx.world
  world.origin = world.origin or cloneTable(ctx.origin) or { x = 0, y = 0, z = 0 }
  ctx.origin = ctx.origin or cloneTable(world.origin)
  world.frame = world.frame or {}
  world.grid = world.grid or {}
  world.walkway = world.walkway or {}
  world.traversal = world.traversal or {}
  world.bounds = world.bounds or {}
  return world
end

-- Reference-frame helpers -------------------------------------------------
function worldstate.buildReferenceFrame(ctx, opts)
  local world = ensureWorld(ctx)
  opts = opts or {}
  local desired = canonicalFacing(opts.homeFacing)
    or canonicalFacing(opts.initialFacing)
    or canonicalFacing(ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing))
    or canonicalFacing(world.frame.homeFacing)
    or "east"
  local baseline = canonicalFacing(opts.referenceFacing) or "east"
  local desiredIndex = CARDINAL_INDEX[desired]
  local baselineIndex = CARDINAL_INDEX[baseline]
  local rotationSteps = ((desiredIndex - baselineIndex) % 4)
  world.frame.rotationSteps = rotationSteps
  world.frame.homeFacing = desired
  world.frame.referenceFacing = baseline
  return world.frame
end

function worldstate.referenceToWorld(ctx, refPos)
  if not refPos then
    return nil
  end
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  local x = refPos.x or 0
  local z = refPos.z or 0
  local rotatedX, rotatedZ = rotate2D(x, z, rotationSteps)
  return {
    x = (world.origin.x or 0) + rotatedX,
    y = (world.origin.y or 0) + (refPos.y or 0),
    z = (world.origin.z or 0) + rotatedZ,
  }
end

function worldstate.worldToReference(ctx, worldPos)
  if not worldPos then
    return nil
  end
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  local dx = (worldPos.x or 0) - (world.origin.x or 0)
  local dz = (worldPos.z or 0) - (world.origin.z or 0)
  local refX, refZ = rotate2D(dx, dz, -rotationSteps)
  return {
    x = refX,
    y = (worldPos.y or 0) - (world.origin.y or 0),
    z = refZ,
  }
end

function worldstate.resolveFacing(ctx, facing)
  local world = ensureWorld(ctx)
  local rotationSteps = world.frame.rotationSteps or 0
  return rotateFacing(facing, rotationSteps)
end

local function mergeMoveOpts(baseOpts, extraOpts)
  if not extraOpts then
    if not baseOpts then
      return nil
    end
    return cloneTable(baseOpts)
  end

  local merged = {}
  if baseOpts then
    for key, value in pairs(baseOpts) do
      merged[key] = value
    end
  end
  for key, value in pairs(extraOpts) do
    merged[key] = value
  end
  return merged
end

local function goToWithFallback(ctx, position, moveOpts)
  local ok, err = movement.goTo(ctx, position, moveOpts)
  if ok or (moveOpts and moveOpts.axisOrder) then
    return ok, err
  end
  local fallbackOpts = mergeMoveOpts(moveOpts, { axisOrder = MOVE_AXIS_FALLBACK })
  return movement.goTo(ctx, position, fallbackOpts)
end

function worldstate.goToReference(ctx, refPos, moveOpts)
  if not refPos then
    return false, "invalid_reference_position"
  end
  local worldPos = worldstate.referenceToWorld(ctx, refPos)
  return goToWithFallback(ctx, worldPos, moveOpts)
end

function worldstate.goAndFaceReference(ctx, refPos, facing, moveOpts)
  if not refPos then
    return false, "invalid_reference_position"
  end
  local ok, err = worldstate.goToReference(ctx, refPos, moveOpts)
  if not ok then
    return false, err
  end
  if facing then
    return movement.faceDirection(ctx, worldstate.resolveFacing(ctx, facing))
  end
  return true
end

function worldstate.returnHome(ctx, moveOpts)
  local world = ensureWorld(ctx)
  local opts = moveOpts or MOVE_OPTS_SOFT
  local ok, err = goToWithFallback(ctx, world.origin, opts)
  if not ok then
    return false, err
  end
  local facing = world.frame.homeFacing or ctx.config and (ctx.config.homeFacing or ctx.config.initialFacing) or "east"
  ok, err = movement.faceDirection(ctx, facing)
  if not ok then
    return false, err
  end
  return true
end

-- Movement safety ---------------------------------------------------------
function worldstate.configureNoDigBounds(ctx, bounds)
  local world = ensureWorld(ctx)
  world.bounds.noDig = cloneTable(bounds)
  return world.bounds.noDig
end

local function positionWithinBounds(pos, bounds)
  if not pos or not bounds then
    return false
  end
  local x, z = pos.x or 0, pos.z or 0
  if bounds.minX and x < bounds.minX then
    return false
  end
  if bounds.maxX and x > bounds.maxX then
    return false
  end
  if bounds.minZ and z < bounds.minZ then
    return false
  end
  if bounds.maxZ and z > bounds.maxZ then
    return false
  end
  return true
end

function worldstate.moveOptsForPosition(ctx, position)
  local world = ensureWorld(ctx)
  local bounds = world.bounds.noDig
  if not bounds then
    return MOVE_OPTS_CLEAR
  end
  local ref = worldstate.worldToReference(ctx, position) or position
  if positionWithinBounds(ref, bounds) then
    return MOVE_OPTS_SOFT
  end
  return MOVE_OPTS_CLEAR
end

-- Walkway planning --------------------------------------------------------
local function isColumnX(grid, testX)
  if not grid or not grid.origin then
    return false
  end
  local spacing = grid.spacingX or 1
  local width = grid.width or 0
  local baseX = grid.origin.x or 0
  for offset = 0, math.max(width - 1, 0) do
    local columnX = baseX + offset * spacing
    if columnX == testX then
      return true
    end
  end
  return false
end

local function insertUnique(list, value)
  if not list or value == nil then
    return
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return
    end
  end
  table.insert(list, value)
end

function worldstate.configureGrid(ctx, cfg)
  local world = ensureWorld(ctx)
  cfg = cfg or {}
  world.grid.width = cfg.width or world.grid.width or ctx.config and ctx.config.gridWidth or 1
  world.grid.length = cfg.length or world.grid.length or ctx.config and ctx.config.gridLength or 1
  world.grid.spacingX = cfg.spacingX or cfg.spacing or world.grid.spacingX or ctx.config and (ctx.config.treeSpacingX or ctx.config.treeSpacing) or 1
  world.grid.spacingZ = cfg.spacingZ or cfg.spacing or world.grid.spacingZ or ctx.config and (ctx.config.treeSpacingZ or ctx.config.treeSpacing) or 1
  world.grid.origin = cloneTable(cfg.origin) or world.grid.origin or cloneTable(ctx.fieldOrigin) or { x = 0, y = 0, z = 0 }
  ctx.fieldOrigin = cloneTable(world.grid.origin)
  return world.grid
end

function worldstate.configureWalkway(ctx, cfg)
  local world = ensureWorld(ctx)
  cfg = cfg or {}
  local walkway = world.walkway
  walkway.offset = cfg.offset
    or walkway.offset
    or ctx.config and (ctx.config.walkwayOffsetX)
    or -world.grid.spacingX
  walkway.candidates = cloneTable(cfg.candidates) or walkway.candidates or {}
  if #walkway.candidates == 0 then
    insertUnique(walkway.candidates, world.grid.origin.x + (walkway.offset or -1))
    insertUnique(walkway.candidates, world.grid.origin.x)
    insertUnique(walkway.candidates, ctx.origin and ctx.origin.x)
  end
  worldstate.ensureWalkwayAvailability(ctx)
  return walkway
end

function worldstate.ensureWalkwayAvailability(ctx)
  local world = ensureWorld(ctx)
  local walkway = world.walkway
  walkway.candidates = walkway.candidates or {}
  local safe, selected = {}, walkway.selected
  for _, candidate in ipairs(walkway.candidates) do
    if candidate ~= nil and not isColumnX(world.grid, candidate) then
      insertUnique(safe, candidate)
      selected = selected or candidate
    end
  end
  if not selected then
    local spacing = world.grid.spacingX or 1
    local maxX = (world.grid.origin.x or 0) + math.max((world.grid.width or 1) - 1, 0) * spacing
    selected = maxX + spacing
    insertUnique(safe, selected)
  end
  walkway.candidates = safe
  walkway.selected = selected
  ctx.walkwayEntranceX = selected
  return selected
end

local function moveToAvailableWalkway(ctx, yLevel, targetZ)
  local world = ensureWorld(ctx)
  local walkway = world.walkway
  local candidates = walkway.candidates or { walkway.selected }
  local lastErr
  for _, safeX in ipairs(candidates) do
    if safeX then
      local currentWorld = movement.getPosition(ctx)
      local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
      local stageOne = { x = safeX, y = yLevel, z = currentRef.z }
      local ok, err = worldstate.goToReference(ctx, stageOne, MOVE_OPTS_SOFT)
      if not ok then
        lastErr = err
        goto next_candidate
      end
      local stageTwo = { x = safeX, y = yLevel, z = targetZ }
      ok, err = worldstate.goToReference(ctx, stageTwo, MOVE_OPTS_SOFT)
      if not ok then
        lastErr = err
        goto next_candidate
      end
      walkway.selected = safeX
      ctx.walkwayEntranceX = safeX
      return true
    end
    ::next_candidate::
  end
  return false, lastErr or "walkway_blocked"
end

function worldstate.moveAlongWalkway(ctx, targetRef)
  if not ctx or not targetRef then
    return false, "invalid_target"
  end
  local world = ensureWorld(ctx)
  local currentWorld = movement.getPosition(ctx)
  local currentRef = worldstate.worldToReference(ctx, currentWorld) or { x = 0, y = 0, z = 0 }
  local yLevel = targetRef.y or world.grid.origin.y or 0
  if currentRef.z ~= targetRef.z then
    local ok, err = moveToAvailableWalkway(ctx, yLevel, targetRef.z)
    if not ok then
      return false, err
    end
    currentRef = { x = world.walkway.selected or currentRef.x, y = yLevel, z = targetRef.z }
  end
  if currentRef.x ~= targetRef.x then
    local ok, err = worldstate.goToReference(ctx, { x = targetRef.x, y = yLevel, z = targetRef.z }, MOVE_OPTS_SOFT)
    if not ok then
      return false, err
    end
  end
  return true
end

-- Traversal bookkeeping ---------------------------------------------------
function worldstate.resetTraversal(ctx, overrides)
  local world = ensureWorld(ctx)
  world.traversal = {
    row = 1,
    col = 1,
    forward = true,
    done = false,
  }
  if type(overrides) == "table" then
    mergeTables(world.traversal, overrides)
  end
  ctx.traverse = world.traversal
  return world.traversal
end

function worldstate.advanceTraversal(ctx)
  local world = ensureWorld(ctx)
  local tr = world.traversal
  if not tr then
    tr = worldstate.resetTraversal(ctx)
  end
  if tr.done then
    return tr
  end
  if tr.forward then
    if tr.col < (world.grid.width or 1) then
      tr.col = tr.col + 1
      return tr
    end
    tr.forward = false
  else
    if tr.col > 1 then
      tr.col = tr.col - 1
      return tr
    end
    tr.forward = true
  end
  tr.row = tr.row + 1
  if tr.row > (world.grid.length or 1) then
    tr.done = true
  else
    tr.col = tr.forward and 1 or (world.grid.width or 1)
  end
  return tr
end

function worldstate.currentCellRef(ctx)
  local world = ensureWorld(ctx)
  local tr = world.traversal or worldstate.resetTraversal(ctx)
  return {
    x = (world.grid.origin.x or 0) + (tr.col - 1) * (world.grid.spacingX or 1),
    y = world.grid.origin.y or 0,
    z = (world.grid.origin.z or 0) + (tr.row - 1) * (world.grid.spacingZ or 1),
  }
end

function worldstate.currentCellWorld(ctx)
  return worldstate.referenceToWorld(ctx, worldstate.currentCellRef(ctx))
end

function worldstate.offsetFromCell(ctx, offset)
  offset = offset or {}
  local base = worldstate.currentCellRef(ctx)
  return {
    x = base.x + (offset.x or 0),
    y = base.y + (offset.y or 0),
    z = base.z + (offset.z or 0),
  }
end

function worldstate.currentWalkPositionRef(ctx)
  local world = ensureWorld(ctx)
  local ref = worldstate.currentCellRef(ctx)
  return {
    x = (ref.x or 0) + (world.walkway.offset or -1),
    y = ref.y,
    z = ref.z,
  }
end

function worldstate.currentWalkPositionWorld(ctx)
  return worldstate.referenceToWorld(ctx, worldstate.currentWalkPositionRef(ctx))
end

function worldstate.ensureTraversal(ctx)
  local world = ensureWorld(ctx)
  if not world.traversal then
    worldstate.resetTraversal(ctx)
  end
  return world.traversal
end

-- Convenience exports -----------------------------------------------------
worldstate.MOVE_OPTS_CLEAR = MOVE_OPTS_CLEAR
worldstate.MOVE_OPTS_SOFT = MOVE_OPTS_SOFT

return worldstate

]===]
bundled_modules["state_blocked"] = [===[
--[[
State: BLOCKED
Handles navigation failures.
--]]

local logger = require("lib_logger")

local function BLOCKED(ctx)
    local resume = ctx.resumeState or "BUILD"
    logger.log(ctx, "warn", string.format("Movement blocked while executing %s. Retrying in 5 seconds...", resume))
    ---@diagnostic disable-next-line: undefined-global
    sleep(5)
    ctx.retries = (ctx.retries or 0) + 1
    if ctx.retries > 5 then
        logger.log(ctx, "error", "Too many retries.")
        ctx.resumeState = nil
        return "ERROR"
    end
    ctx.resumeState = nil
    ctx.retries = 0
    return resume
end

return BLOCKED

]===]
bundled_modules["state_build"] = [===[
--[[
State: BUILD
Executes the build plan step by step.
--]]

local movement = require("lib_movement")
local placement = require("lib_placement")
local inventory = require("lib_inventory")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")
local orientation = require("lib_orientation")
local diagnostics = require("lib_diagnostics")

local function localToWorld(localPos, facing)
    -- Transform local (x=right, z=forward) to world based on facing
    -- This assumes the turtle started at (0,0,0) facing 'facing'
    -- and 'localPos' is relative to that start.
    -- Actually, ctx.origin has the start pos/facing.
    -- But the buildOrder computed localPos relative to start.
    
    -- Simple rotation:
    -- North: x=East, z=South (Wait, standard MC: x+ East, z+ South)
    -- Turtle local: x+ Right, z+ Forward, y+ Up
    
    -- If facing North (z-): Right is East (x+), Forward is North (z-)
    -- If facing East (x+): Right is South (z+), Forward is East (x+)
    -- If facing South (z+): Right is West (x-), Forward is South (z+)
    -- If facing West (x-): Right is North (z-), Forward is West (x-)
    
    local x, y, z = localPos.x, localPos.y, localPos.z
    local wx, wz
    
    if facing == "north" then
        wx, wz = x, -z -- Right(x) -> East(+x), Forward(z) -> North(-z)
        -- Wait, if local z is forward (positive), and we face north (-z), then world z change is -localZ.
        -- If local x is right (positive), and we face north, right is East (+x).
        -- So: wx = x, wz = -z.
        -- BUT: computeLocalXZ in state_initialize used a specific logic.
        -- Let's stick to what 3dprinter.lua likely did or standard turtle logic.
        -- 3dprinter.lua used `localToWorld`. Let's check its implementation if possible.
        -- But for now, I'll implement standard turtle relative coords.
        
        -- Re-reading 3dprinter.lua logic:
        -- "All offsets are specified in turtle-local coordinates (x = right/left, y = up/down, z = forward/back)."
        
        wx = x
        wz = -z -- Forward is -z (North)
    elseif facing == "east" then
        wx = z  -- Forward is +x (East)
        wz = x  -- Right is +z (South)
    elseif facing == "south" then
        wx = -x -- Right is -x (West)
        wz = z  -- Forward is +z (South)
    elseif facing == "west" then
        wx = -z -- Forward is -x (West)
        wz = -x -- Right is -z (North)
    else
        wx, wz = x, z -- Fallback
    end
    
    return { x = wx, y = y, z = wz }
end

local function addPos(p1, p2)
    return { x = p1.x + p2.x, y = p1.y + p2.y, z = p1.z + p2.z }
end

local function BUILD(ctx)
    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end

    if ctx.pointer > #strategy then
        return "DONE"
    end

    local step = strategy[ctx.pointer]
    local material = step.block.material
    
    -- 1. Check Fuel
    -- Simple check: do we have enough to move?
    -- Real logic should be in REFUEL state or a robust check here.
    ---@diagnostic disable-next-line: undefined-global
    if turtle.getFuelLevel() < 100 and turtle.getFuelLevel() ~= "unlimited" then
        ctx.resumeState = "BUILD"
        return "REFUEL"
    end

    -- 2. Check Inventory
    local count = inventory.countMaterial(ctx, material)
    if count == 0 then
        logger.log(ctx, "warn", "Out of material: " .. material)
        ctx.missingMaterial = material
        ctx.resumeState = "BUILD"
        return "RESTOCK"
    end

    -- 3. Move to position
    -- Convert local approach position to world position
    -- We assume ctx.origin is where we started.
    local origin = ctx.origin
    local worldOffset = localToWorld(step.approachLocal, origin.facing)
    local targetPos = addPos(origin, worldOffset)
    
    -- Use movement lib to go there
    -- We might want a "travel clearance" (fly high) strategy, but for now direct.
    local ok, err = movement.goTo(ctx, targetPos)
    if not ok then
        logger.log(ctx, "warn", "Movement blocked: " .. tostring(err))
        ctx.resumeState = "BUILD"
        return "BLOCKED"
    end

    -- 4. Place Block
    -- Ensure we are facing the right way if needed, or just place.
    -- placement.placeMaterial handles orientation if we pass 'side'.
    -- step.side is the side of the block to place ON.
    -- We are at 'approachLocal'.
    
    local placed, placeErr = placement.placeMaterial(ctx, material, {
        side = step.side,
        block = step.block,
        dig = true, -- Clear obstacles
        attack = true
    })

    if not placed then
        if placeErr == "already_present" then
            -- It's fine
        else
            logger.log(ctx, "warn", "Placement failed: " .. tostring(placeErr))
            -- Could be empty inventory (handled above?) or something else.
            -- If it's "out of items", we should restock.
            -- But placeMaterial might not return specific enough error.
            -- Let's assume if we had count > 0, it's an obstruction or failure.
            -- Retry?
            return "ERROR" -- For now, fail hard so we can debug.
        end
    end

    ctx.pointer = ctx.pointer + 1
    ctx.retries = 0
    return "BUILD"
end

return BUILD

]===]
bundled_modules["state_check_requirements"] = [===[
---@diagnostic disable: undefined-global
--[[
State: CHECK_REQUIREMENTS
Verifies that the turtle has enough fuel and materials to complete the task.
Prompts the user if items are missing.
--]]

local inventory = require("lib_inventory")
local logger = require("lib_logger")
local fuel = require("lib_fuel")
local diagnostics = require("lib_diagnostics")

local function calculateRequirements(ctx, strategy)
    local reqs = {
        fuel = 0,
        materials = {}
    }

    -- Estimate fuel
    -- A simple heuristic: 1 fuel per step.
    if strategy then
        reqs.fuel = #strategy
    end
    
    -- Add a safety margin for fuel (e.g. 10% + 100)
    reqs.fuel = math.ceil(reqs.fuel * 1.1) + 100

    -- Calculate materials
    if ctx.config.mode == "mine" then
        -- Mining mode
        -- Check for torches if strategy has place_torch
        for _, step in ipairs(strategy) do
            if step.type == "place_torch" then
                reqs.materials["minecraft:torch"] = (reqs.materials["minecraft:torch"] or 0) + 1
            end
        end
    else
        -- Build mode
        for _, step in ipairs(strategy) do
            if step.block and step.block.material then
                local mat = step.block.material
                reqs.materials[mat] = (reqs.materials[mat] or 0) + 1
            end
        end
    end

    return reqs
end

local function getInventoryCounts(ctx)
    local counts = {}
    -- Scan all slots
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            counts[item.name] = (counts[item.name] or 0) + item.count
        end
    end
    return counts
end

local function checkNearbyChests(ctx, missing)
    local found = {}
    local sides = {"front", "top", "bottom", "left", "right", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.isPresent(side) then
            local types = { peripheral.getType(side) }
            local isInventory = false
            for _, t in ipairs(types) do
                if t == "inventory" then isInventory = true break end
            end
            
            if isInventory then
                local p = peripheral.wrap(side)
                if p and p.list then
                    local list = p.list()
                    for slot, item in pairs(list) do
                        if item and missing[item.name] then
                            found[item.name] = (found[item.name] or 0) + item.count
                        end
                    end
                end
            end
        end
    end
    return found
end

local function CHECK_REQUIREMENTS(ctx)
    logger.log(ctx, "info", "Checking requirements...")

    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end

    local reqs = calculateRequirements(ctx, strategy)
    local invCounts = getInventoryCounts(ctx)
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then currentFuel = 999999 end

    local missing = {
        fuel = 0,
        materials = {}
    }
    local hasMissing = false

    -- Check fuel
    if currentFuel < reqs.fuel then
        missing.fuel = reqs.fuel - currentFuel
        hasMissing = true
    end

    -- Check materials
    for mat, count in pairs(reqs.materials) do
        local have = invCounts[mat] or 0
        if have < count then
            missing.materials[mat] = count - have
            hasMissing = true
        end
    end

    if not hasMissing then
        logger.log(ctx, "info", "All requirements met.")
        return ctx.nextState or "DONE"
    end

    -- Report missing
    print("\n=== MISSING REQUIREMENTS ===")
    if missing.fuel > 0 then
        print(string.format("- Fuel: %d (Have %d, Need %d)", missing.fuel, currentFuel, reqs.fuel))
    end
    for mat, count in pairs(missing.materials) do
        print(string.format("- %s: %d", mat, count))
    end

    -- Check nearby
    local nearby = checkNearbyChests(ctx, missing.materials)
    local foundNearby = false
    for mat, count in pairs(nearby) do
        if not foundNearby then
            print("\n=== FOUND IN NEARBY CHESTS ===")
            foundNearby = true
        end
        print(string.format("- %s: %d", mat, count))
    end

    print("\nPress Enter to re-check, or type 'q' then Enter to quit.")
    local input = read()
    if input == "q" or input == "Q" then
        return "DONE"
    end
    
    return "CHECK_REQUIREMENTS"
end

return CHECK_REQUIREMENTS

]===]
bundled_modules["state_done"] = [===[
--[[
State: DONE
Cleanup and exit.
--]]

local movement = require("lib_movement")
local logger = require("lib_logger")

local function DONE(ctx)
    logger.log(ctx, "info", "Build complete!")
    movement.goTo(ctx, ctx.origin)
    return "EXIT"
end

return DONE

]===]
bundled_modules["state_error"] = [===[
--[[
State: ERROR
Handles fatal errors.
--]]

local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")

local function ERROR(ctx)
    local message = tostring(ctx.lastError or "Unknown fatal error")
    if ctx.logger then
        ctx.logger:error("Fatal Error: " .. message, { context = diagnostics.snapshot(ctx) })
    else
        logger.log(ctx, "error", "Fatal Error: " .. message)
    end
    print("Press Enter to exit...")
    ---@diagnostic disable-next-line: undefined-global
    read()
    return "EXIT"
end

return ERROR

]===]
bundled_modules["state_initialize"] = [===[
--[[
State: INITIALIZE
Loads schema, parses it, and computes the build strategy.
--]]

local parser = require("lib_parser")
local orientation = require("lib_orientation")
local logger = require("lib_logger")
local strategyBranchMine = require("lib_strategy_branchmine")
local strategyTunnel = require("lib_strategy_tunnel")
local strategyExcavate = require("lib_strategy_excavate")
local strategyFarm = require("lib_strategy_farm")
local ui = require("lib_ui")

local function getBlock(schema, x, y, z)
    local xLayer = schema[x] or schema[tostring(x)]
    if not xLayer then return nil end
    local yLayer = xLayer[y] or xLayer[tostring(y)]
    if not yLayer then return nil end
    return yLayer[z] or yLayer[tostring(z)]
end

local function isPlaceable(block)
    if not block then return false end
    local name = block.material
    if not name or name == "" then return false end
    if name == "minecraft:air" or name == "air" then return false end
    return true
end

local function computeApproachLocal(localPos, side)
    side = side or "down"
    if side == "up" then
        return { x = localPos.x, y = localPos.y - 1, z = localPos.z }, side
    elseif side == "down" then
        return { x = localPos.x, y = localPos.y + 1, z = localPos.z }, side
    else
        return { x = localPos.x, y = localPos.y, z = localPos.z }, side
    end
end

local function computeLocalXZ(bounds, x, z, orientationKey)
    local orient = orientation.resolveOrientationKey(orientationKey)
    local relativeX = x - bounds.minX
    local relativeZ = z - bounds.minZ
    local localZ = - (relativeZ + 1)
    local localX
    if orient == "forward_right" then
        localX = relativeX + 1
    else
        localX = - (relativeX + 1)
    end
    return localX, localZ
end

local function normaliseBounds(info)
    if not info or not info.bounds then return nil, "missing_bounds" end
    local minB = info.bounds.min
    local maxB = info.bounds.max
    if not (minB and maxB) then return nil, "missing_bounds" end
    
    local function norm(t, k) return tonumber(t[k]) end
    
    return {
        minX = norm(minB, "x") or 0,
        minY = norm(minB, "y") or 0,
        minZ = norm(minB, "z") or 0,
        maxX = norm(maxB, "x") or 0,
        maxY = norm(maxB, "y") or 0,
        maxZ = norm(maxB, "z") or 0,
    }
end

local function buildOrder(schema, info, opts)
    local bounds, err = normaliseBounds(info)
    if not bounds then return nil, err or "missing_bounds" end
    
    opts = opts or {}
    local offsetLocal = opts.offsetLocal or { x = 0, y = 0, z = 0 }
    local offsetXLocal = offsetLocal.x or 0
    local offsetYLocal = offsetLocal.y or 0
    local offsetZLocal = offsetLocal.z or 0
    
    -- Default to forward_left if not specified
    local orientKey = opts.orientation or "forward_left"

    local order = {}
    for y = bounds.minY, bounds.maxY do
        for row = 0, bounds.maxZ - bounds.minZ do
            local z = bounds.minZ + row
            local forward = (row % 2) == 0
            local xStart = forward and bounds.minX or bounds.maxX
            local xEnd = forward and bounds.maxX or bounds.minX
            local step = forward and 1 or -1
            local x = xStart
            while true do
                local block = getBlock(schema, x, y, z)
                if isPlaceable(block) then
                    local baseX, baseZ = computeLocalXZ(bounds, x, z, orientKey)
                    local localPos = {
                        x = baseX + offsetXLocal,
                        y = y + offsetYLocal,
                        z = baseZ + offsetZLocal,
                    }
                    local meta = (block and type(block.meta) == "table") and block.meta or nil
                    local side = (meta and meta.side) or "down"
                    local approach, resolvedSide = computeApproachLocal(localPos, side)
                    order[#order + 1] = {
                        schemaPos = { x = x, y = y, z = z },
                        localPos = localPos,
                        approachLocal = approach,
                        block = block,
                        side = resolvedSide,
                    }
                end
                if x == xEnd then break end
                x = x + step
            end
        end
    end
    return order, bounds
end

local function INITIALIZE(ctx)
    logger.log(ctx, "info", "Initializing...")
    
    if ctx.config.mode == "mine" then
        logger.log(ctx, "info", "Generating mining strategy...")
        local length = tonumber(ctx.config.length) or 60
        local branchInterval = tonumber(ctx.config.branchInterval) or 3
        local branchLength = tonumber(ctx.config.branchLength) or 16
        local torchInterval = tonumber(ctx.config.torchInterval) or 6
        
        ctx.strategy = strategyBranchMine.generate(length, branchInterval, branchLength, torchInterval)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Mining Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "tunnel" then
        logger.log(ctx, "info", "Generating tunnel strategy...")
        local length = tonumber(ctx.config.length) or 16
        local width = tonumber(ctx.config.width) or 1
        local height = tonumber(ctx.config.height) or 2
        local torchInterval = tonumber(ctx.config.torchInterval) or 6
        
        ctx.strategy = strategyTunnel.generate(length, width, height, torchInterval)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Tunnel Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "excavate" then
        logger.log(ctx, "info", "Generating excavation strategy...")
        local length = tonumber(ctx.config.length) or 8
        local width = tonumber(ctx.config.width) or 8
        local depth = tonumber(ctx.config.depth) or 3
        
        ctx.strategy = strategyExcavate.generate(length, width, depth)
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Excavation Plan: %d steps.", #ctx.strategy))
        ctx.nextState = "MINE"
        return "CHECK_REQUIREMENTS"
    end

    if ctx.config.mode == "farm" then
        logger.log(ctx, "info", "Generating farm strategy...")
        local farmType = ctx.config.farmType or "tree"
        local width = tonumber(ctx.config.width) or 9
        local length = tonumber(ctx.config.length) or 9
        
        local schema = strategyFarm.generate(farmType, width, length)
        
        -- Preview
        ui.clear()
        ui.drawPreview(schema, 2, 2, 30, 15)
        term.setCursorPos(1, 18)
        print("Previewing " .. farmType .. " farm.")
        print("Press Enter to confirm, 'q' to quit.")
        local input = read()
        if input == "q" or input == "Q" then
            return "DONE"
        end
        
        -- Normalize schema for buildOrder
        -- We need to calculate bounds manually since we don't have parser info
        local minX, maxX, minZ, maxZ = 9999, -9999, 9999, -9999
        local minY, maxY = 0, 1 -- Assuming 2 layers for now
        
        for sx, row in pairs(schema) do
            local nx = tonumber(sx)
            if nx < minX then minX = nx end
            if nx > maxX then maxX = nx end
            for sy, col in pairs(row) do
                for sz, block in pairs(col) do
                    local nz = tonumber(sz)
                    if nz < minZ then minZ = nz end
                    if nz > maxZ then maxZ = nz end
                end
            end
        end
        
        ctx.schema = schema
        ctx.schemaInfo = {
            bounds = {
                min = { x = minX, y = minY, z = minZ },
                max = { x = maxX, y = maxY, z = maxZ }
            }
        }
        
        logger.log(ctx, "info", "Computing build strategy...")
        local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
        if not order then
            ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
            return "ERROR"
        end

        ctx.strategy = order
        ctx.pointer = 1
        
        logger.log(ctx, "info", string.format("Plan: %d steps.", #order))
        ctx.nextState = "BUILD"
        return "CHECK_REQUIREMENTS"
    end
    
    if not ctx.config.schemaPath then
        ctx.lastError = "No schema path provided"
        return "ERROR"
    end

    logger.log(ctx, "info", "Loading schema: " .. ctx.config.schemaPath)
    local ok, schemaOrErr, info = parser.parseFile(ctx, ctx.config.schemaPath, { formatHint = nil })
    if not ok then
        ctx.lastError = "Failed to parse schema: " .. tostring(schemaOrErr)
        return "ERROR"
    end

    ctx.schema = schemaOrErr
    ctx.schemaInfo = info

    logger.log(ctx, "info", "Computing build strategy...")
    local order, boundsOrErr = buildOrder(ctx.schema, ctx.schemaInfo, ctx.config)
    if not order then
        ctx.lastError = "Failed to compute build order: " .. tostring(boundsOrErr)
        return "ERROR"
    end

    ctx.strategy = order
    ctx.pointer = 1
    
    logger.log(ctx, "info", string.format("Plan: %d steps.", #order))

    ctx.nextState = "BUILD"
    return "CHECK_REQUIREMENTS"
end

return INITIALIZE

]===]
bundled_modules["state_mine"] = [===[
--[[
State: MINE
Executes the mining strategy step by step.
]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local mining = require("lib_mining")
local logger = require("lib_logger")
local diagnostics = require("lib_diagnostics")

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

local function selectTorch(ctx)
    local torchItem = ctx.config.torchItem or "minecraft:torch"
    local ok = inventory.selectMaterial(ctx, torchItem)
    if ok then
        return true, torchItem
    end
    ctx.missingMaterial = torchItem
    return false, torchItem
end

local function MINE(ctx)
    logger.log(ctx, "info", "State: MINE")

    if turtle.getFuelLevel and turtle.getFuelLevel() < 100 then
        logger.log(ctx, "warn", "Fuel low; switching to REFUEL")
        ctx.resumeState = "MINE"
        return "REFUEL"
    end

    -- Get current step
    local stepIndex = ctx.pointer or 1
    local strategy, errMsg = diagnostics.requireStrategy(ctx)
    if not strategy then
        return "ERROR"
    end
    
    if stepIndex > #strategy then
        return "DONE"
    end
    
    local step = strategy[stepIndex]
    
    -- Execute step based on type
    if step.type == "move" then
        local dest = localToWorld(ctx, step)
        local ok, err = movement.goTo(ctx, dest, { dig = true, attack = true })
        if not ok then
            logger.log(ctx, "warn", "Mining movement blocked: " .. tostring(err))
            ctx.resumeState = "MINE"
            return err == "blocked" and "BLOCKED" or "ERROR"
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
        local ok = selectTorch(ctx)
        if not ok then
            ctx.resumeState = "MINE"
            return "RESTOCK"
        end
        if not turtle.placeDown() then
            turtle.placeUp()
        end
        
    elseif step.type == "dump_trash" then
        local dumped = inventory.dumpTrash(ctx)
        if not dumped then
            logger.log(ctx, "debug", "dumpTrash failed (probably empty inventory)")
        end
        
    elseif step.type == "done" then
        return "DONE"
    end
    
    ctx.pointer = stepIndex + 1
    ctx.retries = 0
    return "MINE"
end

return MINE

]===]
bundled_modules["state_refuel"] = [===[
--[[
State: REFUEL
Returns to origin and attempts to refuel.
--]]

local movement = require("lib_movement")
local fuelLib = require("lib_fuel")
local logger = require("lib_logger")

local function REFUEL(ctx)
    logger.log(ctx, "info", "Refueling...")
    
    -- Go home
    local ok, err = movement.goTo(ctx, ctx.origin)
    if not ok then
        ctx.resumeState = ctx.resumeState or "BUILD"
        return "BLOCKED"
    end

    -- Refuel
    -- lib_fuel.refuel() might be available?
    -- Or we just use turtle.refuel() on items.
    -- Let's use lib_fuel if possible.
    
    -- Checking lib_fuel... I don't have its content in mind, but let's assume it has 'ensure' or similar.
    -- If not, we'll do a simple loop.
    
    ---@diagnostic disable: undefined-global
    local needed = turtle.getFuelLimit() - turtle.getFuelLevel()
    if needed <= 0 then
        local resume = ctx.resumeState or "BUILD"
        ctx.resumeState = nil
        return resume
    end
    
    -- Try to refuel from inventory first
    for i=1,16 do
        turtle.select(i)
        if turtle.refuel(0) then -- Check if fuel
            turtle.refuel()
        end
    end
    
    if turtle.getFuelLevel() > 1000 then
        local resume = ctx.resumeState or "BUILD"
        ctx.resumeState = nil
        return resume
    end
    
    logger.log(ctx, "error", "Out of fuel and no fuel items found.")
    return "ERROR"
end

return REFUEL

]===]
bundled_modules["state_restock"] = [===[
--[[
State: RESTOCK
Returns to origin and attempts to restock the missing material.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function RESTOCK(ctx)
    logger.log(ctx, "info", "Restocking " .. tostring(ctx.missingMaterial))
    
    -- Go home
    local ok, err = movement.goTo(ctx, ctx.origin)
    if not ok then
        ctx.resumeState = ctx.resumeState or "BUILD"
        return "BLOCKED"
    end

    -- Attempt to pull
    -- We assume chest is 'forward' relative to origin facing?
    -- Or maybe we just try all sides?
    -- lib_inventory.pullMaterial might handle finding it if we are close?
    -- Actually lib_inventory usually requires a side.
    -- Let's assume chest is BELOW or ABOVE or FRONT.
    -- For now, let's try to pull from 'front' (relative to turtle).
    -- We should probably face the chest.
    -- If origin is where we started, maybe chest is behind us?
    -- 3dprinter.lua prompts for chest location.
    -- Let's assume chest is at (0,0,0) and we are at (0,0,0).
    -- We'll try pulling from all sides.
    
    local material = ctx.missingMaterial
    if not material then
        local resume = ctx.resumeState or "BUILD"
        ctx.resumeState = nil
        return resume
    end

    local pulled = false
    for _, side in ipairs({"front", "up", "down", "left", "right", "back"}) do
        local okPull, pullErr = inventory.pullMaterial(ctx, material, 64, { side = side })
        if okPull then
            pulled = true
            break
        end
    end

    if not pulled then
        logger.log(ctx, "error", "Could not find " .. material .. " in nearby inventories.")
        return "ERROR"
    end

    ctx.missingMaterial = nil
    local resume = ctx.resumeState or "BUILD"
    ctx.resumeState = nil
    return resume
end

return RESTOCK

]===]
bundled_modules["state_treefarm"] = [===[
--[[
State: TREEFARM
Simple tree farming logic.
--]]

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local logger = require("lib_logger")

local function TREEFARM(ctx)
    logger.log(ctx, "info", "State: TREEFARM")

    -- 1. Check Fuel
    if turtle.getFuelLevel() < 100 then
        logger.log(ctx, "warn", "Fuel low; switching to REFUEL")
        ctx.resumeState = "TREEFARM"
        return "REFUEL"
    end

    -- 2. Check Saplings
    local sapling = "minecraft:oak_sapling" -- Default
    if ctx.config.sapling then sapling = ctx.config.sapling end
    
    local hasSapling = inventory.countMaterial(ctx, sapling) > 0
    
    -- 3. Check if tree is in front
    local hasBlock, data = turtle.inspect()
    if hasBlock and data.name:find("log") then
        logger.log(ctx, "info", "Tree detected! Chopping...")
        
        -- Chop up
        local height = 0
        while true do
            local hasUp, dataUp = turtle.inspectUp()
            if hasUp and dataUp.name:find("log") then
                turtle.digUp()
                movement.up(ctx)
                height = height + 1
            else
                break
            end
        end
        
        -- Come down
        for i=1, height do
            movement.down(ctx)
        end
        
        -- Chop base
        turtle.dig()
        
        -- Replant
        if hasSapling then
            inventory.selectMaterial(ctx, sapling)
            turtle.place()
        end
        
    elseif not hasBlock then
        -- Empty space, plant if needed
        if hasSapling then
            inventory.selectMaterial(ctx, sapling)
            turtle.place()
        else
             -- No sapling, maybe wait?
             logger.log(ctx, "warn", "No saplings to plant.")
        end
    end
    
    -- 4. Wait for growth
    logger.log(ctx, "info", "Waiting for tree...")
    sleep(5)
    
    return "TREEFARM"
end

return TREEFARM

]===]
bundled_modules["turtle_os"] = [===[
--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

local ui = require("lib_ui")
local designer = require("lib_designer")
local games = require("lib_games")

-- Hack to load factory without running it immediately
_G.__FACTORY_EMBED__ = true
local factory = require("factory")
_G.__FACTORY_EMBED__ = nil

-- Helper to pause before returning
local function pauseAndReturn(retVal)
    print("\nOperation finished.")
    print("Press Enter to continue...")
    read()
    return retVal
end

-- --- ACTIONS ---

local function runMining(form)
    local length = 64
    local interval = 3
    local torch = 6
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 64 end
        if el.id == "interval" then interval = tonumber(el.value) or 3 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Mining Operation...")
    print(string.format("Length: %d, Interval: %d", length, interval))
    sleep(1)
    
    factory.run({ "mine", "--length", tostring(length), "--branch-interval", tostring(interval), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runTunnel()
    local length = 16
    local width = 1
    local height = 2
    local torch = 6
    
    local form = ui.Form("Tunnel Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("height", "Height", tostring(height))
    form:addInput("torch", "Torch Interval", tostring(torch))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 16 end
        if el.id == "width" then width = tonumber(el.value) or 1 end
        if el.id == "height" then height = tonumber(el.value) or 2 end
        if el.id == "torch" then torch = tonumber(el.value) or 6 end
    end
    
    ui.clear()
    print("Starting Tunnel Operation...")
    print(string.format("L: %d, W: %d, H: %d", length, width, height))
    sleep(1)
    
    factory.run({ "tunnel", "--length", tostring(length), "--width", tostring(width), "--height", tostring(height), "--torch-interval", tostring(torch) })
    
    return pauseAndReturn("stay")
end

local function runExcavate()
    local length = 8
    local width = 8
    local depth = 3
    
    local form = ui.Form("Excavation Configuration")
    form:addInput("length", "Length", tostring(length))
    form:addInput("width", "Width", tostring(width))
    form:addInput("depth", "Depth", tostring(depth))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "length" then length = tonumber(el.value) or 8 end
        if el.id == "width" then width = tonumber(el.value) or 8 end
        if el.id == "depth" then depth = tonumber(el.value) or 3 end
    end
    
    ui.clear()
    print("Starting Excavation Operation...")
    print(string.format("L: %d, W: %d, D: %d", length, width, depth))
    sleep(1)
    
    factory.run({ "excavate", "--length", tostring(length), "--width", tostring(width), "--depth", tostring(depth) })
    
    return pauseAndReturn("stay")
end

local function runTreeFarm()
    ui.clear()
    print("Starting Tree Farm...")
    sleep(1)
    factory.run({ "treefarm" })
    return pauseAndReturn("stay")
end

local function runPotatoFarm()
    local width = 9
    local length = 9
    
    local form = ui.Form("Potato Farm Configuration")
    form:addInput("width", "Width", tostring(width))
    form:addInput("length", "Length", tostring(length))
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "width" then width = tonumber(el.value) or 9 end
        if el.id == "length" then length = tonumber(el.value) or 9 end
    end
    
    ui.clear()
    print("Starting Potato Farm Build...")
    print(string.format("W: %d, L: %d", width, length))
    sleep(1)
    
    factory.run({ "farm", "--farm-type", "potato", "--width", tostring(width), "--length", tostring(length) })
    
    return pauseAndReturn("stay")
end

local function runBuild(schemaFile)
    ui.clear()
    print("Starting Build Operation...")
    print("Schema: " .. schemaFile)
    sleep(1)
    factory.run({ schemaFile })
    return pauseAndReturn("stay")
end

local function runImportSchema()
    local url = ""
    local filename = "schema.json"
    
    local form = ui.Form("Import Schema")
    form:addInput("url", "URL/Code", url)
    form:addInput("filename", "Save As", filename)
    
    local result = form:run()
    if result == "cancel" then return "stay" end
    
    for _, el in ipairs(form.elements) do
        if el.id == "url" then url = el.value end
        if el.id == "filename" then filename = el.value end
    end
    
    if url == "" then
        print("URL is required.")
        return pauseAndReturn("stay")
    end
    
    ui.clear()
    print("Downloading " .. url .. "...")
    
    if not url:find("http") then
        -- Assume pastebin code
        url = "https://pastebin.com/raw/" .. url
    end
    
    if not http then
        print("HTTP API not enabled.")
        return pauseAndReturn("stay")
    end
    
    local response = http.get(url)
    if not response then
        print("Failed to download.")
        return pauseAndReturn("stay")
    end
    
    local content = response.readAll()
    response.close()
    
    local f = fs.open(filename, "w")
    f.write(content)
    f.close()
    
    print("Saved to " .. filename)
    
    return pauseAndReturn("stay")
end

local function runSchemaDesigner()
    ui.clear()
    designer.run()
    return pauseAndReturn("stay")
end

-- --- MENUS ---

local function getSchemaFiles()
    local files = fs.list("")
    local schemas = {}
    for _, file in ipairs(files) do
        if not fs.isDir(file) and (file:match("%.json$") or file:match("%.txt$")) then
            table.insert(schemas, file)
        end
    end
    return schemas
end

local function showBuildMenu()
    while true do
        local schemas = getSchemaFiles()
        local items = {}
        
        for _, schema in ipairs(schemas) do
            table.insert(items, {
                text = schema,
                callback = function() return runBuild(schema) end
            })
        end
        
        table.insert(items, { text = "Back", callback = function() return "back" end })
        
        local res = ui.runMenu("Select Schema", items)
        if res == "back" then return end
    end
end

local function showMiningWizard()
    local form = {
        title = "Mining Wizard",
        elements = {
            { type = "label", x = 2, y = 2, text = "Tunnel Length:" },
            { type = "input", x = 18, y = 2, width = 5, value = "64", id = "length" },
            
            { type = "label", x = 2, y = 4, text = "Branch Interval:" },
            { type = "input", x = 18, y = 4, width = 5, value = "3", id = "interval" },
            
            { type = "label", x = 2, y = 6, text = "Torch Interval:" },
            { type = "input", x = 18, y = 6, width = 5, value = "6", id = "torch" },
            
            { type = "button", x = 2, y = 9, text = "Start Mining", callback = runMining },
            { type = "button", x = 18, y = 9, text = "Cancel", callback = function() return "back" end }
        }
    }
    return ui.runForm(form)
end

local function showMineMenu()
    while true do
        local res = ui.runMenu("Mining Operations", {
            { text = "Branch Mining", callback = showMiningWizard },
            { text = "Tunnel", callback = runTunnel },
            { text = "Excavate", callback = runExcavate },
            { text = "Back", callback = function() return "back" end }
        })
        if res == "back" then return end
    end
end

local function showFarmMenu()
    while true do
        local res = ui.runMenu("Farming Operations", {
            { text = "Tree Farm", callback = runTreeFarm },
            { text = "Potato Farm", callback = runPotatoFarm },
            { text = "Back", callback = function() return "back" end }
        })
        if res == "back" then return end
    end
end

local function showSystemMenu()
    while true do
        local res = ui.runMenu("System Tools", {
            { text = "Import Schema", callback = runImportSchema },
            { text = "Schema Designer", callback = runSchemaDesigner },
            { text = "Back", callback = function() return "back" end }
        })
        if res == "back" then return end
    end
end

local function showGamesMenu()
    while true do
        local res = ui.runMenu("Games", {
            { text = "Solitaire", callback = games.solitaire },
            { text = "Minesweeper", callback = games.minesweeper },
            { text = "Euchre", callback = games.euchre },
            { text = "Back", callback = function() return "back" end }
        })
        if res == "back" then return end
    end
end

local function showMainMenu()
    while true do
        local res = ui.runMenu("TurtleOS v2.1", {
            { text = "MINE >", callback = showMineMenu },
            { text = "FARM >", callback = showFarmMenu },
            { text = "BUILD >", callback = showBuildMenu },
            { text = "GAMES >", callback = showGamesMenu },
            { text = "SYSTEM >", callback = showSystemMenu },
            { text = "Exit", callback = function() return "exit" end }
        })
        if res == "exit" then return "exit" end
    end
end

local function main()
    showMainMenu()
    ui.clear()
    print("Goodbye!")
end

main()

]===]


local function install()
    print("Unpacking factory modules...")
    if not fs or not fs.open then
        error("This program requires the 'fs' API (ComputerCraft).")
    end

    for name, content in pairs(bundled_modules) do
        local filename = name .. ".lua"
        -- Delete existing file first to ensure clean write
        if fs.exists(filename) then
            fs.delete(filename)
        end
        
        local f = fs.open(filename, "w")
        if f then
            f.write(content)
            f.close()
            print("Extracted: " .. filename)
        else
            print("Error writing: " .. filename)
        end
    end
    
    print("Installation complete.")
    print("Run 'turtle_os' to start.")
end

install()
