--[[
Branch mining routine driven by the cc-factory libraries.
Clears a 2x2 spine, carves side branches, scans adjacent blocks for ores,
and unloads into a nearby chest when inventory fills.
]]

---@diagnostic disable: undefined-global

local movement = require("lib_movement")
local inventory = require("lib_inventory")
local placement = require("lib_placement")
local loggerLib = require("lib_logger")
local fuelLib = require("lib_fuel")

if not turtle then
	error("branchminer must run on a turtle")
end

local HELP = [[
branchminer - carved tunnel + branches

Usage:
  branchminer [options]

Options:
	--length <n>          Number of spine segments to dig (default 60)
	--branch-interval <n> Dig a branch every n spine segments (default 3)
	--branch-length <n>   Branch length in blocks (default 2)
	--torch-interval <n>  Place torches every n segments (default 6)
	--torch-item <id>     Item id for torches (default minecraft:torch)
	--fuel-item <id>      Allowed fuel item (repeatable; defaults include coal/charcoal)
	--no-torches          Disable torch placement
	--min-fuel <n>        Minimum fuel level before refueling (default 180)
	--facing <dir>        Initial/home facing (north|south|east|west)
	--verbose             Enable debug logging
	--help                Show this message
]]

local DEFAULT_OPTIONS = {
	length = 60,
	branchInterval = 3,
	branchLength = 16,
	torchInterval = 6,
	torchItem = "minecraft:torch",
	minFuel = 180,
	facing = "north",
	verbose = false,
	fuelItems = nil,
}

local MOVE_OPTS = { dig = true, attack = true }

local DEFAULT_TRASH = {
	["minecraft:air"] = true,
	["minecraft:stone"] = true,
	["minecraft:cobblestone"] = true,
	["minecraft:deepslate"] = true,
	["minecraft:cobbled_deepslate"] = true,
	["minecraft:tuff"] = true,
	["minecraft:diorite"] = true,
	["minecraft:granite"] = true,
	["minecraft:andesite"] = true,
	["minecraft:calcite"] = true,
	["minecraft:netherrack"] = true,
	["minecraft:end_stone"] = true,
	["minecraft:basalt"] = true,
	["minecraft:blackstone"] = true,
	["minecraft:gravel"] = true,
	["minecraft:dirt"] = true,
	["minecraft:coarse_dirt"] = true,
	["minecraft:rooted_dirt"] = true,
	["minecraft:mycelium"] = true,
	["minecraft:sand"] = true,
	["minecraft:red_sand"] = true,
	["minecraft:sandstone"] = true,
	["minecraft:red_sandstone"] = true,
	["minecraft:clay"] = true,
	["minecraft:dripstone_block"] = true,
	["minecraft:pointed_dripstone"] = true,
	["minecraft:bedrock"] = true,
	["minecraft:lava"] = true,
	["minecraft:water"] = true,
	["minecraft:torch"] = true,
}

local TRASH_PLACEMENT_EXCLUDE = {
	["minecraft:air"] = true,
	["minecraft:bedrock"] = true,
	["minecraft:lava"] = true,
	["minecraft:torch"] = true,
	["minecraft:water"] = true,
}

local DEFAULT_FUEL_ITEMS = {
	"minecraft:coal",
	"minecraft:charcoal",
	"minecraft:coal_block",
	"minecraft:lava_bucket",
	"minecraft:blaze_rod",
	"minecraft:dried_kelp_block",
}

local FACING_VECTORS = {
	north = { x = 0, y = 0, z = -1 },
	east = { x = 1, y = 0, z = 0 },
	south = { x = 0, y = 0, z = 1 },
	west = { x = -1, y = 0, z = 0 },
}

local TURN_LEFT_OF = {
	north = "west",
	west = "south",
	south = "east",
	east = "north",
}

local TURN_RIGHT_OF = {
	north = "east",
	east = "south",
	south = "west",
	west = "north",
}

local TURN_BACK_OF = {
	north = "south",
	south = "north",
	east = "west",
	west = "east",
}

local ORE_TAG_HINTS = {
	"/ores",
	":ores",
	"_ores",
	"is_ore",
}

