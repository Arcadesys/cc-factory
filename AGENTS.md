
*A specification for modular, schema-driven Minecraft Turtle automation.*

## Overview

This repository defines a modular system that turns CC:Tweaked turtles into schema-driven construction, mining, and automation agents. Each turtle behaves as a state machine. Each state delegates all low-level actions to reusable libraries (movement, inventory, placement, parsing, navigation).

The system’s goal:
**Given a schema (JSON, text, or voxel grid), a turtle can autonomously construct or excavate the described structure while handling restocking, refueling, and navigation.**

This document explains the roles of each subsystem and agent.

---

## **1. Core Architecture**

### 1.1 Turtle Context (`ctx`)

A shared table passed to every state and library. It contains:

* `schema` — parsed representation (3D grid).
* `strategy` — linear list of build steps (computed by INITIALIZE).
* `pointer` — index of the current step in `strategy`.
* `origin` — absolute home coordinates and facing (`{x, y, z, facing}`).
* `config` — runtime settings (verbose, schema path, etc.).
* `state` — current state label.
* `missingMaterial` — (transient) material causing a RESTOCK trigger.
* `retries` — (transient) counter for navigation retry logic.
* `lastError` — (transient) error message if state is ERROR.

States must treat `ctx` as the single source of truth.

---

## **2. Schema System**

### 2.1 Accepted Formats

* **JSON**: preferred; supports material names and coordinates.
* **Text grid**: simple symbolic map where symbols map to materials via a legend.
* **Voxel dataset**: optional advanced format.

### 2.2 Parsing Pipeline

* `parser.lua` converts any supported input into a canonical 3D array.
* Canonical format:

  ```lua
  schema[x][y][z] = { material="minecraft:stone", meta={} }
  ```
* Parser validates:

  * Dimensions
  * Unknown symbols
  * Missing legend entries
  * Invalid materials

---

## **3. State Machine**

Each turtle runs a finite state machine. All states have the signature:

```lua
function STATE_NAME(ctx)
    -- state logic
    return NEXT_STATE
end
```

### 3.1 `INITIALIZE`

* Load schema from file.
* Parse into canonical format.
* Compute **Build Strategy**: A linear list of steps (serpentine path).
* Store strategy in `ctx.strategy` and set `ctx.pointer = 1`.
* Transition to `BUILD`.

### 3.2 `BUILD`

* **Check Fuel**: If low (< 100), transition to `REFUEL`.
* **Check Inventory**: If missing required material, set `ctx.missingMaterial` and transition to `RESTOCK`.
* **Move**: Navigate to the target coordinate (converting local strategy pos to world pos).
  * If blocked, transition to `BLOCKED`.
* **Place**: Attempt to place the block.
  * If placement fails (obstruction), transition to `ERROR` (or retry logic).
* **Advance**: Increment `ctx.pointer`.
* If pointer > strategy length, transition to `DONE`.

### 3.3 `RESTOCK`

* Return to `ctx.origin`.
* Attempt to pull `ctx.missingMaterial` from any adjacent inventory (front, up, down, etc.).
* If successful, clear `missingMaterial` and return to `BUILD`.
* If failed (item not found), transition to `ERROR`.

### 3.4 `REFUEL`

* Return to `ctx.origin`.
* Consume any fuel items currently in inventory.
* (Optional) Pull fuel items from storage.
* If fuel level is sufficient (> 1000), return to `BUILD`.
* If still low, transition to `ERROR`.

### 3.5 `BLOCKED`

* Wait for a short duration (5s).
* Increment `ctx.retries`.
* If retries > limit, transition to `ERROR`.
* Otherwise, return to `BUILD` to retry movement.

### 3.6 `ERROR`

* Write diagnostic message.
* Await manual intervention.
* Pressing Enter returns to last known safe state.

### 3.7 `DONE`

* Turtle returns home and powers down.

---

## **4. Library Responsibilities**

### 4.1 `movement.lua`

Responsible for all locomotion.

* Safe forward/up/down with retries
* Obstacle detection
* Orientation tracking
* “Return to origin” navigation
* Path planning (simple or advanced)

### 4.2 `inventory.lua`

Handles inventory state and item acquisition.

* Find slots containing a material
* Count items
* Select item by material
* Pull and push between chests
* Detect empty inventory

### 4.3 `placement.lua`

Responsible for all block placement behavior.

* Safe placement checks
* Overwrite prevention
* Vertical/horizontal placement helpers
* Block detection + early failure reporting

### 4.4 `parser.lua`

Responsible for turning JSON/text/voxel schema into canonical format.

### 4.5 `navigation.lua`

Optional module for A*-like routing or multi-layer pathing.

### 4.6 `logger.lua`

Optional module for structured logs and on-screen feedback.

---

## **5. Build Strategy**

The system uses a **serpentine** traversal by default: left-to-right on each layer, alternating direction per row.

Build order is computed during `INITIALIZE` and stored in `ctx.strategy`.

---

## **6. Error Handling and Recovery**

All major operations must return `(success, errorMessage)`.

States never crash; they route failure to:

* `REFUEL`
* `RESTOCK`
* `BLOCKED`
* `ERROR`

All library functions must fail gracefully.

---

## **7. File Structure (Reference)**

Computercraft turtles run best with a flat disk layout. Use filename prefixes to keep related states and libraries grouped without subdirectories.

```text
state_initialize.lua
state_build.lua
state_restock.lua
state_refuel.lua
state_blocked.lua
state_error.lua
state_done.lua

lib_movement.lua
lib_inventory.lua
lib_placement.lua
lib_parser.lua
lib_navigation.lua
lib_logger.lua

main.lua
config.lua
schema.json (or schema.txt)
```

---

## **8. Future Extensions**

* Multi-turtle cooperative building
* Dynamic path optimization
* Networked inventory management
* On-turtle caching of material usage stats
* Remote telemetry dashboard