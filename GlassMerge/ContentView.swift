//
//  ContentView.swift
//  GlassMerge
//
//  Created by Loaner on 6/9/25.
//

import SwiftUI
import Foundation
import SpriteKit
import CoreData
#if os(iOS)
import UIKit
import CoreMotion
import CoreHaptics
#endif

// MARK: - DATA MODELS (NON-CODABLE)

enum FlaskSize: String, Codable, CaseIterable {
    case small
    case medium
    case large
    
    var displayName: String {
        switch self {
        case .small: return "Small (Basic)"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    
    var description: String {
        switch self {
        case .small: return "Base flask size with standard balls"
        case .medium: return "75% ball scale, up to 60 balls"
        case .large: return "50% ball scale, up to 120 balls"
        }
    }
    
    var cost: Int {
        switch self {
        case .small: return 0
        case .medium: return 250
        case .large: return 500
        }
    }
    
    var ballScale: CGFloat {
        switch self {
        case .small: return 1.0
        case .medium: return 0.75
        case .large: return 0.5
        }
    }
}

// Power-up Model
enum PowerUpCategory: String, CaseIterable {
    case gravity = "Gravity"
    case magnetism = "Magnetism"
    case void = "Void"
    case physics = "Physics"
    
    var description: String {
        switch self {
        case .gravity: return "Physics-based effects that modify mass and gravity"
        case .magnetism: return "Attraction and repulsion effects"
        case .void: return "Object removal and deletion effects"
        case .physics: return "Surface and material property modifiers"
        }
    }
}

enum PowerUpType: String, Codable {
    case singleUse
    case environment
    case targeting
}

struct PowerUpStats {
    var duration: TimeInterval?  // nil for single-use effects
    var forceMagnitude: Double
    var massMultiplier: Double = 1.0  // New: Multiplier for physics mass
    var cooldown: TimeInterval = 15.0 // Base cooldown, modified by level for environmental
    
    static func baseStats(for powerUp: PowerUp) -> PowerUpStats {
        switch powerUp.name {
        // Single-use power-ups (no duration)
        case "Super Massive Ball":
            return PowerUpStats(duration: nil, forceMagnitude: 0.75, massMultiplier: 2.0, cooldown: 60.0)
        case "Selective Deletion":
            return PowerUpStats(duration: nil, forceMagnitude: 1.0, cooldown: 15.0)
            
        // Environmental power-ups (all need duration)
        case "Low Gravity":
            return PowerUpStats(duration: 15, forceMagnitude: 0.5, cooldown: 60.0)
        case "Rubber World":
            return PowerUpStats(duration: 15, forceMagnitude: 1.5, cooldown: 60.0)
        case "Ice World":
            return PowerUpStats(duration: 15, forceMagnitude: 0.01, cooldown: 60.0) // Extremely slippery
        case "Tilt World":
            return PowerUpStats(duration: 15, forceMagnitude: 1.0, cooldown: 60.0)
            
        default:
            return PowerUpStats(duration: nil, forceMagnitude: 1.0, cooldown: 15.0)
        }
    }
    
    func scaled(to level: Int) -> PowerUpStats {
        var stats = self
        
        // Scale cooldown for environmental power-ups
        if stats.duration != nil {
            // Inverse scaling: 60s -> 30s -> 15s
             stats.cooldown = stats.cooldown / pow(2.0, Double(level - 1))
        } else {
             // Normal scaling for other power-ups (cooldown decreases by 2.5s per level)
             stats.cooldown = max(5.0, stats.cooldown - (Double(level - 1) * 2.5))
        }
        
        // Special scaling for Super Massive Ball
        if stats.massMultiplier > 1.0 {  // This identifies Super Massive Ball
            // Scale cooldown: 60s -> 30s -> 15s (divide by 2 for each level)
            stats.cooldown = stats.cooldown / pow(2.0, Double(level - 1))
            
            switch level {
            case 1:
                // Base level stats (already set)
                break
            case 2:
                // Level 2 doubles the effect
                stats.massMultiplier *= 2.0
                stats.forceMagnitude *= 1.75
            case 3:
                // Level 3 massively increases the effect (50% of previous values)
                stats.massMultiplier *= 4.0  // Was 8.0
                stats.forceMagnitude *= 2.0  // Was 4.0
            default:
                break
            }
        } else if duration != nil { // This identifies all environmental power-ups
            // Scale duration: 15s -> 30s -> 60s
            if let baseDuration = stats.duration {
                stats.duration = baseDuration * pow(2.0, Double(level - 1))
            }
            
             if abs(forceMagnitude - 0.01) < 0.001 { // This identifies Ice World
                // Ice World has no level scaling for force - always extremely slippery
                stats.forceMagnitude = 0.01
            } else if abs(forceMagnitude - 0.5) < 0.001 { // This identifies Low Gravity
                // Low Gravity has no level scaling for force - always 0.5
                stats.forceMagnitude = 0.5
            }
            // For other environmental power-ups like Rubber World,
            // we will apply scaling to their forceMagnitude.
            else {
                 let levelMultiplier = Double(level - 1) * 0.25
                 stats.forceMagnitude += levelMultiplier
            }
        } else {
            // Normal scaling for other power-ups
            let levelMultiplier = Double(level - 1) * 0.25
            stats.forceMagnitude += levelMultiplier
            stats.massMultiplier *= (1.0 + levelMultiplier)
        }
        
        return stats
    }
}

struct PowerUp: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: PowerUpCategory
    let type: PowerUpType
    let icon: String // SF Symbol name
    var isUnlocked: Bool
    var level: Int
    var cost: Int
    var slotIndex: Int? // Track where this power-up starts
    
    // Computed properties
    var baseStats: PowerUpStats {
        PowerUpStats.baseStats(for: self)
    }
    
    var currentStats: PowerUpStats {
        baseStats.scaled(to: level)
    }
    
    // Game state
    var isPrimed: Bool = false
    var isActive: Bool = false
    var remainingDuration: TimeInterval = 0 // Only for environmental power-ups
    var remainingCooldown: TimeInterval = 0 // Cooldown timer for environmental power-ups (starts after effect ends)
    var hasBeenOffered: Bool = false
    var slotsOccupied: Int {
        return 1 // Always occupy 1 slot regardless of level
    }
    
    // Charge system
    var currentCharges: Int = 1  // Start with 1 charge
    var isRecharging: Bool = false
    var rechargeTimeRemaining: TimeInterval = 0
    var rechargeDuration: TimeInterval {
        return currentStats.cooldown
    }
    
    var canBeUsed: Bool {
        // For environmental power-ups, also check cooldown
        if type == .environment {
            return currentCharges > 0 && !isRecharging && remainingCooldown <= 0 && !isActive
        }
        return currentCharges > 0 && !isRecharging
    }
    
    var isOnCooldown: Bool {
        return type == .environment && remainingCooldown > 0
    }
    
    // Upgrade costs
    var upgradeCost: Int {
        switch level {
        case 1: return cost * 2 // Cost to upgrade to level 2
        case 2: return cost * 4 // Cost to upgrade to level 3
        default: return Int.max // No upgrade available
        }
    }
    
    static let maxLevel = 3
    
    // Charge system methods
    mutating func useCharge() -> Bool {
        if currentCharges > 0 {
            currentCharges -= 1
            
            // For environmental power-ups, don't start recharge - cooldown handles timing
            // Recharge will be handled separately if needed
            if currentCharges == 0 && type != .environment {
                startRecharge()
            }
            return true
        }
        return false
    }
    
    mutating func startRecharge() {
        isRecharging = true
        rechargeTimeRemaining = rechargeDuration
    }
    
    mutating func updateRecharge(deltaTime: TimeInterval) {
        if isRecharging {
            rechargeTimeRemaining -= deltaTime
            if rechargeTimeRemaining <= 0 {
                completeRecharge()
            }
        }
    }
    
    mutating func completeRecharge() {
        currentCharges = 1
        isRecharging = false
        rechargeTimeRemaining = 0
    }
}

class PowerUpManager: ObservableObject {
    // MARK: - Singleton
    static let shared = PowerUpManager()
    
    // Default power-up definitions (used to reset state)
    private static let defaultPowerUps: [PowerUp] = [
        // SINGLE-USE POWER-UPS (affect next spawned ball)
        PowerUp(
            name: "Super Massive Ball",
            description: "Makes selected ball super dense, applies strong downward impulse on release",
            category: .gravity,
            type: .singleUse,
            icon: "circle.circle.fill",
            isUnlocked: true, // Unlocked by default
            level: 1,
            cost: 15
        ),
        
        // ENVIRONMENTAL POWER-UPS (affect entire play area)
        PowerUp(
            name: "Low Gravity",
            description: "Modifies physics world gravity, affects all balls in play area",
            category: .gravity,
            type: .environment,
            icon: "arrow.down.circle",
            isUnlocked: false,
            level: 1,
            cost: 15
        ),
        PowerUp(
            name: "Ice World",
            description: "Makes all surfaces ultra slippery with minimal friction",
            category: .physics,
            type: .environment,
            icon: "snowflake",
            isUnlocked: false,
            level: 1,
            cost: 30
        ),
        PowerUp(
            name: "Tilt World",
            description: "Use your device's motion to control gravity's direction.",
            category: .physics,
            type: .environment,
            icon: "move.3d",
            isUnlocked: false,
            level: 1,
            cost: 45
        ),
    ]
    
    @Published var powerUps: [PowerUp] = PowerUpManager.defaultPowerUps
    
    // Game currency and progression
    @Published var currency: Int = 0
    
    // Track which power-ups have been offered in this run
    private var offeredPowerUps = Set<UUID>()

    private init() {
        #if DEBUG
        print("[PowerUpManager] INIT v2 - Singleton being initialized")
        #endif
        // Load progression on init
        reloadFromCoreData()
    }
    
    // MARK: - Core Data Synchronization
    
    /// Reloads all powerup and currency data from Core Data.
    /// Call this whenever you need to ensure the in-memory state matches persisted state.
    func reloadFromCoreData() {
        #if DEBUG
        print("[PowerUpManager] reloadFromCoreData() called")
        print("  - Before reload, in-memory unlocked: \(powerUps.filter { $0.isUnlocked }.map { $0.name })")
        #endif
        
        // Refresh the Core Data context to ensure we have the latest data
        CoreDataManager.shared.refreshContext()
        
        let gameData = CoreDataManager.shared.getGameData()
        
        // Update currency
        self.currency = Int(gameData.currency)
        
        let progressions = gameData.powerUpProgressions as? Set<PowerUpProgression> ?? []
        
        #if DEBUG
        print("  - Core Data has \(progressions.count) progressions")
        for prog in progressions {
            print("    - \(prog.id ?? "nil"): isUnlocked=\(prog.isUnlocked), level=\(prog.level)")
        }
        #endif
        
        // If there are no progressions stored, create them for current powerups
        if progressions.isEmpty {
            #if DEBUG
            print("[PowerUpManager] No progressions found, creating initial ones...")
            #endif
            for i in powerUps.indices {
                let progression = PowerUpProgression(context: CoreDataManager.shared.context)
                progression.id = powerUps[i].name
                progression.isUnlocked = powerUps[i].isUnlocked // Use default value
                progression.level = Int64(powerUps[i].level)
                gameData.addToPowerUpProgressions(progression)
            }
            CoreDataManager.shared.saveContext()
            #if DEBUG
            print("[PowerUpManager] Created initial progressions for \(powerUps.count) powerups")
            #endif
        } else {
            // Update in-memory power-ups with saved progression
            for progression in progressions {
                // Unwrap the optional id to ensure we have a valid name
                guard let progressionId = progression.id, !progressionId.isEmpty else {
                    #if DEBUG
                    print("[PowerUpManager] WARNING: progression has nil or empty id!")
                    #endif
                    continue
                }
                
                if let index = powerUps.firstIndex(where: { $0.name == progressionId }) {
                    let wasUnlocked = powerUps[index].isUnlocked
                    powerUps[index].isUnlocked = progression.isUnlocked
                    powerUps[index].level = Int(progression.level)
                    #if DEBUG
                    print("[PowerUpManager] Synced '\(progressionId)': wasUnlocked=\(wasUnlocked) -> isUnlocked=\(progression.isUnlocked)")
                    #endif
                } else {
                    #if DEBUG
                    print("[PowerUpManager] WARNING: progression '\(progressionId)' not found in powerUps array!")
                    print("  - Available powerups: \(powerUps.map { $0.name })")
                    #endif
                }
            }
            
            // Check for any new power-ups not in progression and add them
            for i in powerUps.indices {
                if !progressions.contains(where: { $0.id == powerUps[i].name }) {
                    let progression = PowerUpProgression(context: CoreDataManager.shared.context)
                    progression.id = powerUps[i].name
                    progression.isUnlocked = powerUps[i].isUnlocked // Use default value
                    progression.level = Int64(powerUps[i].level)
                    gameData.addToPowerUpProgressions(progression)
                    #if DEBUG
                    print("[PowerUpManager] Added missing powerup to progressions: \(powerUps[i].name)")
                    #endif
                }
            }
            if gameData.hasChanges {
                CoreDataManager.shared.saveContext()
            }
        }
        
        #if DEBUG
        let unlockedNames = powerUps.filter { $0.isUnlocked }.map { $0.name }
        print("[PowerUpManager] reloadFromCoreData complete:")
        print("  - currency: \(currency)")
        print("  - unlocked powerups: \(unlockedNames)")
        #endif
    }

    func getUnlockedFlaskSizes() -> Set<FlaskSize> {
        // Always get fresh data from Core Data
        let gameData = CoreDataManager.shared.getGameData()
        guard let rawSizes = gameData.unlockedFlaskSizes, !rawSizes.isEmpty else { return [.small] }
        let sizeStrings = rawSizes.split(separator: ",").map(String.init)
        return Set(sizeStrings.compactMap(FlaskSize.init))
    }
    
    // Reset offered power-ups (call this when starting a new run)
    func resetOfferedPowerUps() {
        offeredPowerUps.removeAll()
        for i in powerUps.indices {
            powerUps[i].hasBeenOffered = false
        }
    }
    
