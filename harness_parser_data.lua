local parser_data = {}

parser_data.SAMPLE_TEXT_GRID = [[
legend:
# = minecraft:cobblestone
~ = minecraft:glass

####
#..#
#..#
####

layer:1
~..~
.##.
~..~
]]

parser_data.SAMPLE_JSON = [[
{
  "legend": {
    "A": "minecraft:oak_planks",
    "B": { "material": "minecraft:stone", "meta": { "variant": "smooth" } }
  },
  "layers": [
    {
      "y": 0,
      "rows": ["AA", "BB"]
    },
    {
      "y": 1,
      "rows": ["BB", "AA"]
    }
  ]
}
]]

parser_data.SAMPLE_VOXEL = [[
{
  "grid": {
    "0": {
      "0": { "0": "minecraft:oak_log", "1": "minecraft:oak_log" },
      "1": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" }
    },
    "1": {
      "0": { "0": "minecraft:oak_leaves", "1": "minecraft:oak_leaves" },
      "1": { "0": "minecraft:air", "1": "minecraft:torch" }
    }
  }
}
]]

parser_data.EXPECT_TEXT_GRID = {
    totalBlocks = 18,
    materials = {
        ["minecraft:cobblestone"] = 14,
        ["minecraft:glass"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 3, y = 1, z = 3 },
    },
}

parser_data.EXPECT_JSON = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_planks"] = 4,
        ["minecraft:stone"] = 4,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

parser_data.EXPECT_VOXEL = {
    totalBlocks = 8,
    materials = {
        ["minecraft:oak_log"] = 2,
        ["minecraft:oak_leaves"] = 4,
        ["minecraft:air"] = 1,
        ["minecraft:torch"] = 1,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 1 },
    },
}

parser_data.SAMPLE_BLOCK_DATA = {
    blocks = {
        { x = 0, y = 0, z = 0, material = "minecraft:cobblestone" },
        { x = 1, y = 0, z = 0, material = "minecraft:stone" },
        { x = 0, y = 1, z = 0, material = "minecraft:stone" },
    },
}

parser_data.SAMPLE_VOXEL_DATA = {
    grid = {
        [0] = {
            [0] = { [0] = "minecraft:oak_log", [1] = "minecraft:oak_log" },
            [1] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
        },
        [1] = {
            [0] = { [0] = "minecraft:oak_leaves", [1] = "minecraft:oak_leaves" },
            [1] = { [0] = "minecraft:air", [1] = "minecraft:torch" },
        },
    },
}

parser_data.EXPECT_BLOCK_DATA = {
    totalBlocks = 3,
    materials = {
        ["minecraft:cobblestone"] = 1,
        ["minecraft:stone"] = 2,
    },
    bounds = {
        min = { x = 0, y = 0, z = 0 },
        max = { x = 1, y = 1, z = 0 },
    },
}

parser_data.FILE_SAMPLES = {
    {
        label = "File Text Grid",
        path = "tmp_sample_grid.txt",
        contents = parser_data.SAMPLE_TEXT_GRID,
        expect = parser_data.EXPECT_TEXT_GRID,
    },
    {
        label = "File JSON",
        path = "tmp_sample_schema.json",
        contents = parser_data.SAMPLE_JSON,
        expect = parser_data.EXPECT_JSON,
    },
    {
        label = "File Voxel",
        path = "tmp_sample_voxel.vox",
        contents = parser_data.SAMPLE_VOXEL,
        expect = parser_data.EXPECT_VOXEL,
        opts = { formatHint = "voxel" },
    },
}

return parser_data
