//
//  ContentView.swift
//  GlassMerge
//
//  Created by Loaner on 6/9/25.
//

import SwiftUI

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
            icon: "magnet.fill",
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
    
    // Game currency
    @Published var currency: Int = 0
    
    // MARK: - Power-up Management
    
    func unlock(_ powerUp: PowerUp) -> Bool {
        guard !powerUp.isUnlocked && currency >= powerUp.cost else { return false }
        currency -= powerUp.cost
        if let index = powerUps.firstIndex(where: { $0.id == powerUp.id }) {
            powerUps[index].isUnlocked = true
            return true
        }
        return false
    }
    
    func upgrade(_ powerUp: PowerUp) -> Bool {
        guard powerUp.isUnlocked && powerUp.level < PowerUp.maxLevel && currency >= powerUp.upgradeCost else { return false }
        currency -= powerUp.upgradeCost
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
    let powerUpManager: PowerUpManager
    
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
    
    init(powerUpManager: PowerUpManager) {
        self.powerUpManager = powerUpManager
    }
    
    func presentLevelUpChoices() {
        var choices: [PowerUpChoice] = []
        
        // Get available new power-ups
        let newPowerUps = powerUpManager.powerUps
            .filter { !$0.hasBeenOffered }
            .map { PowerUpChoice.new($0) }
        
        // Get upgradeable power-ups
        let upgradeablePowerUps = getUpgradeablePowerUps()
            .map { PowerUpChoice.upgrade($0) }
        
        // Combine and shuffle all options
        choices = (newPowerUps + upgradeablePowerUps).shuffled()
        
        // Take first 3 or all if less than 3
        powerUpChoices = Array(choices.prefix(3))
        isLevelUpViewPresented = true
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
}

struct ContentView: View {
    @State private var currentScreen: GameScreen = .mainMenu
    
    enum GameScreen {
        case mainMenu
        case game
        case upgradeShop
        case collection
        case settings
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentScreen {
                case .mainMenu:
                    MainMenuView(currentScreen: $currentScreen)
                case .game:
                    GameView(currentScreen: $currentScreen)
                case .upgradeShop:
                    UpgradeShopView(currentScreen: $currentScreen)
                case .collection:
                    CollectionView(currentScreen: $currentScreen)
                case .settings:
                    SettingsView(currentScreen: $currentScreen)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

struct MainMenuView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @AppStorage("hasExistingSave") private var hasExistingSave = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Glass Merge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(spacing: 15) {
                Button("New Game") {
                    currentScreen = .game
                }
                .buttonStyle(.borderedProminent)
                
                Button("Continue") {
                    currentScreen = .game
                }
                .buttonStyle(.bordered)
                .disabled(!hasExistingSave)
                
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
    }
}

struct GameView: View {
    @Binding var currentScreen: ContentView.GameScreen
    @StateObject private var powerUpManager = PowerUpManager()
    @StateObject private var viewModel: GameViewModel
    @State private var isPaused: Bool = false
    
    init(currentScreen: Binding<ContentView.GameScreen>) {
        self._currentScreen = currentScreen
        let manager = PowerUpManager()
        self._powerUpManager = StateObject(wrappedValue: manager)
        self._viewModel = StateObject(wrappedValue: GameViewModel(powerUpManager: manager))
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Text("Score: 0")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: {
                        isPaused = true
                    }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                
                Spacer()
                
                // Game area with test level up button
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 375, height: 500)
                    .overlay(
                        Button("Level Up!") {
                            viewModel.presentLevelUpChoices()
                        }
                        .buttonStyle(.borderedProminent)
                    )
                
                Spacer()
                
                // Power-up slots
                PowerUpSlotView(powerUps: viewModel.equippedPowerUps)
                    .padding()
            }
            
            if isPaused {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                PauseMenuView(isPaused: $isPaused, currentScreen: $currentScreen)
                    .transition(.scale)
            }
            
            if viewModel.isLevelUpViewPresented {
                LevelUpView(viewModel: viewModel)
                    .transition(.scale)
            }
        }
    }
}

struct PowerUpSlotView: View {
    let powerUps: [PowerUp?]
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
        if let powerUp = powerUps[index] {
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
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Paused")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 20)
            
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
                .fill(Color.white)
                .shadow(radius: 10)
        )
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
                
                HStack(spacing: 12) {
                    ForEach(viewModel.powerUpChoices) { choice in
                        PowerUpChoiceCard(choice: choice) {
                            viewModel.selectPowerUp(choice)
                        }
                    }
                }
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

#Preview {
    ContentView()
}