    // Mark a power-up as offered
    func markAsOffered(_ powerUp: PowerUp) {
        offeredPowerUps.insert(powerUp.id)
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].hasBeenOffered = true
        }
    }
    
    // Get available power-ups that haven't been offered yet
    func getAvailablePowerUps() -> [PowerUp] {
        return powerUps.filter { !offeredPowerUps.contains($0.id) }
    }
    
    /// Returns a list of all currently unlocked power-ups (fresh from in-memory state after reloadFromCoreData)
    func getUnlockedPowerUps() -> [PowerUp] {
        return powerUps.filter { $0.isUnlocked }
    }
    
    // MARK: - Power-up Management
    
    func unlock(_ powerUp: PowerUp) -> Bool {
        #if DEBUG
        print("[PowerUpManager] unlock() called for: \(powerUp.name)")
        print("  - powerUp.isUnlocked: \(powerUp.isUnlocked)")
        print("  - currency: \(currency), cost: \(powerUp.cost)")
        #endif
        
        let gameData = CoreDataManager.shared.getGameData()
        
        guard !powerUp.isUnlocked && currency >= powerUp.cost else {
            #if DEBUG
            print("[PowerUpManager] unlock() guard failed - already unlocked: \(powerUp.isUnlocked), can afford: \(currency >= powerUp.cost)")
            #endif
            return false
        }
        
        currency -= powerUp.cost
        gameData.currency = Int64(currency)

        if let index = powerUps.firstIndex(where: { $0.name == powerUp.name }) {
            // Create a mutable copy, modify it, and reassign to trigger @Published
            var updatedPowerUp = powerUps[index]
            updatedPowerUp.isUnlocked = true
            powerUps[index] = updatedPowerUp
            
            // Also manually trigger the publisher to ensure SwiftUI updates
            objectWillChange.send()
            
            #if DEBUG
            print("[PowerUpManager] Updated in-memory powerUps[\(index)].isUnlocked = true")
            print("[PowerUpManager] Triggered objectWillChange.send()")
            #endif
            
            // Also update the Core Data progression
            let progressions = gameData.powerUpProgressions as? Set<PowerUpProgression> ?? []
            #if DEBUG
            print("[PowerUpManager] Found \(progressions.count) progressions in Core Data")
            #endif
            
            if let progression = progressions.first(where: { $0.id == powerUp.name }) {
                progression.isUnlocked = true
                #if DEBUG
                print("[PowerUpManager] Updated Core Data progression for \(powerUp.name): isUnlocked = \(progression.isUnlocked)")
                #endif
            } else {
                #if DEBUG
                print("[PowerUpManager] ERROR: Could not find progression for \(powerUp.name) in Core Data!")
                print("  Available progressions: \(progressions.map { $0.id ?? "nil" })")
                #endif
                // Create the missing progression
                let newProgression = PowerUpProgression(context: CoreDataManager.shared.context)
                newProgression.id = powerUp.name
                newProgression.isUnlocked = true
                newProgression.level = Int64(powerUp.level)
                gameData.addToPowerUpProgressions(newProgression)
                #if DEBUG
                print("[PowerUpManager] Created missing progression for \(powerUp.name)")
                #endif
            }
        } else {
            #if DEBUG
            print("[PowerUpManager] ERROR: Could not find powerup \(powerUp.name) in powerUps array!")
            #endif
        }
        
        CoreDataManager.shared.saveContext()
        
        #if DEBUG
        // Verify the save worked
        let verifyGameData = CoreDataManager.shared.getGameData()
        let verifyProgressions = verifyGameData.powerUpProgressions as? Set<PowerUpProgression> ?? []
        if let verifyProg = verifyProgressions.first(where: { $0.id == powerUp.name }) {
            print("[PowerUpManager] Verification: \(powerUp.name) isUnlocked = \(verifyProg.isUnlocked)")
        }
        #endif
        
        return true
    }
    
    func unlockFlaskSize(_ size: FlaskSize) -> Bool {
        let gameData = CoreDataManager.shared.getGameData()
        guard !getUnlockedFlaskSizes().contains(size) && currency >= size.cost else { return false }
        
        currency -= size.cost
        gameData.currency = Int64(currency)
        
        var currentSizes = getUnlockedFlaskSizes()
        currentSizes.insert(size)
        gameData.unlockedFlaskSizes = currentSizes.map { $0.rawValue }.joined(separator: ",")
        
        CoreDataManager.shared.saveContext()
        #if DEBUG
        print("[PowerUpManager] Unlocked flask size: \(size.rawValue)")
        #endif
        return true
    }
    
    func upgrade(_ powerUp: PowerUp) -> Bool {
        let gameData = CoreDataManager.shared.getGameData()
        guard powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && currency >= powerUp.upgradeCost else { return false }
        
        currency -= powerUp.upgradeCost
        gameData.currency = Int64(currency)

        if let index = powerUps.firstIndex(where: { $0.name == powerUp.name }) {
            powerUps[index].level += 1
            if let progression = (gameData.powerUpProgressions as? Set<PowerUpProgression>)?.first(where: { $0.id == powerUp.name }) {
                progression.level = Int64(powerUps[index].level)
                #if DEBUG
                print("[PowerUpManager] Upgraded powerup: \(powerUp.name) to level \(powerUps[index].level)")
                #endif
            }
        }
        CoreDataManager.shared.saveContext()
        return true
    }
    
    func activate(_ powerUp: PowerUp) -> Bool {
        guard powerUp.isUnlocked else { return false }
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].isActive = true
            return true
        }
        return false
    }
    
    /// Adds currency and persists to Core Data
    func addCurrency(_ amount: Int) {
        let gameData = CoreDataManager.shared.getGameData()
        currency += amount
        gameData.currency = Int64(currency)
        CoreDataManager.shared.saveContext()
        #if DEBUG
        print("[PowerUpManager] Added \(amount) currency, new total: \(currency)")
        #endif
    }
}

class GameViewModel: ObservableObject {
    @Published var equippedPowerUps: [PowerUp] = []
    @Published var score: Int = 0
    @Published var highScore: Int = 0
    @Published var isGamePaused: Bool = false
    @Published var selectedFlaskSize: FlaskSize = .small
    @Published var fps: Int = 0
    @Published var nodeCount: Int = 0

    let powerUpManager: PowerUpManager
    private var run: Run?
    var sphereStateProvider: (() -> [Sphere])?
    private var powerUpTimer: Timer?
    
    #if DEBUG
    @Published var debug_spawnBallTier: Int? = nil
    @Published var debug_spawnBallTierSelection: Int = 1 {
        didSet {
            if debug_spawnBallTierSelection < 1 {
                debug_spawnBallTierSelection = 1
            } else if debug_spawnBallTierSelection > GameScene.tierData.count {
                debug_spawnBallTierSelection = GameScene.tierData.count
            }
        }
    }
    #endif
    
    init(powerUpManager: PowerUpManager, gameData: GameData) {
        self.powerUpManager = powerUpManager
        self.run = gameData.currentRun
        self.highScore = Int(gameData.highScore)
        
        // DON'T reload from Core Data here! The PowerUpManager singleton already has
        // the correct in-memory state (updated when user unlocked powerups in shop).
        // Reloading here can cause stale Core Data to overwrite correct in-memory state.
        
        // Initialize with all unlocked power-ups from the manager's IN-MEMORY state
        self.equippedPowerUps = powerUpManager.getUnlockedPowerUps()
        
        #if DEBUG
        let unlockedNames = equippedPowerUps.map { $0.name }
        print("[GameViewModel] init: Loaded \(equippedPowerUps.count) unlocked powerups: \(unlockedNames)")
        #endif
        
        if let run = self.run {
            self.applyRunState(run)
        }
        
        // After applying run state, ensure all unlocked powerups are in the equipped list
        refreshEquippedPowerUps()
        
        startPowerUpTimer()
    }
    
    private func refreshEquippedPowerUps() {
        // DON'T reload from Core Data here - trust the singleton's in-memory state
        // The PowerUpManager singleton is the source of truth and was updated when 
        // powerups were unlocked in the shop. Reloading here can cause stale data issues.
        
        // Get all currently unlocked powerups from the manager's IN-MEMORY state
        let allUnlocked = powerUpManager.getUnlockedPowerUps()
        
        #if DEBUG
        print("[GameViewModel] refreshEquippedPowerUps: Manager has \(allUnlocked.count) unlocked powerups: \(allUnlocked.map { $0.name })")
        print("[GameViewModel] refreshEquippedPowerUps: Current equippedPowerUps has \(equippedPowerUps.count): \(equippedPowerUps.map { $0.name })")
        #endif
        
        // If no powerups are unlocked, clear equippedPowerUps and return
        guard !allUnlocked.isEmpty else {
            equippedPowerUps = []
            return
        }
        
        // Create a map of current equipped powerups by name to preserve their runtime state
        var equippedMap: [String: PowerUp] = [:]
        for powerUp in equippedPowerUps {
            equippedMap[powerUp.name] = powerUp
        }
        
        // Build new equipped list with all unlocked powerups, preserving runtime state from equippedMap
        var newEquipped: [PowerUp] = []
        for unlockedPowerUp in allUnlocked {
            if let existing = equippedMap[unlockedPowerUp.name] {
                // Preserve existing runtime state (active, primed, timers, charges)
                // but use unlock status and level from the manager (source of truth)
                var updated = existing
                updated.isUnlocked = true // Always true since it's in allUnlocked
                updated.level = unlockedPowerUp.level
                newEquipped.append(updated)
            } else {
                // Newly unlocked powerup not yet in equipped list, add it
                #if DEBUG
                print("[GameViewModel] refreshEquippedPowerUps: Adding newly unlocked powerup: \(unlockedPowerUp.name)")
                #endif
                newEquipped.append(unlockedPowerUp)
            }
        }
        
        equippedPowerUps = newEquipped
        
        #if DEBUG
        print("[GameViewModel] refreshEquippedPowerUps complete: equippedPowerUps now has \(equippedPowerUps.count) powerups")
        #endif
    }
    
    deinit {
        powerUpTimer?.invalidate()
    }
    
