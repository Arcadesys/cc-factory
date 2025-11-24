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
