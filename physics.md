# Game Physics Breakdown

This document outlines the physics configuration for the game world and the dynamic objects within it.

## Physics World Configuration

The overall physics world is configured with standard Earth-like gravity. This setup is found in `physics_reference.md`.

- **Gravity:** The scene's gravity is set to `(dx: 0, dy: -9.8)`, simulating a standard downward gravitational pull.
- **Boundaries:** The invisible walls of the game area have a low `friction` of `0.05` and `restitution` (bounciness) of `0.3`.

## Game Object Physics (`MaterialNode`)

The physical properties of the balls (`MaterialNode` objects) are determined by their `tier`.

- **Friction:** All balls have a low `friction` of **`0.05`**. This allows them to slide against each other and the walls quite easily.

- **Bounciness (Restitution):** They have a moderate `restitution` of **`0.3`**, meaning they will bounce, but not excessively.

- **Damping:** Both `linearDamping` and `angularDamping` are set to `0.1`, simulating slight air and rotational resistance.

- **Size (Radius):** The size of a ball is directly tied to its tier. Higher tiers result in larger balls. The radius is calculated with this formula from `mergeapp Shared/GameScene.swift`:

  ```swift
  // Base radius of 15, plus 10 for each tier above 1
  static func calculateRadius(forTier tier: Int) -> CGFloat {
      let baseSize: CGFloat = 15
      return baseSize + (tier > 1 ? CGFloat((tier - 1) * 10) : 0)
  }
  ```
  - **Tier 1:** 15 points
  - **Tier 2:** 25 points
  - **Tier 3:** 35 points
  - ...and so on.

- **Mass and Density:** Mass is **inversely proportional to the tier**. Higher-tiered (and larger) balls are lighter and less massive than lower-tiered balls. This creates a dynamic where smaller balls are heavier and can push larger, lighter balls more easily.

  The mass is calculated with this formula from `mergeapp Shared/GameScene.swift`:
  ```swift
  // mass is calculated exponentially, decreasing for higher tiers
  let maxTier: CGFloat = 12
  let baseMass: CGFloat = 10.0
  let massMultiplier = pow(2.0, maxTier - CGFloat(tier))
  body.mass = baseMass * massMultiplier
  ```
  **Density** is not set directly. SpriteKit calculates it from mass and volume (area in 2D), meaning higher-tier balls are significantly less dense. 