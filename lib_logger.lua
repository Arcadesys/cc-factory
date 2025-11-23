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