local ORE_NAME_HINTS = {
	"_ore",
	"ancient_debris",
}

local function copyVector(vec)
	if type(vec) ~= "table" then
		return nil
	end
	return { x = vec.x or 0, y = vec.y or 0, z = vec.z or 0 }
end

local function positionsEqual(a, b)
	a = a or {}
	b = b or {}
	return (a.x or 0) == (b.x or 0)
		and (a.y or 0) == (b.y or 0)
		and (a.z or 0) == (b.z or 0)
end

local function copyOptions(base, overrides)
	local result = {}
	for k, v in pairs(base) do
		result[k] = v
	end
	for k, v in pairs(overrides or {}) do
		result[k] = v
	end
	return result
end

local function expandFuelItems(custom)
	if type(custom) ~= "table" or #custom == 0 then
		return nil
	end
	local list = {}
	local seen = {}
	local function append(name)
		if type(name) ~= "string" or name == "" then
			return
		end
		if seen[name] then
			return
		end
		seen[name] = true
		list[#list + 1] = name
	end
	for _, name in ipairs(DEFAULT_FUEL_ITEMS) do
		append(name)
	end
	for _, name in ipairs(custom) do
		append(name)
	end
	return list
end

local function normaliseFacing(value)
	if type(value) ~= "string" then
		return DEFAULT_OPTIONS.facing
	end
	local name = value:lower()
	if name == "north" or name == "south" or name == "east" or name == "west" then
		return name
	end
	return DEFAULT_OPTIONS.facing
end

local function parseArgs(argv)
	local opts = {}
	local i = 1
	while i <= #argv do
		local arg = argv[i]
		if arg == "--length" then
			local value = tonumber(argv[i + 1])
			if value and value > 0 then
				opts.length = math.floor(value)
			end
			i = i + 2
		elseif arg == "--branch-interval" then
			local value = tonumber(argv[i + 1])
			if value and value > 0 then
				opts.branchInterval = math.floor(value)
			end
			i = i + 2
		elseif arg == "--branch-length" then
			local value = tonumber(argv[i + 1])
			if value and value > 0 then
				opts.branchLength = math.floor(value)
			end
			i = i + 2
		elseif arg == "--torch-interval" then
			local value = tonumber(argv[i + 1])
			if value and value >= 0 then
				opts.torchInterval = math.floor(value)
			end
			i = i + 2
		elseif arg == "--torch-item" then
			local value = argv[i + 1]
			if value then
				opts.torchItem = value
			end
			i = i + 2
		elseif arg == "--fuel-item" then
			local value = argv[i + 1]
			if value then
				opts.fuelItems = opts.fuelItems or {}
				opts.fuelItems[#opts.fuelItems + 1] = value
			end
			i = i + 2
		elseif arg == "--no-torches" then
			opts.torchInterval = 0
			i = i + 1
		elseif arg == "--min-fuel" then
			local value = tonumber(argv[i + 1])
			if value and value > 0 then
				opts.minFuel = math.floor(value)
			end
			i = i + 2
		elseif arg == "--facing" then
			local value = argv[i + 1]
			if value then
				opts.facing = normaliseFacing(value)
			end
			i = i + 2
		elseif arg == "--verbose" then
			opts.verbose = true
			i = i + 1
		elseif arg == "--help" or arg == "-h" then
			opts.help = true
			break
		else
			local value = tonumber(arg)
			if value and value > 0 then
				opts.length = math.floor(value)
			end
			i = i + 1
		end
	end
	return opts
end

local BranchMiner = {}
BranchMiner.__index = BranchMiner

local function buildTrashSet(extra)
	local set = {}
	for name, flag in pairs(DEFAULT_TRASH) do
		set[name] = flag and true or false
	end
	if type(extra) == "table" then
		for name, flag in pairs(extra) do
			if type(name) == "string" then
				set[name] = flag and true or false
			end
		end
	end

	local list = {}
	for name, flag in pairs(set) do
		if flag and not TRASH_PLACEMENT_EXCLUDE[name] then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return set, list
end

function BranchMiner:new(opts)
	local config = copyOptions(DEFAULT_OPTIONS, opts)
	config.facing = normaliseFacing(config.facing)
	config.fuelItems = expandFuelItems(config.fuelItems)

	local logger = loggerLib.new({
		level = config.verbose and "debug" or "info",
		tag = "BranchMiner",
	})

	local trashSet, trashList = buildTrashSet()

	local ctx = {
		origin = { x = 0, y = 0, z = 0 },
		pointer = { x = 0, y = 0, z = 0 },
		config = {
			verbose = config.verbose,
			initialFacing = config.facing,
			homeFacing = config.facing,
			digOnMove = true,
			attackOnMove = true,
			maxMoveRetries = 12,
			moveRetryDelay = 0.4,
			fuelItems = config.fuelItems,
		},
		logger = logger,
	}

	movement.ensureState(ctx)
	inventory.ensureState(ctx)
	placement.ensureState(ctx)
	fuelLib.ensureState(ctx)

	local miner = {
		ctx = ctx,
		logger = logger,
		options = config,
		trash = trashSet,
		trashList = trashList,
		torchEnabled = config.torchInterval and config.torchInterval > 0,
		torchItem = config.torchItem,
		stepCount = 0,
		chestAvailable = false,
		homeFacing = config.facing,
		detectedValuables = {},
		fuelItems = config.fuelItems,
	}

	return setmetatable(miner, BranchMiner)
end

function BranchMiner:isTrash(name)
	if name == nil then
		return false
	end
	return self.trash[name] == true
end

function BranchMiner:selectTrashForPlacement()
	if not turtle then
		return false, "turtle API unavailable"
	end
	if type(self.trashList) ~= "table" then
		return false, "no_trash_configured"
	end
	for _, name in ipairs(self.trashList) do
		local ok = inventory.selectMaterial(self.ctx, name)
		if ok then
			local count = turtle.getItemCount and turtle.getItemCount() or 0
			if count > 0 then
				return true
			end
		end
	end
	return false, "no_trash_available"
end

function BranchMiner:placeTrash(direction)
	if not turtle then
		return false, "turtle API unavailable"
	end
	local selectOk, selectErr = self:selectTrashForPlacement()
	if not selectOk then
		return false, selectErr
	end

	local placeFn
	if direction == "up" then
		placeFn = turtle.placeUp
	elseif direction == "down" then
		placeFn = turtle.placeDown
	else
		placeFn = turtle.place
	end

	if type(placeFn) ~= "function" then
		return false, "place_unavailable"
	end

	local ok, err = placeFn()
	if not ok then
		if err == "No block to place against" then
			return false, "no_support"
		end
		if err == "Nothing to place" or err == "No items to place" then
			return false, "no_trash_available"
		end
		return false, err or "place_failed"
	end

	inventory.invalidate(self.ctx)
	return true
end

function BranchMiner:getDirectionFns(direction)
	if direction == "forward" then
		return turtle.inspect, turtle.dig
	elseif direction == "up" then
		return turtle.inspectUp, turtle.digUp
	elseif direction == "down" then
		return turtle.inspectDown, turtle.digDown
	end
	return nil, nil
end

function BranchMiner:getFacingVector(facing)
	if type(facing) ~= "string" then
		return nil
	end
	return copyVector(FACING_VECTORS[facing])
end

function BranchMiner:getOffsetForDirection(direction)
	direction = direction or "forward"
	if direction == "up" then
		return { x = 0, y = 1, z = 0 }
	elseif direction == "down" then
		return { x = 0, y = -1, z = 0 }
	end

	local facing = movement.getFacing(self.ctx)
	if not facing then
		return nil
	end

	if direction == "forward" then
		return self:getFacingVector(facing)
	elseif direction == "back" then
		local vec = self:getFacingVector(facing)
		if not vec then
			return nil
		end
		return { x = -vec.x, y = -vec.y, z = -vec.z }
	elseif direction == "left" then
		local heading = TURN_LEFT_OF[facing]
		return self:getFacingVector(heading)
	elseif direction == "right" then
		local heading = TURN_RIGHT_OF[facing]
		return self:getFacingVector(heading)
	end

	return nil
end

function BranchMiner:inspectAndMine(direction, opts)
	opts = opts or {}
	local force = opts.force
	local inspectFn, digFn = self:getDirectionFns(direction)
	if not digFn then
		return true
	end

	local hasBlock = false
	local detail
	if inspectFn then
		local ok, data = inspectFn()
		if ok and type(data) == "table" then
			hasBlock = true
			detail = data
			self:logValuableDetail(detail, direction)
		end
	end

	local name = detail and (detail.name or detail.id) or nil
	local shouldMine = force
	if not shouldMine and hasBlock then
		shouldMine = not self:isTrash(name)
	end

	if shouldMine then
		local ok = digFn()
		if ok then
			inventory.invalidate(self.ctx)
			if name and self.logger then
				self.logger:debug(string.format("Mined %s (%s)", name, direction))
			end
		elseif hasBlock then
			return false, string.format("dig_failed_%s", direction)
		end
	end
	return true
end

function BranchMiner:isValuableDetail(detail)
	if type(detail) ~= "table" then
		return false
	end
	local name = detail.name or detail.id
	if type(name) ~= "string" or name == "" then
		return false
	end
	if self:isTrash(name) then
		return false
	end
	if name == self.torchItem then
		return false
	end
	for _, hint in ipairs(ORE_NAME_HINTS) do
		if name:find(hint, 1, true) then
			return true
		end
	end
	if type(detail.tags) == "table" then
		for tag, present in pairs(detail.tags) do
			if present and type(tag) == "string" then
				for _, fragment in ipairs(ORE_TAG_HINTS) do
					if tag:find(fragment, 1, true) then
						return true
					end
				end
			end
		end
	end
	return false

end

function BranchMiner:logValuableDetail(detail, direction)
	if not self.logger then
		return
	end
	if not self:isValuableDetail(detail) then
		return
	end
	local name = detail.name or detail.id or "unknown"
	self.logger:info(string.format("Detected ore %s at %s", name, direction or "unknown"))
end

local function warnBackfill(logger, label, err)
	if not logger then
		return
	end
	logger:warn(string.format("Backfill failed at %s: %s", label or "unknown", tostring(err or "unknown")))
end

function BranchMiner:harvestForward(label)
	if not turtle or type(turtle.inspect) ~= "function" or type(turtle.dig) ~= "function" then
		return true
	end
	local success, detail = turtle.inspect()
	if not success or type(detail) ~= "table" then
		return true
	end
	if not self:isValuableDetail(detail) then
		return true
	end
	self:logValuableDetail(detail, label or "forward")
	local digOk, digErr = turtle.dig()
	if not digOk then
		return false, digErr or "dig_failed_forward"
	end
	inventory.invalidate(self.ctx)
	local placeOk, placeErr = self:placeTrash("forward")
	if not placeOk then
		warnBackfill(self.logger, label or "forward", placeErr)
	end
	return true
end

function BranchMiner:harvestVertical(direction)
	if not turtle then
		return true
	end
	local inspectFn
	local digFn
	local placeDir = direction
	if direction == "up" then
		inspectFn = turtle.inspectUp
		digFn = turtle.digUp
	elseif direction == "down" then
		inspectFn = turtle.inspectDown
		digFn = turtle.digDown
	else
		return false, "invalid_direction"
	end
	if type(inspectFn) ~= "function" or type(digFn) ~= "function" then
		return true
	end
	local success, detail = inspectFn()
	if not success or type(detail) ~= "table" then
		return true
	end
	if not self:isValuableDetail(detail) then
		return true
	end
	self:logValuableDetail(detail, direction)
	local digOk, digErr = digFn()
	if not digOk then
		return false, digErr or string.format("dig_failed_%s", direction)
	end
	inventory.invalidate(self.ctx)
	local placeOk, placeErr = self:placeTrash(placeDir)
	if not placeOk then
		warnBackfill(self.logger, direction, placeErr)
	end
	return true
end

function BranchMiner:scanForValuables(opts)
	if not turtle then
		return true
	end

	opts = opts or {}
	local skipDown = opts.skipDown
	local skipUp = opts.skipUp

	local startFacing = movement.getFacing(self.ctx)

	local function restoreFacing()
		if not startFacing then
			return true
		end
		local ok, err = movement.faceDirection(self.ctx, startFacing)
		if not ok then
			return false, err
		end
		return true
	end

	if not skipUp then
		local ok, err = self:harvestVertical("up")
		if not ok then
			return false, err
		end
	end

	if not skipDown then
		local ok, err = self:harvestVertical("down")
		if not ok then
			return false, err
		end
	end

	local ok, err = self:harvestForward("forward")
	if not ok then
		return false, err
	end

	local function harvestWithTurn(turnFn, undoFn, label)
		local aligned, alignErr = restoreFacing()
		if not aligned then
			return false, alignErr
		end
		local turnOk, turnErr = turnFn()
		if not turnOk then
			return false, turnErr
		end
		local harvestOk, harvestErr = self:harvestForward(label)
		local undoOk, undoErr = undoFn()
		if not undoOk then
			return false, undoErr
		end
		local faceOk, faceErr = restoreFacing()
		if not faceOk then
			return false, faceErr
		end
		if not harvestOk then
			return false, harvestErr
		end
		return true
	end

	ok, err = harvestWithTurn(function()
		return movement.turnLeft(self.ctx)
	end, function()
		return movement.turnRight(self.ctx)
	end, "left")
	if not ok then
		return false, err
	end

	ok, err = harvestWithTurn(function()
		return movement.turnRight(self.ctx)
	end, function()
		return movement.turnLeft(self.ctx)
	end, "right")
	if not ok then
		return false, err
	end

	ok, err = harvestWithTurn(function()
		return movement.turnAround(self.ctx)
	end, function()
		return movement.turnAround(self.ctx)
	end, "back")
	if not ok then
		return false, err
	end

	local restoreOk, restoreErr = restoreFacing()
	if not restoreOk then
		return false, restoreErr
	end

	return true
end

function BranchMiner:harvestNearbyValuables()
	local baseOk, baseErr = self:scanForValuables()
	if not baseOk then
		return false, baseErr
	end

	local upOk, upErr = movement.up(self.ctx, MOVE_OPTS)
	if upOk then
		local scanOk, scanErr = self:scanForValuables({ skipDown = true })
		local downOk, downErr = movement.down(self.ctx, MOVE_OPTS)
		if not downOk then
			return false, downErr
		end
		if not scanOk then
			return false, scanErr
		end
	else
		if upErr and self.logger then
			self.logger:debug("Upper scan skipped: " .. tostring(upErr))
		end
	end

	return true
end

function BranchMiner:ensureFuel()
	local ok, report = fuelLib.check(self.ctx, { threshold = self.options.minFuel })
	if ok or (report and report.unlimited) then
		return true
	end

	local beforePos = movement.getPosition(self.ctx)
	local beforeFacing = movement.getFacing(self.ctx)
	self.logger:info("Fuel below threshold; attempting refuel")
	local refueled, info = fuelLib.ensure(self.ctx, {
		threshold = self.options.minFuel,
		fuelItems = self.options.fuelItems,
	})
	if not refueled then
		self.logger:error("Refuel failed; stopping")
		if info and info.service and textutils and textutils.serialize then
			self.logger:error("Service report: " .. textutils.serialize(info.service))
		end
		return false, "refuel_failed"
	end

	local afterPos = movement.getPosition(self.ctx)
	local afterFacing = movement.getFacing(self.ctx)
	if not positionsEqual(beforePos, afterPos) or (beforeFacing and afterFacing and beforeFacing ~= afterFacing) then
		self.logger:debug("Returning to work site after refuel")
		local returnOk, returnErr = movement.goTo(self.ctx, beforePos, MOVE_OPTS)
		if not returnOk then
			self.logger:error("Failed to return after refuel: " .. tostring(returnErr))
			return false, "post_refuel_return_failed"
		end
		if beforeFacing then
			local faceOk, faceErr = movement.faceDirection(self.ctx, beforeFacing)
			if not faceOk then
				self.logger:error("Unable to restore facing after refuel: " .. tostring(faceErr))
				return false, "post_refuel_face_failed"
			end
		end
	end

	return true
end

function BranchMiner:detectChest()
	local info = inventory.detectContainer(self.ctx, { side = "forward" })
	if info then
		self.logger:info(string.format("Detected drop-off container (%s)", info.side or "forward"))
		self.chestAvailable = true
	else
		self.logger:warn("No adjacent chest detected; auto-unload disabled")
		self.chestAvailable = false
	end
	movement.faceDirection(self.ctx, self.homeFacing)
end

function BranchMiner:depositInventory()
	if not self.chestAvailable then
		return true
	end
	inventory.scan(self.ctx, { force = true })
	for slot = 1, 16 do
		local count = turtle.getItemCount(slot)
		if count and count > 0 then
			local ok, err = inventory.pushSlot(self.ctx, slot, nil, { side = "forward" })
			if not ok and err ~= "empty_slot" then
				self.logger:warn(string.format("Failed to drop slot %d: %s", slot, tostring(err)))
			end
		end
	end
	return true
end

function BranchMiner:returnToDropoff(stayAtOrigin)
	local pos = movement.getPosition(self.ctx)
	local facing = movement.getFacing(self.ctx)

	local ok, err = movement.returnToOrigin(self.ctx, { facing = self.homeFacing })
	if not ok then
		return false, err
	end

	self:depositInventory()

	if stayAtOrigin then
		return true
	end

	ok, err = movement.goTo(self.ctx, pos, MOVE_OPTS)
	if not ok then
		return false, err
	end
	if facing then
		movement.faceDirection(self.ctx, facing)
	end
	return true
end

function BranchMiner:ensureCapacity()
	local slot = inventory.findEmptySlot(self.ctx)
	if slot then
		return true
	end
	if not self.chestAvailable then
		self.logger:error("Inventory full and no chest available; stopping")
		return false, "inventory_full"
	end
	self.logger:info("Inventory full; returning to drop-off")
	local ok, err = self:returnToDropoff(false)
	if not ok then
		return false, err
	end
	inventory.invalidate(self.ctx)
	return true
end

function BranchMiner:advanceForward()
	local ok, err = self:inspectAndMine("forward", { force = true })
	if not ok then
		return false, err
	end
	ok, err = movement.forward(self.ctx, MOVE_OPTS)
	if not ok then
		return false, err
	end
	local headOk, headErr = self:inspectAndMine("up", { force = true })
	if not headOk then
		return false, headErr
	end
	return true
end

function BranchMiner:clearLeftLane()
	local ok, err = movement.turnLeft(self.ctx)
	if not ok then
		return false, err
	end

	local digOk, digErr = self:inspectAndMine("forward", { force = true })
	if not digOk then
		movement.turnRight(self.ctx)
		return false, digErr
	end

	local moved = false
	ok, err = movement.forward(self.ctx, MOVE_OPTS)
	if ok then
		moved = true
		self:inspectAndMine("up", { force = true })
		self:inspectAndMine("forward", { force = false })
	else
		self.logger:warn("Unable to open left lane: " .. tostring(err))
	end

	if moved then
		ok, err = movement.turnAround(self.ctx)
		if not ok then
			return false, err
		end
		ok, err = movement.forward(self.ctx, MOVE_OPTS)
		if not ok then
			return false, err
		end
		ok, err = movement.turnAround(self.ctx)
		if not ok then
			return false, err
		end
	end

	ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end
	return true
end

function BranchMiner:scanRightWall()
	local ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end
	self:inspectAndMine("forward", { force = false })
	ok, err = movement.turnLeft(self.ctx)
	if not ok then
		return false, err
	end
	return true
end

function BranchMiner:shouldPlaceTorch()
	if not self.torchEnabled then
		return false
	end
	local interval = self.options.torchInterval
	if not interval or interval <= 0 then
		return false
	end
	return (self.stepCount % interval) == 0
end

function BranchMiner:placeTorchOnWall(side)
	local turnFn, restoreFn
	if side == "right" then
		turnFn = movement.turnRight
		restoreFn = movement.turnLeft
	elseif side == "left" then
		turnFn = movement.turnLeft
		restoreFn = movement.turnRight
	else
		return nil, "invalid_side"
	end

	local ok, err = turnFn(self.ctx)
	if not ok then
		return nil, err
	end

	local hasWall = false
	local inspectDetail
	if turtle then
		local inspectFn = turtle.inspect
		if inspectFn then
			local okInspect, success, detail = pcall(inspectFn)
			if okInspect and success then
				hasWall = true
				inspectDetail = detail
			end
		end
		if not hasWall then
			local detectFn = turtle.detect
			if detectFn then
				local okDetect, result = pcall(detectFn)
				if okDetect and result then
					hasWall = true
				end
			end
		end
	end

	if inspectDetail and type(inspectDetail) == "table" then
		local name = inspectDetail.name or inspectDetail.id
		if name == self.torchItem then
			local restoreOk, restoreErr = restoreFn(self.ctx)
			if not restoreOk then
				return nil, restoreErr
			end
			return true, "already_present"
		end
	end

	local placed = false
	local perr
	if hasWall then
		local selectOk, selectErr = inventory.selectMaterial(self.ctx, self.torchItem)
		if not selectOk then
			perr = selectErr or "missing_material"
		else
			if turtle and turtle.getItemCount and turtle.getItemCount() <= 0 then
				perr = "missing_material"
			else
				local placeFn = turtle and turtle.place or nil
				if placeFn then
					local placeOk, placeErr = placeFn()
					if placeOk then
						placed = true
						perr = nil
						if inventory.invalidate then
							inventory.invalidate(self.ctx)
						end
					else
						perr = placeErr or "place_failed"
						if placeErr == "No block to place against" then
							perr = "no_wall"
						elseif placeErr == "No items to place" or placeErr == "Nothing to place" then
							perr = "missing_material"
						end
					end
				else
					perr = "turtle API unavailable"
				end
			end
		end
	else
		perr = "no_wall"
	end

	local restoreOk, restoreErr = restoreFn(self.ctx)
	if not restoreOk then
		return nil, restoreErr
	end

	return placed, perr
end

function BranchMiner:maybePlaceTorch()
	if not self:shouldPlaceTorch() then
		return true
	end
	local movedUp = false
	local placed, perr

	-- Try to mount the torch on the side wall one block above the path.
	local upOk, upErr = movement.up(self.ctx, MOVE_OPTS)
	if upOk then
		movedUp = true
		placed, perr = self:placeTorchOnWall("right")
	else
		if upErr and self.logger then
			self.logger:debug("Torch placement: unable to elevate for wall mount: " .. tostring(upErr))
		end
	end

	if movedUp then
		local downOk, downErr = movement.down(self.ctx, MOVE_OPTS)
		if not downOk then
			return false, downErr
		end
		if placed == nil then
			return false, perr
		end
		if not placed and perr == "no_wall" then
			local retryPlaced, retryErr = self:placeTorchOnWall("right")
			if retryPlaced == nil then
				return false, retryErr
			end
			placed, perr = retryPlaced, retryErr
		end
	else
		placed, perr = self:placeTorchOnWall("right")
		if placed == nil then
			return false, perr
		end
	end

	if placed then
		return true
	end

	if perr == "missing_material" then
		self.logger:warn("Out of torches; disabling torch placement")
		self.torchEnabled = false
	elseif perr == "no_wall" then
		self.logger:debug("Torch placement skipped: missing wall surface")
	elseif perr ~= "occupied" then
		self.logger:debug("Torch placement skipped: " .. tostring(perr))
	end

	return true
end

function BranchMiner:scanBranchWalls()
	local ok, err = movement.turnLeft(self.ctx)
	if not ok then
		return false, err
	end
	self:inspectAndMine("forward", { force = false })

	ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end
	ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end
	self:inspectAndMine("forward", { force = false })

	ok, err = movement.turnLeft(self.ctx)
	if not ok then
		return false, err
	end
	return true
end

function BranchMiner:digBranch()
	local ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end

	for _ = 1, self.options.branchLength do
		local digOk, digErr = self:inspectAndMine("forward", { force = true })
		if not digOk then
			return false, digErr
		end
		ok, err = movement.forward(self.ctx, MOVE_OPTS)
		if not ok then
			return false, err
		end
		self:inspectAndMine("up", { force = true })
		local wallOk, wallErr = self:scanBranchWalls()
		if not wallOk then
			return false, wallErr
		end

		local upOk, upErr = movement.up(self.ctx, MOVE_OPTS)
		if upOk then
			local scanOk, scanErr = self:scanBranchWalls()
			local downOk, downErr = movement.down(self.ctx, MOVE_OPTS)
			if not downOk then
				return false, downErr
			end
			if not scanOk then
				return false, scanErr
			end
		else
			if upErr and self.logger then
				self.logger:debug("Upper branch scan skipped: " .. tostring(upErr))
			end
		end
	end

	self:inspectAndMine("forward", { force = false })

	ok, err = movement.turnAround(self.ctx)
	if not ok then
		return false, err
	end
	for _ = 1, self.options.branchLength do
		ok, err = movement.forward(self.ctx, MOVE_OPTS)
		if not ok then
			return false, err
		end
	end
	ok, err = movement.turnRight(self.ctx)
	if not ok then
		return false, err
	end
	return true
end

function BranchMiner:shouldBranch()
	local interval = self.options.branchInterval
	if not interval or interval <= 0 then
		return false
	end
	return (self.stepCount % interval) == 0
end

function BranchMiner:advance()
	local ok, err = self:advanceForward()
	if not ok then
		return false, err
	end

	self.stepCount = self.stepCount + 1

	ok, err = self:clearLeftLane()
	if not ok then
		return false, err
	end

	ok, err = self:scanRightWall()
	if not ok then
		return false, err
	end

	ok, err = self:maybePlaceTorch()
	if not ok then
		return false, err
	end

	if self:shouldBranch() then
		ok, err = self:ensureCapacity()
		if not ok then
			return false, err
		end
		ok, err = self:digBranch()
		if not ok then
			return false, err
		end
	end

	local scanOk, scanErr = self:harvestNearbyValuables()
	if not scanOk then
		return false, scanErr or "valuable_scan_failed"
	end

	return true
end

function BranchMiner:prepareStart()
	local ok, err = self:inspectAndMine("up", { force = true })
	if not ok then
		return false, err
	end
	ok, err = self:clearLeftLane()
	if not ok then
		return false, err
	end
	local scanOk, scanErr = self:harvestNearbyValuables()
	if not scanOk then
		return false, scanErr
	end
	return true
end

function BranchMiner:wrapUp()
	if self.chestAvailable then
		self:returnToDropoff(true)
	else
		movement.returnToOrigin(self.ctx, { facing = self.homeFacing })
	end
	self.logger:info(string.format("Branch miner complete after %d segments", self.stepCount))
end

function BranchMiner:run()
	local ok, err = self:ensureFuel()
	if not ok then
		self.logger:error("Startup fuel check failed: " .. tostring(err))
		return false
	end

	self:detectChest()
	local prepOk, prepErr = self:prepareStart()
	if not prepOk then
		self.logger:error("Startup preparation failed: " .. tostring(prepErr))
		self:wrapUp()
		return false
	end

	local target = self.options.length
	while true do
		if target and self.stepCount >= target then
			break
		end

		ok, err = self:ensureFuel()
		if not ok then
			self.logger:error("Fuel check failed: " .. tostring(err))
			break
		end

		ok, err = self:ensureCapacity()
		if not ok then
			self.logger:error("Capacity check failed: " .. tostring(err))
			break
		end

		ok, err = self:advance()
		if not ok then
			self.logger:error("Advance failed: " .. tostring(err))
			break
		end
	end

	self:wrapUp()
	return true
end

local function main(...)
	local rawArgs = { ... }
	local parsed = parseArgs(rawArgs)
	if parsed.help then
		print(HELP)
		return
	end
	local miner = BranchMiner:new(parsed)
	miner:run()
end

main(...)

