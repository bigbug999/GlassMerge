# August 2024 Changes & Game Refactor Plan

This document outlines the planned changes for GlassMerge, grouped by area of focus. Each item includes an estimated complexity and a brief description of the work involved.

---

## I. Physics & Core Gameplay Feel

This group of tasks focuses on improving the tactile feel of the game. They are relatively small and can be implemented independently.

### 1. Increase Base Friction
- **Complexity**: Small
- **Description**: Increase the base friction of all spheres to make power-ups that reduce friction (like "Ice World") more impactful. This is a simple change to the default physics properties in `ContentView.swift`.

### 2. Increase Jostle Physics on Merge
- **Complexity**: Small
- **Description**: When spheres merge, apply a small outward force to nearby spheres to create a more dynamic and satisfying "jostle" effect. This will involve locating the merge logic in the `SKPhysicsContactDelegate` methods and applying an impulse to surrounding bodies.

### 3. Refine Haptic Feedback
- **Complexity**: Medium-Large
- **Description**: The haptic feedback system needs refinement to provide better tactile response during gameplay. Currently, rapid merge sequences create overwhelming feedback, and unnecessary haptics on ball drops distract from the core experience.

  **Current Implementation**:
    - Direct haptic calls in `HapticManager` singleton
    - No timing control or debouncing
    - Haptics fire immediately for every merge
    - Full intensity (1.0) for all merges regardless of significance
    - Drop haptics at 0.4 intensity
    
  **Current Issues**:
    - Overwhelming feedback during chain reactions
    - Every merge triggers a full-intensity haptic
    - No cooldown between haptic events
    - Unnecessary haptic feedback on ball drops
    - Performance impact from rapid haptic calls
    - Debug logging cluttering haptic-related code

  **Technical Analysis**:
    - Current Implementation:
      ```swift
      // Merge haptics
      let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
      let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
      
      // Drop haptics (to be removed)
      let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
      let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
      ```

  **Proposed Solution**:
    1. **Core Changes**:
       - Implement a debounce manager for haptic events
       - Remove ball drop haptics entirely
       - Add haptic cooldown system
       - Scale haptic intensity with merge tier
    
    2. **Technical Implementation**:
       - Create `HapticDebounceManager` class to handle event timing
       - Use combine/timer-based debouncing with ~100ms cooldown
       - Implement merge-tier-based intensity scaling
       - Add haptic presets for different game events
       - Clean up debug logging
    
    3. **New Features**:
       - Smart haptic coalescing for rapid merges
       - Progressive intensity based on merge chain length
       - Distinct haptic patterns for special events
       - Optional haptic preferences for players
    
  **Expected Impact**:
    - More satisfying merge feedback
    - Reduced haptic fatigue during gameplay
    - Better performance due to reduced haptic calls
    - Clearer distinction between different game events
    - Improved overall game feel

  **Dependencies**:
    - CoreHaptics framework
    - Merge detection system
    - Game state management

### 4. Add Merge Animation
- **Complexity**: Medium
- **Description**: Instead of spheres instantly disappearing and a new one appearing on merge, we will add a small, satisfying animation. This could involve a flash, a particle effect, or the two spheres visibly shrinking into the new, larger one.

### 5. Add Trajectory Preview
- **Complexity**: Large
- **Description**: Implement a system to show the player where a ball will land before they drop it. This will involve ray-casting or physics simulation to predict the trajectory and drawing a visual indicator on the screen.

---

## II. Progression System Refactor

- **Complexity**: Large
- **Description**: A complete overhaul of the out-of-game progression systems. This involves removing the current in-game leveling mechanics and introducing a new system for unlocking and upgrading power-ups.
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


