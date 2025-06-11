//
//  ContentView.swift
//  GlassMerge
//
//  Created by Loaner on 6/9/25.
//

import SwiftUI
import Foundation
import SpriteKit
#if os(iOS)
import UIKit
import CoreHaptics
#endif

// MARK: - SAVE SYSTEM (embedded)

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

struct GameState: Codable {
    var schemaVersion: Int = 1
    var progression: Progression
    var run: RunState?
    var meta: MetaState
}

struct MetaState: Codable {
    var firstLaunchDate: Date = Date()
    var totalPlayTime: TimeInterval = 0
}

struct Progression: Codable {
    var currency: Int
    var powerUps: [PowerUpProgress]
    var unlockedFlaskSizes: Set<FlaskSize> = [.small]  // Small is always unlocked
}

struct PowerUpProgress: Codable {
    let id: String // power-up name key
    var isUnlocked: Bool
    var level: Int
}

struct RunState: Codable {
    var score: Int
    var level: Int
    var xp: Int
    var equipped: [PowerUpSave?]
    var spheres: [SphereState]
    var selectedFlaskSize: FlaskSize = .small
}

struct PowerUpSave: Codable {
    let id: String // power-up name key
    var level: Int
    var slotIndex: Int
}

struct SphereState: Codable {
    var tier: Int
    var position: CGPoint
    
    enum CodingKeys: String, CodingKey {
        case tier, position, radius, color // Keep old keys for decoding compatibility
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier, forKey: .tier)
        try container.encode(["x": position.x, "y": position.y], forKey: .position)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // If 'tier' exists, use it. Otherwise, default to 1 for old save data.
        self.tier = (try? container.decode(Int.self, forKey: .tier)) ?? 1
        let posDict = try container.decode([String: CGFloat].self, forKey: .position)
        self.position = CGPoint(x: posDict["x"] ?? 0, y: posDict["y"] ?? 0)
    }
    
    init(tier: Int, position: CGPoint) {
        self.tier = tier
        self.position = position
    }
}

final class SaveManager {
    static let shared = SaveManager()
    private init() {}

    private let fileName = "GameState.json"

    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    func save(_ state: GameState) {
        DispatchQueue.global(qos: .background).async { [url = saveURL] in
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: url, options: .atomic)
                #if DEBUG
                print("[SaveManager] Saved game to \(url.path)")
                #endif
            } catch {
                assertionFailure("Failed to save game state: \(error)")
            }
        }
    }

    func load() -> GameState? {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: saveURL)
            let state = try JSONDecoder().decode(GameState.self, from: data)
            #if DEBUG
            print("[SaveManager] Loaded game from \(saveURL.path)")
            #endif
            return state
        } catch {
            print("Failed to load game state: \(error)")
            return nil
        }
    }
}

// Power-up Model
enum PowerUpCategory: String, CaseIterable {
    case gravity = "Gravity"
    case magnetism = "Magnetism"
    case void = "Void"
    case friction = "Friction"
    
    var description: String {
        switch self {
        case .gravity: return "Physics-based effects that modify mass and gravity"
        case .magnetism: return "Attraction and repulsion effects"
        case .void: return "Object removal and deletion effects"
        case .friction: return "Surface and movement modifiers"
        }
    }
}

enum PowerUpType {
    case singleUse
    case environment
}

struct PowerUpStats {
    var duration: TimeInterval?  // nil for single-use effects
    var cooldown: TimeInterval
    var forceMagnitude: Double
    
    static func baseStats(for powerUp: PowerUp) -> PowerUpStats {
        switch powerUp.name {
        case "Super Massive Ball":
            return PowerUpStats(duration: nil, cooldown: 35, forceMagnitude: 1.5)
        case "Low Gravity":
            return PowerUpStats(duration: 10, cooldown: 45, forceMagnitude: 0.5)
        case "Magnetic Ball":
            return PowerUpStats(duration: nil, cooldown: 30, forceMagnitude: 0.5)
        case "Repulsion Field":
            return PowerUpStats(duration: nil, cooldown: 40, forceMagnitude: 0.5)
        case "Negative Ball":
            return PowerUpStats(duration: nil, cooldown: 45, forceMagnitude: 1.0)
        case "Selective Deletion":
            return PowerUpStats(duration: nil, cooldown: 60, forceMagnitude: 1.0)
        default:
            return PowerUpStats(duration: nil, cooldown: 30, forceMagnitude: 1.0)
        }
    }
    
