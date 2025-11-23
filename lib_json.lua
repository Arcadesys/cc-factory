--[[
JSON library for CC:Tweaked turtles.
Provides helpers for encoding and decoding JSON.
--]]

---@diagnostic disable: undefined-global

local json_utils = {}

function json_utils.decodeJson(text)
    if type(text) ~= "string" then
        return nil, "invalid_json"
    end
    if textutils and textutils.unserializeJSON then
        local ok, result = pcall(textutils.unserializeJSON, text)
        if ok and result ~= nil then
            return result
        end
        return nil, "json_parse_failed"
    end
    local ok, json = pcall(require, "json")
    if ok and type(json) == "table" and type(json.decode) == "function" then
        local okDecode, result = pcall(json.decode, text)
        if okDecode then
            return result
        end
        return nil, "json_parse_failed"
    end
    return nil, "json_decoder_unavailable"
end

return json_utils
