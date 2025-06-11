# Game Implementation Plan

## Main Menu Structure
### Core Screens
1. **Main Menu Screen**
   - New Game Button
   - Continue Button (disabled if no save data exists)
   - Upgrade Shop Button
   - Collection Button
   - Settings Button

2. **Run Setup Screen**
   - Flask Size Selection
     - Small (Basic)
       - Base flask size: 375x500 points
       - Base ball diameter: 50 points
       - Maximum practical ball count: ~35 balls
     - Medium (Unlockable - 1000 currency)
       - Flask size: 375x500 points
       - Ball scale: 0.75x base size (37.5 points diameter)
       - Maximum practical ball count: ~60 balls
       - Enables higher tier merges through increased capacity
     - Large (Unlockable - 10000 currency)
       - Flask size: 375x500 points
       - Ball scale: 0.5x base size (25 points diameter)
       - Maximum practical ball count: ~120 balls
       - Enables highest tier merges through maximum capacity
   - Starting Power-Up Selection
     - Display available starting power-ups
     - Show locked items with unlock conditions
   - Start Run Button
   - Back to Main Menu Button

3. **Upgrade Shop**
   - Currency Display
   - Currency Earning:
     - Tier 8 merge: 100 currency
     - Tier 9 merge: 250 currency
     - Tier 10+ merges: Additional 250 currency per tier
   - Permanent Upgrades
     - Flask Size Upgrades
       - Medium Flask: 1000 currency (0.75x ball scale)
       - Large Flask: 10000 currency (0.5x ball scale)
     - Starting Power-Up Slots (1000 currency each)
     - Power-Ups
       - Base unlock cost: 1000 currency
       - Each power-up costs the same for initial unlock
       - All power-ups start at Level 1
   - Back Button

4. **Collection Screen**
   - Power-Up Categories
     - Physics
     - Gravity
     - Magnetism
     - Void
     - Friction
   - For Each Power-Up:
     - Icon
     - Name
     - Description
     - Unlock Status
   - Back Button

5. **Settings Screen**
   - Sound Effects Volume
   - Music Volume
   - Haptic Feedback Toggle
   - Performance Mode Toggle
   - Credits
   - Privacy Policy
   - Terms of Service

## Power-Up System
### Organization
1. **Power-Up Categories and Abilities**
   - **Gravity**
     - Super Massive Ball
       - Activation makes spawned ball super dense
       - Applies strong downward impulse on release
       - Useful for breaking up clusters
     - Low Gravity Environment
       - Modifies physics world gravity
       - Affects all balls in play area
   
   - **Magnetism**
     - Magnetic Ball
       - Creates attraction force to same-tier balls
       - Helps create matching combinations
       - Force scales with distance
     - Repulsion Field
       - Repels balls of different tiers
       - Creates natural sorting effect
       - Helps separate unwanted combinations

   - **Void**
     - Negative Ball
       - Single-use deletion tool
       - Removes itself and first ball touched
       - Strategic removal for tight situations
     - Selective Deletion
       - Tap-to-select mechanic
       - Double-tap to confirm deletion
       - User-controlled removal tool

   - **Friction**
     - Bouncy Environment
       - Increases restitution globally
       - Makes balls extra bouncy
       - Creates more dynamic gameplay
     - Slick Surface
       - Reduces friction coefficient
       - Enables longer sliding movements
       - Helps balls find natural combinations

