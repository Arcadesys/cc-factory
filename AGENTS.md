
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

* `schema` — parsed representation (3D grid, layer list, etc.)
* `pointer` — current build location within the schema
* `origin` — absolute home coordinates
* `inventoryState` — cached inventory info
* `fuelState` — remaining fuel and thresholds
* `config` — runtime settings (verbose, safety checks, etc.)
* `state` — current state label

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

* Load schema from file or network.
* Parse into canonical format.
* Compute build order (e.g., serpentine, optimized path, or custom strategy).
* Populate `ctx.pointer` with initial coordinates.
* Validate materials and inventory availability.

### 3.2 `BUILD`

* Move to target coordinate.
* Place the required material using safe placement logic.
* If placement fails due to missing blocks → switch to `RESTOCK`.
* If fuel below threshold → switch to `REFUEL`.
* If navigation blocked → switch to `BLOCKED`.
* Otherwise, advance pointer and continue.

### 3.3 `RESTOCK`

* Return to origin.
* Look up required item.
* Attempt to pull a full stack from chest.
* If absent → go to `ERROR`.
* Return to previous state.

### 3.4 `REFUEL`

* Return to origin.
* Pull available fuel items.
* If absent → go to `ERROR`.
* Refuel until threshold reached.
* Return to previous state.

### 3.5 `BLOCKED`

* Attempt alternate pathfinding.
* Retry movement with safety logic.
* If still blocked after N retries → `ERROR`.

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

---

If you want, I can also generate:

• a starter `main.lua`
• templated state files
• a canonical example `schema.json`
• a test harness for parsing and movement
• or an “agent kit”-style spec for how to prompt Codex to extend this system

Just say what you want to tackle next.
