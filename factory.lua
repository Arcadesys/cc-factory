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
        elseif value == "farm" then
            ctx.config.mode = "farm"
        elseif value == "--farm-type" then
            index = index + 1
            ctx.config.farmType = args[index]
        elseif value == "--width" then
            index = index + 1
            ctx.config.width = tonumber(args[index])
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
