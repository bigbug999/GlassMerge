### **Project Plan: Unlocking & Progression System**

This document outlines the necessary code changes to implement a currency-based unlocking and progression system for flasks and power-ups. The implementation is broken down into four phases.

#### **Phase 1: Adjusting Core Data & Initial Player State**

The first step is to ensure that new players start with the correct items unlocked and that our data models are prepared for the new economy.

1.  **File to Modify:** `CoreDataManager.swift`
2.  **Function to Update:** `getGameData()`
    *   **Action:** Inside the block where a new `GameData` object is created for a first-time player, we will set the correct initial values.
    *   **Details:**
        *   Set the initial `currency` to `0`.
        *   Ensure `unlockedFlaskSizes` defaults to `"small"`.
        *   When creating the initial `PowerUpProgression` objects, we will set `isUnlocked` to `true` **only** for "Super Massive Ball", "Selective Deletion", and "Low Gravity". All other power-ups will be locked (`isUnlocked = false`). All will start at `level = 1`.

#### **Phase 2: Updating Game Logic Models & Costs**

Next, we'll update the in-memory data structures to reflect the new coin-based costs for all unlockable and upgradeable items.

1.  **File to Modify:** `ContentView.swift`
2.  **Models to Update:** `FlaskSize` enum and `PowerUp` struct.
    *   **`FlaskSize` Enum:**
        *   **Action:** Update the `cost` computed property for each case.
        *   **Details:**
            *   `.medium`: `250`
            *   `.large`: `500`
    *   **`PowerUp` Struct & `PowerUpManager` `powerUps` array:**
        *   **Action:** Standardize the initial unlock `cost` for all power-ups and revise the `upgradeCost` logic.
        *   **Details:**
            *   Set the base `cost` property to `25` for all power-ups. This is the cost to unlock (Level 1).
            *   Modify the `upgradeCost` computed property to use a tiered structure:
                *   Cost to upgrade to Level 2: `50` coins.
                *   Cost to upgrade to Level 3: `100` coins.

#### **Phase 3: Implementing Currency Awards**

We need to establish the system for players to earn currency from their gameplay.

1.  **File to Modify:** `GameViewModel.swift`
2.  **Function to Update:** `endRun()`
    *   **Action:** Calculate and award coins at the end of a game session.
    *   **Details:**
        *   When a run is concluded, we will calculate the coins earned using the formula: `coins = ceil(Double(score) / 10.0)`.
        *   We'll then add these coins to the player's total `currency` stored in the `GameData` object via the `powerUpManager` and save the game state. This will happen just before the old run data is deleted.

#### **Phase 4: UI and Shop Implementation**

Finally, we'll surface these new systems to the player through the user interface, focusing on the main menu and the upgrade shop.

1.  **File to Modify:** `ContentView.swift`
2.  **Views to Update:** `MainMenuView` and `UpgradeShopView`.
    *   **`MainMenuView`:**
        *   **Action:** Display the player's current coin total.
        *   **Details:** We'll add a UI element that fetches and displays the currency from `CoreData` when the view appears.
    *   **`UpgradeShopView`:**
        *   **Action:** Overhaul the shop to include flasks and reflect the new currency and costs.
        *   **Details:**
            *   A coin counter will be added to the top of the view.
            *   A new section for "Flasks" will be created. It will list the Medium and Large flasks, showing their costs and allowing the player to unlock them.
            *   The existing "Power-ups" section will be updated to show the new unlock (`25`) and upgrade (`50`, `100`) costs.
            *   All "Unlock" or "Upgrade" buttons will be connected to the corresponding functions in `PowerUpManager` and will be disabled if the player has insufficient funds.

--- 