    private func startPowerUpTimer() {
        powerUpTimer?.invalidate()
        powerUpTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePowerUpTimers()
        }
    }
    
    private func updatePowerUpTimers() {
        guard !isGamePaused else { return }
        
        let deltaTime: TimeInterval = 0.1
        
        for i in equippedPowerUps.indices {
            var powerUp = equippedPowerUps[i]
            
            // Update cooldown timer
            if powerUp.isRecharging {
                powerUp.updateRecharge(deltaTime: deltaTime)
                equippedPowerUps[i] = powerUp
            }
            
            // Update duration for active environmental power-ups
            if powerUp.type == .environment && powerUp.isActive {
                if powerUp.remainingDuration > 0 {
                    powerUp.remainingDuration = max(0, powerUp.remainingDuration - deltaTime)
                    
                    // Deactivate if duration is up and start cooldown
                    if powerUp.remainingDuration == 0 {
                        powerUp.isActive = false
                        powerUp.isPrimed = false
                        // Start cooldown timer after effect ends
                        powerUp.remainingCooldown = powerUp.currentStats.cooldown
                        #if DEBUG
                        print("\(powerUp.name) deactivated due to duration end! Starting cooldown: \(powerUp.remainingCooldown)s")
                        #endif
                    }
                    equippedPowerUps[i] = powerUp
                }
            }
            
            // Update cooldown timer for environmental power-ups (only when not active)
            if powerUp.type == .environment && !powerUp.isActive && powerUp.remainingCooldown > 0 {
                powerUp.remainingCooldown = max(0, powerUp.remainingCooldown - deltaTime)
                
                // When cooldown ends, restore the charge so it can be used again
                if powerUp.remainingCooldown == 0 && powerUp.currentCharges == 0 {
                    powerUp.currentCharges = 1
                    #if DEBUG
                    print("\(powerUp.name) cooldown ended, charge restored!")
                    #endif
                }
                
                equippedPowerUps[i] = powerUp
            }
        }
    }
    
    private func applyRunState(_ run: Run) {
        // Restore run state
        self.score = Int(run.score)
        self.selectedFlaskSize = FlaskSize(rawValue: run.selectedFlaskSize ?? "small") ?? .small
        
        // Restore equipped power-ups
        if let equipped = run.equippedPowerUps as? Set<EquippedPowerUp>, !equipped.isEmpty {
            #if DEBUG
            print("GameViewModel: Restoring \(equipped.count) saved powerups from run")
            #endif
            for savedPowerUp in equipped {
                if let index = equippedPowerUps.firstIndex(where: { $0.name == savedPowerUp.id }) {
                    var instance = equippedPowerUps[index]
                    // Restore runtime state (active, primed, timers, charges)
                    instance.isActive = savedPowerUp.isActive
                    instance.isPrimed = savedPowerUp.isPrimed
                    instance.remainingDuration = savedPowerUp.remainingDuration
                    instance.remainingCooldown = savedPowerUp.remainingCooldown
                    instance.currentCharges = Int(savedPowerUp.currentCharges)
                    instance.isRecharging = savedPowerUp.isRecharging
                    // DO NOT restore level from saved run - always use current progression level
                    // The level in instance is already correct from powerUpManager.powerUps
                    // Merges until recharge is deprecated, but we can initialize rechargeTimeRemaining if needed
                    // For now, if it was recharging, just restart the timer to full duration or 0 if unknown
                    if instance.isRecharging {
                        instance.rechargeTimeRemaining = instance.rechargeDuration
                    }
                    
                    equippedPowerUps[index] = instance
                    
                    // If this is an active environmental power-up, make sure the timer is running
                    if instance.type == .environment && instance.isActive && instance.remainingDuration > 0 {
                        #if DEBUG
                        print("Restored active environmental power-up: \(instance.name) with \(instance.remainingDuration)s remaining")
                        #endif
                    }
                    
                    // Log recharge state if recharging
                    #if DEBUG
                    if instance.isRecharging {
                        print("Restored recharging power-up: \(instance.name)")
                    }
                    #endif
                } else {
                    #if DEBUG
                    print("GameViewModel: Warning - saved powerup '\(savedPowerUp.id ?? "unknown")' not found in equippedPowerUps")
                    #endif
                }
            }
        } else {
            #if DEBUG
            print("GameViewModel: No saved powerups in run (new run or empty), will use initialized powerups")
            #endif
        }

        #if DEBUG
        print("GameViewModel: Restored from Core Data Run object. equippedPowerUps count: \(equippedPowerUps.count)")
        #endif
    }
    
    
    func activatePowerUp(_ powerUpToActivate: PowerUp) {
        // Find the power-up in equipped slots by name (since UUID is generated fresh each time)
        guard let index = equippedPowerUps.firstIndex(where: { $0.name == powerUpToActivate.name }) else { return }
        var powerUp = equippedPowerUps[index]
        
        #if DEBUG
        print("Activating power-up: \(powerUp.name), type: \(powerUp.type), current state - isPrimed: \(powerUp.isPrimed), isActive: \(powerUp.isActive)")
        #endif
        
        // Handle targeting power-ups differently
        if powerUp.type == .targeting {
            // If it's already primed, tapping it again de-primes it.
            if powerUp.isPrimed {
                powerUp.isPrimed = false
                #if DEBUG
                print("\(powerUp.name) de-primed.")
                #endif
            }
            // If it's not primed, try to prime it.
            else {
                // You can only prime a power-up if it has charges.
                guard powerUp.canBeUsed else {
                    #if DEBUG
                    print("Cannot prime \(powerUp.name): no charges available.")
                    #endif
                    return
                }

                // Deprime any other targeting power-ups
                for i in equippedPowerUps.indices {
                    if equippedPowerUps[i].id != powerUp.id &&
                       equippedPowerUps[i].type == .targeting &&
                       equippedPowerUps[i].isPrimed {
                        equippedPowerUps[i].isPrimed = false
                        #if DEBUG
                        print("\(equippedPowerUps[i].name) deprimed due to new targeting activation!")
                        #endif
                    }
                }
                
                powerUp.isPrimed = true
                #if DEBUG
                print("\(powerUp.name) primed!")
                #endif
            }
        }
        // Handle environmental power-ups
        else if powerUp.type == .environment {
            // If already active, do nothing (can only be deactivated by timer)
            if powerUp.isActive {
                return
            }

            // Check if power-up can be used (charges, cooldown, etc.)
            guard powerUp.canBeUsed else {
                #if DEBUG
                if powerUp.remainingCooldown > 0 {
                    print("Cannot activate \(powerUp.name): on cooldown for \(powerUp.remainingCooldown)s")
                } else {
                    print("Cannot activate \(powerUp.name): no charges available.")
                }
                #endif
                return
            }

            // Deactivate any other active environmental power-ups
            for i in equippedPowerUps.indices {
                if equippedPowerUps[i].id != powerUp.id &&
                   equippedPowerUps[i].type == .environment &&
                   equippedPowerUps[i].isActive {
                    equippedPowerUps[i].isActive = false
                    equippedPowerUps[i].isPrimed = false // also reset primed state just in case
                    
                    #if DEBUG
                    print("\(equippedPowerUps[i].name) deactivated due to new environmental activation!")
                    #endif
                }
            }

            // Activate the selected power-up (cooldown will start after effect ends)
            if powerUp.useCharge() {
                powerUp.isActive = true
                powerUp.isPrimed = false // No more priming
                powerUp.remainingDuration = powerUp.currentStats.duration ?? 0
                powerUp.remainingCooldown = 0 // Reset cooldown when activating (it will start after effect ends)
                // Ensure recharge is not active for environmental power-ups (cooldown handles timing)
                powerUp.isRecharging = false
                powerUp.rechargeTimeRemaining = 0
                #if DEBUG
                print("\(powerUp.name) activated with duration: \(powerUp.remainingDuration)s!")
                #endif
            }
        }
        // Handle single-use power-ups
        else {
            // Check if power-up can be used
            guard powerUp.canBeUsed else {
                #if DEBUG
                print("Cannot activate \(powerUp.name): no charges available or recharging")
                #endif
                return
            }
            
            // Deactivate any other active single-use power-ups
            for i in equippedPowerUps.indices {
                if equippedPowerUps[i].id != powerUp.id &&
                   equippedPowerUps[i].type == .singleUse &&
                   equippedPowerUps[i].isActive {
                    equippedPowerUps[i].isActive = false
                    #if DEBUG
                    print("\(equippedPowerUps[i].name) deactivated due to new activation!")
                    #endif
                }
            }
            
            // Just activate the power-up, charge will be consumed when used
            powerUp.isActive = true
            #if DEBUG
            print("\(powerUp.name) activated! Will consume charge when used.")
            #endif
        }
        
        // Update the slot
        equippedPowerUps[index] = powerUp
    }
    
    // Call this when a single-use power-up's effect is actually applied
    func consumeSingleUsePowerUp(_ powerUpName: String) {
        for i in equippedPowerUps.indices {
            var powerUp = equippedPowerUps[i]
            if powerUp.name == powerUpName,
               powerUp.type == .singleUse,
               powerUp.isActive {
                if powerUp.useCharge() {
                    powerUp.isActive = false
                    equippedPowerUps[i] = powerUp
                    #if DEBUG
                    print("\(powerUp.name) used and deactivated!")
                    #endif
                }
            }
        }
    }
    
    private func deactivateSingleUsePowerUp(_ powerUp: PowerUp) {
        // Find and deactivate the power-up
        for i in equippedPowerUps.indices {
            var slotPowerUp = equippedPowerUps[i]
            if slotPowerUp.id == powerUp.id {
                slotPowerUp.isActive = false
                equippedPowerUps[i] = slotPowerUp
                
                #if DEBUG
                print("\(powerUp.name) auto-deactivated after use!")
                #endif
            }
        }
    }
    
    
    // MARK: - Saving
    func saveGameState() {
        guard let run = self.run else { return }

        // Update run stats
        run.score = Int64(score)
        run.selectedFlaskSize = selectedFlaskSize.rawValue

        // Update high score in GameData
        if let gameData = run.gameData {
            if score > gameData.highScore {
                gameData.highScore = Int64(score)
                self.highScore = score
            }
        }

        // Update sphere states
        if let provider = sphereStateProvider {
            let currentSphereStates = provider()
            // Clear old spheres
            if let existingSpheres = run.spheres {
                run.removeFromSpheres(existingSpheres)
            }
            // Add new spheres
            run.addToSpheres(NSSet(array: currentSphereStates))
        }
        
        // Update equipped powerups
        if let existingEquipped = run.equippedPowerUps {
            run.removeFromEquippedPowerUps(existingEquipped)
        }
        
        let context = CoreDataManager.shared.context
        var equippedToSave: [EquippedPowerUp] = []
        
        for (index, powerUp) in equippedPowerUps.enumerated() {
            let equipped = EquippedPowerUp(context: context)
            equipped.id = powerUp.name
            equipped.level = Int64(powerUp.level)
            equipped.slotIndex = Int64(index)
            equipped.isActive = powerUp.isActive
            equipped.isPrimed = powerUp.isPrimed
            equipped.remainingDuration = powerUp.remainingDuration
            equipped.remainingCooldown = powerUp.remainingCooldown
            equipped.type = powerUp.type.rawValue
            equipped.currentCharges = Int64(powerUp.currentCharges)
            equipped.isRecharging = powerUp.isRecharging
            equipped.mergesUntilRecharge = Int64(powerUp.rechargeTimeRemaining)
            equippedToSave.append(equipped)
        }
        run.addToEquippedPowerUps(NSSet(array: equippedToSave))

        CoreDataManager.shared.saveContext()
        #if DEBUG
        print("[CoreData] Game state saved.")
        #endif
    }
    
    func endRun() {
        // Calculate and award currency before deleting the run
        let coinsEarned = Int(ceil(Double(score) / 10.0))
        
        // Use the proper method to add currency and persist
        powerUpManager.addCurrency(coinsEarned)
        
        if let run = self.run {
             CoreDataManager.shared.context.delete(run)
             CoreDataManager.shared.saveContext()
        }
        
        self.run = nil
        
        #if DEBUG
        print("[GameViewModel] endRun: Awarded \(coinsEarned) coins")
        #endif
    }
    
    func earnScore(points: Int = 1) {
        score += points

        if score > highScore {
            highScore = score
        }
        
        #if DEBUG
        print("EarnScore: score=\(score)")
        #endif
    }
    
    func getSphereStates() -> [Sphere]? {
        guard let spheres = run?.spheres as? Set<Sphere>, !spheres.isEmpty else { return nil }
        #if DEBUG
        print("GameViewModel: getSphereStates called, has \(spheres.count) states")
        #endif
        return Array(spheres)
    }
    
    func saveSphereStates(_ states: [Sphere]) {
        #if DEBUG
        print("GameViewModel: Saving \(states.count) sphere states")
        #endif
        guard let run = run else { return }
        if let existing = run.spheres {
            run.removeFromSpheres(existing)
        }
        run.addToSpheres(NSSet(array: states))
        saveGameState()
    }
    
    func reset() {
        score = 0
        
        // Use the manager's IN-MEMORY state - don't reload from Core Data
        // The singleton already has correct state from shop interactions
        equippedPowerUps = powerUpManager.getUnlockedPowerUps()
        
        if let run = self.run {
             CoreDataManager.shared.context.delete(run)
             CoreDataManager.shared.saveContext()
        }
        self.run = nil
        selectedFlaskSize = .small
        powerUpManager.resetOfferedPowerUps() // Reset offered power-ups when starting new game
        
        #if DEBUG
        print("[GameViewModel] reset: Loaded \(equippedPowerUps.count) unlocked powerups: \(equippedPowerUps.map { $0.name })")
        #endif
    }

    #if DEBUG
    func debug_spawnBall() {
        debug_spawnBallTier = debug_spawnBallTierSelection
    }
    #endif
}

struct ContentView: View {
    @State private var currentScreen: GameScreen = .mainMenu
    @State private var gameData: GameData? = nil
    // Use ObservedObject for singleton since we don't own its lifecycle
    @ObservedObject private var powerUpManager = PowerUpManager.shared
    
    enum GameScreen {
        case mainMenu
        case game
        case upgradeShop
        case settings
        case runSetup
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentScreen {
                case .mainMenu:
                    MainMenuView(currentScreen: $currentScreen, onNewGame: {
                        gameData = CoreDataManager.shared.getGameData()
                        // If a run exists, it will be cleared in RunSetupView/createNewRun
                    }, onContinue: {
                        gameData = CoreDataManager.shared.getGameData()
                    })
                case .game:
                    // Ensure we have gameData before starting a game
                    if let gameData = gameData {
                         GameView(currentScreen: $currentScreen, gameData: gameData)
                    } else {
                        // Fallback to main menu if gameData is nil
                        MainMenuView(currentScreen: $currentScreen, onNewGame: {}, onContinue: {})
                    }
                case .upgradeShop:
                    UpgradeShopView(currentScreen: $currentScreen)
                case .settings:
                    SettingsView(currentScreen: $currentScreen)
                case .runSetup:
                    RunSetupView(currentScreen: $currentScreen, onGameStart: { newRun in
                        // The run is already part of gameData, just need to trigger the view update
                         gameData = CoreDataManager.shared.getGameData()
                    })
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .environmentObject(powerUpManager)
        .preferredColorScheme(.dark)
    }
}

struct MainMenuView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @State private var hasSave: Bool = CoreDataManager.shared.hasActiveRun()
    @State private var highScore: Int = 0
    @EnvironmentObject var powerUpManager: PowerUpManager
    var onNewGame: (() -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image("alkhemlogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .padding(.bottom, 30)
            
            VStack(spacing: 15) {
                Button("New Game") {
                    onNewGame?()
                    currentScreen = .runSetup
                }
                .frame(width: 200)
                .buttonStyle(.bordered)
                .tint(.white)
                
                Button("Continue") {
                    onContinue?()
                    currentScreen = .game
                }
                .frame(width: 200)
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(!hasSave)
                
                Button("Upgrade Shop") {
                    currentScreen = .upgradeShop
                }
                .frame(width: 200)
                .buttonStyle(.bordered)
                .tint(.white)
                
                Button("Settings") {
                    currentScreen = .settings
                }
                .frame(width: 200)
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 10) {
                if highScore > 0 {
                    Text("High Score: \(highScore)")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                
                Text("Coins: \(powerUpManager.currency)")
                    .font(.title2)
                    .foregroundColor(.yellow)
            }
            .padding(.bottom, 30)
        }
        .onAppear {
            hasSave = CoreDataManager.shared.hasActiveRun()
            highScore = Int(CoreDataManager.shared.getGameData().highScore)
            // Reload powerup data from Core Data to ensure we have the latest state
            powerUpManager.reloadFromCoreData()
        }
    }
}

struct RunSetupView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @EnvironmentObject var powerUpManager: PowerUpManager
    @State private var selectedFlaskSize: FlaskSize = .small
    let onGameStart: (Run) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: {
                    currentScreen = .mainMenu
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .padding()
                Spacer()
            }
            
            Text("Run Setup")
                .font(.title)
                .padding(.bottom)
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Flask Size")
                    .font(.headline)
                
                ForEach(FlaskSize.allCases, id: \.self) { size in
                    FlaskSizeOption(
                        flaskSize: size,
                        isSelected: selectedFlaskSize == size,
                        isUnlocked: size == .small || powerUpManager.getUnlockedFlaskSizes().contains(size),
                        onSelect: {
                            selectedFlaskSize = size
                        }
                    )
                }
            }
            .padding()
            
            Spacer()
            
            Button("Start Game") {
                // Create a new run in Core Data
                let newRun = CoreDataManager.shared.createNewRun(selectedFlask: selectedFlaskSize)
                onGameStart(newRun)
                currentScreen = .game
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .onAppear {
            // Reload to ensure we have the latest flask unlock state
            powerUpManager.reloadFromCoreData()
        }
    }
}

struct FlaskSizeOption: View {
    let flaskSize: FlaskSize
    let isSelected: Bool
    let isUnlocked: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            if isUnlocked {
                onSelect()
            }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(flaskSize.displayName)
                        .font(.headline)
                    Text(flaskSize.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if !isUnlocked {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("\(flaskSize.cost)")
                    }
                    .foregroundColor(.gray)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: isSelected ? 0.2 : 0.15))
            )
        }
        .buttonStyle(.plain)
        .opacity(isUnlocked ? 1 : 0.6)
    }
}

