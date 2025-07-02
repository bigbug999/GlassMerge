# GlassMerge Save-System Overview (Core Data)

_Last updated: 2025-06-11_

---

## 1. Architecture

The game's persistence layer is built on Apple's **Core Data** framework, providing a robust and scalable solution for managing the object graph.

### 1.1 Core Components
* **`CoreDataManager.swift`**: A singleton that encapsulates the entire Core Data stack. It is the single source of truth for creating, fetching, and saving game data.
* **`GlassMerge.xcdatamodeld`**: The visual data model file that defines all entities, attributes, and relationships. Xcode uses this file to auto-generate the `NSManagedObject` subclasses.

### 1.2 Data Model Entities
The data model is composed of five core entities:

* **`GameData`**: A "singleton" entity that holds all global, persistent data. There should only ever be one instance of this object in the database.
  - `currency`: Player's permanent coins.
  - `unlockedFlaskSizes`: A comma-separated string of unlocked flask raw values.
  - `powerUpProgressions` (Relationship): A to-many relationship linking to all `PowerUpProgression` objects.
  - `currentRun` (Relationship): An optional to-one relationship to a `Run` object, which exists only when a game is in progress.

* **`PowerUpProgression`**: Tracks the persistent state of a single power-up in the game's catalog.
  - `id`: The name of the power-up (e.g., "Super Massive Ball").
  - `isUnlocked`: Boolean flag for unlock status.
  - `level`: The permanent level of the power-up.

* **`Run`**: Represents the complete state of a single game session. This object is created when a new game starts and is deleted when the run is over.
  - `score`, `level`, `xp`: Current run statistics.
  - `selectedFlaskSize`: The raw value of the `FlaskSize` enum for this run.
  - `equippedPowerUps` (Relationship): A to-many relationship to the `EquippedPowerUp` objects for this run.
  - `spheres` (Relationship): A to-many relationship to the `Sphere` objects currently in the play area.

* **`EquippedPowerUp`**: A snapshot of a power-up as it exists in a power-up slot during a specific run.
  - `id`, `level`, `slotIndex`: Basic identifying info.
  - `isActive`, `isPrimed`, `remainingDuration`: Live state of the power-up.
  - `currentCharges`, `isRecharging`, `mergesUntilRecharge`: State of the charge/recharge system.

* **`Sphere`**: A snapshot of a single sphere in the play area.
  - `tier`, `positionX`, `positionY`: Core physical properties.
  - `activePowerUps`: A comma-separated string of power-up names affecting this sphere.

---

## 2. Core Data Operations

All database interactions are funneled through the `CoreDataManager`.

* **Fetching Data**: `CoreDataManager.shared.getGameData()` is the primary entry point. It fetches the singleton `GameData` object or creates a new one on the first launch.
* **Saving Data**: Saving is performed by calling `CoreDataManager.shared.saveContext()`. The `GameViewModel` is responsible for updating the attributes of the managed objects before calling save.
* **Creating a New Run**: `CoreDataManager.shared.createNewRun(selectedFlask:)` creates a new `Run` object, links it to the `GameData` object, and clears any previous run.

---

## 3. Save / Load Hooks
The game saves its state at critical points to ensure progress is not lost. The main trigger is `GameViewModel.saveGameState()`.

| Event                  | Method / Trigger                        | Notes                                                                |
|------------------------|-----------------------------------------|----------------------------------------------------------------------|
| Pause Button Tapped    | `GameView.onChange(of: isPaused)`       | Persists the entire run state, including live sphere positions.      |
| Auto-Save Timer        | `GameView.onReceive(autoSaveTimer)`     | A periodic save occurs every 10 seconds during active gameplay.      |
| Level-Up Choice        | `GameViewModel.selectPowerUp()`         | Saves the newly acquired or upgraded power-up to the `Run` state.    |
| Return to Main Menu    | `PauseMenuView.onMainMenu`              | Final save before the game view is torn down.                        |
| App Backgrounding      | SceneDelegate / `sceneWillResignActive` | (Future) Add a call here to protect against force-quits.             |

The **Continue** button on the main menu is enabled by checking `CoreDataManager.shared.hasActiveRun()`, which verifies if a `Run` object is associated with the main `GameData`.

---

## 4. JSON to Core Data Migration

A private `MigrationManager` class exists within `CoreDataManager.swift` to handle a one-time data migration from the old `GameState.json` file.

* **Process**: On the first launch of this app version, the manager checks for `GameState.json`.
* **If Found**: It decodes the JSON file, maps its contents to the new Core Data entities, saves the new objects, and then **deletes the old JSON file** to prevent future migrations.
* **If Not Found**: It skips the migration process, which is the normal behavior after the first run.

---

## 5. Extending the Schema

Modifying the data model is straightforward with Core Data's tooling.

1.  **Add/Modify Attributes**: Open `GlassMerge.xcdatamodeld` and add new attributes or entities directly in the visual editor.
2.  **Lightweight Migration**: For simple changes (like adding a new optional attribute), Core Data can often perform an automatic, lightweight migration. Ensure this is enabled in your project settings.
3.  **Heavy Migration**: For complex changes (renaming fields, changing data types), a full migration policy may be needed.

---

## 6. Loading & Saving Workflow

1.  **Launch**: `ContentView` asks `CoreDataManager` for the `GameData` object.
2.  **Continue**: If a `Run` object exists, the "Continue" button is enabled. Tapping it passes the existing `GameData` object to the `GameView`.
3.  **New Game**: Tapping "New Game" takes the user to `RunSetupView`. When "Start Game" is tapped, `createNewRun()` is called, which sets up a fresh `Run` object in Core Data.
4.  **ViewModel Initialization**: `GameViewModel` is initialized with the `GameData` object. It reads the properties from the `Run` and `PowerUpProgression` objects to set up its initial state.
5.  **Gameplay Saving**: During gameplay, `GameViewModel.saveGameState()` is called. This function:
    *   Updates the attributes of the existing `Run` managed object (score, xp, etc.).
    *   Invokes a `sphereStateProvider` closure to get the latest sphere data from the `GameScene`.
    *   The `GameScene` creates new `Sphere` managed objects for the current context.
    *   The view model clears the old `Sphere` and `EquippedPowerUp` objects and attaches the new ones to the `Run`.
    - Finally, it calls `CoreDataManager.shared.saveContext()` to commit all changes to the database. 