    func scaled(to level: Int) -> PowerUpStats {
        var stats = self
        
        // Duration increases by 2 seconds per level for environment effects
        if let duration = stats.duration {
            stats.duration = duration + (Double(level - 1) * 2)
        }
        
        // Cooldown reduction of 5 seconds per level
        stats.cooldown = max(15, cooldown - (Double(level - 1) * 5))
        
        // Force magnitude scaling based on power-up type
        let forceMagnitudeIncrease = Double(level - 1) * 0.25
        stats.forceMagnitude += forceMagnitudeIncrease
        
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
    var isActive: Bool = false
    var remainingCooldown: TimeInterval = 0
    var hasBeenOffered: Bool = false
    var slotsOccupied: Int {
        return level
    }
    
    // Upgrade costs
    var upgradeCost: Int {
        return cost * level
    }
    
    static let maxLevel = 3
}

class PowerUpManager: ObservableObject {
    @Published var powerUps: [PowerUp] = [
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
            name: "Repulsion Field",
            description: "Repels balls of different tiers",
            category: .magnetism,
            type: .singleUse,
            icon: "rays",
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
        PowerUp(
            name: "Selective Deletion",
            description: "Tap-to-select mechanic for strategic ball removal",
            category: .void,
            type: .singleUse,
            icon: "trash.circle.fill",
            isUnlocked: false,
            level: 1,
            cost: 1000
        )
    ]
    
    // Game currency and progression
    @Published var currency: Int = 0
    @Published var progression = Progression(
        currency: 0,
        powerUps: [],
        unlockedFlaskSizes: Set(FlaskSize.allCases) // Unlock all flask sizes by default
    )
    
    // MARK: - Power-up Management
    
