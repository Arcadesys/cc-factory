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