struct GameView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @EnvironmentObject var powerUpManager: PowerUpManager
    @StateObject private var viewModel: GameViewModel
    @State private var isPaused: Bool = false
    @State private var isGameOver: Bool = false
    // Add auto-save timer
    private let autoSaveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    init(currentScreen: Binding<ContentView.GameScreen>, gameData: GameData) {
        self._currentScreen = currentScreen
        // Use the shared PowerUpManager singleton
        let manager = PowerUpManager.shared
        self._viewModel = StateObject(wrappedValue: GameViewModel(powerUpManager: manager, gameData: gameData))
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                HStack {
                    // Score in glass chip
                    HStack(spacing: 6) {
                        Text("Score:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(viewModel.score)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.15),
                                                .white.opacity(0.05),
                                                .clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.4),
                                                .white.opacity(0.1),
                                                .white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    
                    Spacer()
                    
                    // Pause button in glass style
                    Button(action: {
                        isPaused = true
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        .white.opacity(0.15),
                                                        .white.opacity(0.05),
                                                        .clear
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        .white.opacity(0.4),
                                                        .white.opacity(0.1),
                                                        .white.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                }
                .frame(width: 375)
                .padding(.horizontal)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 375, height: 650)
                    
                    #if os(iOS)
                    SpriteKitContainer(viewModel: viewModel, isGameOver: $isGameOver)
                        .frame(width: 375, height: 650)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    #else
                    Text("SpriteKit not supported on this platform")
                        .frame(width: 375, height: 650)
                    #endif
                }
                
                PowerUpSlotView(
                    powerUpManager: powerUpManager,
                    equippedPowerUps: $viewModel.equippedPowerUps,
                    onActivate: viewModel.activatePowerUp
                )
            }
            .padding(.top, 20)
            
            if isPaused {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                PauseMenuView(
                    viewModel: viewModel,
                    isPaused: $isPaused,
                    currentScreen: $currentScreen,
                    onMainMenu: {
                        viewModel.saveGameState()
                    }
                )
            }
            
            if isGameOver {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                let coinsEarned = Int(ceil(Double(viewModel.score) / 10.0))
                GameOverView(
                    score: viewModel.score,
                    highScore: viewModel.highScore,
                    coinsEarned: coinsEarned,
                    onMainMenu: {
                        viewModel.endRun()
                        currentScreen = .mainMenu
                    }
                )
            }
        }
        .onChange(of: isPaused) { _, newValue in
            viewModel.isGamePaused = newValue
            if newValue {
                viewModel.saveGameState()
            }
        }
        .onChange(of: isGameOver) { _, newValue in
            if newValue {
                viewModel.saveGameState()
            }
        }
        // Add auto-save timer subscription
        .onReceive(autoSaveTimer) { _ in
            if !isPaused && !isGameOver {
                #if DEBUG
                print("[AutoSave] Saving game state...")
                #endif
                viewModel.saveGameState()
            }
        }
        // Cancel timer when view disappears
        .onDisappear {
            autoSaveTimer.upstream.connect().cancel()
        }
    }
}

struct PowerUpSlotView: View {
    let powerUpManager: PowerUpManager
    @Binding var equippedPowerUps: [PowerUp]
    let onActivate: (PowerUp) -> Void
    let slotHeight: CGFloat = 50
    let spacing: CGFloat = 12
    let horizontalPadding: CGFloat = 16
    
    // Get all 4 power-ups in order, using equipped version if unlocked, nil if locked
    private var allPowerUps: [PowerUp?] {
        powerUpManager.powerUps.map { powerUp in
            // If unlocked, return the equipped version (which has current state), otherwise nil
            // Match by name since UUID is generated fresh each time
            if powerUp.isUnlocked {
                return equippedPowerUps.first { $0.name == powerUp.name } ?? powerUp
            } else {
                return nil
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let slotWidth = (availableWidth - (spacing * 3)) / 4 // 4 power-ups with 3 gaps between them
            
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(allPowerUps.enumerated()), id: \.offset) { index, powerUp in
                    PowerUpSlot(
                        powerUp: powerUp
                    )
                    .frame(width: slotWidth, height: slotHeight)
                    .onTapGesture {
                        if let powerUp = powerUp {
                            onActivate(powerUp)
                        }
                    }
                }
                Spacer() // Push power-ups to the left
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: slotHeight)
    }
}

struct PowerUpSlot: View {
    let powerUp: PowerUp?
    let isPartOfMultiSlot: Bool
    let isFirstSlot: Bool
    let totalSlots: Int
    
    init(powerUp: PowerUp?, isPartOfMultiSlot: Bool = false, isFirstSlot: Bool = true, totalSlots: Int = 1) {
        self.powerUp = powerUp
        self.isPartOfMultiSlot = isPartOfMultiSlot
        self.isFirstSlot = isFirstSlot
        self.totalSlots = totalSlots
    }
    
    
    // Whether the button should appear disabled (not active power-ups - they should glow)
    private var isDisabled: Bool {
        guard let powerUp = powerUp else { return true }
        // Active or primed power-ups should NOT appear disabled
        if powerUp.isActive || powerUp.isPrimed {
            return false
        }
        return !powerUp.canBeUsed
    }
    
    // Icon color based on power-up state
    private var iconColor: Color {
        guard let powerUp = powerUp else { return .gray.opacity(0.3) }
        
        // Active power-ups get bright white (check first before canBeUsed)
        if powerUp.isActive {
            return .white
        }
        
        if powerUp.isPrimed {
            return .white.opacity(0.8)
        }
        
        if !powerUp.canBeUsed {
            return .gray.opacity(0.4)
        }
        
        return .white
    }
    
    // Accent color for active states
    private var accentColor: Color {
        guard let powerUp = powerUp else { return .clear }
        
        if powerUp.isActive {
            return .white
        }
        
        if powerUp.isPrimed {
            return .white.opacity(0.6)
        }
        
        return .clear
    }
    
    // Cooldown progress (0 = ready, 1 = full cooldown)
    private var cooldownProgress: CGFloat {
        guard let powerUp = powerUp else { return 0 }
        
        // Environmental power-ups use remainingCooldown
        if powerUp.type == .environment && powerUp.remainingCooldown > 0 {
            let totalCooldown = powerUp.currentStats.cooldown
            return CGFloat(powerUp.remainingCooldown / totalCooldown)
        }
        
        // Other power-ups use recharge
        if powerUp.isRecharging {
            return CGFloat(powerUp.rechargeTimeRemaining / powerUp.rechargeDuration)
        }
        
        return 0
    }
    
    var body: some View {
        ZStack {
            // Glass background - different style for disabled vs enabled
            if isDisabled {
                // Disabled: darker, flatter, more muted
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            } else {
                // Enabled: glass effect with material blur
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Subtle gradient highlight for glass effect
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.15),
                                        .white.opacity(0.05),
                                        .clear,
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        // Border with glass-like appearance
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            
            // Duration progress ring for active environmental power-ups
            if let powerUp = powerUp,
               powerUp.type == .environment,
               powerUp.isActive,
               let duration = powerUp.currentStats.duration {
                let progress = powerUp.remainingDuration / duration
                GeometryReader { geometry in
                    let circleSize = min(geometry.size.width, geometry.size.height) * 0.75
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            Color.white.opacity(0.8),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: circleSize, height: circleSize)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            
            // Main content
            VStack(spacing: 2) {
                if let powerUp = powerUp {
                    Image(systemName: powerUp.icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 20, weight: .semibold))
                        .shadow(color: .white.opacity(powerUp.isActive ? 0.6 : 0), radius: 6)
                        .symbolEffect(.pulse, options: .repeating, isActive: powerUp.isActive)
                    
                    if powerUp.level > 1 {
                        Text("Lv\(powerUp.level)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // Locked placeholder - very muted
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.gray.opacity(0.25))
                        .font(.system(size: 16))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Cooldown bar at bottom (grey)
            if cooldownProgress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: geometry.size.width, height: 3)
                            // Progress (depletes as cooldown completes)
                            Capsule()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: geometry.size.width * cooldownProgress, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
            
            // Active state glow ring (white)
            if let powerUp = powerUp, (powerUp.isActive || powerUp.isPrimed) {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        Color.white.opacity(powerUp.isActive ? 0.8 : 0.4),
                        lineWidth: 2
                    )
                    .shadow(color: .white.opacity(powerUp.isActive ? 0.5 : 0.2), radius: 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.2), value: powerUp?.isActive)
        .animation(.easeInOut(duration: 0.2), value: powerUp?.isPrimed)
    }
}

struct DebugMenuView: View {
    @ObservedObject var viewModel: GameViewModel
    @Binding var isPaused: Bool
    @Binding var showDebugMenu: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: {
                    isPaused = true
                    showDebugMenu = false
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .padding()
                Spacer()
            }
            
            Text("Debug Tools")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 20)
                .foregroundColor(.white)
            
            Button("Trigger Level Up") {
                #if DEBUG
                // Level up logic has been removed, button does nothing for now
                #endif
                isPaused = false
            }
            .buttonStyle(.bordered)
            .frame(width: 200)
            
            VStack {
                HStack {
                    Text("Spawn Tier:")
                        .foregroundColor(.white)
                    Spacer()
                    #if DEBUG
                    Text("\(viewModel.debug_spawnBallTierSelection)")
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                    Stepper("", 
                        value: .init(
                            get: { viewModel.debug_spawnBallTierSelection },
                            set: { viewModel.debug_spawnBallTierSelection = $0 }
                        ),
                        in: 1...(GameScene.tierData.count)
                    )
                    .labelsHidden()
                    #endif
                }
                Button("Spawn") {
                    #if DEBUG
                    viewModel.debug_spawnBallTier = viewModel.debug_spawnBallTierSelection
                    #endif
                    isPaused = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .frame(width: 200)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.15))
                .shadow(radius: 10)
        )
        .foregroundColor(.white)
    }
}

struct PauseMenuView: View {
    @ObservedObject var viewModel: GameViewModel
    @Binding var isPaused: Bool
    @Binding var currentScreen: ContentView.GameScreen
    @State private var showDebugMenu: Bool = false
    var onMainMenu: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("Paused")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
                    .foregroundColor(.white)
                
                Button(action: {
                    isPaused = false
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    onMainMenu?()
                    currentScreen = .mainMenu
                }) {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("Main Menu")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
                
                #if DEBUG
                Button(action: {
                    showDebugMenu = true
                }) {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("Debug Menu")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
                #endif
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.15))
                    .shadow(radius: 10)
            )
            .foregroundColor(.white)
            
            if showDebugMenu {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                DebugMenuView(viewModel: viewModel, isPaused: $isPaused, showDebugMenu: $showDebugMenu)
            }
        }
    }
}

