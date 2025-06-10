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

* `PowerUpProgress`
  * `id : String` – **power-up name** (stable key)
  * `isUnlocked`, `level`

* `PowerUpSave`
  * `id : String` – power-up name
  * `level` – per-run level (mirrors permanent level at save time)
  * `slotIndex` – first slot the power-up occupies (multi-slot awareness)

* `MetaState` – currently `firstLaunchDate`, `totalPlayTime`; free to extend.

---

## 2. Serialization
* **Codable → JSON** (human-readable while developing).
* `SaveManager` singleton handles:
  * Background encoding on a utility queue.
  * Atomic writes (`.atomic`) to avoid partial files.
  * Debug prints in `DEBUG` builds: path + action.
* File: `Documents/GameState.json`.

---

## 3. Save / Load Hooks
| Event | Method | Notes |
|-------|--------|-------|
| Level-up choice selected | `GameViewModel.saveGameState()` | Keeps run up-to-date after each reward. |
| Pause → Main Menu | `PauseMenuView.onMainMenu` | Persists before tearing down the game view. |
| App lifecycle (future) | SceneDelegate / `sceneWillResignActive` | Add call to `SaveManager.save` to guard against force-quit. |

The **Continue** button is enabled when `SaveManager.load()?.run != nil`, guaranteeing an actual run is present.

---

## 4. Extending the Schema

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

## 5. Loading Workflow in UI
1. Main menu checks for a valid `run` → enables _Continue_.
2. Pressing _Continue_ reads `GameState` and injects it into `GameView`.
3. `GameViewModel` asynchronously calls `applyGameState` to populate:
   * currency, unlocked status, levels
   * equipped slots (multi-slot lengths respected)
4. UI updates through `@Published` bindings.

---

## 6. Future Ideas
* **Cloud sync** – serialize JSON, base-64 & push to iCloud key-value store.
* **Compression** – wrap data with `Compression` framework (e.g., LZFSE) before writing.
* **Checksum** – append SHA-256 hash to detect corruption.
* **Multiple save slots** – change `fileName` to include a slot index; expose picker UI. 