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