2. **Power-Up Properties**
   - Base Stats (Level 1)
     - Duration (for environment effects)
       - Low Gravity: 10 seconds (45s cooldown)
       - Repellant Environment: 8 seconds (40s cooldown)
       - Slick Surface: 12 seconds (50s cooldown)
     - Single-Use Effects
       - Super Massive Ball: 35s cooldown
       - Magnetic Ball: 30s cooldown
       - Repulsion Field: 40s cooldown
       - Negative Ball: 45s cooldown
       - Selective Deletion: 60s cooldown
     - Force Magnitudes
       - Super Massive Ball: 1.5x normal mass
       - Magnetic/Repulsion: 0.5x force
       - Low Gravity: 0.5x normal gravity
   
   - Level Scaling (per level)
     - Duration Increases
       - Environment effects: +2 seconds per level
     - Cooldown Reduction
       - All powers: -5 seconds per level
       - Minimum cooldown at max level (Level 5):
         - Environment effects: 20-25 seconds
         - Single-use effects: 15-30 seconds
     - Force Magnitude Increases
       - Super Massive Ball: +0.5x mass per level
       - Magnetic/Repulsion: +0.25x force per level
       - Low Gravity: +0.1x gravity control per level
   
   - Visual Indicators
     - Cooldown timer displayed on power-up icon
     - Power-up icon grays out during cooldown
     - Circular progress indicator shows remaining cooldown
     - Pulsing effect when power-up becomes available
   
   - Unlock Conditions
     - Achievement-based unlocks
     - Currency purchase requirements
     - Level requirements

### Roguelite Progression
1. **Level Up System**
   - Experience Points from:
     - Scoring points from merges
     - Merge combo multipliers
   - Level Requirements:
     - Level 1: 400 XP
     - Level 2: 1000 XP
     - Level 3: 2000 XP
     - Level 4: 4000 XP
     - Level 5: 8000 XP
     - Each subsequent level: Previous requirement × 2

2. **Power-Up Selection**
   - Level Up Pause Mechanics:
     - Physics simulation freezes immediately
     - All ball movement stops
     - Current game state preserved
     - Dim background to focus on selection UI
   - Selection Interface:
     - Three random options presented:
       - Option 1: New Power-Up (if available)
       - Option 2: Upgrade Existing Power-Up
       - Option 3: Alternative Power-Up/Upgrade
     - Clear visual preview of each option
     - 'Choose Reward' prompt
     - No time pressure during selection
   - After Selection:
     - Choice is immediately applied
     - Physics simulation resumes
     - Brief visual feedback of acquired power
     - Game continues from preserved state

3. **Scoring System**
   - Base Merge Points:
     - Tier 1 merge: 10 points
     - Each higher tier: Previous tier × 2
   - Combo System:
     - Consecutive merges within 2 seconds
     - Each combo adds 50% bonus to base points
     - Combo counter displayed on screen
     - Points contribute to XP 1:1 ratio

## Data Management
1. **Save System**
   - Single Save Implementation:
     - Uses NSKeyedArchiver for SpriteKit game state
     - Save file stored in app's Documents directory
     - Filename: "gameState.archive"
   
   - Saved Game State:
     - Active Game Elements:
       - All sphere positions and velocities
       - Sphere properties (size, tier, scale)
       - Current physics world state
       - Active power-up effects
     - Player Progress:
       - Current score
       - Current level and XP
       - Combo state
       - Available currency
     - Unlocked Content:
       - Purchased flask sizes
       - Unlocked power-ups
       - Power-up levels
     
   - Save Operations:
     - Auto-save triggers:
       - Every successful merge
       - Power-up usage
       - Level up
       - Entering background
     - Save file structure:
       ```swift
       class GameState: NSCoder {
           var spheres: [SphereSaveData]
           var physicsState: PhysicsWorldData
           var playerProgress: PlayerProgress
           var unlockedContent: UnlockedContent
           var activeEffects: [PowerUpEffect]
       }
       ```
     
   - Technical Implementation:
     - Use `NSSecureCoding` protocol
     - Implement error handling and backup
     - Maintain save file integrity
     - Version control for save format
     - Graceful handling of corrupted saves

2. **Progress Tracking**
   - Statistics stored separately from main save
   - Tracks lifetime achievements
   - Records best scores
   - Maintains play time statistics

## Technical Implementation Notes
1. **SwiftUI Views**
   - Separate view files for each major screen
   - Reusable components
   - Consistent styling system
   - Smooth transitions

2. **Game State Management**
   - ObservableObject for game state
   - Separate managers for:
     - Power-ups
     - Progress
     - Settings
     - Audio

