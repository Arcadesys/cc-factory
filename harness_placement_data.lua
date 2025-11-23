local placement_data = {}

placement_data.scenarios = {
    {
        name = "Forward placement",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Step 1: clear the space in front of the turtle and ensure cobblestone is in inventory.",
        inventory = "present",
        expect = "DONE",
    },
    {
        name = "Reuse existing block",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Leave the cobblestone block from step 1 in place to trigger already-present handling.",
        expect = "DONE",
    },
    {
        name = "Upward placement",
        material = "minecraft:oak_planks",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "up" },
        prompt = "Clear the space directly above the turtle and load oak planks (adjust material if needed).",
        inventory = "present",
        expect = "DONE",
    },
    {
        name = "Blocked fallback",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward", overwrite = true, dig = false, attack = false },
        prompt = "Place an indestructible block in front (e.g., obsidian). Turtle should switch to BLOCKED.",
        expect = "BLOCKED",
        after = function(io)
            common.promptEnter(io, "Break the blocking block before continuing.")
        end,
    },
    {
        name = "Restock detection",
        material = "minecraft:cobblestone",
        pointer = { x = 0, y = 0, z = 0 },
        meta = { side = "forward" },
        prompt = "Remove all cobblestone from inventory so the turtle requests RESTOCK.",
        inventory = "absent",
        expect = "RESTOCK",
    },
}

return placement_data