    func unlock(_ powerUp: PowerUp) -> Bool {
        guard !powerUp.isUnlocked && currency >= powerUp.cost else { return false }
        currency -= powerUp.cost
        progression.currency = currency
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].isUnlocked = true
            return true
        }
        return false
    }
    
    func unlockFlaskSize(_ size: FlaskSize) -> Bool {
        guard !progression.unlockedFlaskSizes.contains(size) && currency >= size.cost else { return false }
        currency -= size.cost
        progression.currency = currency
        progression.unlockedFlaskSizes.insert(size)
        return true
    }
    
    func upgrade(_ powerUp: PowerUp) -> Bool {
        guard powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && currency >= powerUp.upgradeCost else { return false }
        currency -= powerUp.upgradeCost
        progression.currency = currency
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].level += 1
            return true
        }
        return false
    }
    
    func activate(_ powerUp: PowerUp) -> Bool {
        guard powerUp.isUnlocked && powerUp.remainingCooldown <= 0 else { return false }
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].isActive = true
            powerUps[index].remainingCooldown = powerUp.currentStats.cooldown
            return true
        }
        return false
    }
    
    func updateCooldowns(deltaTime: TimeInterval) {
        for (index, powerUp) in powerUps.enumerated() where powerUp.remainingCooldown > 0 {
            powerUps[index].remainingCooldown = max(0, powerUp.remainingCooldown - deltaTime)
            if powerUp.remainingCooldown == 0 {
                powerUps[index].isActive = false
            }
        }
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
    let xpNeededPerLevel: Int = 30
    let powerUpManager: PowerUpManager
    @Published private var sphereStates: [SphereState] = []
    var sphereStateProvider: (() -> [SphereState])?
    
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
    
    init(powerUpManager: PowerUpManager, restore state: GameState? = nil) {
        self.powerUpManager = powerUpManager
        if let state = state {
            self.applyGameState(state)
        }
    }
    
    private func applyGameState(_ state: GameState) {
        // Restore progression
        powerUpManager.currency = state.progression.currency
        powerUpManager.progression = state.progression

        // Restore power-up progression
        for progress in state.progression.powerUps {
            if let index = powerUpManager.powerUps.firstIndex(where: { $0.name == progress.id }) {
                powerUpManager.powerUps[index].isUnlocked = progress.isUnlocked
                powerUpManager.powerUps[index].level = progress.level
            }
        }

        // Restore equipped power-ups and run state
        if let run = state.run {
            equippedPowerUps = Array(repeating: nil, count: 6)
            for (slot, save) in run.equipped.enumerated() {
                guard let save = save else { continue }
                if let base = powerUpManager.powerUps.first(where: { $0.name == save.id }) {
                    var instance = base
                    instance.level = save.level
                    instance.slotIndex = save.slotIndex
                    equippedPowerUps[slot] = instance
                }
            }
            self.score = run.score
            self.xp = run.xp
            self.level = run.level
            self.sphereStates = run.spheres
            self.selectedFlaskSize = run.selectedFlaskSize
            #if DEBUG
            print("GameViewModel: Restored \(run.spheres.count) sphere states from save")
            #endif
        }
    }
    
    func presentLevelUpChoices() {
        // Check if there are any empty slots or upgradeable power-ups
        let hasEmptySlot = equippedPowerUps.contains(where: { $0 == nil })
        let hasUpgradeablePowerUps = !getUpgradeablePowerUps().isEmpty
        
        // Don't show level up screen if no slots available and no upgrades possible
        guard hasEmptySlot || hasUpgradeablePowerUps else { return }
        
        #if DEBUG
        print("Presenting level up choices at level \(level)")
        #endif
        var choices: [PowerUpChoice] = []
        var seenPowerUpIds = Set<UUID>()
        
        // Get available new power-ups only if there are empty slots
        if hasEmptySlot {
            let newPowerUps = powerUpManager.powerUps
                .filter { !$0.hasBeenOffered }
                .map { PowerUpChoice.new($0) }
            for choice in newPowerUps {
                if !seenPowerUpIds.contains(choice.powerUp.id) {
                    choices.append(choice)
                    seenPowerUpIds.insert(choice.powerUp.id)
                }
            }
        }
        
        // Get upgradeable power-ups
        let upgradeablePowerUps = getUpgradeablePowerUps()
            .map { PowerUpChoice.upgrade($0) }
        for choice in upgradeablePowerUps {
            if !seenPowerUpIds.contains(choice.powerUp.id) {
                choices.append(choice)
                seenPowerUpIds.insert(choice.powerUp.id)
            }
        }
        
        // If no choices available, don't show the screen
        guard !choices.isEmpty else { return }
        
        // Shuffle and take first 3 or all if less than 3
        choices.shuffle()
        powerUpChoices = Array(choices.prefix(3))
        isLevelUpViewPresented = true
        saveGameState() // Save upon reaching a new level
    }
    
    func rerollChoices() {
        guard hasReroll else { return }
        hasReroll = false
        presentLevelUpChoices()
    }
    
    func skipLevelUp() {
        isLevelUpViewPresented = false
    }
    
    private func getUpgradeablePowerUps() -> [PowerUp] {
        return equippedPowerUps.compactMap { $0 }
            .filter { $0.level < PowerUp.maxLevel }
            .filter { hasEnoughSlotsForUpgrade($0) }
    }
    
    private func hasEnoughSlotsForUpgrade(_ powerUp: PowerUp) -> Bool {
        // Find the start index of this power-up
        guard let currentIndex = powerUp.slotIndex ?? equippedPowerUps.firstIndex(where: { $0?.id == powerUp.id }) else {
            return false
        }
        
        let neededSlots = powerUp.level + 1 // Next level needs this many slots
        var availableSlots = 0
        
        // Count available slots starting from the power-up's current position
        for i in currentIndex..<equippedPowerUps.count {
            let slot = equippedPowerUps[i]
            if slot == nil || slot?.id == powerUp.id {
                availableSlots += 1
                if availableSlots >= neededSlots {
                    return true
                }
            } else {
                break
            }
        }
        
        return false
    }
    
    func selectPowerUp(_ choice: PowerUpChoice) {
        switch choice {
        case .new(let powerUp):
            addNewPowerUp(powerUp)
        case .upgrade(let powerUp):
            upgradePowerUp(powerUp)
        }
        isLevelUpViewPresented = false
        saveGameState() // Save after applying choice
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
        
        // Create upgraded version
        var upgradedPowerUp = powerUp
        upgradedPowerUp.level += 1
        upgradedPowerUp.slotIndex = startIndex
        
        // Clear all slots occupied by any instance of this power-up
        for index in instances {
            clearSlotsForPowerUp(startingAt: index)
        }
        
        // Place upgraded version in consecutive slots
        for i in startIndex..<min(startIndex + upgradedPowerUp.slotsOccupied, equippedPowerUps.count) {
            equippedPowerUps[i] = upgradedPowerUp
        }
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
    func saveGameState(fromScene: Bool = true) {
        if fromScene, let provider = sphereStateProvider {
            self.sphereStates = provider()
        }
        let gameState = makeGameState()
        SaveManager.shared.save(gameState)
    }
    
    private func makeGameState() -> GameState {
        // Build Progression
        let progressEntries = powerUpManager.powerUps.map { powerUp in
            PowerUpProgress(id: powerUp.name, isUnlocked: powerUp.isUnlocked, level: powerUp.level)
        }
        let progression = Progression(currency: powerUpManager.currency, powerUps: progressEntries, unlockedFlaskSizes: powerUpManager.progression.unlockedFlaskSizes)
        
        // Build RunState with equipped power-ups
        let equipped: [PowerUpSave?] = equippedPowerUps.enumerated().map { index, item in
            guard let item = item else { return nil }
            return PowerUpSave(id: item.name, level: item.level, slotIndex: item.slotIndex ?? index)
        }
        let run = RunState(score: score, level: level, xp: xp, equipped: equipped, spheres: sphereStates, selectedFlaskSize: selectedFlaskSize)
        
        return GameState(progression: progression, run: run, meta: MetaState())
    }
    
    func earnScore(points: Int = 1) {
        score += points
        xp += points
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
    
    func getSphereStates() -> [SphereState]? {
        #if DEBUG
        print("GameViewModel: getSphereStates called, has \(sphereStates.count) states")
        #endif
        return sphereStates.isEmpty ? nil : sphereStates
    }
    
    func saveSphereStates(_ states: [SphereState]) {
        #if DEBUG
        print("GameViewModel: Saving \(states.count) sphere states")
        #endif
        sphereStates = states
        saveGameState(fromScene: false)
    }
    
    func reset() {
        score = 0
        xp = 0
        level = 1
        equippedPowerUps = Array(repeating: nil, count: 6)
        powerUpChoices = []
        hasReroll = true
        isLevelUpViewPresented = false
        sphereStates = []
        selectedFlaskSize = .small
    }
}

struct ContentView: View {
    @State private var currentScreen: GameScreen = .mainMenu
    @State private var loadedState: GameState? = nil
    
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
                        loadedState = nil
                    }, onContinue: {
                        loadedState = SaveManager.shared.load()
                    })
                case .game:
                    GameView(currentScreen: $currentScreen, restore: loadedState)
                case .upgradeShop:
                    UpgradeShopView(currentScreen: $currentScreen)
                case .collection:
                    CollectionView(currentScreen: $currentScreen)
                case .settings:
                    SettingsView(currentScreen: $currentScreen)
                case .runSetup:
                    RunSetupView(currentScreen: $currentScreen, onGameStart: { state in
                        loadedState = state
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
    @State private var hasSave: Bool = SaveManager.shared.load()?.run != nil
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
            hasSave = SaveManager.shared.load()?.run != nil
        }
    }
}