struct UpgradeShopView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @EnvironmentObject var powerUpManager: PowerUpManager
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    private var sortedPowerUps: [PowerUp] {
        let originalIndices = Dictionary(uniqueKeysWithValues: powerUpManager.powerUps.enumerated().map { ($0.element.id, $0.offset) })
        
        return powerUpManager.powerUps.sorted { p1, p2 in
            if p1.isUnlocked != p2.isUnlocked {
                return p1.isUnlocked // Unlocked power-ups come first
            }
            
            // Otherwise, maintain the original order
            guard let index1 = originalIndices[p1.id], let index2 = originalIndices[p2.id] else {
                return false
            }
            return index1 < index2
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    currentScreen = .mainMenu
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .padding()
                Spacer()
            }
            
            Text("Upgrade Shop")
                .font(.title)
                .padding(.bottom)
            
            HStack {
                Text("Coins: \(powerUpManager.currency)")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                #if DEBUG
                Button(action: {
                    print("[Shop] Manual refresh triggered")
                    powerUpManager.reloadFromCoreData()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                #endif
            }
            .padding(.bottom)
            
            #if DEBUG
            // Debug info
            let unlockedCount = powerUpManager.powerUps.filter { $0.isUnlocked }.count
            Text("Unlocked: \(unlockedCount)/\(powerUpManager.powerUps.count)")
                .font(.caption)
                .foregroundColor(.gray)
            #endif
            
            ScrollView {
                // Flasks Section
                VStack(alignment: .leading) {
                    Text("Flasks")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(FlaskSize.allCases.filter { $0 != .small }, id: \.self) { size in
                        let isUnlocked = powerUpManager.getUnlockedFlaskSizes().contains(size)
                        Button(action: {
                            if !isUnlocked {
                                _ = powerUpManager.unlockFlaskSize(size)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(size.displayName)
                                        .font(.headline)
                                    Text(size.description)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if isUnlocked {
                                    Text("Unlocked")
                                        .foregroundColor(.green)
                                } else {
                                    HStack {
                                        Image(systemName: "lock.fill")
                                        Text("\(size.cost) Coins")
                                    }
                                    .foregroundColor(powerUpManager.currency >= size.cost ? .yellow : .gray)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(white: 0.15))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUnlocked || powerUpManager.currency < size.cost)
                    }
                }
                .padding()
                
                // Power-ups Section
                VStack(alignment: .leading) {
                    Text("Power-ups")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        ForEach(sortedPowerUps) { powerUp in
                            Button(action: {
                                if powerUp.isUnlocked {
                                    if powerUp.level < PowerUp.maxLevel {
                                        _ = powerUpManager.upgrade(powerUp)
                                    }
                                } else {
                                    _ = powerUpManager.unlock(powerUp)
                                }
                            }) {
                                HStack(alignment: .top, spacing: 12) {
                                    // Icon Section
                                    VStack {
                                        PowerUpSlot(powerUp: powerUp)
                                            .frame(width: 60, height: 60)
                                        if powerUp.isUnlocked {
                                            Text("Lvl \(powerUp.level)")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.3))
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    // Content Section
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(powerUp.name)
                                                .font(.headline)
                                            Spacer()
                                            // Cost/Status
                                            if !powerUp.isUnlocked {
                                                 HStack(spacing: 4) {
                                                     Image(systemName: "lock.fill")
                                                     Text("\(powerUp.cost)")
                                                 }
                                                 .foregroundColor(powerUpManager.currency >= powerUp.cost ? .yellow : .gray)
                                            } else if powerUp.level < PowerUp.maxLevel {
                                                 HStack(spacing: 4) {
                                                     Image(systemName: "arrow.up.circle.fill")
                                                     Text("\(powerUp.upgradeCost)")
                                                 }
                                                 .foregroundColor(powerUpManager.currency >= powerUp.upgradeCost ? .yellow : .gray)
                                            } else {
                                                Text("MAX")
                                                    .foregroundColor(.green)
                                                    .fontWeight(.bold)
                                            }
                                        }
                                        
                                        Text(powerUp.description)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .padding(.bottom, 4)
                                        
                                        // Stats Section
                                        if powerUp.isUnlocked {
                                            HStack(alignment: .top, spacing: 16) {
                                                // Current Stats
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Current")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                    
                                                    let stats = powerUp.currentStats
                                                    Text("Cooldown: \(Int(stats.cooldown))s")
                                                    
                                                    if let duration = stats.duration {
                                                        Text("Duration: \(Int(duration))s")
                                                    }
                                                    
                                                    if powerUp.name == "Super Massive Ball" {
                                                        Text("Mass: \(String(format: "%.1fx", stats.massMultiplier))")
                                                        Text("Force: \(String(format: "%.2f", stats.forceMagnitude))")
                                                    } else if powerUp.name == "Low Gravity" {
                                                        Text("Gravity: \(String(format: "%.2f", stats.forceMagnitude))")
                                                    } else if powerUp.name == "Rubber World" {
                                                        Text("Bounce: \(String(format: "%.2f", stats.forceMagnitude))")
                                                    } else if powerUp.name == "Ice World" {
                                                        Text("Friction: \(String(format: "%.2f", stats.forceMagnitude))")
                                                    }
                                                }
                                                .font(.caption2)
                                                
                                                // Next Level Stats
                                                if powerUp.level < PowerUp.maxLevel {
                                                    Image(systemName: "arrow.right")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                        .padding(.top, 12)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Level \(powerUp.level + 1)")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.green)
                                                        
                                                        let stats = powerUp.baseStats.scaled(to: powerUp.level + 1)
                                                        Text("Cooldown: \(Int(stats.cooldown))s")
                                                        
                                                        if let duration = stats.duration {
                                                            Text("Duration: \(Int(duration))s")
                                                        }
                                                        
                                                        if powerUp.name == "Super Massive Ball" {
                                                            Text("Mass: \(String(format: "%.1fx", stats.massMultiplier))")
                                                            Text("Force: \(String(format: "%.2f", stats.forceMagnitude))")
                                                        } else if powerUp.name == "Low Gravity" {
                                                            Text("Gravity: \(String(format: "%.2f", stats.forceMagnitude))")
                                                        } else if powerUp.name == "Rubber World" {
                                                            Text("Bounce: \(String(format: "%.2f", stats.forceMagnitude))")
                                                        } else if powerUp.name == "Ice World" {
                                                            Text("Friction: \(String(format: "%.2f", stats.forceMagnitude))")
                                                        }
                                                    }
                                                    .font(.caption2)
                                                    .foregroundColor(.green)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(white: 0.15))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled((!powerUp.isUnlocked && powerUpManager.currency < powerUp.cost) || (powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && powerUpManager.currency < powerUp.upgradeCost))
                            .opacity((!powerUp.isUnlocked && powerUpManager.currency < powerUp.cost) || (powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && powerUpManager.currency < powerUp.upgradeCost) ? 0.6 : 1.0)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            // Reload data when the view appears to get the latest currency and unlocks
            powerUpManager.reloadFromCoreData()
        }
    }
}


struct SettingsView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @EnvironmentObject var powerUpManager: PowerUpManager
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    currentScreen = .mainMenu
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .padding()
                Spacer()
            }
            
            Text("Settings")
                .font(.title)
                .padding(.bottom)
            
            Spacer()
            
            #if DEBUG
            VStack {
                Text("Debug Tools")
                    .font(.headline)
                    .padding(.top)

                Button("Reset Progress") {
                    CoreDataManager.shared.resetGameData()
                    // Reload data to reflect changes
                    powerUpManager.reloadFromCoreData()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button("Add 1000 Coins") {
                    powerUpManager.addCurrency(1000)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
            #endif
            
            Spacer()
        }
    }
}


struct GameOverView: View {
    let score: Int
    let highScore: Int
    let coinsEarned: Int
    let onMainMenu: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Game Over!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Score: \(score)")
                .font(.title2)
                .foregroundColor(.white)

            Text("High Score: \(highScore)")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.bottom, 10)
            
            Text("Coins Earned: \(coinsEarned)")
                .font(.headline)
                .foregroundColor(.yellow)
                .padding(.bottom, 20)
            
            Button(action: onMainMenu) {
                HStack {
                    Image(systemName: "house.fill")
                    Text("Main Menu")
                }
                .frame(width: 200)
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.15))
                .shadow(radius: 10)
        )
    }
}

#if os(iOS)
struct SpriteKitContainer: UIViewRepresentable {
    @ObservedObject var viewModel: GameViewModel
    @Binding var isGameOver: Bool
    
    class Coordinator: NSObject {
        var scene: GameScene?
        let viewModel: GameViewModel
        let isGameOver: Binding<Bool>
        
        init(viewModel: GameViewModel, isGameOver: Binding<Bool>) {
            self.viewModel = viewModel
            self.isGameOver = isGameOver
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, isGameOver: $isGameOver)
    }
    
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
        
        let scene = GameScene(size: CGSize(width: 375, height: 650))
        scene.scaleMode = .fill
        scene.viewModel = viewModel
        scene.onGameOver = {
            DispatchQueue.main.async {
                context.coordinator.isGameOver.wrappedValue = true
            }
        }
        context.coordinator.scene = scene
        
        context.coordinator.viewModel.sphereStateProvider = { [weak scene] in
            return scene?.getCurrentSphereStates() ?? []
        }
        
        view.presentScene(scene)
        return view
    }
    
    func updateUIView(_ view: SKView, context: Context) {
        if let scene = context.coordinator.scene {
            scene.viewModel = viewModel
            scene.isPaused = viewModel.isGamePaused
            
            // Update grid and ball sizes when flask size changes
            if scene.viewModel?.selectedFlaskSize != viewModel.selectedFlaskSize {
                scene.updateFlaskSize()
            }
        }
    }
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    weak var viewModel: GameViewModel?
    
    private var currentSphere: SKSpriteNode?
    private var isTransitioning = false
    private var dangerZone: SKShapeNode?
    private var spheresInDangerZone = Set<SKPhysicsBody>()
    private let topBufferHeight: CGFloat = 80
    private let dangerGracePeriod: TimeInterval = 3.0
    private let gameOverThreshold: TimeInterval = 5.0
    private var dangerStartTime: TimeInterval?
    private var gridNode: SKNode?
    private var sphereEffectNode: SKEffectNode?
    private var environmentalBorder: SKShapeNode?
    private var previouslyActiveEnvironmentalPowerUpName: String?
    private let motionManager = CMMotionManager()
    
    // Debug Stats
    private var lastUpdateTime: TimeInterval = 0
    private var frameCount: Int = 0
    private var timeSinceLastFPSUpdate: TimeInterval = 0
    
    // MARK: - Targeting System
    enum TargetingState {
        case none           // No targeting active
        case primed        // Targeting power-up is primed, showing center circle
        case selecting     // User is selecting a target
        case targeted      // Target selected, waiting for activation
        case active        // Effect is active on target
    }
    
    private var targetingState: TargetingState = .none
    private var targetingPowerUp: PowerUp?
    private var selectedTarget: SKSpriteNode?
    private var targetingCircle: SKShapeNode?
    
    // Define power-up colors
    private let powerUpColors: [String: SKColor] = [
        // Single-use power-ups
        "Super Massive Ball": SKColor(Color.blue),
        
        // Environmental power-ups
        "Low Gravity": SKColor(Color.blue),
        "Rubber World": SKColor(Color.green),
        "Ice World": SKColor(Color.cyan),
        "Tilt World": SKColor(Color.yellow),
        
        // Targeting power-ups
        "Selective Deletion": SKColor(Color.red.opacity(0.7))
    ]
    
    // Helper for checking active power-ups
    private func hasActivePowerUp(_ name: String) -> Bool {
        return viewModel?.equippedPowerUps.contains(where: { powerUp in
            powerUp.name == name && powerUp.isActive == true
        }) ?? false
    }
    
    // Environmental power-up colors with opacity variants
    private func getEnvironmentalColor(for powerUpName: String) -> SKColor {
        return powerUpColors[powerUpName] ?? SKColor(Color.blue)
    }
    
    // Update the border color method
    private func updateEnvironmentalBorder() {
        let activeEnvironmentalPowerUp = getActiveEnvironmentalPowerUp()
        let activePowerUpName = activeEnvironmentalPowerUp?.name

        // Check if Rubber World was just deactivated
        if previouslyActiveEnvironmentalPowerUpName == "Rubber World" && activePowerUpName != "Rubber World" {
            applyCalmDownEffect()
        }
        
        if let powerUp = activeEnvironmentalPowerUp {
            let color = getEnvironmentalColor(for: powerUp.name)
            environmentalBorder?.strokeColor = color
            
            // Apply environmental physics effects
            switch powerUp.name {
            case "Low Gravity":
                resetRubberWorldEffect()
                resetIceWorldEffect()
                applyLowGravityEffect()
            case "Rubber World":
                // Reset other environmental effects first
                physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
                resetIceWorldEffect()
                applyRubberWorldEffect()
            case "Ice World":
                // Reset other environmental effects first
                physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
                resetRubberWorldEffect()
                applyIceWorldEffect()
            case "Tilt World":
                resetRubberWorldEffect()
                resetIceWorldEffect()
                applyTiltWorldEffect()
            default:
                // Reset all environmental effects if an unknown one is active
                physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
                resetRubberWorldEffect()
                resetIceWorldEffect()
            }
        } else {
            environmentalBorder?.strokeColor = .clear
            // Reset all environmental effects
            physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
            resetRubberWorldEffect()
            resetIceWorldEffect()
        }

        // Store the current active power-up name for the next frame
        previouslyActiveEnvironmentalPowerUpName = activePowerUpName
    }
    
    // Helper for checking primed or active environmental power-ups
    private func getActiveEnvironmentalPowerUp() -> PowerUp? {
        return viewModel?.equippedPowerUps
            .first(where: { $0.type == .environment && $0.isActive })
    }
    
    // Get the active power-up that should affect the current ball
    private var currentActivePowerUp: (name: String, color: SKColor)? {
        for (powerUpName, color) in powerUpColors {
            if let powerUp = viewModel?.equippedPowerUps.first(where: { $0.name == powerUpName && $0.isActive }) {
                // Only return non-environmental power-ups for ball effects
                if powerUp.type != .environment {
                    return (powerUpName, color)
                }
            }
        }
        return nil
    }
    
    // Grid configuration
    private let baseGridSpacing: CGFloat = 50 // Base spacing between grid lines
    private let gridLineWidth: CGFloat = 0.5
    private let gridLineColor = SKColor(white: 0.3, alpha: 0.3)
    private let gridDotRadius: CGFloat = 1.5
    private let gridDotColor = SKColor(white: 0.4, alpha: 0.4)
    
    var onGameOver: (() -> Void)?
    
    struct PhysicsCategory {
        static let none: UInt32 = 0
        static let sphere: UInt32 = 0x1 << 0
        static let wall: UInt32 = 0x1 << 1
        static let dangerZone: UInt32 = 0x1 << 2
    }
    
    private var scheduledForMerge = Set<SKSpriteNode>()
    
    struct TierInfo {
        let radius: CGFloat
        let spriteName: String
    }
    
    static func calculateRadius(forTier tier: Int) -> CGFloat {
        let baseSize: CGFloat = 18
        return baseSize + (tier > 1 ? CGFloat((tier - 1) * 12) : 0)
    }
    
    // From cyan to a dark gray/black
    static let tierData: [TierInfo] = (1...12).map { tier in
        return TierInfo(radius: calculateRadius(forTier: tier), spriteName: "ball_\(tier)")
    }
    let maxTier = tierData.count
    
    private var currentFlaskSize: FlaskSize {
        viewModel?.selectedFlaskSize ?? .small
    }
    
    private var ballScale: CGFloat {
        currentFlaskSize.ballScale
    }
    
    private var gridSpacing: CGFloat {
        baseGridSpacing * ballScale
    }
    
    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        
        // Setup boundary physics body that extends above the visible area, with a ceiling.
        let extendedHeight = self.frame.height * 2
        // Extend the bottom slightly to ensure balls sit flush with the visual border and match rounded corners
        let bottomOffset: CGFloat = 2.0
        let physicsRect = CGRect(x: self.frame.minX, y: self.frame.minY - bottomOffset, width: self.frame.width, height: extendedHeight + bottomOffset)
        
        // Create a rounded rect path to match the visual style
        let cornerRadius: CGFloat = 12
        let path = CGPath(roundedRect: physicsRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        let frameBody = SKPhysicsBody(edgeLoopFrom: path)
        frameBody.friction = 0.2
        frameBody.restitution = 0.2
        self.physicsBody = frameBody
        self.physicsBody?.categoryBitMask = PhysicsCategory.wall
        
        backgroundColor = .black
        
        // Reset targeting state
        targetingState = .none
        selectedTarget = nil
        targetingCircle?.removeFromParent()
        targetingCircle = nil
        
        // Reset any active targeting power-ups
        if let viewModel = viewModel {
            for i in viewModel.equippedPowerUps.indices {
                var powerUp = viewModel.equippedPowerUps[i]
                if powerUp.type == .targeting &&
                   (powerUp.isPrimed || powerUp.isActive) {
                    powerUp.isPrimed = false
                    powerUp.isActive = false
                    viewModel.equippedPowerUps[i] = powerUp
                }
            }
        }
        
        setupGrid()
        setupSphereEffectNode()
        setupDangerZone()
        setupEnvironmentalBorder()
        
        warmUpMetaballEffect()
        
        startAccelerometer()
        
        var restoredCurrentSphere = false
        // Restore spheres from saved state if available
        if let sphereStates = viewModel?.getSphereStates(), !sphereStates.isEmpty {
            // Separate the current sphere from the rest
            let currentSphereState = sphereStates.first(where: { $0.isCurrentSphere })
            let otherSphereStates = sphereStates.filter { !$0.isCurrentSphere }

            // Restore other spheres with physics
            for state in otherSphereStates {
                let position = CGPoint(x: state.positionX, y: state.positionY)
                let activePowerUps = state.activePowerUps?.split(separator: ",").map(String.init) ?? []
                if let sphere = createAndPlaceSphere(at: position, tier: Int(state.tier), activePowerUps: activePowerUps) {
                    // Make restored spheres immediately "live" for the danger zone
                    sphere.userData?["creationTime"] = Date.distantPast.timeIntervalSinceReferenceDate
                }
            }
            
            // Restore the current sphere without physics
            if let state = currentSphereState {
                let tier = Int(state.tier)
                if let sphere = createSphereNode(tier: tier) {
                    let position = CGPoint(x: state.positionX, y: state.positionY)
                    sphere.position = position

                    // Restore its power-up visual state
                    let activePowerUps = state.activePowerUps?.split(separator: ",").map(String.init) ?? []
                    sphere.userData?["activePowerUps"] = activePowerUps
                    if let powerUpName = activePowerUps.first, let color = powerUpColors[powerUpName] {
                        sphere.color = color
                        sphere.colorBlendFactor = 0.7
                    }

                    sphereEffectNode?.addChild(sphere)
                    self.currentSphere = sphere
                    restoredCurrentSphere = true
                }
            }
        }
        
        // If no current sphere was restored (new game or old save file), spawn a new one.
        if !restoredCurrentSphere {
            spawnNewSphere(at: nil, animated: false)
        }
    }
    
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        stopAccelerometer()
    }
    
    private func setupGrid() {
        // Remove existing grid if any
        gridNode?.removeFromParent()
        
        // Create a container node for the grid
        let container = SKNode()
        
        // Calculate number of lines needed
        let horizontalLines = Int(frame.height / gridSpacing)
        let verticalLines = Int(frame.width / gridSpacing)
        
        // Create horizontal lines
        for i in 0...horizontalLines {
            let y = CGFloat(i) * gridSpacing
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: frame.width, y: y))
            line.path = path
            line.strokeColor = gridLineColor
            line.lineWidth = gridLineWidth
            container.addChild(line)
        }
        
        // Create vertical lines
        for i in 0...verticalLines {
            let x = CGFloat(i) * gridSpacing
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: frame.height))
            line.path = path
            line.strokeColor = gridLineColor
            line.lineWidth = gridLineWidth
            container.addChild(line)
        }
        
        // Add dots at intersections
        for i in 0...horizontalLines {
            for j in 0...verticalLines {
                let x = CGFloat(j) * gridSpacing
                let y = CGFloat(i) * gridSpacing
                let dot = SKShapeNode(circleOfRadius: gridDotRadius)
                dot.position = CGPoint(x: x, y: y)
                dot.fillColor = gridDotColor
                dot.strokeColor = .clear
                container.addChild(dot)
            }
        }
        
        // Add the grid container to the scene
        gridNode = container
        addChild(container)
        
        // Move grid to back
        container.zPosition = -1
    }
    
    func updateGrid() {
        setupGrid() // Recreate grid with new spacing
    }
    
    // Update the SpriteKitContainer to handle flask size changes
    func updateFlaskSize() {
        updateGrid()
        // Rescale existing spheres
        sphereEffectNode?.enumerateChildNodes(withName: "sphere") { node, _ in
            guard let sphere = node as? SKSpriteNode,
                  let tier = sphere.userData?["tier"] as? Int else { return }
            
            let tierIndex = tier - 1
            let tierInfo = GameScene.tierData[tierIndex]
            let scaledRadius = tierInfo.radius * self.ballScale
            
            // Create new path with scaled radius
            sphere.size = CGSize(width: scaledRadius * 2, height: scaledRadius * 2)
            
            // Update physics body
            if let body = sphere.physicsBody {
                let newBody = SKPhysicsBody(circleOfRadius: scaledRadius)
                newBody.categoryBitMask = body.categoryBitMask
                newBody.contactTestBitMask = body.contactTestBitMask
                newBody.collisionBitMask = body.collisionBitMask
                newBody.restitution = body.restitution
                newBody.friction = body.friction
                newBody.allowsRotation = body.allowsRotation
                newBody.linearDamping = body.linearDamping
                newBody.angularDamping = body.angularDamping
                newBody.velocity = body.velocity
                newBody.angularVelocity = body.angularVelocity
                
                let maxTierMass: CGFloat = 12
                let baseMass: CGFloat = 10.0
                let massMultiplier = pow(1.5, maxTierMass - CGFloat(tier))
                newBody.mass = baseMass * massMultiplier * self.ballScale
                
                sphere.physicsBody = newBody
            }
        }
    }
    
    private func setupSphereEffectNode() {
        let effectNode = SKEffectNode()
        effectNode.shouldEnableEffects = true
        let filter = MetaballFilter()
        filter.blurRadius = 10.0
        filter.threshold = 0.5
        filter.opacity = 0.8 // Transparent glass
        effectNode.filter = filter
        effectNode.zPosition = 10
        addChild(effectNode)
        self.sphereEffectNode = effectNode
    }

    func setupDangerZone() {
        let dangerHeight: CGFloat = topBufferHeight
        let dangerRect = CGRect(x: 0, y: frame.height - dangerHeight, width: frame.width, height: dangerHeight)
        
        dangerZone = SKShapeNode(rect: dangerRect)
        dangerZone?.name = "dangerZone"
        dangerZone?.fillColor = .clear
        dangerZone?.strokeColor = .clear // Initially no stroke on the rect itself
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: dangerRect.minY))
        path.addLine(to: CGPoint(x: dangerRect.maxX, y: dangerRect.minY))
        
        let bottomLine = SKShapeNode(path: path)
        bottomLine.name = "dangerZoneLine"
        bottomLine.strokeColor = SKColor(white: 0.5, alpha: 0.3)
        bottomLine.lineWidth = 2
        dangerZone?.addChild(bottomLine)
        
        addChild(dangerZone!)
        
        let body = SKPhysicsBody(rectangleOf: dangerRect.size, center: CGPoint(x: dangerRect.midX, y: dangerRect.midY))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.dangerZone
        body.contactTestBitMask = PhysicsCategory.sphere
        body.collisionBitMask = PhysicsCategory.none
        dangerZone?.physicsBody = body
    }
    
    func setupEnvironmentalBorder() {
        let borderRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let border = SKShapeNode(rect: borderRect, cornerRadius: 12)
        border.strokeColor = .clear
        border.lineWidth = 4
        border.name = "environmentalBorder"
        addChild(border)
        environmentalBorder = border
    }
    
    func spawnNewSphere(at position: CGPoint? = nil, animated: Bool) {
        let tier = Int.random(in: 1...3)
        guard let sphere = createSphereNode(tier: tier) else {
            self.isTransitioning = false
            return
        }
        
        let spawnY = size.height - topBufferHeight
        let initialPosition = position ?? CGPoint(x: size.width / 2, y: spawnY)
        sphere.position = initialPosition
        
        sphereEffectNode?.addChild(sphere)
        
        if animated {
            sphere.setScale(0)
            let scaleAction = SKAction.scale(to: 1.0, duration: 0.1)
            scaleAction.timingMode = .easeOut
            
            sphere.run(scaleAction) { [weak self] in
                self?.currentSphere = sphere
                
                // After scaling, check if we need to adjust position
                if let strongSelf = self, let currentSphere = strongSelf.currentSphere {
                    let radius = currentSphere.size.width.half
                    let currentX = sphere.position.x
                    let constrainedX = min(max(radius, currentX), strongSelf.frame.width - radius)
                    
                    if currentX != constrainedX {
                        let moveAction = SKAction.moveTo(x: constrainedX, duration: 0.2)
                        moveAction.timingMode = .easeInEaseOut
                        sphere.run(moveAction)
                    }
                }
                
                self?.isTransitioning = false
            }
        } else {
            self.currentSphere = sphere
            
            // Immediately adjust position if needed
            let radius = sphere.size.width.half
            let currentX = sphere.position.x
            let constrainedX = min(max(radius, currentX), frame.width - radius)
            sphere.position = CGPoint(x: constrainedX, y: spawnY)
        }
    }
    
    // Generate a flat grey circle texture for a given tier
    private func createGreyCircleTexture(radius: CGFloat, tier: Int, maxTier: Int) -> SKTexture {
        let size = CGSize(width: radius * 2, height: radius * 2)
        
        #if os(iOS)
        // Use Core Graphics on iOS for better performance
        let scale: CGFloat = 2.0 // Use @2x scale for better quality
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale))
        let greyValue = getGreyColorValue(for: tier, maxTier: maxTier)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(red: greyValue, green: greyValue, blue: greyValue, alpha: 1.0)
            cgContext.setStrokeColor(UIColor.clear.cgColor)
            
            // Draw circle
            let rect = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            cgContext.fillEllipse(in: rect)
        }
        return SKTexture(image: image)
        #else
        // Use SpriteKit shape node approach for macOS
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = getGreyColor(for: tier, maxTier: maxTier)
        circle.strokeColor = .clear
        circle.position = CGPoint(x: radius, y: radius)
        
        let textureScene = SKScene(size: size)
        textureScene.backgroundColor = .clear
        textureScene.addChild(circle)
        
        // Create a temporary view to render the texture
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let texture = view.texture(from: textureScene) ?? SKTexture()
        return texture
        #endif
    }
    
    // Get grey color for a tier (darker for lower tiers, lighter for higher tiers)
    private func getGreyColor(for tier: Int, maxTier: Int) -> SKColor {
        let greyValue = getGreyColorValue(for: tier, maxTier: maxTier)
        return SKColor(white: greyValue, alpha: 1.0)
    }
    
    // Get grey color value (0.0 to 1.0) for a tier
    private func getGreyColorValue(for tier: Int, maxTier: Int) -> CGFloat {
        // Interpolate from dark grey (0.2) to light grey (0.8)
        // Tier 1 = darkest, Tier maxTier = lightest
        let normalizedTier = CGFloat(tier - 1) / CGFloat(maxTier - 1)
        return 0.2 + (normalizedTier * 0.6) // Range from 0.2 to 0.8
    }
    
    func createSphereNode(tier: Int) -> SKSpriteNode? {
        guard tier >= 1 && tier <= GameScene.tierData.count else { return nil }
        
        let tierIndex = tier - 1
        let tierInfo = GameScene.tierData[tierIndex]
        let scaledRadius = tierInfo.radius * ballScale
        
        // Create sphere with flat grey color instead of texture
        let texture = createGreyCircleTexture(radius: scaledRadius, tier: tier, maxTier: GameScene.tierData.count)
        let sphere = SKSpriteNode(texture: texture)
        sphere.size = CGSize(width: scaledRadius * 2, height: scaledRadius * 2)
        sphere.name = "sphere"
        sphere.userData = [
            "tier": tier,
            "activePowerUps": [String]()
        ]
        
        return sphere
    }
    

    func createAndPlaceSphere(at position: CGPoint, tier: Int, activePowerUps: [String] = []) -> SKSpriteNode? {
        guard let sphere = createSphereNode(tier: tier) else { return nil }
        sphere.position = position
        
        // Store active power-ups in userData
        sphere.userData?["activePowerUps"] = activePowerUps
        
        // Apply visual effects based on active power-ups
        if let powerUpName = activePowerUps.first, // For now, we'll only show one power-up effect
           let color = powerUpColors[powerUpName] {
            sphere.color = color
            sphere.colorBlendFactor = 0.7
        }
        
        addPhysics(to: sphere)
        sphereEffectNode?.addChild(sphere)
        return sphere
    }

    private func constrainPosition(_ position: CGPoint, forSphere sphere: SKSpriteNode) -> CGPoint {
        let radius = sphere.size.width.half
        
        // Ensure the ball stays within bounds horizontally
        let constrainedX = min(max(radius, position.x), frame.width - radius)
        
        return CGPoint(
            x: constrainedX,
            y: size.height - topBufferHeight
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPaused, let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Handle targeting mode touches
        if targetingState == .primed || targetingState == .targeted {
            if let sphere = findSelectableSphere(at: location) {
                if sphere === selectedTarget {
                    // Second tap on the same sphere activates the power-up
                    if let powerUp = targetingPowerUp {
                        activateTargetingPowerUp(powerUp, on: sphere)
                    }
                } else {
                    // First tap on a new sphere selects it
                    if let currentTarget = selectedTarget {
                        unhighlightSphere(currentTarget)
                    }
                    highlightSphere(sphere)
                    selectSphere(sphere)
                }
            }
            // Prevent any other touch handling during targeting mode
            return
        }
        
        // Only handle normal sphere movement if not in targeting mode
        if !isTransitioning, let sphere = currentSphere {
            sphere.position = constrainPosition(location, forSphere: sphere)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPaused, let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Ignore touch movement during targeting mode
        if targetingState != .none { return }
        
        // Only handle sphere movement in normal mode
        if !isTransitioning, let sphere = currentSphere {
            sphere.position = constrainPosition(location, forSphere: sphere)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPaused, let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Ignore touch end during targeting mode
        if targetingState != .none { return }
        
        // Handle normal sphere drops only when not in targeting mode
        if !isTransitioning, let sphereToDrop = currentSphere {
            isTransitioning = true
            
            let constrainedPosition = constrainPosition(location, forSphere: sphereToDrop)
            sphereToDrop.position = constrainedPosition
            
            // Apply any active power-ups to the sphere before dropping
            if let activePowerUp = currentActivePowerUp {
                var activePowerUps = sphereToDrop.userData?["activePowerUps"] as? [String] ?? []
                activePowerUps.append(activePowerUp.name)
                sphereToDrop.userData?["activePowerUps"] = activePowerUps
                viewModel?.consumeSingleUsePowerUp(activePowerUp.name)
            }
            
            addPhysics(to: sphereToDrop)
            
            // Drop haptics removed to reduce feedback noise
            
            self.currentSphere = nil
            
            // Use the same constrained x position for spawning the next sphere
            let spawnPosition = constrainedPosition
            
            // Use a slight delay to allow the dropped sphere to start falling before the next appears
            run(SKAction.wait(forDuration: 0.1)) { [weak self] in
                self?.spawnNewSphere(at: spawnPosition, animated: true)
            }
        }
    }
    
    func getCurrentSphereStates() -> [Sphere] {
        let context = CoreDataManager.shared.context
        let nodesToCheck = sphereEffectNode?.children ?? []
        let states = nodesToCheck.compactMap { node -> Sphere? in
            guard let sphereNode = node as? SKSpriteNode,
                  sphereNode.name == "sphere",
                  let tier = sphereNode.userData?["tier"] as? Int else { return nil }
            
            let sphereEntity = Sphere(context: context)
            sphereEntity.tier = Int64(tier)
            sphereEntity.positionX = sphereNode.position.x
            sphereEntity.positionY = sphereNode.position.y
            sphereEntity.isCurrentSphere = (sphereNode === currentSphere) // Tag the held sphere
            
            // Get active power-ups for this sphere
            let activePowerUps = sphereNode.userData?["activePowerUps"] as? [String] ?? []
            sphereEntity.activePowerUps = activePowerUps.joined(separator: ",")
            
            return sphereEntity
        }
        return states
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        
        // Sphere-DangerZone contact
        if contactMask == (PhysicsCategory.sphere | PhysicsCategory.dangerZone) {
            let sphereBody = contact.bodyA.categoryBitMask == PhysicsCategory.sphere ? contact.bodyA : contact.bodyB
            guard let sphereNode = sphereBody.node as? SKSpriteNode,
                  let creationTime = sphereNode.userData?["creationTime"] as? TimeInterval else { return }
            
            let currentTime = Date().timeIntervalSinceReferenceDate
            if currentTime - creationTime >= dangerGracePeriod {
                spheresInDangerZone.insert(sphereBody)
                if let line = dangerZone?.childNode(withName: "dangerZoneLine") as? SKShapeNode {
                    line.strokeColor = .red
                }
            }
        }
        
        // Sphere-Sphere contact for merging
        if contactMask == (PhysicsCategory.sphere | PhysicsCategory.sphere) {
            guard let nodeA = contact.bodyA.node as? SKSpriteNode,
                  let nodeB = contact.bodyB.node as? SKSpriteNode else { return }

            guard !scheduledForMerge.contains(nodeA) && !scheduledForMerge.contains(nodeB) else { return }

            guard let tierA = nodeA.userData?["tier"] as? Int,
                  let tierB = nodeB.userData?["tier"] as? Int else { return }

            if tierA == tierB && tierA < maxTier {
                scheduledForMerge.insert(nodeA)
                scheduledForMerge.insert(nodeB)
            }
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        // Calculate FPS and Node Count
        if lastUpdateTime > 0 {
            let deltaTime = currentTime - lastUpdateTime
            frameCount += 1
            timeSinceLastFPSUpdate += deltaTime
            
            if timeSinceLastFPSUpdate >= 0.5 {
                let fps = Int(Double(frameCount) / timeSinceLastFPSUpdate)
                let nodeCount = self.children.count
                
                DispatchQueue.main.async { [weak self] in
                    self?.viewModel?.fps = fps
                    self?.viewModel?.nodeCount = nodeCount
                }
                
                frameCount = 0
                timeSinceLastFPSUpdate = 0
            }
        }
        lastUpdateTime = currentTime
        
        // Update holographic rainbow effect time
        if let filter = sphereEffectNode?.filter as? MetaballFilter {
            // Use a wrapping time value to avoid precision issues over long runs
            // Slowing down the effect by factor of 10 (dividing time by 10.0)
            let timeLoop = CGFloat((currentTime * 0.1).truncatingRemainder(dividingBy: 10000.0))
            filter.time = timeLoop
        }

        #if DEBUG
        if let viewModel = viewModel, let tier = viewModel.debug_spawnBallTier {
            let centerPosition = CGPoint(x: frame.midX, y: frame.midY)
            if let sphere = createAndPlaceSphere(at: centerPosition, tier: tier) {
                 sphere.userData?["creationTime"] = Date.distantPast.timeIntervalSinceReferenceDate
            }
            viewModel.debug_spawnBallTier = nil // Reset after spawning
        }
        #endif
        // Update environmental border state
        updateEnvironmentalBorder()
        
        // Update targeting circle position if we have a selected target
        if targetingState == .targeted,
           let selectedSphere = selectedTarget,
           let targetingCircle = targetingCircle {
            targetingCircle.position = selectedSphere.position
        }
        
        // Update targeting state based on power-up changes
        if let viewModel = viewModel {
            // Clean up targeting when game is paused
            if isPaused {
                if targetingState != .none {
                    exitTargetingMode()
            // Also reset any primed or active targeting power-ups
            for i in viewModel.equippedPowerUps.indices {
                var powerUp = viewModel.equippedPowerUps[i]
                if powerUp.type == .targeting &&
                   (powerUp.isPrimed || powerUp.isActive) {
                    powerUp.isPrimed = false
                    powerUp.isActive = false
                    viewModel.equippedPowerUps[i] = powerUp
                }
            }
        }
        targetingCircle?.alpha = 0
    } else {
        targetingCircle?.alpha = 0.5
    }
    
    let targetingPowerUp = viewModel.equippedPowerUps
        .first { $0.type == .targeting && ($0.isPrimed || $0.isActive) }
            
            #if DEBUG
            if let powerUp = targetingPowerUp {
                print("Found targeting power-up: \(powerUp.name), isPrimed: \(powerUp.isPrimed), isActive: \(powerUp.isActive)")
            }
            #endif
            
            if let powerUp = targetingPowerUp {
                if powerUp.isPrimed && targetingState == .none {
                    #if DEBUG
                    print("Entering targeting mode...")
                    #endif
                    enterTargetingMode(powerUp)
                } else if !powerUp.isPrimed && !powerUp.isActive {
                    #if DEBUG
                    print("Exiting targeting mode...")
                    #endif
                    exitTargetingMode()
                }
            } else if targetingState != .none {
                #if DEBUG
                print("No targeting power-up found, exiting targeting mode...")
                #endif
                exitTargetingMode()
            }
        }
        
        // Update current sphere appearance if power-up state changes
        if let currentSphere = currentSphere {
            if let activePowerUp = currentActivePowerUp {
                currentSphere.color = activePowerUp.color
                currentSphere.colorBlendFactor = 0.7
            } else {
                currentSphere.colorBlendFactor = 0.0
            }
        }
        
        // Cleanup stale bodies from danger zone set
        spheresInDangerZone = spheresInDangerZone.filter { $0.node != nil }
        
        // Update danger zone state
        if !spheresInDangerZone.isEmpty {
            if dangerStartTime == nil {
                dangerStartTime = currentTime
            } else if currentTime - dangerStartTime! >= gameOverThreshold {
                isPaused = true
                onGameOver?()
                return
            }
            
            if let line = dangerZone?.childNode(withName: "dangerZoneLine") as? SKShapeNode {
                line.strokeColor = .red
            }
        } else {
            dangerStartTime = nil
            if let line = dangerZone?.childNode(withName: "dangerZoneLine") as? SKShapeNode {
                line.strokeColor = SKColor(white: 0.5, alpha: 0.3)
            }
        }
        
        guard !scheduledForMerge.isEmpty else { return }
        
        var toMerge = scheduledForMerge
        scheduledForMerge.removeAll()
        
        while !toMerge.isEmpty {
            let nodeA = toMerge.removeFirst()
            
            // Find a merge partner from the remaining set
            guard let tierA = nodeA.userData?["tier"] as? Int else { continue }
            
            // Ensure nodeA is still in the scene before proceeding
            guard nodeA.parent != nil else { continue }
            
            if let nodeB = toMerge.first(where: { ($0.userData?["tier"] as? Int) == tierA }) {
                toMerge.remove(nodeB) // Partner found and removed from set
                
                // Ensure nodeB is still in the scene
                guard nodeB.parent != nil else { continue }
                
                let nextTier = tierA + 1
                
                // Run Metaball Merge Animation
                // This handles creating the new sphere, animating the merge, and removing the temporary effects
                runMetaballMerge(nodeA: nodeA, nodeB: nodeB, nextTier: nextTier)
                
                // Remove original nodes immediately so they don't interfere physically or visually
                nodeA.removeFromParent()
                nodeB.removeFromParent()
                
                viewModel?.earnScore(points: 1)
                
                #if os(iOS)
                HapticManager.shared.playMergeHaptic()
                #endif
                
            } else {
                // No partner found for nodeA in this batch, maybe it was a 3-way collision.
                // It can try again next frame if it collides with a new partner.
            }
        }
    }
    
    func addPhysics(to sphere: SKSpriteNode) {
        guard sphere.physicsBody == nil,
              let tier = sphere.userData?["tier"] as? Int,
              sphere.size.width > 0
        else { return }
        
        let radius = sphere.size.width / 2
        
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.categoryBitMask = PhysicsCategory.sphere
        body.contactTestBitMask = PhysicsCategory.sphere | PhysicsCategory.dangerZone
        body.collisionBitMask = PhysicsCategory.sphere | PhysicsCategory.wall
        
        // Apply power-up mass multiplier if Super Massive Ball is active
        if let activePowerUps = sphere.userData?["activePowerUps"] as? [String],
           activePowerUps.contains("Super Massive Ball") {
            // Super Massive Ball specific physics properties
            body.restitution = 0.3  // More bouncy
            body.friction = 0.5    // Same as normal spheres
            body.linearDamping = 0.05  // Much less air resistance
            body.angularDamping = 0.05
            
            // Calculate enhanced mass
            let maxTierMass: CGFloat = 12
            let baseMass: CGFloat = 7.5  // 50% of previous value (was 15.0)
            let massMultiplier = pow(2.0, maxTierMass - CGFloat(tier))
            var finalMass = baseMass * massMultiplier * ballScale
            
            if let powerUp = viewModel?.equippedPowerUps.first(where: { $0.name == "Super Massive Ball" }) {
                #if DEBUG
                print("\nApplying Super Massive Ball physics:")
                print("- Power-up level: \(powerUp.level)")
                #endif
                
                let stats = PowerUpStats.baseStats(for: powerUp).scaled(to: powerUp.level)
                finalMass *= CGFloat(stats.massMultiplier)
                
                // Scale the impulse based on the power-up level
                let impulseMultiplier = CGFloat(stats.forceMagnitude) * -600.0  // 50% of previous value (was -1200.0)
                let downwardImpulse = CGVector(dx: 0, dy: impulseMultiplier * finalMass)
                
                #if DEBUG
                print("- Base mass: \(baseMass)")
                print("- Mass multiplier: \(stats.massMultiplier)x")
                print("- Force magnitude: \(stats.forceMagnitude)x")
                print("- Final mass: \(finalMass)")
                print("- Impulse multiplier: \(impulseMultiplier)")
                print("- Final impulse: \(downwardImpulse.dy)")
                #endif
                
                // Apply the impulse after a short delay to ensure physics body is ready
                sphere.run(SKAction.wait(forDuration: 0.1)) {
                    body.applyImpulse(downwardImpulse)
                }
            }
            body.mass = finalMass
        } else {
            // Normal ball physics properties
            body.restitution = 0.1
            body.friction = 0.5 // Base friction for normal spheres
            body.linearDamping = 0.1
            body.angularDamping = 0.1
            
            let maxTierMass: CGFloat = 12
            let baseMass: CGFloat = 10.0
            let massMultiplier = pow(1.5, maxTierMass - CGFloat(tier))
            body.mass = baseMass * massMultiplier * ballScale
        }
        
        // Handle Rubber World effect for all balls
        if let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Rubber World" {
            let newRestitution: CGFloat
            
            switch powerUp.level {
            case 1: newRestitution = 0.7
            case 2: newRestitution = 0.8
            case 3: newRestitution = 0.9
            default: newRestitution = 0.7
            }
            body.restitution = newRestitution
        }
        
        // Handle Ice World effect for all balls
        if let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Ice World" {
            let newFriction = CGFloat(powerUp.currentStats.forceMagnitude)
            body.friction = newFriction
        }
        
        sphere.physicsBody = body
        
        // Add constraint to prevent visual rotation
        let noRotationConstraint = SKConstraint.zRotation(SKRange(constantValue: 0.0))
        sphere.constraints = [noRotationConstraint]
        
        sphere.userData?["creationTime"] = Date().timeIntervalSinceReferenceDate
    }
    
    func didEnd(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if contactMask == (PhysicsCategory.sphere | PhysicsCategory.dangerZone) {
            
            let sphereBody = contact.bodyA.categoryBitMask == PhysicsCategory.sphere ? contact.bodyA : contact.bodyB
            spheresInDangerZone.remove(sphereBody)
            
            if spheresInDangerZone.isEmpty {
                if let line = dangerZone?.childNode(withName: "dangerZoneLine") as? SKShapeNode {
                    line.strokeColor = SKColor(white: 0.5, alpha: 0.3)
                }
            }
        }
    }
    
    // MARK: - Targeting Methods
    private func enterTargetingMode(_ powerUp: PowerUp) {
        guard powerUp.type == .targeting else { return }
        
        targetingPowerUp = powerUp
        targetingState = .primed
        
        // Show targeting circle when entering targeting mode
        showTargetingCircle()
        
        #if DEBUG
        print("Entered targeting mode with power-up: \(powerUp.name)")
        #endif
    }
    
    private func exitTargetingMode() {
        targetingState = .none
        targetingPowerUp = nil
        selectedTarget = nil
        
        // Hide targeting circle when exiting targeting mode
        hideTargetingCircle()
        
        #if DEBUG
        print("Exited targeting mode")
        #endif
    }
    
    private func updateTargetingState(_ newState: TargetingState) {
        let oldState = targetingState
        targetingState = newState
        
        // Update targeting circle visibility based on state changes
        switch newState {
        case .none:
            hideTargetingCircle()
        case .primed:
            if oldState == .none {
                showTargetingCircle()
            }
        case .selecting, .targeted, .active:
            // We'll handle these states when implementing targeting animation
            break
        }
        
        #if DEBUG
        print("Targeting state updated to: \(newState)")
        #endif
    }
    
    // MARK: - Targeting Circle
    private let targetingCircleRadius: CGFloat = 25.0 // Half of base grid spacing
    
    private func calculateTargetingPadding(forTier tier: Int) -> CGFloat {
        // Base padding of 6px for tier 1, scaling up by 2px per tier
        let basePadding: CGFloat = 6.0
        let paddingIncreasePerTier: CGFloat = 2.0
        return basePadding + (CGFloat(tier - 1) * paddingIncreasePerTier)
    }

    private func createTargetingCircle() -> SKShapeNode {
        let circle = SKShapeNode()
        
        // Start with smallest tier radius + scaled padding
        let padding = calculateTargetingPadding(forTier: 1)
        let radius = (GameScene.calculateRadius(forTier: 1) * ballScale) + padding
        let segments = 32
        let segmentAngle = 2 * CGFloat.pi / CGFloat(segments)
        
        // Create dashed segments
        let path = CGMutablePath()
        for i in 0..<segments {
            if i % 2 == 0 { // Draw every other segment
                let startAngle = segmentAngle * CGFloat(i)
                let endAngle = segmentAngle * CGFloat(i + 1)
                
                path.move(to: CGPoint(
                    x: radius * cos(startAngle),
                    y: radius * sin(startAngle)
                ))
                path.addArc(
                    center: .zero,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
            }
        }
        
        circle.path = path
        circle.strokeColor = SKColor.white
        circle.lineWidth = 2.0
        circle.alpha = 0.7
        circle.name = "targetingCircle"
        circle.zPosition = 100
        
        let centerY = frame.height - (frame.height - topBufferHeight) / 2
        circle.position = CGPoint(x: frame.midX, y: centerY)
        
        return circle
    }
    
    private func showTargetingCircle() {
        #if DEBUG
        print("Showing targeting circle")
        #endif
        
        // Remove existing circle if any
        targetingCircle?.removeFromParent()
        
        // Create and add new circle
        let circle = createTargetingCircle()
        addChild(circle)
        targetingCircle = circle
        
        // Add fade-in animation
        circle.alpha = 0
        let fadeIn = SKAction.fadeAlpha(to: 0.7, duration: 0.2)
        circle.run(fadeIn)
        
        #if DEBUG
        print("Added targeting circle to scene, running fade-in animation")
        #endif
    }
    
    private func hideTargetingCircle() {
        guard let circle = targetingCircle else { return }
        
        // Add fade-out animation
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.2)
        let remove = SKAction.removeFromParent()
        let sequence = SKAction.sequence([fadeOut, remove])
        
        circle.run(sequence)
        targetingCircle = nil
    }
    
    // MARK: - Sphere Selection
    private func findSelectableSphere(at position: CGPoint) -> SKSpriteNode? {
        let touchedNodes = nodes(at: position)
        return touchedNodes.first { node in
            guard let sphere = node as? SKSpriteNode,
                  sphere.name == "sphere",
                  sphere !== currentSphere else { return false }
            return true
        } as? SKSpriteNode
    }
    
    private func highlightSphere(_ sphere: SKSpriteNode) {
        // Highlight effect
        sphere.color = .yellow
        sphere.colorBlendFactor = 0.7
        
        // Add subtle scale animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.1)
        sphere.run(scaleUp)
    }
    
    private func unhighlightSphere(_ sphere: SKSpriteNode) {
        // Restore original stroke color
        if let activePowerUps = sphere.userData?["activePowerUps"] as? [String],
           let powerUpName = activePowerUps.first,
           let color = powerUpColors[powerUpName] {
            sphere.color = color
            sphere.colorBlendFactor = 0.7
        } else {
            sphere.colorBlendFactor = 0.0
        }
        
        // Remove scale
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
        sphere.run(scaleDown)
    }
    
    private func selectSphere(_ sphere: SKSpriteNode) {
        // If we already have a selected target, unhighlight it
        if let currentTarget = selectedTarget {
            unhighlightSphere(currentTarget)
        }
        
        selectedTarget = sphere
        updateTargetingState(.targeted)
        
        // Move targeting circle to selected sphere immediately
        guard let targetingCircle = targetingCircle,
              let tier = sphere.userData?["tier"] as? Int else { return }
        
        // Calculate the exact radius for this tier + scaled padding
        let padding = calculateTargetingPadding(forTier: tier)
        let radius = (GameScene.calculateRadius(forTier: tier) * ballScale) + padding
        
        // Create new path with exact size
        let segments = 32
        let segmentAngle = 2 * CGFloat.pi / CGFloat(segments)
        let path = CGMutablePath()
        
        for i in 0..<segments {
            if i % 2 == 0 {
                let startAngle = segmentAngle * CGFloat(i)
                let endAngle = segmentAngle * CGFloat(i + 1)
                
                path.move(to: CGPoint(
                    x: radius * cos(startAngle),
                    y: radius * sin(startAngle)
                ))
                path.addArc(
                    center: .zero,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
            }
        }
        
        targetingCircle.path = path
        targetingCircle.position = sphere.position
        
        // Drop haptics removed to reduce feedback noise
    }
    
    private func deselectSphere() {
        guard let sphere = selectedTarget else { return }
        unhighlightSphere(sphere)
        selectedTarget = nil
        updateTargetingState(.primed)
        
        // Reset targeting circle position and scale immediately
        guard let targetingCircle = targetingCircle else { return }
        
        let centerY = frame.height - (frame.height - topBufferHeight) / 2
        targetingCircle.position = CGPoint(x: frame.midX, y: centerY)
        targetingCircle.setScale(1.0)
    }
    
    private func activateTargetingPowerUp(_ powerUp: PowerUp, on sphere: SKSpriteNode) {
        // Find the power-up in the view model to ensure we're modifying the source of truth
        guard var vmPowerUp = viewModel?.equippedPowerUps.first(where: { $0.id == powerUp.id }) else { return }
        
        // Use a charge, and if successful, apply the effect
        guard vmPowerUp.useCharge() else { return }
        
        // Apply power-up effect based on its name
        switch powerUp.name {
        case "Selective Deletion":
            sphere.removeFromParent()
        default:
            var activePowerUps = sphere.userData?["activePowerUps"] as? [String] ?? []
            activePowerUps.append(powerUp.name)
            sphere.userData?["activePowerUps"] = activePowerUps
            
            if let color = powerUpColors[powerUp.name] {
                sphere.color = color
                sphere.colorBlendFactor = 0.7
            }
        }
        
        // Clean up targeting state in the scene
        exitTargetingMode()
        
        // Reset the power-up state to idle after use
        vmPowerUp.isActive = false
        vmPowerUp.isPrimed = false
        
        // Update all slots in the view model with the modified power-up
        if let viewModel = viewModel {
            for i in viewModel.equippedPowerUps.indices {
                if viewModel.equippedPowerUps[i].id == vmPowerUp.id {
                    viewModel.equippedPowerUps[i] = vmPowerUp
                }
            }
        }

        #if os(iOS)
        HapticManager.shared.playMergeHaptic()
        #endif
        
        #if DEBUG
        print("Activated targeting power-up: \(powerUp.name) on sphere, charge consumed.")
        #endif
    }
    
    // MARK: - Environmental Power-Up Effects
    
    private func applyLowGravityEffect() {
        // Find the active Low Gravity power-up
        guard let powerUp = viewModel?.equippedPowerUps
            .first(where: { $0.name == "Low Gravity" && $0.isActive }) else {
            return
        }
        
        // Low gravity - constant floaty effect at all levels
        // 20% of normal gravity (dy: -1.96) - floaty but balls still move at good speed
        let baseGravity: CGFloat = -9.8
        let gravityMultiplier: CGFloat = 0.20 // 80% reduction - same at all levels
        
        let newGravity = baseGravity * gravityMultiplier
        
        let alreadyApplied = abs(physicsWorld.gravity.dy - newGravity) < 0.001
        
        // Apply the modified gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: newGravity)
        
        #if DEBUG
        if !alreadyApplied {
            print("Applying Low Gravity effect:")
            print("- Power-up level: \(powerUp.level)")
            print("- Gravity multiplier: \(gravityMultiplier)x")
            print("- New gravity: \(newGravity)")
            print("- Gravity reduction: \((1 - gravityMultiplier) * 100)%")
        }
        #endif
    }
    
    private func applyRubberWorldEffect() {
        guard let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Rubber World" else { return }
        
        let newRestitution: CGFloat
        
        switch powerUp.level {
        case 1: newRestitution = 0.7
        case 2: newRestitution = 0.8
        case 3: newRestitution = 0.9
        default: newRestitution = 0.7
        }
        
        let alreadyApplied = abs((self.physicsBody?.restitution ?? 0) - newRestitution) < 0.001
        
        // Update walls
        self.physicsBody?.restitution = newRestitution
        
        // Update existing spheres
        enumerateChildNodes(withName: "sphere") { node, _ in
            node.physicsBody?.restitution = newRestitution
        }
        
        #if DEBUG
        if !alreadyApplied {
            print("Applying Rubber World effect: Level \(powerUp.level), Restitution: \(newRestitution)")
        }
        #endif
    }
    
    private func resetRubberWorldEffect() {
        let alreadyReset = abs((self.physicsBody?.restitution ?? 0) - 0.2) < 0.001
        
        // Reset walls to default
        self.physicsBody?.restitution = 0.2
        
        // Reset existing spheres to their defaults
        enumerateChildNodes(withName: "sphere") { node, _ in
            if let sphereNode = node as? SKSpriteNode,
               let activePowerUps = sphereNode.userData?["activePowerUps"] as? [String],
               activePowerUps.contains("Super Massive Ball") {
                node.physicsBody?.restitution = 0.3 // Super Massive Ball restitution
            } else {
                node.physicsBody?.restitution = 0.1 // Default sphere restitution
            }
        }
        
        #if DEBUG
        if !alreadyReset {
            print("Resetting Rubber World effect")
        }
        #endif
    }
    
    private func applyIceWorldEffect() {
        guard let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Ice World" else { return }
        
        let newFriction = CGFloat(powerUp.currentStats.forceMagnitude)
        
        let alreadyApplied = abs((self.physicsBody?.friction ?? 0) - newFriction) < 0.001
        
        // Update walls
        self.physicsBody?.friction = newFriction
        
        // Update existing spheres
        enumerateChildNodes(withName: "sphere") { node, _ in
            node.physicsBody?.friction = newFriction
        }
        
        #if DEBUG
        if !alreadyApplied {
            print("Applying Ice World effect: Level \(powerUp.level), Friction: \(newFriction)")
        }
        #endif
    }
    
    private func resetIceWorldEffect() {
        let alreadyReset = abs((self.physicsBody?.friction ?? 0) - 0.3) < 0.001
        
        // Reset walls to default
        self.physicsBody?.friction = 0.3 // Wall friction
        
        // Reset existing spheres to their defaults
        enumerateChildNodes(withName: "sphere") { node, _ in
            if let sphereNode = node as? SKSpriteNode,
               let activePowerUps = sphereNode.userData?["activePowerUps"] as? [String],
               activePowerUps.contains("Super Massive Ball") {
                node.physicsBody?.friction = 0.5 // Same as normal spheres
            } else {
                node.physicsBody?.friction = 0.5 // Default sphere friction
            }
        }
        
        #if DEBUG
        if !alreadyReset {
            print("Resetting Ice World effect")
        }
        #endif
    }
    
    private func applyCalmDownEffect() {
        #if DEBUG
        print("Applying calm down effect after Rubber World deactivation.")
        #endif

        let highDamping: CGFloat = 5.0
        let duration: TimeInterval = 1.5

        // Apply high damping to all spheres
        enumerateChildNodes(withName: "sphere") { node, _ in
            if let body = node.physicsBody {
                body.linearDamping = highDamping
                body.angularDamping = highDamping
            }
        }

        // Schedule the reset of damping to default values
        run(SKAction.wait(forDuration: duration)) { [weak self] in
            #if DEBUG
            print("Restoring normal damping after calm down effect.")
            #endif
            self?.enumerateChildNodes(withName: "sphere") { node, _ in
                if let body = node.physicsBody {
                    if let sphereNode = node as? SKSpriteNode,
                       let activePowerUps = sphereNode.userData?["activePowerUps"] as? [String],
                       activePowerUps.contains("Super Massive Ball") {
                        body.linearDamping = 0.05
                        body.angularDamping = 0.05
                    } else {
                        body.linearDamping = 0.1
                        body.angularDamping = 0.1
                    }
                }
            }
        }
    }
    
    private func applyTiltWorldEffect() {
        guard let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Tilt World", let data = motionManager.accelerometerData else { return }

        let sensitivity = powerUp.currentStats.forceMagnitude
        let gravityStrength = 9.8 * sensitivity

        let dx = data.acceleration.x * gravityStrength
        let dy = data.acceleration.y * gravityStrength

        physicsWorld.gravity = CGVector(dx: dx, dy: dy)
    }
    
    func startAccelerometer() {
        guard motionManager.isAccelerometerAvailable else {
            #if DEBUG
            print("Accelerometer is not available on this device.")
            #endif
            return
        }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates()
    }

    func stopAccelerometer() {
        motionManager.stopAccelerometerUpdates()
    }
}

class HapticManager {
    static let shared = HapticManager()
    private var engine: CHHapticEngine?
    private var lastMergeTime: TimeInterval = 0
    private let mergeCooldown: TimeInterval = 0.2 // 200ms cooldown between haptics
    private var queuedHaptics: [TimeInterval] = []
    private var isProcessingQueue = false
    
    init() {
        prepareHaptics()
    }
    
    private func processHapticQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        
        // Process all queued haptics
        while !queuedHaptics.isEmpty {
            let nextHapticTime = queuedHaptics[0]
            let currentTime = Date().timeIntervalSinceReferenceDate
            
            if currentTime >= nextHapticTime {
                queuedHaptics.removeFirst()
                playHapticImmediately()
                lastMergeTime = currentTime
            } else {
                // Wait until the next haptic should be played
                DispatchQueue.main.asyncAfter(deadline: .now() + (nextHapticTime - currentTime)) {
                    self.processHapticQueue()
                }
                break
            }
        }
        
        isProcessingQueue = false
    }
    
    private func playHapticImmediately() {
        guard let engine = engine else { return }
        
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            
            #if DEBUG
            print("Merge haptic played at: \(Date().timeIntervalSinceReferenceDate)")
            #endif
        } catch {
            print("Failed to play merge haptic: \(error.localizedDescription)")
        }
    }
    
    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            // Restart the engine if it stops due to timeout or other reasons
            engine?.resetHandler = { [weak self] in
                self?.prepareHaptics()
            }
            
            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
            }
            
        } catch {
            print("Failed to create haptic engine: \(error.localizedDescription)")
        }
    }
    
    func playMergeHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        let currentTime = Date().timeIntervalSinceReferenceDate
        
        // If we're not in cooldown, play immediately
        if currentTime - lastMergeTime >= mergeCooldown {
            playHapticImmediately()
            lastMergeTime = currentTime
        } else {
            // Queue the haptic to play after the cooldown
            let nextPlayTime = lastMergeTime + mergeCooldown
            queuedHaptics.append(nextPlayTime)
            queuedHaptics.sort() // Keep the queue ordered by time
            
            #if DEBUG
            print("Haptic queued for: \(nextPlayTime)")
            #endif
            
            // Start processing the queue if not already processing
            processHapticQueue()
        }
    }
    
    // Drop haptics removed to reduce feedback noise
}
#else
struct SpriteKitContainer: View {
    @ObservedObject var viewModel: GameViewModel
    
    var body: some View {
        Text("SpriteKit not supported on this platform")
    }
}
#endif

// Add CGFloat extension for convenience
extension CGFloat {
    var half: CGFloat { self / 2.0 }
}

#Preview {
    ContentView()
}
