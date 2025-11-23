local inventory_utils = {}

local common = require("harness_common")

function inventory_utils.hasMaterial(material)
    if not turtle or not turtle.getItemDetail then
        return false
    end
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == material and detail.count and detail.count > 0 then
            return true
        end
    end
    return false
end

function inventory_utils.ensureMaterialPresent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if inventory_utils.hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Turtle is missing " .. material .. ". Load it, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until inventory_utils.hasMaterial(material)
end

function inventory_utils.ensureMaterialAbsent(io, material)
    if not turtle or not turtle.getItemDetail then
        return
    end
    if not inventory_utils.hasMaterial(material) then
        return
    end
    if io.print then
        io.print("Remove all " .. material .. " from the turtle inventory, then press Enter.")
    end
    repeat
        common.promptEnter(io, "")
    until not inventory_utils.hasMaterial(material)
end

return inventory_utils
