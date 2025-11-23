--[[
Main entry point for the modular agent system.
Implements the finite state machine loop.
--]]

local logger = require("lib_logger")
local movement = require("lib_movement")

-- Load states
local states = {
    INITIALIZE = require("state_initialize"),
    BUILD = require("state_build"),
    MINE = require("state_mine"),
    RESTOCK = require("state_restock"),
    REFUEL = require("state_refuel"),
    BLOCKED = require("state_blocked"),
    ERROR = require("state_error"),
    DONE = require("state_done")
}

local function main(args)
    -- Initialize context
    local ctx = {
        state = "INITIALIZE",
        config = {
            verbose = false,
            schemaPath = nil
        },
        origin = { x=0, y=0, z=0, facing="north" }, -- Default home
        pointer = 1, -- Current step in the build path
        schema = nil, -- Will be loaded by INITIALIZE
        strategy = nil, -- Will be computed by INITIALIZE
        inventoryState = {},
        fuelState = {},
        retries = 0
    }

    -- Parse args
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "--verbose" then
            ctx.config.verbose = true
        elseif arg == "mine" then
            ctx.config.mode = "mine"
        elseif arg == "--length" then
            i = i + 1
            ctx.config.length = tonumber(args[i])
        elseif arg == "--branch-interval" then
            i = i + 1
            ctx.config.branchInterval = tonumber(args[i])
        elseif arg == "--branch-length" then
            i = i + 1
            ctx.config.branchLength = tonumber(args[i])
        elseif arg == "--torch-interval" then
            i = i + 1
            ctx.config.torchInterval = tonumber(args[i])
        elseif not arg:find("^--") and not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
             ctx.config.schemaPath = arg
        end
        i = i + 1
    end
    
    if not ctx.config.schemaPath and ctx.config.mode ~= "mine" then
        ctx.config.schemaPath = "schema.json"
    end

    logger.init(ctx.config.verbose)
    logger.info("Agent starting...")

    -- State machine loop
    while ctx.state ~= "EXIT" do
        local currentStateFunc = states[ctx.state]
        if not currentStateFunc then
            logger.error("Unknown state: " .. tostring(ctx.state))
            break
        end

        logger.debug("Entering state: " .. ctx.state)
        
        local ok, nextStateOrErr = pcall(currentStateFunc, ctx)
        
        if not ok then
            logger.error("Crash in state " .. ctx.state .. ": " .. tostring(nextStateOrErr))
            ctx.lastError = nextStateOrErr
            ctx.state = "ERROR"
        else
            ctx.state = nextStateOrErr
        end
        
        ---@diagnostic disable-next-line: undefined-global
        sleep(0) -- Yield to avoid "Too long without yielding"
    end

    logger.info("Agent finished.")
end

local args = { ... }
main(args)
