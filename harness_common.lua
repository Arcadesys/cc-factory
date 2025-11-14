-- Shared utilities for harness_* scripts.
-- Provides standardized logging, prompting, and step/result tracking so
-- harnesses can double as automated tests while keeping console output short.

local common = {}

local function resolveIo(io)
    if type(io) ~= "table" then
        io = {}
    end

    local resolved = {
        print = io.print or print,
        read = io.read or _G.read,
        sleep = io.sleep or _G.sleep,
        write = io.write or _G.write or write,
    }

    if type(resolved.write) ~= "function" then
        local printFn = resolved.print
        resolved.write = function(text)
            if printFn then
                printFn(text)
            end
        end
    end

    resolved.term = io.term or term
    resolved.colors = io.colors or colors

    return resolved
end

common.resolveIo = resolveIo

function common.makeLogger(ctx, io)
    io = resolveIo(io)
    local logger = {}

    local function emit(prefix, msg)
        if io.print then
            io.print(string.format("[%s] %s", prefix, msg))
        end
    end

    function logger.info(msg)
        emit("INFO", msg)
    end

    function logger.warn(msg)
        emit("WARN", msg)
    end

    function logger.error(msg)
        emit("ERROR", msg)
    end

    function logger.debug(msg)
        if ctx.config and ctx.config.verbose then
            emit("DEBUG", msg)
        end
    end

    return logger
end

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

function common.merge(base, overrides)
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
                result[k] = common.merge(result[k], v)
            else
                result[k] = deepCopy(v)
            end
        end
    elseif overrides ~= nil then
        return deepCopy(overrides)
    end

    return result
end

local function trim(text)
    if type(text) ~= "string" then
        return text
    end
    return text:match("^%s*(.-)%s*$")
end

function common.prompt(io, message, opts)
    io = resolveIo(io)
    opts = opts or {}
    if io.print then
        io.print(message)
    end

    if io.read then
        local line = io.read()
        if not opts.allowEmpty then
            line = trim(line)
            if line and line ~= "" then
                return line
            end
        else
            return line
        end
    elseif io.sleep and opts.sleepSeconds then
        io.sleep(opts.sleepSeconds)
    elseif io.sleep then
        io.sleep(1)
    end

    return opts.default
end

function common.promptEnter(io, message)
    return common.prompt(io, message, { allowEmpty = true })
end

function common.promptInput(io, message, default)
    local suffix = ""
    if default and default ~= "" then
        suffix = string.format(" [%s]", default)
    end
    return common.prompt(io, message .. suffix, { default = default }) or default
end

local function supportsColor(io)
    local termObj = io.term
    local colorsObj = io.colors
    if not termObj or type(termObj.setTextColor) ~= "function" then
        return false
    end
    if type(termObj.isColor) == "function" then
        local ok, result = pcall(termObj.isColor)
        if ok then
            return result and colorsObj
        end
    end
    return false
end

local function runStep(fn)
    local ok, result, extra = xpcall(fn, debug.traceback)
    if not ok then
        return false, result
    end
    if type(result) == "boolean" then
        if result then
            return true, extra
        else
            return false, extra
        end
    end
    if result == nil then
        return true
    end
    return true, result
end

function common.createSuite(opts)
    opts = opts or {}
    local io = resolveIo(opts.io)
    local suite = {
        name = opts.name or "Harness",
        results = {},
        io = io,
    }

    function suite:step(name, fn)
        if self.io.print then
            self.io.print("\n== " .. name .. " ==")
        end
        local ok, err = runStep(fn)
        if self.io.print then
            if ok then
                self.io.print("Result: PASS")
            else
                self.io.print("Result: FAIL - " .. tostring(err))
            end
        end
        self.results[#self.results + 1] = {
            name = name,
            ok = ok,
            err = err,
        }
        return ok, err
    end

    function suite:summary()
        if not self.io.print then
            return
        end

        local count = #self.results
        local passed = 0
        self.io.print("\n== Summary: " .. self.name .. " ==")
        local hasColor = supportsColor(self.io)
        local defaultColor
        if hasColor and type(self.io.term.getTextColor) == "function" then
            defaultColor = self.io.term.getTextColor()
        end
        for index, result in ipairs(self.results) do
            local label = result.ok and "PASS" or "FAIL"
            local color = nil
            if hasColor and self.io.colors then
                color = result.ok and self.io.colors.green or self.io.colors.red
            end
            if self.io.write then
                self.io.write(string.format("%2d) ", index))
            else
                self.io.print(string.format("%2d) ", index))
            end
            if hasColor and color then
                self.io.term.setTextColor(color)
            end
            if self.io.write then
                self.io.write("[" .. label .. "]")
            else
                self.io.print("[" .. label .. "]")
            end
            if hasColor and defaultColor then
                self.io.term.setTextColor(defaultColor)
            end
            if self.io.write then
                self.io.write(" " .. result.name .. "\n")
            else
                self.io.print(" " .. result.name)
            end
            if result.ok then
                passed = passed + 1
            end
        end
        self.io.print(string.format("Completed %d/%d steps.", passed, count))
    end

    return suite
end

return common
