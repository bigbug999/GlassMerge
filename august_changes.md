# August 2024 Changes & Game Refactor Plan

This document outlines the planned changes for GlassMerge, grouped by area of focus. Each item includes an estimated complexity and a brief description of the work involved.

---

## I. Physics & Core Gameplay Feel

This group of tasks focuses on improving the tactile feel of the game. They are relatively small and can be implemented independently.

### 1. Increase Base Friction ✅
- **Complexity**: Small
- **Description**: Increase the base friction of all spheres to make power-ups that reduce friction (like "Ice World") more impactful. This is a simple change to the default physics properties in `ContentView.swift`.
- **Implementation**:
    - Set base sphere friction to 0.5
    - Set wall friction to 0.3
    - Unified Super Massive Ball friction with normal spheres
    - Commit: [a90e8d1]

### 2. Increase Jostle Physics on Merge ❌
- **Complexity**: Small
- **Description**: When spheres merge, apply a small outward force to nearby spheres to create a more dynamic and satisfying "jostle" effect. This will involve locating the merge logic in the `SKPhysicsContactDelegate` methods and applying an impulse to surrounding bodies.
- **Status**: Cancelled - Task deprioritized

### 3. Refine Haptic Feedback ✅
- **Complexity**: Medium-Large
- **Description**: The haptic feedback system needs refinement to provide better tactile response during gameplay. Currently, rapid merge sequences create overwhelming feedback, and unnecessary haptics on ball drops distract from the core experience.

  **Implementation Details**:
    - Removed all ball drop haptics to reduce feedback noise
    - Added proper haptic debouncing system:
        - Queue-based implementation that preserves all haptic events
        - 200ms cooldown between haptic triggers
        - Events play in sequence with consistent timing
        - Debug logging for haptic timing and queue state
    - Improved `HapticManager` architecture:
        - Added queue management system
        - Implemented proper state tracking
        - Added safeguards against queue processing races
    - Commit: [a90e8d1]

  **Technical Notes**:
    - Uses `TimeInterval` for precise timing control
    - Queue system ensures no haptics are lost during chain reactions
    - Automatic queue processing with async dispatch
    - Thread-safe implementation with queue state tracking



  **Results**:
    - More satisfying merge feedback with consistent timing
    - No haptic fatigue during chain reactions
    - Better performance through optimized haptic calls
    - Cleaner, more maintainable haptic system
    - Improved overall game feel

### 4. Add Merge Animation ✅
- **Complexity**: Medium
- **Description**: Added a particle-based merge animation that follows the merged ball.

  **Implementation Details**:
  - Created `createMergeEffect` function in `GameScene`
  - Particle effect attaches to and moves with the merged ball
  - Uses same texture as the merged ball for consistency
  - Duration: 0.3 seconds
  - Commit: [a90e8d1]

  **Key Parameters for Future Refinement**:
  ```swift
  // Particle emission
  emitter.particleBirthRate = 80
  emitter.numParticlesToEmit = 8
  emitter.particleLifetime = 0.3
  
  // Size and movement
  emitter.particleSize = radius * 0.8
  emitter.particleSpeed = radius * 3.0
  emitter.particleSpeedRange = radius * 0.5
  
  // Appearance
  emitter.particleAlpha = 1.0
  emitter.particleAlphaSpeed = -3.0
  emitter.particleScale = 1.0
  emitter.particleScaleSpeed = -1.0
  ```

  **Potential Future Improvements**:
  - Fine-tune particle count and distribution
  - Adjust particle size relative to ball size
  - Experiment with different fade-out patterns
  - Add optional color tinting
  - Consider adding secondary effects (e.g., shockwave)

### 5. Add Trajectory Preview ❌
- **Complexity**: Large
- **Description**: Implement a system to show the player where a ball will land before they drop it. This will involve ray-casting or physics simulation to predict the trajectory and drawing a visual indicator on the screen.
- **Status**: Cancelled - Task deprioritized

### 6. Holographic Shader Test
- **Complexity**: Medium
- **Description**: Create a holographic shader effect for vector shapes. The effect will be a rainbow gradient that shifts based on the accelerometer's input. The initial test will involve applying this effect to a rectangle at the bottom of the home screen.

---

## II. Progression System Refactor

- **Complexity**: Large
- **Description**: A complete overwhaul of the out-of-game progression systems. This involves removing the current in-game leveling mechanics and introducing a new system for unlocking and upgrading power-ups.
- **Core Tasks**:
    - Refactor meta progression system
    - Refactor power-ups to be leveled in the shop
    - Remove in-game level-ups
    
- **Critical Sub-Systems**:
    1. **Power-up Slot System Refactor**:
       - **Complexity**: Critical
       - **Description**: The current power-up slot system needs a complete overhaul due to fundamental reliability issues. The system manages a fixed array of slots (`equippedPowerUps`) where power-ups can occupy multiple consecutive slots based on their level, but the current implementation is prone to errors.

       **Current Issues**:
         - Slot allocation is unreliable during power-up upgrades
         - Multiple complex algorithms trying to find consecutive slots
         - Inconsistent state after failed upgrades
         - Race conditions when clearing and reassigning slots
         - No proper rollback mechanism for failed operations
         - Slots can become "orphaned" during certain operations
         - Edge cases when upgrading power-ups at array boundaries
         - Lack of proper state validation

       **Technical Debt**:
         - Multiple overlapping methods for slot management
         - Complex, nested conditional logic
         - Redundant slot scanning operations
         - Insufficient error handling
         - Debug-only validation code
    
       **Proposed Solution**:
         1. **Core Changes**:
            - Implement a new data structure specifically for slot management
            - Use a transaction-like system for atomic updates
            - Add proper state validation
            - Implement rollback capabilities
    
         2. **New Features**:
            - Slot reservation system for pending changes
            - Validation layer to prevent invalid states
            - Proper error handling and recovery
            - Comprehensive slot state tracking
    
         3. **Implementation Details**:
            - Replace array-based storage with a more robust structure
            - Add slot state enumeration (Empty, Reserved, Occupied)
            - Implement proper locking mechanism for slot updates
            - Add comprehensive logging for debugging
            - Create test suite for edge cases
    
       **Impact**: This refactor is critical as the slot system affects:
         - Power-up upgrading
         - Save/load functionality
         - Game progression
         - UI stability
         - Player experience

    2. **Currency System**:
       - **Description**: Players will earn a currency during gameplay. The scaling of this currency will need to be balanced for the new shop-based progression.

    3. **Power-up Recharging**:
       - **Description**: The recharge mechanic will change from being based on the *number* of merges to the *tier* of the merge. For example, a power-up might require a tier 7 merge to recharge. This recharge requirement will be upgradable through the new meta-progression system. The game's flask size will also be a factor in balancing this system.

---

## III. New Features & Content

This group includes new, self-contained features and content additions.

### 1. Add Sound Effects
- **Complexity**: Medium
- **Description**: Implement a sound manager to handle playing sound effects for key game events, such as ball drops, merges, collisions, and UI interactions.

### 2. Create Basic Tutorial Flow
- **Complexity**: Medium
- **Description**: Create a simple, guided tutorial for first-time players that explains the basic mechanics of dropping, merging, and perhaps using a power-up.

### 3. Add More Flask & Material Tiers
- **Complexity**: Small
- **Description**:
    - Add 2 more tiers to the flask size, for a total of 5.
    - Add 5-10 new material/ball tiers.
    - This is primarily a data-entry task, adding new data to the existing systems that define tiers.


