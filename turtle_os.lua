--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

local ui = require("lib_ui")
local designer = require("lib_designer")
local games = require("lib_games")
local parser = require("lib_parser")
local json = require("lib_json")
local schema_utils = require("lib_schema")

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

local function runEditSchema(schemaFile)
    ui.clear()
    print("Validating Schema...")
    print("Schema: " .. schemaFile)

    local ctx = {}
    local ok, schema, metadata = parser.parseFile(ctx, schemaFile)
    if not ok then
        print("Failed to parse schema: " .. tostring(schema))
        return pauseAndReturn("stay")
    end

    local editedSchema, exportInfo = designer.run({
        schema = schema,
        metadata = metadata,
        returnSchema = true,
    })

    if not editedSchema then
        local errMsg = exportInfo or "Editor closed without returning a schema."
        print(tostring(errMsg))
        return pauseAndReturn("stay")
    end

    print(string.format("Editor returned %d blocks.", (exportInfo and exportInfo.totalBlocks) or 0))

    local defaultName = schemaFile
    local form = ui.Form("Save Edited Schema")
    form:addInput("filename", "Filename", defaultName)
    local result = form:run()
    if result == "cancel" then return "stay" end

    local filename = defaultName
    for _, el in ipairs(form.elements) do
        if el.id == "filename" then filename = el.value end
    end
    if filename == "" then filename = defaultName end
    if not filename:match("%.json$") then filename = filename .. ".json" end

    if fs.exists(filename) then
        local backup = filename .. ".bak"
        fs.copy(filename, backup)
        print("Existing file backed up to " .. backup)
    end

    local definition = schema_utils.canonicalToVoxelDefinition(editedSchema)
    local f = fs.open(filename, "w")
    f.write(json.encode(definition))
    f.close()

    print("Saved edited schema to " .. filename)
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

local function showEditMenu()
    while true do
        local schemas = getSchemaFiles()
        local items = {}

        for _, schema in ipairs(schemas) do
            table.insert(items, {
                text = "Edit " .. schema,
                callback = function() return runEditSchema(schema) end
            })
        end

        table.insert(items, { text = "Back", callback = function() return "back" end })

        local res = ui.runMenu("Validate & Edit Schema", items)
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
            { text = "Validate & Edit Schema", callback = showEditMenu },
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
