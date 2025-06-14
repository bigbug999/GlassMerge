# GlassMerge Save-System Overview

_Last updated: 2025-06-11_

---

## 1. Architecture

### 1.1 Root Object
* `GameState` (Codable)
  * `schemaVersion` – bump on breaking changes
  * `progression` – persistent meta-progress
  * `run` (optional) – active run snapshot; `nil` when no run in progress
  * `meta` – analytics / play-time data

### 1.2 Sub-Objects
* `Progression`
  * `currency` – player's permanent coins
  * `powerUps : [PowerUpProgress]` – unlock + level for every catalogued power-up

* `RunState`
  * `score`, `level`, `xp` – current run stats (expandable)
  * `equipped : [PowerUpSave?]` – fixed-length (6) array representing each slot; `nil` = empty
  * `spheres: [SphereState]` - snapshot of all spheres in the play area with their active power-ups
  * Note: Multiple power-ups can be active simultaneously if they are different types

* `PowerUpProgress`
  * `id : String` – **power-up name** (stable key)
  * `isUnlocked`, `level`

* `PowerUpSave`
  * `id : String` – power-up name
  * `level` – per-run level (mirrors permanent level at save time)
  * `slotIndex` – first slot the power-up occupies (multi-slot awareness)
  * `isActive` – whether the power-up is currently active
  * `isPrimed` – whether an environmental power-up is in primed state
  * `remainingDuration` – time left for environmental power-ups
  * `type` – PowerUpType (singleUse/environment/targeting)
  * `currentCharges` – number of charges remaining (starts at 1)
  * `isRecharging` – whether power-up is in recharge state
  * `mergesUntilRecharge` – merges needed to complete recharge

* `PowerUpStats` (not saved, computed at runtime)
  * `duration` – base duration for environmental power-ups (nil for others)
  * `forceMagnitude` – effect strength multiplier
  * `massMultiplier` – physics mass multiplier

* `SphereState`
  * `tier` – sphere's current tier
  * `position` – sphere's current position
  * `activePowerUps` – array of power-up names currently affecting this sphere
  * Note: Can have multiple active power-ups of different types

* `MetaState` – currently `firstLaunchDate`, `totalPlayTime`; free to extend.

---

## 2. Power-Up Types & Activation

### 2.1 Power-Up Categories
* **Single-Use** (affect next spawned ball)
  - Super Massive Ball (Blue)
  - Magnetic Ball (Purple)
  - Negative Ball (Red)
  - Features:
    * Charge-based system (1 charge)
    * Recharge through merges
    * Recharge time scales with level

* **Environmental** (affect entire play area)
  - Low Gravity (Blue)
  - Rubber World (Green)
  - Ice World (Cyan)
  - Features:
    * Two-stage activation (Prime → Active)
    * Duration system (10s base + 2s/level)
    * Visual countdown
    * Auto-deactivation
    * Charge-based system

* **Targeting** (affect existing balls)
  - Selective Deletion (Red 70%)
  - Repulsion Field (Orange)
  - Features:
    * Charge-based system
    * Recharge through merges
    * Tap-to-select mechanics

### 2.2 Activation Rules
* Environmental power-ups:
  - Can be primed (50% opacity)
  - When activated, run for full duration
  - Show border effect around game area
  - Auto-deactivate when duration expires
  - Any new activation deactivates primed power-ups
* Single-use and targeting power-ups:
  - Instant activation/deactivation
  - No duration/timer system
  - Consume charge on use
  - Enter recharge state when depleted
* Multiple types can be active simultaneously
* Recharge system:
  - Level 1: 50 merges to recharge
  - Level 2: 40 merges to recharge
  - Level 3: 20 merges to recharge
  - Recharge state persists in save file

---

## 3. Serialization
* **Codable → JSON** (human-readable while developing).
* `SaveManager` singleton handles:
  * Background encoding on a utility queue.
  * Atomic writes (`.atomic`) to avoid partial files.
  * Debug prints in `DEBUG` builds: path + action.
* File: `Documents/GameState.json`.

---

## 4. Save / Load Hooks
| Event | Method | Notes |
|-------|--------|-------|
| Level-up choice selected | `GameViewModel.saveGameState()` | Keeps run up-to-date after each reward. |
| Pause button tapped | `GameView.onChange(of: isPaused)` | Persists sphere positions and run state when pausing. |
| Pause → Main Menu | `PauseMenuView.onMainMenu` | Final save before tearing down the game view. |
| Power-up duration end | `GameViewModel.updatePowerUpTimers` | Auto-saves when environmental power-ups expire. |
| Power-up recharge | `GameViewModel.earnScore` | Auto-saves when merges affect recharge counters. |
| App lifecycle (future) | SceneDelegate / `sceneWillResignActive` | Add call to `SaveManager.save` to guard against force-quit. |

The **Continue** button is enabled when `SaveManager.load()?.run != nil`, guaranteeing an actual run is present.

---

## 5. Extending the Schema

1. **Add new fields**
   * Simply append optional properties to any Codable struct. Older saves ignore unknown keys; new saves populate them.
2. **New systems**
   * Example: Flask sizes
     ```swift
     struct Progression {
         ...
         var flasks : [FlaskSize: Bool]? // optional keeps old saves valid
     }
     ```
3. **Breaking changes**
   * When you _must_ rename/remove fields, bump `schemaVersion` and perform a lightweight migration inside `SaveManager.load()`.
     ```swift
     if state.schemaVersion < 2 {
         // transform / default new fields
     }
     ```
4. **Additional trigger points**
   * Call `SaveManager.shared.save(currentState)` whenever you add meaningful, durable changes (currency spend, shop purchase, achievement unlock).
5. **Switch to binary**
   * Replace `JSONEncoder/Decoder` with `PropertyListEncoder` or `NSSecureCoding` if file size becomes a concern.

---

## 6. Loading Workflow in UI
1. Main menu checks for a valid `run` → enables _Continue_.
2. Pressing _Continue_ reads `GameState` and injects it into `GameView`.
3. `GameViewModel`'s initializer **synchronously** calls `applyGameState` to populate:
   * currency, unlocked status, levels
   * equipped slots (multi-slot lengths respected)
   * power-up states (active, primed, remaining duration)
   * **Crucially, sphere positions from the previous session.**
4. The `GameScene` is created with this fully-loaded initial state, preventing race conditions.
5. UI updates through `@Published` bindings.

---

## 7. Communication During Gameplay (Saving)
* The `GameViewModel` holds a `sphereStateProvider` closure.
* `SpriteKitContainer` sets this provider, giving it a reference to the `GameScene`'s `getCurrentSphereStates()` method.
* When `saveGameState()` is called (e.g., on pause), it invokes the provider to get live sphere positions from the `SKScene` before serializing. This avoids coupling the scene directly to the view model while ensuring the most up-to-date state is saved.

---

## 8. Future Ideas
* **Cloud sync** – serialize JSON, base-64 & push to iCloud key-value store.
* **Compression** – wrap data with `Compression` framework (e.g., LZFSE) before writing.
* **Checksum** – append SHA-256 hash to detect corruption.
* **Multiple save slots** – change `fileName` to include a slot index; expose picker UI. 