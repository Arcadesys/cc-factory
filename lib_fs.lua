local fs_utils = {}

local createdArtifacts = {}

function fs_utils.stageArtifact(path)
    for _, existing in ipairs(createdArtifacts) do
        if existing == path then
            return
        end
    end
    createdArtifacts[#createdArtifacts + 1] = path
end

function fs_utils.writeFile(path, contents)
    if type(path) ~= "string" or path == "" then
        return false, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "w")
        if not handle then
            return false, "open_failed"
        end
        handle.write(contents)
        handle.close()
        return true
    end
    if io and io.open then
        local handle, err = io.open(path, "w")
        if not handle then
            return false, err or "open_failed"
        end
        handle:write(contents)
        handle:close()
        return true
    end
    return false, "fs_unavailable"
end

function fs_utils.deleteFile(path)
    if fs and fs.delete and fs.exists then
        local ok, exists = pcall(fs.exists, path)
        if ok and exists then
            fs.delete(path)
        end
        return true
    end
    if os and os.remove then
        os.remove(path)
        return true
    end
    return false
end

function fs_utils.readFile(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid_path"
    end
    if fs and fs.open then
        local handle = fs.open(path, "r")
        if not handle then
            return nil, "open_failed"
        end
        local ok, contents = pcall(handle.readAll)
        handle.close()
        if not ok then
            return nil, "read_failed"
        end
        return contents
    end
    if io and io.open then
        local handle, err = io.open(path, "r")
        if not handle then
            return nil, err or "open_failed"
        end
        local contents = handle:read("*a")
        handle:close()
        return contents
    end
    return nil, "fs_unavailable"
end

function fs_utils.cleanupArtifacts()
    for index = #createdArtifacts, 1, -1 do
        local path = createdArtifacts[index]
        fs_utils.deleteFile(path)
        createdArtifacts[index] = nil
    end
end

return fs_utils
