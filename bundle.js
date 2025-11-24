const fs = require('fs');
const path = require('path');

const OUTPUT_DIR = 'dist';
const OUTPUT_FILE = path.join(OUTPUT_DIR, 'factory.lua');

if (!fs.existsSync(OUTPUT_DIR)){
    fs.mkdirSync(OUTPUT_DIR);
}

// Dynamic file discovery
// We want to bundle:
// 1. factory.lua (Entry point)
// 2. turtle_os.lua (UI)
// 3. state_*.lua (State machine states)
// 4. lib_*.lua (Libraries)
// We exclude:
// 1. harness_*.lua (Test harnesses)
// 2. main.lua (Legacy/Dev entry point)
// 3. bundle.js (The bundler itself)
// 4. dist/ (Output directory)

const allFiles = fs.readdirSync(__dirname);

const MODULE_FILES = allFiles.filter(file => {
    // Must be a .lua file
    if (!file.endsWith('.lua')) return false;
    
    // Exclude harnesses
    if (file.startsWith('harness_')) return false;
    
    // Exclude main.lua (legacy/dev entry point, factory.lua is the production one)
    if (file === 'main.lua') return false;

    // Explicitly include specific categories to avoid bundling random scripts
    if (file === 'factory.lua' || 
        file === 'turtle_os.lua' || 
        file.startsWith('state_') || 
        file.startsWith('lib_')) {
        return true;
    }
    
    return false;
});

let bundledModules = "";

MODULE_FILES.forEach(file => {
    const filePath = path.join(__dirname, file);
    try {
        let content = fs.readFileSync(filePath, 'utf8');
        // Normalize line endings
        content = content.replace(/\r\n/g, '\n');
        
        // Get module name (filename without extension)
        const moduleName = path.basename(file, '.lua');
        
        // Append to bundled modules string
        // Using [===[ ... ]===] for long strings.
        // We assume content doesn't contain ]===]. 
        // If it does, we'd need a more complex escaping strategy, but for Lua code it's usually fine.
        bundledModules += `bundled_modules["${moduleName}"] = [===[
${content}
]===]\n`;
        console.log(`Bundled ${file}`);
    } catch (err) {
        console.error(`Error reading ${file}: ${err.message}`);
        process.exit(1);
    }
});

const bootstrapCode = `
-- Auto-generated installer by bundle.js
local bundled_modules = {}
${bundledModules}

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
`;

fs.writeFileSync(OUTPUT_FILE, bootstrapCode);
console.log(`Successfully created ${OUTPUT_FILE}`);