3. **Performance Considerations**
   - Efficient state updates
   - Memory management for particle effects
   - Cache management
   - Ball Scaling System:
     - Use SpriteKit's native scaling for optimal performance
     - Maintain consistent physics properties despite visual scale
     - Adjust physics body radius proportionally
     - Scale collision detection boundaries automatically
     - Maintain consistent mass-to-size ratio across scales

## Future Considerations
1. **Expansion Points**
   - Additional power-up categories
   - New flask types
   - Special events
   - Visual effects
   - Additional power-ups beyond initial 8

## Implementation Order

### Phase 1: Core Game Mechanics ✓ (COMPLETED)
1. **Basic Physics Setup** ✓
   - Create base flask size 
   - Implement basic sphere physics
   - Set up collision detection
   - Configure base ball size (50 points)

2. **Merge Mechanics** ✓
   - Implement sphere combination logic
   - Add tier progression system
   - Create merge detection
   - Setup scoring system

### Phase 2: Save System and Progression (NEXT PRIORITY)
3. **Save System Foundation**
   - Implement GameState structure
   - Setup NSKeyedArchiver integration
   - Create basic save/load functions
   - Dependencies: None (can start immediately)

4. **Score and XP System** COMPLETED
   - Implement point calculation
   - Add combo detection (2-second window)
   - Create XP accumulation
   - Setup level thresholds
   - Dependencies: None (can start immediately)

5. **Level Up System**
   - Add physics pause functionality
   - Implement level up detection
   - Create choice presentation UI
   - Setup state preservation during pause
   - Dependencies: Score and XP System

6. **Currency System**
   - Implement currency earning (Tier 8+)
   - Add currency tracking
   - Create persistent currency storage
   - Dependencies: None (can start immediately)

### Phase 3: Power-Ups
7. **Base Power-Up Framework**
   - Create power-up base class
   - Implement cooldown system
   - Add power-up UI elements
   - Setup activation mechanics
   - Dependencies: Level Up System

8. **Individual Power-Ups**
   - Implement in this order:
     a. Gravity powers (easiest physics modification)
       - Super Massive Ball
       - Low Gravity Environment
     b. Friction powers (surface property changes)
       - Repellant Environment
       - Slick Surface
     c. Magnetism powers (force-based interactions)
       - Magnetic Ball
       - Repulsion Field
     d. Void powers (object manipulation)
       - Negative Ball
       - Selective Deletion
   - Dependencies: Base Power-Up Framework

### Phase 4: Flask and Scaling
9. **Flask Size System**
   - Implement ball scaling logic
   - Add flask size selection
   - Create unlock system
   - Setup size transition handling
   - Dependencies: Currency System, Basic Physics

### Phase 5: UI and Menus
10. **Main Menu System**
    - Create menu navigation
    - Implement game state management
    - Add continue/new game logic
    - Dependencies: Save System

11. **Shop Implementation**
    - Create upgrade purchase system
    - Implement unlock tracking
    - Add power-up store
    - Dependencies: Currency System

12. **Collection Screen**
    - Create power-up display system
    - Implement unlock status tracking
    - Add power-up information display
    - Dependencies: Power-Ups

### Phase 6: Polish and Integration
13. **Visual Feedback**
    - Add merge effects
    - Implement power-up indicators
    - Create level up animations
    - Dependencies: All previous systems

14. **Settings and Audio**
    - Implement audio system
    - Add settings storage
    - Create volume controls
    - Dependencies: Save System

15. **Testing and Balancing**
    - Balance currency earning rates
    - Adjust power-up cooldowns
    - Fine-tune physics parameters
    - Test save system reliability
    - Dependencies: All systems

### Revised Timeline Breakdown
- Phase 2: 25% of remaining development time
- Phase 3: 25% of remaining development time
- Phase 4: 15% of remaining development time
- Phase 5: 20% of remaining development time
- Phase 6: 15% of remaining development time

### Next Steps (Immediate Priority)
1. Begin implementing the save system using NSKeyedArchiver
2. Add scoring system and XP tracking
3. Implement level up pause mechanics

These next steps can be worked on in parallel as they build on the existing physics and merge systems but don't depend on each other. 