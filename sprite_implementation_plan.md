# Plan: Implementing Sprites for Balls

This document outlines the plan to replace the procedurally generated `SKShapeNode` circles with `SKSpriteNode` instances for the game's balls, using the existing sprite atlas.

**File to be Modified:** `GlassMerge/ContentView.swift` (primarily the `GameScene` class).

## 1. Update Core Data Structures in `GameScene`

The first step is to adapt our `TierInfo` struct to reference sprite names instead of colors.

-   **Modify `TierInfo` Struct:** We will replace the `color: SKColor` property with `spriteName: String`.
-   **Update `tierData` Collection:** The static `tierData` array will be updated to map each tier to its corresponding sprite name (e.g., "ball_1", "ball_2").

## 2. Refactor Ball Creation Logic

Next, we'll change the functions responsible for creating balls to use sprites.

-   **`createSphereNode(tier:)`:**
    -   This function's return type will be changed from `SKShapeNode?` to `SKSpriteNode?`.
    -   It will now instantiate `SKSpriteNode(imageNamed: tierInfo.spriteName)`.
    -   The sprite's `size` will be set based on the `radius` from `tierData`, ensuring balls maintain their correct physical size.
-   **Type Updates:**
    -   All variables and properties that currently hold a reference to a ball (e.g., `currentSphere`, `selectedTarget`, elements in `scheduledForMerge`) will be updated from `SKShapeNode` to `SKSpriteNode`.
    -   Function signatures and type casts throughout `GameScene` will be updated accordingly. For example, `addPhysics(to:)` will now accept an `SKSpriteNode`.

## 3. Adapt Visual Effects for Sprites

`SKSpriteNode` does not have a `strokeColor`, so we need a new way to display power-up effects and targeting highlights. We will use color tinting.

-   **Highlighting & Power-ups:**
    -   We will use the `color` and `colorBlendFactor` properties of `SKSpriteNode`.
    -   For example, to highlight a sphere, we can set its `color` to yellow and `colorBlendFactor` to `0.7`. To remove the highlight, we reset `colorBlendFactor` to `0.0`.
-   **Affected Functions:**
    -   `highlightSphere(_:)` / `unhighlightSphere(_:)`: Will be updated to use tinting for selection.
    -   `currentActivePowerUp` / `createAndPlaceSphere(...)`: Will be updated to apply a tint to balls that have an active power-up.
    -   The `powerUpColors` dictionary will be preserved as its values will be used for the `color` property when tinting.

## 4. Physics Adjustments

The physics implementation will remain largely the same, as `SKPhysicsBody` can be attached to any `SKNode` subclass.

-   **`addPhysics(to:)`:** The function will now take an `SKSpriteNode` as its argument. The physics body will continue to be a circle (`SKPhysicsBody(circleOfRadius:)`), matching the sprite's visual size. The mass and other physics properties will be applied as they are now.

This plan ensures a smooth transition to sprites while reusing as much of the existing game logic as possible, primarily by swapping out the node type and changing how visual effects are rendered. 