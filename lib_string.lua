local string_utils = {}

function string_utils.trim(text)
    if type(text) ~= "string" then
        return text
    end
    return text:match("^%s*(.-)%s*$")
end

return string_utils
