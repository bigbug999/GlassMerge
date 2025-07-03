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
        case .medium: return 1000
        case .large: return 10000
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
    
    static func baseStats(for powerUp: PowerUp) -> PowerUpStats {
        switch powerUp.name {
        // Single-use power-ups (no duration)
        case "Super Massive Ball":
            return PowerUpStats(duration: nil, forceMagnitude: 0.75, massMultiplier: 2.0)  // Level 1 base stats (50% of previous)
        case "Magnetic Ball":
            return PowerUpStats(duration: nil, forceMagnitude: 0.5)
        case "Negative Ball":
            return PowerUpStats(duration: nil, forceMagnitude: 1.0)
        case "Selective Deletion":
            return PowerUpStats(duration: nil, forceMagnitude: 1.0)
        case "Repulsion Field":
            return PowerUpStats(duration: nil, forceMagnitude: 0.5)
            
        // Environmental power-ups (all need duration)
        case "Low Gravity":
            return PowerUpStats(duration: 30, forceMagnitude: 0.5)
        case "Rubber World":
            return PowerUpStats(duration: 30, forceMagnitude: 1.5)
        case "Ice World":
            return PowerUpStats(duration: 30, forceMagnitude: 0.1)
            
        default:
            return PowerUpStats(duration: nil, forceMagnitude: 1.0)
        }
    }
    
    func scaled(to level: Int) -> PowerUpStats {
        var stats = self
        
        // Duration increases by 15 seconds per level for environment effects
        if stats.duration != nil {
            stats.duration = 30 + (Double(level - 1) * 15)
        }
        
        // Special scaling for Super Massive Ball
        if stats.massMultiplier > 1.0 {  // This identifies Super Massive Ball
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
    var hasBeenOffered: Bool = false
    var slotsOccupied: Int {
        return min(level, PowerUp.maxLevel)  // Cap slots at maxLevel
    }
    
    // Charge system
    var currentCharges: Int = 1  // Start with 1 charge
    var isRecharging: Bool = false
    var mergesUntilRecharge: Int = 0  // Track merges needed for recharge
    var requiredMergesForRecharge: Int {
        switch level {
            case 1: return 50
            case 2: return 40
            case 3: return 20
            default: return 50
        }
    }
    
    var canBeUsed: Bool {
        return currentCharges > 0 && !isRecharging
    }
    
    // Upgrade costs
    var upgradeCost: Int {
        return cost * level
    }
    
    static let maxLevel = 3
    
    // Charge system methods
    mutating func useCharge() -> Bool {
        if canBeUsed {
            currentCharges -= 1
            if currentCharges == 0 {
                startRecharge()
            }
            return true
        }
        return false
    }
    
    mutating func startRecharge() {
        isRecharging = true
        mergesUntilRecharge = requiredMergesForRecharge
    }
    
    mutating func handleMerge() {
        if isRecharging {
            mergesUntilRecharge -= 1
            if mergesUntilRecharge <= 0 {
                completeRecharge()
            }
        }
    }
    
    mutating func completeRecharge() {
        currentCharges = 1
        isRecharging = false
        mergesUntilRecharge = 0
    }
}

class PowerUpManager: ObservableObject {
    @Published var powerUps: [PowerUp] = [
        // SINGLE-USE POWER-UPS (affect next spawned ball)
        PowerUp(
            name: "Super Massive Ball",
            description: "Makes selected ball super dense, applies strong downward impulse on release",
            category: .gravity,
            type: .singleUse,
            icon: "circle.circle.fill",
            isUnlocked: false,
            level: 1,
            cost: 1000
        ),
        PowerUp(
            name: "Magnetic Ball",
            description: "Creates attraction force to same-tier balls",
            category: .magnetism,
            type: .singleUse,
            icon: "bolt.circle.fill",
            isUnlocked: false,
            level: 1,
            cost: 1000
        ),
        PowerUp(
            name: "Negative Ball",
            description: "Single-use deletion tool, removes itself and first ball touched",
            category: .void,
            type: .singleUse,
            icon: "xmark.circle.fill",
            isUnlocked: false,
            level: 1,
            cost: 1000
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
            cost: 1000
        ),
        PowerUp(
            name: "Rubber World",
            description: "Makes all surfaces and balls extremely bouncy",
            category: .physics,
            type: .environment,
            icon: "arrow.up.and.down.circle",
            isUnlocked: false,
            level: 1,
            cost: 1000
        ),
        PowerUp(
            name: "Ice World",
            description: "Makes all surfaces ultra slippery with minimal friction",
            category: .physics,
            type: .environment,
            icon: "snowflake",
            isUnlocked: false,
            level: 1,
            cost: 1000
        ),
        
        // TARGETING POWER-UPS (affect existing balls)
        PowerUp(
            name: "Selective Deletion",
            description: "Tap-to-select mechanic for strategic ball removal",
            category: .void,
            type: .targeting,
            icon: "trash.circle.fill",
            isUnlocked: false,
            level: 1,
            cost: 1000
        ),
        PowerUp(
            name: "Repulsion Field",
            description: "Creates a repulsion zone around selected ball",
            category: .magnetism,
            type: .targeting,
            icon: "rays",
            isUnlocked: false,
            level: 1,
            cost: 1000
        )
    ]
    
    // Game currency and progression
    @Published var currency: Int = 0
    private var gameData: GameData?
    
    // Track which power-ups have been offered in this run
    private var offeredPowerUps = Set<UUID>()

    init() {
        self.gameData = CoreDataManager.shared.getGameData()
        self.loadProgression()
    }

    private func loadProgression() {
        guard let gameData = self.gameData else { return }
        
        self.currency = Int(gameData.currency)
        
        let progressions = gameData.powerUpProgressions as? Set<PowerUpProgression> ?? []
        for progression in progressions {
            if let index = powerUps.firstIndex(where: { $0.name == progression.id }) {
                powerUps[index].isUnlocked = progression.isUnlocked
                powerUps[index].level = Int(progression.level)
            }
        }
    }

    func getUnlockedFlaskSizes() -> Set<FlaskSize> {
        guard let rawSizes = gameData?.unlockedFlaskSizes else { return [.small] }
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
    
    // MARK: - Power-up Management
    
    func unlock(_ powerUp: PowerUp) -> Bool {
        guard let gameData = gameData, !powerUp.isUnlocked && currency >= powerUp.cost else { return false }
        currency -= powerUp.cost
        gameData.currency = Int64(currency)

        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].isUnlocked = true
            // Also update the Core Data progression
            if let progression = (gameData.powerUpProgressions as? Set<PowerUpProgression>)?.first(where: { $0.id == powerUp.name }) {
                progression.isUnlocked = true
            }
        }
        CoreDataManager.shared.saveContext()
        return true
    }
    
    func unlockFlaskSize(_ size: FlaskSize) -> Bool {
        guard let gameData = gameData, !getUnlockedFlaskSizes().contains(size) && currency >= size.cost else { return false }
        currency -= size.cost
        gameData.currency = Int64(currency)
        
        var currentSizes = getUnlockedFlaskSizes()
        currentSizes.insert(size)
        gameData.unlockedFlaskSizes = currentSizes.map { $0.rawValue }.joined(separator: ",")
        
        CoreDataManager.shared.saveContext()
        return true
    }
    
    func upgrade(_ powerUp: PowerUp) -> Bool {
        guard let gameData = gameData, powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && currency >= powerUp.upgradeCost else { return false }
        currency -= powerUp.upgradeCost
        gameData.currency = Int64(currency)

        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].level += 1
             if let progression = (gameData.powerUpProgressions as? Set<PowerUpProgression>)?.first(where: { $0.id == powerUp.name }) {
                progression.level = Int64(powerUps[index].level)
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
}

class GameViewModel: ObservableObject {
    @Published var equippedPowerUps: [PowerUp?] = Array(repeating: nil, count: 6)
    @Published var isLevelUpViewPresented = false
    @Published var powerUpChoices: [PowerUpChoice] = []
    @Published var hasReroll: Bool = true
    @Published var score: Int = 0
    @Published var xp: Int = 0
    @Published var level: Int = 1
    @Published var isGamePaused: Bool = false
    @Published var selectedFlaskSize: FlaskSize = .small
    let xpNeededPerLevel: Int = 10  // Changed from 30 to 10 for testing
    let powerUpManager: PowerUpManager
    private var run: Run?
    var sphereStateProvider: (() -> [Sphere])?
    private var powerUpTimer: Timer?
    
    // Define a type to represent either a new power-up or an upgrade
    enum PowerUpChoice: Identifiable {
        case new(PowerUp)
        case upgrade(PowerUp)
        
        var id: UUID {
            switch self {
            case .new(let powerUp), .upgrade(let powerUp):
                return powerUp.id
            }
        }
        
        var powerUp: PowerUp {
            switch self {
            case .new(let powerUp), .upgrade(let powerUp):
                return powerUp
            }
        }
        
        var isUpgrade: Bool {
            switch self {
            case .new: return false
            case .upgrade: return true
            }
        }
    }
    
    init(powerUpManager: PowerUpManager, gameData: GameData) {
        self.powerUpManager = powerUpManager
        self.run = gameData.currentRun
        
        if let run = self.run {
            self.applyRunState(run)
        }
        
        startPowerUpTimer()
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
        var needsUpdate = false
        
        for i in equippedPowerUps.indices {
            guard var powerUp = equippedPowerUps[i] else { continue }
            
            // Update duration for active environmental power-ups
            if powerUp.type == .environment && powerUp.isActive {
                if powerUp.remainingDuration > 0 {
                    powerUp.remainingDuration = max(0, powerUp.remainingDuration - deltaTime)
                    needsUpdate = true
                    
                    // Deactivate if duration is up
                    if powerUp.remainingDuration == 0 {
                        powerUp.isActive = false
                        powerUp.isPrimed = false
                        #if DEBUG
                        print("\(powerUp.name) deactivated due to duration end!")
                        #endif
                    }
                }
            }
            
            if needsUpdate {
                // Update all slots for this power up
                let idToUpdate = powerUp.id
                for j in equippedPowerUps.indices {
                    if equippedPowerUps[j]?.id == idToUpdate {
                        equippedPowerUps[j] = powerUp
                    }
                }
            }
        }
    }
    
    private func applyRunState(_ run: Run) {
        // Restore run state
        self.score = Int(run.score)
        self.xp = Int(run.xp)
        self.level = Int(run.level)
        self.selectedFlaskSize = FlaskSize(rawValue: run.selectedFlaskSize ?? "small") ?? .small
        
        // Restore equipped power-ups
        equippedPowerUps = Array(repeating: nil, count: 6)
        if let equipped = run.equippedPowerUps as? Set<EquippedPowerUp> {
            for savedPowerUp in equipped {
                guard let basePowerUp = powerUpManager.powerUps.first(where: { $0.name == savedPowerUp.id }) else { continue }
                var instance = basePowerUp
                instance.level = Int(savedPowerUp.level)
                instance.slotIndex = Int(savedPowerUp.slotIndex)
                instance.isActive = savedPowerUp.isActive
                instance.isPrimed = savedPowerUp.isPrimed
                instance.remainingDuration = savedPowerUp.remainingDuration
                instance.currentCharges = Int(savedPowerUp.currentCharges)
                instance.isRecharging = savedPowerUp.isRecharging
                instance.mergesUntilRecharge = Int(savedPowerUp.mergesUntilRecharge)
                
                let slotIndex = Int(savedPowerUp.slotIndex)
                if slotIndex >= 0 && slotIndex < equippedPowerUps.count {
                     equippedPowerUps[slotIndex] = instance
                }

                // If this is an active environmental power-up, make sure the timer is running
                if instance.type == .environment && instance.isActive && instance.remainingDuration > 0 {
                    #if DEBUG
                    print("Restored active environmental power-up: \(instance.name) with \(instance.remainingDuration)s remaining")
                    #endif
                }
                
                // Log recharge state if recharging
                #if DEBUG
                if instance.isRecharging {
                    print("Restored recharging power-up: \(instance.name) with \(instance.mergesUntilRecharge) merges remaining")
                }
                #endif
            }
        }

        #if DEBUG
        print("GameViewModel: Restored from Core Data Run object.")
        #endif
    }
    
    private func hasEnoughSlotsForUpgrade(_ powerUp: PowerUp) -> Bool {
        let neededSlots = powerUp.level + 1 // Next level needs this many slots
        
        #if DEBUG
        print("\nChecking upgrade possibility for \(powerUp.name):")
        print("Current level: \(powerUp.level)")
        print("Slots needed: \(neededSlots)")
        #endif
        
        // First try to find slots around the current position
        if let currentIndex = powerUp.slotIndex ?? equippedPowerUps.firstIndex(where: { $0?.id == powerUp.id }) {
            // Check slots before current position
            var beforeSlots = 0
            for i in (0..<currentIndex).reversed() {
                if equippedPowerUps[i] == nil {
                    beforeSlots += 1
                } else {
                    break
                }
            }
            
            // Check current position and slots after
            var afterSlots = 1  // Count current position
            for i in (currentIndex + 1)..<equippedPowerUps.count {
                if equippedPowerUps[i] == nil || equippedPowerUps[i]?.id == powerUp.id {
                    afterSlots += 1
                } else {
                    break
                }
            }
            
            let totalAdjacentSlots = beforeSlots + afterSlots
            
            #if DEBUG
            print("Adjacent slots check:")
            print("- Before current position: \(beforeSlots)")
            print("- After current position: \(afterSlots)")
            print("- Total adjacent: \(totalAdjacentSlots)")
            #endif
            
            if totalAdjacentSlots >= neededSlots {
                #if DEBUG
                print("✅ Found enough adjacent slots!")
                #endif
                return true
            }
        }
        
        // If we can't find enough adjacent slots, look for any consecutive empty slots
        var consecutiveEmptySlots = 0
        var maxConsecutiveEmpty = 0
        
        for (_, slot) in equippedPowerUps.enumerated() {
            if slot == nil {
                consecutiveEmptySlots += 1
                maxConsecutiveEmpty = max(maxConsecutiveEmpty, consecutiveEmptySlots)
            } else if slot?.id != powerUp.id {
                consecutiveEmptySlots = 0
            }
        }
        
        #if DEBUG
        print("Consecutive empty slots check:")
        print("- Maximum consecutive empty slots: \(maxConsecutiveEmpty)")
        print("- Needed slots: \(neededSlots)")
        print(maxConsecutiveEmpty >= neededSlots ? "✅ Found enough consecutive empty slots!" : "❌ Not enough consecutive slots available")
        #endif
        
        return maxConsecutiveEmpty >= neededSlots
    }
    
    func presentLevelUpChoices() {
        let hasEmptySlot = equippedPowerUps.contains(where: { $0 == nil })
        
        #if DEBUG
        print("\n=== Level Up Choices Debug ===")
        print("Current equipped power-ups:")
        for (index, powerUp) in equippedPowerUps.enumerated() {
            if let powerUp = powerUp {
                print("Slot \(index): \(powerUp.name) (Level \(powerUp.level))")
            } else {
                print("Slot \(index): Empty")
            }
        }
        #endif
        
        // Get ALL equipped power-ups that aren't max level and have enough slots for upgrade
        let upgradeablePowerUps = equippedPowerUps.compactMap { powerUp -> PowerUp? in
            guard let powerUp = powerUp,
                  powerUp.level < PowerUp.maxLevel else { return nil }
            
            let hasSlots = hasEnoughSlotsForUpgrade(powerUp)
            
            #if DEBUG
            print("\nPower-up upgrade check: \(powerUp.name)")
            print("- Current level: \(powerUp.level)")
            print("- Max level: \(PowerUp.maxLevel)")
            print("- Has enough slots: \(hasSlots)")
            #endif
            
            return hasSlots ? powerUp : nil
        }
        
        // Don't show level up screen if no slots available and no upgrades possible
        guard hasEmptySlot || !upgradeablePowerUps.isEmpty else {
            #if DEBUG
            print("\nNo level up screen shown:")
            print("- Has empty slot: \(hasEmptySlot)")
            print("- Upgradeable power-ups count: \(upgradeablePowerUps.count)")
            #endif
            return
        }
        
        var choices: [PowerUpChoice] = []
        var seenPowerUpNames = Set<String>()
        
        // Get available new power-ups if there are empty slots
        if hasEmptySlot {
            let availablePowerUps = powerUpManager.getAvailablePowerUps()
                .filter { powerUp in
                    !seenPowerUpNames.contains(powerUp.name) &&
                    !equippedPowerUps.contains(where: { $0?.name == powerUp.name })
                }
            
            let newPowerUps = availablePowerUps.shuffled()
            
            // Add up to 3 new power-ups
            for powerUp in newPowerUps.prefix(3) {
                choices.append(PowerUpChoice.new(powerUp))
                seenPowerUpNames.insert(powerUp.name)
                
                #if DEBUG
                print("\nAdded new power-up choice:")
                print("- Power-up: \(powerUp.name)")
                #endif
            }
        }
        
        // If we have less than 3 choices and upgrades are available,
        // fill remaining slots with upgrades
        if choices.count < 3 && !upgradeablePowerUps.isEmpty {
            let shuffledUpgrades = upgradeablePowerUps.shuffled()
            let slotsToFill = 3 - choices.count
            let upgradesForMainSlots = shuffledUpgrades.prefix(slotsToFill)
            
            for powerUp in upgradesForMainSlots {
                choices.append(PowerUpChoice.upgrade(powerUp))
                seenPowerUpNames.insert(powerUp.name)
                
                #if DEBUG
                print("\nAdded upgrade choice to main slots:")
                print("- Power-up: \(powerUp.name)")
                print("- Current Level: \(powerUp.level)")
                print("- Next Level: \(powerUp.level + 1)")
                #endif
            }
        }
        
        // Ensure we have exactly 3 main choices
        choices = Array(choices.prefix(3))
        
        // If we have upgradeable power-ups that weren't used in the main slots,
        // add one as a fourth choice
        if !upgradeablePowerUps.isEmpty {
            let remainingUpgrades = upgradeablePowerUps.filter { powerUp in
                !seenPowerUpNames.contains(powerUp.name)
            }
            
            if let extraUpgrade = remainingUpgrades.randomElement() {
                choices.append(PowerUpChoice.upgrade(extraUpgrade))
                
                #if DEBUG
                print("\nAdded extra upgrade choice in fourth slot:")
                print("- Power-up: \(extraUpgrade.name)")
                print("- Current Level: \(extraUpgrade.level)")
                print("- Next Level: \(extraUpgrade.level + 1)")
                #endif
            }
        }
        
        // Shuffle only the first 3 choices, keeping any fourth upgrade choice in place
        let mainChoices = Array(choices.prefix(3)).shuffled()
        let extraChoice = choices.count > 3 ? [choices[3]] : []
        powerUpChoices = mainChoices + extraChoice
        
        #if DEBUG
        print("\nFinal choices (\(powerUpChoices.count)):")
        for (index, choice) in powerUpChoices.enumerated() {
            switch choice {
            case .new(let powerUp):
                print("\(index + 1). New: \(powerUp.name)")
            case .upgrade(let powerUp):
                print("\(index + 1). Upgrade: \(powerUp.name) (Level \(powerUp.level) → \(powerUp.level + 1))")
            }
        }
        print("=== End Debug ===\n")
        #endif
        
        isLevelUpViewPresented = true
        saveGameState()
    }
    
    func rerollChoices() {
        guard hasReroll else { return }
        hasReroll = false
        presentLevelUpChoices()
    }
    
    func skipLevelUp() {
        isLevelUpViewPresented = false
    }
    
    func selectPowerUp(_ choice: PowerUpChoice) {
        switch choice {
        case .new(let powerUp):
            powerUpManager.markAsOffered(powerUp)
            addNewPowerUp(powerUp)
        case .upgrade(let powerUp):
            upgradePowerUp(powerUp)
        }
        isLevelUpViewPresented = false
        saveGameState() // Save after applying choice
    }
    
    func activatePowerUp(_ powerUpToActivate: PowerUp) {
        // Find the power-up in equipped slots
        guard let index = equippedPowerUps.firstIndex(where: { $0?.id == powerUpToActivate.id }),
              var powerUp = equippedPowerUps[index] else { return }
        
        #if DEBUG
        print("Activating power-up: \(powerUp.name), type: \(powerUp.type), current state - isPrimed: \(powerUp.isPrimed), isActive: \(powerUp.isActive)")
        #endif
        
        // If already active, just deactivate it (but only for non-single-use or if manually toggling)
        if powerUp.isActive && (powerUp.type != .singleUse || !powerUp.canBeUsed) {
            powerUp.isActive = false
            powerUp.isPrimed = false
            #if DEBUG
            print("\(powerUp.name) deactivated!")
            #endif
            
            // Update all slots and return
            let idToUpdate = powerUp.id
            for i in equippedPowerUps.indices {
                if equippedPowerUps[i]?.id == idToUpdate {
                    equippedPowerUps[i] = powerUp
                }
            }
            return
        }
        
        // Check if power-up can be used
        guard powerUp.canBeUsed else {
            #if DEBUG
            print("Cannot activate \(powerUp.name): no charges available or recharging")
            #endif
            return
        }
        
        // Handle targeting power-ups differently
        if powerUp.type == .targeting {
            // ... existing targeting code ...
        }
        // Handle environmental power-ups
        else if powerUp.type == .environment {
            // If already active, do nothing (can only be deactivated by timer)
            if powerUp.isActive {
                return
            }

            // Deactivate any other active environmental power-ups
            for i in equippedPowerUps.indices {
                if var otherPowerUp = equippedPowerUps[i],
                   otherPowerUp.id != powerUp.id,
                   otherPowerUp.type == .environment,
                   otherPowerUp.isActive {
                    otherPowerUp.isActive = false
                    otherPowerUp.isPrimed = false // also reset primed state just in case
                    
                    // Update all slots for this other power-up
                    let idToUpdate = otherPowerUp.id
                    for j in equippedPowerUps.indices {
                        if equippedPowerUps[j]?.id == idToUpdate {
                            equippedPowerUps[j] = otherPowerUp
                        }
                    }
                    
                    #if DEBUG
                    print("\(otherPowerUp.name) deactivated due to new environmental activation!")
                    #endif
                }
            }

            // Activate the selected power-up
            if powerUp.useCharge() {
                powerUp.isActive = true
                powerUp.isPrimed = false // No more priming
                powerUp.remainingDuration = powerUp.currentStats.duration ?? 0
                #if DEBUG
                print("\(powerUp.name) activated with duration: \(powerUp.remainingDuration)s!")
                #endif
            }
        }
        // Handle single-use power-ups
        else {
            // Deactivate any other active single-use power-ups
            for i in equippedPowerUps.indices {
                if var otherPowerUp = equippedPowerUps[i],
                   otherPowerUp.id != powerUp.id,
                   otherPowerUp.type == .singleUse,
                   otherPowerUp.isActive {
                    otherPowerUp.isActive = false
                    #if DEBUG
                    print("\(otherPowerUp.name) deactivated due to new activation!")
                    #endif
                    
                    // Update all slots for this power up
                    let idToUpdate = otherPowerUp.id
                    for j in equippedPowerUps.indices {
                        if equippedPowerUps[j]?.id == idToUpdate {
                            equippedPowerUps[j] = otherPowerUp
                        }
                    }
                }
            }
            
            // Just activate the power-up, charge will be consumed when used
            powerUp.isActive = true
            #if DEBUG
            print("\(powerUp.name) activated! Will consume charge when used.")
            #endif
        }
        
        // Update all slots for this power up
        let idToUpdate = powerUp.id
        for i in equippedPowerUps.indices {
            if equippedPowerUps[i]?.id == idToUpdate {
                equippedPowerUps[i] = powerUp
            }
        }
    }
    
    // Call this when a single-use power-up's effect is actually applied
    func consumeSingleUsePowerUp(_ powerUpName: String) {
        for i in equippedPowerUps.indices {
            if var powerUp = equippedPowerUps[i],
               powerUp.name == powerUpName,
               powerUp.type == .singleUse,
               powerUp.isActive {
                if powerUp.useCharge() {
                    powerUp.isActive = false
                    // Update all slots for this power-up
                    let idToUpdate = powerUp.id
                    for j in equippedPowerUps.indices {
                        if equippedPowerUps[j]?.id == idToUpdate {
                            equippedPowerUps[j] = powerUp
                        }
                    }
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
            if var slotPowerUp = equippedPowerUps[i],
               slotPowerUp.id == powerUp.id {
                slotPowerUp.isActive = false
                equippedPowerUps[i] = slotPowerUp
                
                #if DEBUG
                print("\(powerUp.name) auto-deactivated after use!")
                #endif
            }
        }
    }
    
    private func addNewPowerUp(_ powerUp: PowerUp) {
        var newPowerUp = powerUp
        newPowerUp.hasBeenOffered = true
        
        // Find first empty slot
        if let startIndex = findFirstEmptySlot() {
            newPowerUp.slotIndex = startIndex
            equippedPowerUps[startIndex] = newPowerUp
            
            // Mark the power-up as offered in the manager
            if let index = powerUpManager.powerUps.firstIndex(where: { $0.id == powerUp.id }) {
                powerUpManager.powerUps[index].hasBeenOffered = true
            }
        }
    }
    
    private func upgradePowerUp(_ powerUp: PowerUp) {
        // Find all instances of this power-up
        let instances = equippedPowerUps.enumerated()
            .filter { $0.element?.id == powerUp.id }
            .map { $0.offset }
        
        guard let startIndex = instances.first else { return }
        
        // Create upgraded version, preserving active state
        var upgradedPowerUp = powerUp
        upgradedPowerUp.level += 1
        upgradedPowerUp.slotIndex = startIndex
        upgradedPowerUp.isActive = powerUp.isActive // Preserve active state during upgrade
        
        // Calculate how many slots we need
        let slotsNeeded = upgradedPowerUp.slotsOccupied
        
        // Check if we have enough consecutive slots without overwriting other power-ups
        var availableSlots: [Int] = []
        var consecutiveSlots = 0
        var bestStartIndex = startIndex
        var maxConsecutiveSlots = 0
        
        // First, try to find slots around the current position
        for i in 0..<equippedPowerUps.count {
            if equippedPowerUps[i] == nil || equippedPowerUps[i]?.id == powerUp.id {
                consecutiveSlots += 1
                availableSlots.append(i)
                
                if consecutiveSlots > maxConsecutiveSlots {
                    maxConsecutiveSlots = consecutiveSlots
                    bestStartIndex = i - (consecutiveSlots - 1)
                }
            } else {
                consecutiveSlots = 0
                availableSlots = []
            }
            
            // If we found enough slots, break
            if consecutiveSlots >= slotsNeeded {
                break
            }
        }
        
        #if DEBUG
        print("\nUpgrading power-up: \(powerUp.name)")
        print("- From level: \(powerUp.level)")
        print("- To level: \(upgradedPowerUp.level)")
        print("- Slots needed: \(slotsNeeded)")
        print("- Best start index: \(bestStartIndex)")
        print("- Max consecutive slots: \(maxConsecutiveSlots)")
        #endif
        
        // Check if we found enough consecutive slots
        guard maxConsecutiveSlots >= slotsNeeded else {
            #if DEBUG
            print("❌ Not enough consecutive slots available for upgrade!")
            #endif
            return
        }
        
        // Clear only the slots that were occupied by this power-up
        for index in instances {
            clearSlotsForPowerUp(startingAt: index)
        }
        
        // Place upgraded version in consecutive slots starting at the best position
        for i in 0..<slotsNeeded {
            let slotIndex = bestStartIndex + i
            if slotIndex < equippedPowerUps.count {
                equippedPowerUps[slotIndex] = upgradedPowerUp
            }
        }
        
        #if DEBUG
        print("✅ Power-up upgraded successfully")
        print("Current slot state:")
        for (index, slot) in equippedPowerUps.enumerated() {
            if let powerUp = slot {
                print("Slot \(index): \(powerUp.name) (Level \(powerUp.level))")
            } else {
                print("Slot \(index): Empty")
            }
        }
        #endif
    }
    
    private func findFirstEmptySlot() -> Int? {
        var consecutiveEmpty = 0
        var startIndex: Int?
        
        for (index, slot) in equippedPowerUps.enumerated() {
            if slot == nil {
                if startIndex == nil {
                    startIndex = index
                }
                consecutiveEmpty += 1
                if consecutiveEmpty >= 1 { // For new power-ups, we only need 1 slot
                    return startIndex
                }
            } else {
                consecutiveEmpty = 0
                startIndex = nil
            }
        }
        return nil
    }
    
    private func clearSlotsForPowerUp(startingAt index: Int) {
        let powerUp = equippedPowerUps[index]
        guard let powerUp = powerUp else { return }
        
        // Find all slots occupied by this power-up instance
        let slotsToCheck = min(index + powerUp.slotsOccupied, equippedPowerUps.count)
        for i in index..<slotsToCheck {
            if equippedPowerUps[i]?.id == powerUp.id {
                equippedPowerUps[i] = nil
            }
        }
    }
    
    // MARK: - Saving
    func saveGameState() {
        guard let run = self.run else { return }

        // Update run stats
        run.score = Int64(score)
        run.level = Int64(level)
        run.xp = Int64(xp)
        run.selectedFlaskSize = selectedFlaskSize.rawValue

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
            guard let powerUp = powerUp else { continue }
            
            let equipped = EquippedPowerUp(context: context)
            equipped.id = powerUp.name
            equipped.level = Int64(powerUp.level)
            equipped.slotIndex = Int64(powerUp.slotIndex ?? index)
            equipped.isActive = powerUp.isActive
            equipped.isPrimed = powerUp.isPrimed
            equipped.remainingDuration = powerUp.remainingDuration
            equipped.type = powerUp.type.rawValue
            equipped.currentCharges = Int64(powerUp.currentCharges)
            equipped.isRecharging = powerUp.isRecharging
            equipped.mergesUntilRecharge = Int64(powerUp.mergesUntilRecharge)
            equippedToSave.append(equipped)
        }
        run.addToEquippedPowerUps(NSSet(array: equippedToSave))

        CoreDataManager.shared.saveContext()
        #if DEBUG
        print("[CoreData] Game state saved.")
        #endif
    }
    
    func earnScore(points: Int = 1) {
        score += points
        xp += points
        
        // Handle power-up recharging on merge
        for i in equippedPowerUps.indices {
            if var powerUp = equippedPowerUps[i] {
                powerUp.handleMerge()
                equippedPowerUps[i] = powerUp
                
                #if DEBUG
                if powerUp.isRecharging {
                    print("Power-up \(powerUp.name) recharging: \(powerUp.mergesUntilRecharge) merges remaining")
                }
                #endif
            }
        }
        
        #if DEBUG
        print("EarnScore: score=\(score) xp=\(xp)/\(xpNeededPerLevel) level=\(level)")
        #endif
        if xp >= xpNeededPerLevel {
            xp -= xpNeededPerLevel
            level += 1
            #if DEBUG
            print("LEVEL UP! new level=\(level) xp reset to \(xp)")
            #endif
            presentLevelUpChoices()
        }
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
        xp = 0
        level = 1
        equippedPowerUps = Array(repeating: nil, count: 6)
        powerUpChoices = []
        hasReroll = true
        isLevelUpViewPresented = false
        if let run = self.run {
             CoreDataManager.shared.context.delete(run)
             CoreDataManager.shared.saveContext()
        }
        self.run = nil
        selectedFlaskSize = .small
        powerUpManager.resetOfferedPowerUps() // Reset offered power-ups when starting new game
    }
}

struct ContentView: View {
    @State private var currentScreen: GameScreen = .mainMenu
    @State private var gameData: GameData? = nil
    
    enum GameScreen {
        case mainMenu
        case game
        case upgradeShop
        case collection
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
                case .collection:
                    CollectionView(currentScreen: $currentScreen)
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
        .preferredColorScheme(.dark)
    }
}

struct MainMenuView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @State private var hasSave: Bool = CoreDataManager.shared.hasActiveRun()
    var onNewGame: (() -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Glass Merge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(spacing: 15) {
                Button("New Game") {
                    onNewGame?()
                    currentScreen = .runSetup
                }
                .buttonStyle(.borderedProminent)
                
                Button("Continue") {
                    onContinue?()
                    currentScreen = .game
                }
                .buttonStyle(.bordered)
                .disabled(!hasSave)
                
                Button("Upgrade Shop") {
                    currentScreen = .upgradeShop
                }
                .buttonStyle(.bordered)
                
                Button("Collection") {
                    currentScreen = .collection
                }
                .buttonStyle(.bordered)
                
                Button("Settings") {
                    currentScreen = .settings
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onAppear {
            hasSave = CoreDataManager.shared.hasActiveRun()
        }
    }
}

struct RunSetupView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @StateObject private var powerUpManager = PowerUpManager()
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
    @StateObject private var powerUpManager = PowerUpManager()
    @StateObject private var viewModel: GameViewModel
    @State private var isPaused: Bool = false
    @State private var isGameOver: Bool = false
    // Add auto-save timer
    private let autoSaveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    init(currentScreen: Binding<ContentView.GameScreen>, gameData: GameData) {
        self._currentScreen = currentScreen
        let manager = PowerUpManager()
        self._powerUpManager = StateObject(wrappedValue: manager)
        self._viewModel = StateObject(wrappedValue: GameViewModel(powerUpManager: manager, gameData: gameData))
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Text("Score: \(viewModel.score)")
                        .font(.headline)
                    Spacer()
                    ProgressView(value: Double(viewModel.xp), total: Double(viewModel.xpNeededPerLevel))
                        .progressViewStyle(.linear)
                        .frame(width: 150)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Lv\(viewModel.level)")
                            .font(.headline)
                        Button(action: {
                            isPaused = true
                        }) {
                            Image(systemName: "pause.circle.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
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
                
                Spacer()
                
                PowerUpSlotView(powerUps: $viewModel.equippedPowerUps, onActivate: viewModel.activatePowerUp)
                    .padding(.bottom)
            }
            
            if isPaused {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                PauseMenuView(isPaused: $isPaused, currentScreen: $currentScreen, onMainMenu: {
                    viewModel.saveGameState()
                })
            }
            
            if isGameOver {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                
                GameOverView(
                    score: viewModel.score,
                    onMainMenu: {
                        currentScreen = .mainMenu
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.isLevelUpViewPresented) {
            LevelUpView(viewModel: viewModel)
        }
        .onChange(of: isPaused) { _, newValue in
            viewModel.isGamePaused = newValue
            if newValue {
                viewModel.saveGameState()
            }
        }
        .onChange(of: viewModel.isLevelUpViewPresented) { _, _ in
            // Physics will pause automatically due to updateUIView
        }
        // Add auto-save timer subscription
        .onReceive(autoSaveTimer) { _ in
            if !isPaused && !isGameOver && !viewModel.isLevelUpViewPresented {
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
    @Binding var powerUps: [PowerUp?]
    let onActivate: (PowerUp) -> Void
    let slotSize: CGFloat = 50
    let spacing: CGFloat = 12
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<6) { index in
                if shouldDrawSlot(at: index) {
                    PowerUpSlot(
                        powerUp: powerUps[index],
                        isPartOfMultiSlot: isPartOfMultiSlot(index),
                        isFirstSlot: isFirstSlotOfPowerUp(index),
                        totalSlots: slotsForPowerUp(at: index)
                    )
                    .frame(width: calculateSlotWidth(for: index))
                    .onTapGesture {
                        if let powerUp = powerUps[index] {
                            onActivate(powerUp)
                        }
                    }
                }
            }
        }
    }
    
    private func shouldDrawSlot(at index: Int) -> Bool {
        // Only draw if this is the first slot of a power-up or an empty slot
        if powerUps[index] != nil {
            return isFirstSlotOfPowerUp(index)
        }
        return true // Empty slots always draw
    }
    
    private func isFirstSlotOfPowerUp(_ index: Int) -> Bool {
        guard let currentPowerUp = powerUps[index] else { return false }
        return index == 0 || powerUps[index - 1]?.id != currentPowerUp.id
    }
    
    private func isPartOfMultiSlot(_ index: Int) -> Bool {
        guard let currentPowerUp = powerUps[index] else { return false }
        return currentPowerUp.slotsOccupied > 1
    }
    
    private func slotsForPowerUp(at index: Int) -> Int {
        return powerUps[index]?.slotsOccupied ?? 1
    }
    
    private func calculateSlotWidth(for index: Int) -> CGFloat {
        guard let powerUp = powerUps[index], isFirstSlotOfPowerUp(index) else {
            return slotSize
        }
        let slots = CGFloat(powerUp.slotsOccupied)
        return slotSize * slots + spacing * (slots - 1)
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
    
    private var strokeColor: Color {
        guard let powerUp = powerUp else { return Color.gray.opacity(0.3) }
        
        // If power-up can't be used, show muted colors
        if !powerUp.canBeUsed {
            if powerUp.isActive {
                return .blue.opacity(0.3)
            }
            if powerUp.isPrimed { // For targeting power-ups
                return .blue.opacity(0.15)
            }
            return Color.gray.opacity(0.15)
        }
        
        if powerUp.isActive {
            return .blue
        }
        
        if powerUp.isPrimed { // For targeting power-ups
            return .blue.opacity(0.5)
        }
        
        return Color.gray.opacity(0.3)
    }
    
    private var strokeWidth: CGFloat {
        guard let powerUp = powerUp else { return 2 }
        return (powerUp.isActive || powerUp.isPrimed) ? 3 : 2
    }
    
    private var rechargeProgress: CGFloat {
        guard let powerUp = powerUp,
              powerUp.isRecharging,
              powerUp.requiredMergesForRecharge > 0 else { return 0 }
        let progress = 1.0 - (CGFloat(powerUp.mergesUntilRecharge) / CGFloat(powerUp.requiredMergesForRecharge))
        return max(0.0, min(1.0, progress)) // Clamp progress between 0 and 1
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background and border
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
                
                // Duration progress for active environmental power-ups
                if let powerUp = powerUp,
                   powerUp.type == .environment,
                   powerUp.isActive,
                   let duration = powerUp.currentStats.duration {
                    let progress = powerUp.remainingDuration / duration
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(strokeColor.opacity(0.3), lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 40)
                }
                
                // Icon and level
                Group {
                    if let powerUp = powerUp {
                        VStack(spacing: 2) {
                            Image(systemName: powerUp.icon)
                                .foregroundColor(powerUp.canBeUsed ? 
                                    (powerUp.isActive ? .blue : .blue.opacity(powerUp.isPrimed ? 0.5 : 1)) :
                                    .gray)
                                .font(.system(size: 20))
                            
                            if powerUp.level > 1 {
                                Text("Lv\(powerUp.level)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                            
                            // Show recharge count if recharging
                            if powerUp.isRecharging {
                                Text("\(powerUp.mergesUntilRecharge)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.system(size: 20))
                    }
                }
                
                // Recharge progress bar at bottom
                if let powerUp = powerUp, powerUp.isRecharging {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: geometry.size.width * rechargeProgress, height: 3)
                        .position(x: geometry.size.width * rechargeProgress / 2, y: geometry.size.height - 2)
                }
            }
        }
        .frame(height: 50)
    }
}

struct PauseMenuView: View {
    @Binding var isPaused: Bool
    @Binding var currentScreen: ContentView.GameScreen
    var onMainMenu: (() -> Void)? = nil
    
    var body: some View {
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

struct UpgradeShopView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @StateObject private var powerUpManager = PowerUpManager()
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
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
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(powerUpManager.powerUps) { powerUp in
                        VStack {
                            PowerUpSlot(powerUp: powerUp)
                            Text(powerUp.name)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            Text("\(powerUp.cost) coins")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct CollectionView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @StateObject private var powerUpManager = PowerUpManager()
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
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
            
            Text("Collection")
                .font(.title)
                .padding(.bottom)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(powerUpManager.powerUps) { powerUp in
                        VStack {
                            PowerUpSlot(powerUp: powerUp)
                            Text(powerUp.name)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            Text("Level \(powerUp.level)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

struct SettingsView: View {
    @Binding var currentScreen: ContentView.GameScreen
    
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
            
            Spacer()
            Text("Settings")
                .font(.title)
            Spacer()
        }
    }
}

struct LevelUpView: View {
    @ObservedObject var viewModel: GameViewModel
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Text("Choose Power-up")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(spacing: 12) {
                    ForEach(viewModel.powerUpChoices) { choice in
                        PowerUpChoiceCard(choice: choice) {
                            viewModel.selectPowerUp(choice)
                        }
                        .frame(maxWidth: 220) // narrower card width for vertical layout
                    }
                }
                
                HStack(spacing: 16) {
                    Button(action: {
                        viewModel.skipLevelUp()
                    }) {
                        Text("Skip")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.bordered)
                    
                    if viewModel.hasReroll {
                        Button(action: {
                            viewModel.rerollChoices()
                        }) {
                            Text("Reroll")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.15))
            )
        }
    }
}

struct PowerUpChoiceCard: View {
    let choice: GameViewModel.PowerUpChoice
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: choice.powerUp.icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(spacing: 2) {
                    Text(choice.powerUp.name)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if choice.isUpgrade {
                        Text("Upgrade to Lv\(choice.powerUp.level + 1)")
                            .font(.caption2)
                            .foregroundColor(.green)  // Make upgrade text green to stand out
                    }
                }
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: choice.isUpgrade ? 0.25 : 0.2))  // Slightly different background for upgrades
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(choice.isUpgrade ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct GameOverView: View {
    let score: Int
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
        view.showsFPS = true
        view.showsNodeCount = true
        
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
            scene.isPaused = viewModel.isGamePaused || viewModel.isLevelUpViewPresented
            
            // Update grid and ball sizes when flask size changes
            if scene.viewModel?.selectedFlaskSize != viewModel.selectedFlaskSize {
                scene.updateFlaskSize()
            }
        }
    }
}

class GameScene: SKScene, SKPhysicsContactDelegate {
    weak var viewModel: GameViewModel?
    
    private var currentSphere: SKShapeNode?
    private var isTransitioning = false
    private var dangerZone: SKShapeNode?
    private var spheresInDangerZone = Set<SKPhysicsBody>()
    private let topBufferHeight: CGFloat = 80
    private let dangerGracePeriod: TimeInterval = 3.0
    private let gameOverThreshold: TimeInterval = 5.0
    private var dangerStartTime: TimeInterval?
    private var gridNode: SKNode?
    private var environmentalBorder: SKShapeNode?
    
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
    private var selectedTarget: SKShapeNode?
    private var targetingCircle: SKShapeNode?
    
    // Define power-up colors
    private let powerUpColors: [String: SKColor] = [
        // Single-use power-ups
        "Super Massive Ball": SKColor(Color.blue),
        "Magnetic Ball": SKColor(Color.purple),
        "Negative Ball": SKColor(Color.red),
        
        // Environmental power-ups
        "Low Gravity": SKColor(Color.blue),
        "Rubber World": SKColor(Color.green),
        "Ice World": SKColor(Color.cyan),
        
        // Targeting power-ups
        "Selective Deletion": SKColor(Color.red.opacity(0.7)),
        "Repulsion Field": SKColor(Color.orange)
    ]
    
    // Helper for checking active power-ups
    private func hasActivePowerUp(_ name: String) -> Bool {
        return viewModel?.equippedPowerUps.contains(where: { powerUp in
            powerUp?.name == name && powerUp?.isActive == true
        }) ?? false
    }
    
    // Environmental power-up colors with opacity variants
    private func getEnvironmentalColor(for powerUpName: String) -> SKColor {
        return powerUpColors[powerUpName] ?? SKColor(Color.blue)
    }
    
    // Update the border color method
    private func updateEnvironmentalBorder() {
        if let powerUp = getActiveEnvironmentalPowerUp() {
            let color = getEnvironmentalColor(for: powerUp.name)
            environmentalBorder?.strokeColor = color
            
            // Apply environmental physics effects
            switch powerUp.name {
            case "Low Gravity":
                resetRubberWorldEffect()
                applyLowGravityEffect()
            case "Rubber World":
                // Reset other environmental effects first
                physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
                applyRubberWorldEffect()
            default:
                // Reset all environmental effects if an unknown one is active
                physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
                resetRubberWorldEffect()
            }
        } else {
            environmentalBorder?.strokeColor = .clear
            // Reset all environmental effects
            physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
            resetRubberWorldEffect()
        }
    }
    
    // Helper for checking primed or active environmental power-ups
    private func getActiveEnvironmentalPowerUp() -> PowerUp? {
        return viewModel?.equippedPowerUps
            .compactMap({ $0 })
            .first(where: { $0.type == .environment && $0.isActive })
    }
    
    // Get the active power-up that should affect the current ball
    private var currentActivePowerUp: (name: String, color: SKColor)? {
        for (powerUpName, color) in powerUpColors {
            if let powerUp = viewModel?.equippedPowerUps.compactMap({ $0 }).first(where: { $0.name == powerUpName && $0.isActive }) {
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
    
    private var scheduledForMerge = Set<SKShapeNode>()
    
    struct TierInfo {
        let radius: CGFloat
        let color: SKColor
    }
    
    static func calculateRadius(forTier tier: Int) -> CGFloat {
        let baseSize: CGFloat = 18
        return baseSize + (tier > 1 ? CGFloat((tier - 1) * 12) : 0)
    }
    
    // From cyan to a dark gray/black
    static let tierData: [TierInfo] = (1...12).map { tier in
        let colors: [SKColor] = [
            SKColor(white: 0.60, alpha: 1.0), SKColor(white: 0.20, alpha: 1.0),
            SKColor(white: 0.66, alpha: 1.0), SKColor(white: 0.26, alpha: 1.0),
            SKColor(white: 0.72, alpha: 1.0), SKColor(white: 0.32, alpha: 1.0),
            SKColor(white: 0.78, alpha: 1.0), SKColor(white: 0.38, alpha: 1.0),
            SKColor(white: 0.84, alpha: 1.0), SKColor(white: 0.44, alpha: 1.0),
            SKColor(white: 0.90, alpha: 1.0), SKColor(white: 0.50, alpha: 1.0)
        ]
        return TierInfo(radius: calculateRadius(forTier: tier), color: colors[tier - 1])
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
        
        // Setup boundary physics body
        let frame = SKPhysicsBody(edgeLoopFrom: self.frame)
        frame.friction = 0.2
        frame.restitution = 0.2
        self.physicsBody = frame
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
                if var powerUp = viewModel.equippedPowerUps[i],
                   powerUp.type == .targeting,
                   (powerUp.isPrimed || powerUp.isActive) {
                    powerUp.isPrimed = false
                    powerUp.isActive = false
                    viewModel.equippedPowerUps[i] = powerUp
                }
            }
        }
        
        setupGrid()
        setupDangerZone()
        setupEnvironmentalBorder()
        
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
                        sphere.strokeColor = color
                        sphere.lineWidth = 3
                    }

                    addChild(sphere)
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
        enumerateChildNodes(withName: "sphere") { node, _ in
            guard let sphere = node as? SKShapeNode,
                  let tier = sphere.userData?["tier"] as? Int else { return }
            
            let tierIndex = tier - 1
            let tierInfo = GameScene.tierData[tierIndex]
            let scaledRadius = tierInfo.radius * self.ballScale
            
            // Create new path with scaled radius
            sphere.path = CGPath(ellipseIn: CGRect(x: -scaledRadius, y: -scaledRadius,
                                                  width: scaledRadius * 2, height: scaledRadius * 2),
                               transform: nil)
            
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
        bottomLine.strokeColor = .gray
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
        
        // Apply any active single-use power-ups to the sphere before adding it
        if let activePowerUp = currentActivePowerUp {
            var activePowerUps = sphere.userData?["activePowerUps"] as? [String] ?? []
            activePowerUps.append(activePowerUp.name)
            sphere.userData?["activePowerUps"] = activePowerUps
            
            // Apply visual effect
            sphere.strokeColor = activePowerUp.color
            sphere.lineWidth = 3
            
            // Consume the power-up
            viewModel?.consumeSingleUsePowerUp(activePowerUp.name)
        }
        
        addChild(sphere)
        
        if animated {
            sphere.setScale(0)
            let scaleAction = SKAction.scale(to: 1.0, duration: 0.1)
            scaleAction.timingMode = .easeOut
            
            sphere.run(scaleAction) { [weak self] in
                self?.currentSphere = sphere
                
                // After scaling, check if we need to adjust position
                if let radius = sphere.path?.boundingBox.width.half,
                   let frameWidth = self?.frame.width {
                    let currentX = sphere.position.x
                    let constrainedX = min(max(radius, currentX), frameWidth - radius)
                    
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
            if let radius = sphere.path?.boundingBox.width.half {
                let currentX = sphere.position.x
                let constrainedX = min(max(radius, currentX), frame.width - radius)
                sphere.position = CGPoint(x: constrainedX, y: spawnY)
            }
        }
    }
    
    func createSphereNode(tier: Int) -> SKShapeNode? {
        guard tier >= 1 && tier <= GameScene.tierData.count else { return nil }
        
        let tierIndex = tier - 1
        let tierInfo = GameScene.tierData[tierIndex]
        let scaledRadius = tierInfo.radius * ballScale
        
        let sphere = SKShapeNode(circleOfRadius: scaledRadius)
        sphere.fillColor = tierInfo.color
        sphere.strokeColor = .white
        sphere.lineWidth = 1
        sphere.name = "sphere"
        sphere.userData = [
            "tier": tier,
            "activePowerUps": [String]()
        ]
        
        return sphere
    }
    
    func createAndPlaceSphere(at position: CGPoint, tier: Int, activePowerUps: [String] = []) -> SKShapeNode? {
        guard let sphere = createSphereNode(tier: tier) else { return nil }
        sphere.position = position
        
        // Store active power-ups in userData
        sphere.userData?["activePowerUps"] = activePowerUps
        
        // Apply visual effects based on active power-ups
        if let powerUpName = activePowerUps.first, // For now, we'll only show one power-up effect
           let color = powerUpColors[powerUpName] {
            sphere.strokeColor = color
            sphere.lineWidth = 3
        }
        
        addPhysics(to: sphere)
        addChild(sphere)
        return sphere
    }

    private func constrainPosition(_ position: CGPoint, forSphere sphere: SKShapeNode) -> CGPoint {
        guard let radius = sphere.path?.boundingBox.width.half else { return position }
        
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
            }
            
            addPhysics(to: sphereToDrop)
            
            #if os(iOS)
            HapticManager.shared.playDropHaptic()
            #endif
            
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
        let states = children.compactMap { node -> Sphere? in
            guard let sphereNode = node as? SKShapeNode,
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
            guard let sphereNode = sphereBody.node as? SKShapeNode,
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
            guard let nodeA = contact.bodyA.node as? SKShapeNode,
                  let nodeB = contact.bodyB.node as? SKShapeNode else { return }

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
                        if var powerUp = viewModel.equippedPowerUps[i],
                           powerUp.type == .targeting,
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
                .compactMap { $0 }
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
                currentSphere.strokeColor = activePowerUp.color
                currentSphere.lineWidth = 3
            } else {
                currentSphere.strokeColor = .white
                currentSphere.lineWidth = 1
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
                line.strokeColor = .gray
            }
        }
        
        guard !scheduledForMerge.isEmpty else { return }
        
        var toMerge = scheduledForMerge
        scheduledForMerge.removeAll()
        
        while !toMerge.isEmpty {
            let nodeA = toMerge.removeFirst()
            
            // Find a merge partner from the remaining set
            guard let tierA = nodeA.userData?["tier"] as? Int else { continue }
            
            if let nodeB = toMerge.first(where: { ($0.userData?["tier"] as? Int) == tierA }) {
                toMerge.remove(nodeB) // Partner found and removed from set
                
                let nextTier = tierA + 1
                let middlePoint = CGPoint(x: (nodeA.position.x + nodeB.position.x) / 2,
                                          y: (nodeA.position.y + nodeB.position.y) / 2)
                
                nodeA.removeFromParent()
                nodeB.removeFromParent()
                
                if let newSphere = createAndPlaceSphere(at: middlePoint, tier: nextTier) {
                    // Make merged spheres immediately "live" for the danger zone
                    newSphere.userData?["creationTime"] = Date.distantPast.timeIntervalSinceReferenceDate
                }
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
    
    func addPhysics(to sphere: SKShapeNode) {
        guard sphere.physicsBody == nil,
              let tier = sphere.userData?["tier"] as? Int,
              let pathWidth = sphere.path?.boundingBox.width,
              pathWidth > 0
        else { return }
        
        let radius = pathWidth / 2
        
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.categoryBitMask = PhysicsCategory.sphere
        body.contactTestBitMask = PhysicsCategory.sphere | PhysicsCategory.dangerZone
        body.collisionBitMask = PhysicsCategory.sphere | PhysicsCategory.wall
        
        // Apply power-up mass multiplier if Super Massive Ball is active
        if let activePowerUps = sphere.userData?["activePowerUps"] as? [String],
           activePowerUps.contains("Super Massive Ball") {
            // Super Massive Ball specific physics properties
            body.restitution = 0.3  // More bouncy
            body.friction = 0.02    // Less friction
            body.linearDamping = 0.05  // Much less air resistance
            body.angularDamping = 0.05
            
            // Calculate enhanced mass
            let maxTierMass: CGFloat = 12
            let baseMass: CGFloat = 7.5  // 50% of previous value (was 15.0)
            let massMultiplier = pow(2.0, maxTierMass - CGFloat(tier))
            var finalMass = baseMass * massMultiplier * ballScale
            
            if let powerUp = viewModel?.equippedPowerUps.compactMap({ $0 }).first(where: { $0.name == "Super Massive Ball" }) {
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
            body.friction = 0.05
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
            case 1: newRestitution = 0.8
            case 2: newRestitution = 0.9
            case 3: newRestitution = 1.0
            default: newRestitution = 0.8
            }
            body.restitution = newRestitution
        }
        
        sphere.physicsBody = body
        sphere.userData?["creationTime"] = Date().timeIntervalSinceReferenceDate
    }
    
    func didEnd(_ contact: SKPhysicsContact) {
        let contactMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if contactMask == (PhysicsCategory.sphere | PhysicsCategory.dangerZone) {
            
            let sphereBody = contact.bodyA.categoryBitMask == PhysicsCategory.sphere ? contact.bodyA : contact.bodyB
            spheresInDangerZone.remove(sphereBody)
            
            if spheresInDangerZone.isEmpty {
                if let line = dangerZone?.childNode(withName: "dangerZoneLine") as? SKShapeNode {
                    line.strokeColor = .gray
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
    private func findSelectableSphere(at position: CGPoint) -> SKShapeNode? {
        let touchedNodes = nodes(at: position)
        return touchedNodes.first { node in
            guard let sphere = node as? SKShapeNode,
                  sphere.name == "sphere",
                  sphere !== currentSphere else { return false }
            return true
        } as? SKShapeNode
    }
    
    private func highlightSphere(_ sphere: SKShapeNode) {
        // Store original stroke color if not already stored
        if sphere.userData?["originalStrokeColor"] == nil {
            sphere.userData?["originalStrokeColor"] = sphere.strokeColor
        }
        
        // Highlight effect
        sphere.strokeColor = .yellow
        sphere.lineWidth = 4.0
        
        // Add subtle scale animation
        let scaleUp = SKAction.scale(to: 1.1, duration: 0.1)
        sphere.run(scaleUp)
    }
    
    private func unhighlightSphere(_ sphere: SKShapeNode) {
        // Restore original stroke color
        if let originalColor = sphere.userData?["originalStrokeColor"] as? SKColor {
            sphere.strokeColor = originalColor
            sphere.lineWidth = 1.0
        }
        
        // Remove scale
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
        sphere.run(scaleDown)
    }
    
    private func selectSphere(_ sphere: SKShapeNode) {
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
        
        #if os(iOS)
        HapticManager.shared.playDropHaptic()
        #endif
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
    
    private func activateTargetingPowerUp(_ powerUp: PowerUp, on sphere: SKShapeNode) {
        // Apply power-up effect
        var activePowerUps = sphere.userData?["activePowerUps"] as? [String] ?? []
        activePowerUps.append(powerUp.name)
        sphere.userData?["activePowerUps"] = activePowerUps
        
        // Apply visual effect
        if let color = powerUpColors[powerUp.name] {
            sphere.strokeColor = color
            sphere.lineWidth = 3.0
        }
        
        // Clean up targeting state
        targetingCircle?.removeFromParent()
        targetingCircle = nil
        selectedTarget = nil
        targetingState = .none
        
        // Reset power-up state in view model
        // First deactivate the current power-up
        viewModel?.activatePowerUp(powerUp) // This will deactivate it since it's currently active
        
        // Then update all slots to ensure the power-up is fully reset
        if let viewModel = viewModel {
            for i in viewModel.equippedPowerUps.indices {
                if var slotPowerUp = viewModel.equippedPowerUps[i],
                   slotPowerUp.id == powerUp.id {
                    slotPowerUp.isActive = false
                    slotPowerUp.isPrimed = false
                    viewModel.equippedPowerUps[i] = slotPowerUp
                }
            }
        }
        
        #if os(iOS)
        HapticManager.shared.playMergeHaptic()
        #endif
        
        #if DEBUG
        print("Activated targeting power-up: \(powerUp.name) on sphere and reset power-up state")
        #endif
    }
    
    // MARK: - Environmental Power-Up Effects
    
    private func applyLowGravityEffect() {
        // Find the active Low Gravity power-up
        guard let powerUp = viewModel?.equippedPowerUps
            .compactMap({ $0 })
            .first(where: { $0.name == "Low Gravity" && $0.isActive }) else {
            return
        }
        
        // Calculate gravity reduction based on level
        // Level 1: 0.5x normal gravity (dy: -4.9)
        // Level 2: 0.25x normal gravity (dy: -2.45) - 75% reduction
        // Level 3: 0.1x normal gravity (dy: -0.98) - 90% reduction
        let baseGravity: CGFloat = -9.8
        let baseReduction: CGFloat = 0.5 // 50% of normal gravity at level 1
        
        // Use exponential scaling for stronger effect at higher levels
        let gravityMultiplier: CGFloat
        switch powerUp.level {
        case 1:
            gravityMultiplier = baseReduction // 50% reduction
        case 2:
            gravityMultiplier = baseReduction * 0.5 // 75% reduction
        case 3:
            gravityMultiplier = baseReduction * 0.2 // 90% reduction
        default:
            gravityMultiplier = baseReduction
        }
        
        let newGravity = baseGravity * gravityMultiplier
        
        #if DEBUG
        print("Applying Low Gravity effect:")
        print("- Power-up level: \(powerUp.level)")
        print("- Gravity multiplier: \(gravityMultiplier)x")
        print("- New gravity: \(newGravity)")
        print("- Gravity reduction: \((1 - gravityMultiplier) * 100)%")
        #endif
        
        // Apply the modified gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: newGravity)
    }
    
    private func applyRubberWorldEffect() {
        guard let powerUp = getActiveEnvironmentalPowerUp(), powerUp.name == "Rubber World" else { return }
        
        let newRestitution: CGFloat
        
        switch powerUp.level {
        case 1:
            newRestitution = 0.8
        case 2:
            newRestitution = 0.9
        case 3:
            newRestitution = 1.0
        default:
            newRestitution = 0.8
        }
        
        // Update walls
        self.physicsBody?.restitution = newRestitution
        
        // Update existing spheres
        enumerateChildNodes(withName: "sphere") { node, _ in
            node.physicsBody?.restitution = newRestitution
        }
        
        #if DEBUG
        print("Applying Rubber World effect: Level \(powerUp.level), Restitution: \(newRestitution)")
        #endif
    }
    
    private func resetRubberWorldEffect() {
        // Reset walls to default
        self.physicsBody?.restitution = 0.2
        
        // Reset existing spheres to their defaults
        enumerateChildNodes(withName: "sphere") { node, _ in
            if let sphereNode = node as? SKShapeNode,
               let activePowerUps = sphereNode.userData?["activePowerUps"] as? [String],
               activePowerUps.contains("Super Massive Ball") {
                node.physicsBody?.restitution = 0.3 // Super Massive Ball restitution
            } else {
                node.physicsBody?.restitution = 0.1 // Default sphere restitution
            }
        }
        
        #if DEBUG
        print("Resetting Rubber World effect")
        #endif
    }
}

class HapticManager {
    static let shared = HapticManager()
    private var engine: CHHapticEngine?
    
    init() {
        prepareHaptics()
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
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play merge haptic: \(error.localizedDescription)")
        }
    }
    
    func playDropHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play drop haptic: \(error.localizedDescription)")
        }
    }
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
