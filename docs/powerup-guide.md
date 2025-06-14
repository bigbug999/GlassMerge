# Power-Up Implementation Guide

## Current Implementation

### Base System
- Power-ups can be equipped in slots at the bottom of the game screen
- Each power-up can occupy 1-3 slots based on its level
- Power-ups are organized into three types:
  1. Single-Use (affect next spawned ball)
  2. Environmental (affect entire play area, duration-based)
  3. Targeting (affect existing balls)
- Environmental power-ups have a two-stage activation:
  1. Prime (50% opacity border)
  2. Active (100% opacity border)
- Environmental power-ups have duration timers:
  - Base duration: 10 seconds
  - +2 seconds per level
  - Visual countdown indicator
  - Auto-deactivation when expired
- Only one power-up can be active at a time per type
- Active power-ups are indicated with colored borders:
  - Super Massive Ball: Blue
  - Negative Ball: Red
  - Magnetic Ball: Purple
  - Low Gravity: Blue
  - Rubber World: Green
  - Ice World: Cyan
- Power-ups have a recharge system:
  - Each power-up starts with 1 charge
  - Using a power-up consumes a charge
  - When charges are depleted, power-up enters recharge state
  - Recharge requires a number of merges based on level:
    * Level 1: 50 merges
    * Level 2: 40 merges
    * Level 3: 20 merges
  - Recharge state persists across game saves
- Debug logging tracks activation/deactivation states
- Power-up states persist across game saves
- Active power-ups are tracked per-sphere
- Level-up system prevents duplicate power-up offerings

### Power-Up Structure
```swift
struct PowerUp {
    let id: UUID
    let name: String
    let description: String
    let category: PowerUpCategory
    let type: PowerUpType
    let icon: String
    var isUnlocked: Bool
    var level: Int
    var cost: Int
    var slotIndex: Int?
    var isActive: Bool = false
    var isPrimed: Bool = false
    var remainingDuration: TimeInterval = 0
    
    // Charge system
    var currentCharges: Int = 1
    var isRecharging: Bool = false
    var mergesUntilRecharge: Int = 0
    
    // Helper function for charge management
    mutating func useCharge() -> Bool {
        if currentCharges > 0 {
            currentCharges -= 1
            if currentCharges == 0 {
                isRecharging = true
                mergesUntilRecharge = 50 - (level - 1) * 10  // Level 1: 50, Level 2: 40, Level 3: 30
            }
            return true
        }
        return false
    }
}

struct PowerUpStats {
    var duration: TimeInterval?  // nil for single-use, 10s base for environmental
    var forceMagnitude: Double   // Effect strength multiplier
    var massMultiplier: Double   // Physics mass multiplier
}
```

## Categories & Implementation Status

### 1. Gravity Category
#### Super Massive Ball (Single-Use)
- **Status**: ✅ Fully Implemented
- **Implementation Progress**:
  - [x] Add visual indicator for affected ball (blue stroke)
  - [x] Implement power-up state persistence
  - [x] Implement single active power-up system
  - [x] Modify ball physics properties when power-up is active
  - [x] Increase mass and downward force on release
  - [x] Add screen shake on impact
- **Level Scaling**:
  - Level 1 (Base):
    - Mass multiplier: 2.0x
    - Force magnitude: 0.75x
    - Base mass: 7.5
    - Base impulse: -600.0
  - Level 2:
    - Mass multiplier: 4.0x
    - Force magnitude: 1.31x (1.75x base)
  - Level 3:
    - Mass multiplier: 8.0x
    - Force magnitude: 1.5x (2.0x base)
- **Physics Properties**:
  - Restitution: 0.3 (more bouncy)
  - Friction: 0.02 (less friction)
  - Linear/Angular Damping: 0.05 (less air resistance)
  - Mass calculation uses pow(2.0) curve for steeper scaling

#### Low Gravity (Environmental)
- **Status**: Partially Implemented
- **Implementation Progress**:
  - [x] Add duration system (10s base + 2s/level)
  - [x] Implement two-stage activation (prime/active)
  - [x] Add visual countdown indicator
  - [x] Auto-deactivation when expired
  - [ ] Modify world gravity when active
  - [ ] Add visual particles/effects
  - [ ] Smooth transition between gravity states

### 2. Physics Category
#### Rubber World (Environmental)
- **Status**: Partially Implemented
- **Implementation Progress**:
  - [x] Add duration system (10s base + 2s/level)
  - [x] Implement two-stage activation
  - [x] Add visual countdown indicator
  - [x] Auto-deactivation when expired
  - [ ] Modify restitution and friction
  - [ ] Add bounce effect visualization
  
#### Ice World (Environmental)
- **Status**: Partially Implemented
- **Implementation Progress**:
  - [x] Add duration system (10s base + 2s/level)
  - [x] Implement two-stage activation
  - [x] Add visual countdown indicator
  - [x] Auto-deactivation when expired
  - [ ] Modify surface friction
  - [ ] Add ice effect visualization

### 3. Magnetism Category
#### Magnetic Ball (Single-Use)
- **Status**: Partially Implemented
- **Implementation Progress**:
  - [x] Add visual indicator for affected ball (purple stroke)
  - [x] Implement power-up state persistence
  - [x] Implement single active power-up system
  - [ ] Implement attraction forces
  - [ ] Add magnetic field visualization
  - [ ] Handle multi-ball interactions

### 4. Targeting Category
#### Targeting Power-Ups (All)
- **Status**: ✅ Fully Implemented
- **Implementation Progress**:
  - [x] Add charge system integration
  - [x] Implement priming mechanics
  - [x] Add targeting state management
  - [x] Handle charge consumption
  - [x] Implement recharge system
  - [x] Add state persistence
- **Charge System**:
  - Each power-up starts with 1 charge
  - Priming doesn't consume a charge
  - Charge is consumed only on successful targeting
  - Recharge requires merges based on level:
    * Level 1: 50 merges
    * Level 2: 40 merges
    * Level 3: 30 merges
- **Targeting Flow**:
  1. First tap primes the power-up (blue border)
  2. Second tap on a sphere activates the effect
  3. Charge is consumed only on successful activation
  4. Power-up enters recharge state if no charges remain
  5. Other primed targeting power-ups are automatically deprimed

## Future Enhancements
1. **Visual Feedback**
   - Power-up activation effects
   - Status indicators
   - Particle effects

2. **Sound & Haptics**
   - Unique activation sounds
   - Haptic feedback patterns
   - Environmental audio effects

3. **UI Improvements**
   - Power-up tooltips
   - Status effect icons
   - Active duration indicators

## Implementation Notes
- Power-ups are implemented as value types (structs)
- State changes are propagated through the view model
- Power-ups are categorized by type:
  - Single-use: Affect next spawned ball
  - Environmental: Timed effects on play area
  - Targeting: Affect existing balls
- Environmental power-ups use a sophisticated duration system
- Multiple power-up types can be active simultaneously 