struct RunSetupView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @StateObject private var powerUpManager = PowerUpManager()
    @State private var selectedFlaskSize: FlaskSize = .small
    let onGameStart: (GameState) -> Void
    
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
                        isUnlocked: size == .small || powerUpManager.progression.unlockedFlaskSizes.contains(size),
                        onSelect: {
                            selectedFlaskSize = size
                        }
                    )
                }
            }
            .padding()
            
            Spacer()
            
            Button("Start Game") {
                // Create initial game state
                let progression = Progression(
                    currency: powerUpManager.currency,
                    powerUps: powerUpManager.powerUps.map { PowerUpProgress(id: $0.name, isUnlocked: $0.isUnlocked, level: $0.level) },
                    unlockedFlaskSizes: powerUpManager.progression.unlockedFlaskSizes
                )
                
                let run = RunState(
                    score: 0,
                    level: 1,
                    xp: 0,
                    equipped: Array(repeating: nil, count: 6),
                    spheres: [],
                    selectedFlaskSize: selectedFlaskSize
                )
                
                let gameState = GameState(
                    progression: progression,
                    run: run,
                    meta: MetaState()
                )
                
                onGameStart(gameState)
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
    
    init(currentScreen: Binding<ContentView.GameScreen>, restore state: GameState? = nil) {
        self._currentScreen = currentScreen
        let manager = PowerUpManager()
        self._powerUpManager = StateObject(wrappedValue: manager)
        self._viewModel = StateObject(wrappedValue: GameViewModel(powerUpManager: manager, restore: state))
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
                
                PowerUpSlotView(powerUps: $viewModel.equippedPowerUps)
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
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                )
                .overlay(
                    Group {
                        if let powerUp = powerUp {
                            VStack(spacing: 2) {
                                Image(systemName: powerUp.icon)
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                                if powerUp.level > 1 {
                                    Text("Lv\(powerUp.level)")
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
                )
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
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.2))
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
        
        setupGrid()
        setupDangerZone()
        
        // Restore spheres from saved state if available
        if let sphereStates = viewModel?.getSphereStates(), !sphereStates.isEmpty {
            for state in sphereStates {
                if let sphere = createAndPlaceSphere(at: state.position, tier: state.tier) {
                    // Make restored spheres immediately "live" for the danger zone
                    sphere.userData?["creationTime"] = Date.distantPast.timeIntervalSinceReferenceDate
                }
            }
        }
        
        spawnNewSphere(at: nil, animated: false)
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
    
    func spawnNewSphere(at position: CGPoint? = nil, animated: Bool) {
        let tier = Int.random(in: 1...3)
        guard let sphere = createSphereNode(tier: tier) else {
            self.isTransitioning = false
            return
        }
        
        let spawnY = size.height - topBufferHeight
        let initialPosition = position ?? CGPoint(x: size.width / 2, y: spawnY)
        sphere.position = initialPosition
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
        sphere.name = "sphere"
        sphere.userData = ["tier": tier]
        
        return sphere
    }
    
    func createAndPlaceSphere(at position: CGPoint, tier: Int) -> SKShapeNode? {
        guard let sphere = createSphereNode(tier: tier) else { return nil }
        sphere.position = position
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
        guard !isPaused, !isTransitioning, let touch = touches.first, let sphere = currentSphere else { return }
        let location = touch.location(in: self)
        sphere.position = constrainPosition(location, forSphere: sphere)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isPaused, !isTransitioning, let touch = touches.first, let sphere = currentSphere else { return }
        let location = touch.location(in: self)
        sphere.position = constrainPosition(location, forSphere: sphere)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If no touch event or we're in a transitioning state, ignore
        guard !isPaused, !isTransitioning, let touch = touches.first else { return }
        
        // If there's no current sphere, this might be the first touch after loading
        // Just ignore it to prevent unwanted drops
        guard let sphereToDrop = currentSphere else { return }
        
        isTransitioning = true
        
        let location = touch.location(in: self)
        let constrainedPosition = constrainPosition(location, forSphere: sphereToDrop)
        sphereToDrop.position = constrainedPosition
        
        addPhysics(to: sphereToDrop)
        
        #if os(iOS)
        HapticManager.shared.playDropHaptic()
        #endif
        
        self.currentSphere = nil
        
        // Use the same constrained x position for spawning the next sphere
        let spawnPosition = constrainedPosition
        
        // Use a slight delay to allow the dropped sphere to start falling before the next appears.
        run(SKAction.wait(forDuration: 0.1)) { [weak self] in
            self?.spawnNewSphere(at: spawnPosition, animated: true)
        }
    }
    
    func getCurrentSphereStates() -> [SphereState] {
        let states = children.compactMap { node -> SphereState? in
            guard let sphere = node as? SKShapeNode,
                  sphere.name == "sphere",
                  let tier = sphere.userData?["tier"] as? Int else { return nil }
            return SphereState(tier: tier, position: sphere.position)
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
        body.restitution = 0.1
        body.friction = 0.05
        body.allowsRotation = true
        body.linearDamping = 0.1
        body.angularDamping = 0.1
        
        let maxTierMass: CGFloat = 12
        let baseMass: CGFloat = 10.0
        let massMultiplier = pow(1.5, maxTierMass - CGFloat(tier))
        body.mass = baseMass * massMultiplier * ballScale // Scale mass with ball size
        
        sphere.physicsBody = body
        
        // Add creation timestamp when physics is added (when the ball is dropped)
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
