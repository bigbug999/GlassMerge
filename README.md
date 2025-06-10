# Merge App

A physics-based merging game with roguelite elements, built with SwiftUI and SpriteKit.

## Game Overview

Merge App is a unique take on the popular Suika-style merging games, incorporating roguelite elements and strategic gameplay. Players combine alchemical materials to create more powerful tiers while managing resources and unlocking new abilities.

## Core Views

### 1. Main Menu
- **New Game**: Start a fresh run
- **Continue**: Resume previous game state
- **Upgrade Shop**: Permanent upgrades between runs
- **Collection**: View discovered combinations and materials
- **Settings**: Game configuration options

### 2. Run Setup
- Configure flask size
- Select starting tools
- Choose special abilities or modifiers
- View high score

### 3. Game View
- Main gameplay area with physics-based merging
- Score and resource display
- power-ups and abilities toolbar
- Pause menu

## Basic Gameplay Loop

1. **Start a Run**
   - Select initial configuration
   - start

2. **Core Mechanics**
   - Drop materials from the top of the play area
   - Materials combine when same tiers collide
   - Higher tier materials are worth more points
   - Physics affects material movement and combinations

3. **Run Progression**
   - Earn points through successful combinations
   - Point multiplier increase with combos
   - Collect resources during gameplay to upgrade and buy powerups
   - Run ends when a body is in the danger zone for more than 5 seconds
   - Resources persist between runs for upgrades

## Initial Features

### Material System
- Start with basic material tiers
- Progressive unlocks of new material types
- Different size tiers for each material category

### Physics
- Realistic gravity and collision
- Material bouncing and stacking
- Size-based weight system

### Roguelite Elements
- Permanent progression between runs
- Unlockable abilities and modifiers
- Resource management

## Future Expansions
- Special abilities and power-ups
- Material combination recipes
- Challenge modes
- Daily runs
- Achievement system

---

*This is a living document and will be updated as new features are implemented.* 