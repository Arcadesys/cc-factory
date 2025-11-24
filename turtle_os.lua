--[[
TurtleOS v2.0
Graphical launcher for the factory agent.
--]]

local ui = require("lib_ui")

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
    ui.clear()
    print("Tunneling not implemented yet.")
    return pauseAndReturn("stay")
end

local function runExcavate()
    ui.clear()
    print("Excavation not implemented yet.")
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
    ui.clear()
    print("Potato Farm not implemented yet.")
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
    ui.clear()
    print("Import Schema not implemented yet.")
    return pauseAndReturn("stay")
end

local function runSchemaDesigner()
    ui.clear()
    print("Schema Designer not implemented yet.")
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

local function showMainMenu()
    while true do
        local res = ui.runMenu("TurtleOS v2.1", {
            { text = "MINE >", callback = showMineMenu },
            { text = "FARM >", callback = showFarmMenu },
            { text = "BUILD >", callback = showBuildMenu },
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
