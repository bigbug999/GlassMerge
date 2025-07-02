import CoreData
import UIKit

// MARK: - Core Data Manager
final class CoreDataManager {
    static let shared = CoreDataManager()

    private let container: NSPersistentContainer
    private let migrationManager = MigrationManager()

    private init() {
        container = NSPersistentContainer(name: "GlassMerge")
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        // Check for and perform migration from JSON if needed
        migrationManager.migrateIfNeeded(context: container.viewContext)
    }

    var context: NSManagedObjectContext {
        return container.viewContext
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
    // MARK: - Game State Helpers
    
    func getGameData() -> GameData {
        let request: NSFetchRequest<GameData> = GameData.fetchRequest()
        
        do {
            let results = try context.fetch(request)
            if let gameData = results.first {
                return gameData
            }
        } catch {
            print("Failed to fetch GameData: \(error)")
        }
        
        // If no GameData exists, create a new one
        let newGameData = GameData(context: context)
        newGameData.currency = 0
        newGameData.firstLaunchDate = Date()
        newGameData.totalPlayTime = 0
        newGameData.unlockedFlaskSizes = FlaskSize.small.rawValue
        
        // Create initial progression for all power-ups
        let initialProgressions = PowerUpManager().powerUps.map { powerUp -> PowerUpProgression in
            let progression = PowerUpProgression(context: context)
            progression.id = powerUp.name
            progression.isUnlocked = false
            progression.level = 1
            return progression
        }
        newGameData.addToPowerUpProgressions(NSSet(array: initialProgressions))
        
        saveContext()
        return newGameData
    }

    func createNewRun(selectedFlask: FlaskSize) -> Run {
        let gameData = getGameData()

        // If a run already exists, delete it
        if let existingRun = gameData.currentRun {
            context.delete(existingRun)
        }

        let newRun = Run(context: context)
        newRun.score = 0
        newRun.level = 1
        newRun.xp = 0
        newRun.selectedFlaskSize = selectedFlask.rawValue
        
        gameData.currentRun = newRun
        
        saveContext()
        return newRun
    }
    
    func hasActiveRun() -> Bool {
        return getGameData().currentRun != nil
    }
}

// MARK: - JSON to Core Data Migration
private class MigrationManager {
    // MARK: - Private Codable Structs for JSON Migration
    private struct GameState: Codable {
        var schemaVersion: Int = 1
        var progression: Progression
        var run: RunState?
        var meta: MetaState
    }

    private struct MetaState: Codable {
        var firstLaunchDate: Date = Date()
        var totalPlayTime: TimeInterval = 0
    }

    private struct Progression: Codable {
        var currency: Int
        var powerUps: [PowerUpProgress]
        var unlockedFlaskSizes: Set<FlaskSize> = [.small]
    }

    private struct PowerUpProgress: Codable {
        let id: String
        var isUnlocked: Bool
        var level: Int
    }

    private struct RunState: Codable {
        var score: Int
        var level: Int
        var xp: Int
        var equipped: [PowerUpSave?]
        var spheres: [SphereState]
        var selectedFlaskSize: FlaskSize = .small
    }

    private struct PowerUpSave: Codable {
        let id: String
        var level: Int
        var slotIndex: Int
        var isActive: Bool
        var isPrimed: Bool
        var remainingDuration: TimeInterval
        var type: PowerUpType
        var currentCharges: Int
        var isRecharging: Bool
        var mergesUntilRecharge: Int
    }

    private struct SphereState: Codable {
        var tier: Int
        var position: CGPoint
        var activePowerUps: [String]
        
        // Custom Codable implementation to handle CGPoint
        enum CodingKeys: String, CodingKey {
            case tier, position, activePowerUps
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(tier, forKey: .tier)
            try container.encode(["x": position.x, "y": position.y], forKey: .position)
            try container.encode(activePowerUps, forKey: .activePowerUps)
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.tier = (try? container.decode(Int.self, forKey: .tier)) ?? 1
            let posDict = try container.decode([String: CGFloat].self, forKey: .position)
            self.position = CGPoint(x: posDict["x"] ?? 0, y: posDict["y"] ?? 0)
            self.activePowerUps = (try? container.decode([String].self, forKey: .activePowerUps)) ?? []
        }
    }
    
    private let fileName = "GameState.json"
    private var saveURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    func migrateIfNeeded(context: NSManagedObjectContext) {
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            #if DEBUG
            print("[MigrationManager] No old JSON save file found. Skipping migration.")
            #endif
            return
        }

        #if DEBUG
        print("[MigrationManager] Old JSON save file found. Starting migration...")
        #endif

        guard let oldState = loadOldState() else {
            #if DEBUG
            print("[MigrationManager] Failed to decode old JSON state.")
            #endif
            return
        }
        
        let request: NSFetchRequest<GameData> = GameData.fetchRequest()
        if let count = try? context.count(for: request), count > 0 {
            #if DEBUG
            print("[MigrationManager] Core Data already populated. Skipping migration.")
            #endif
            deleteOldSaveFile()
            return
        }

        // Create new GameData object from old state
        let gameData = GameData(context: context)
        gameData.currency = Int64(oldState.progression.currency)
        gameData.totalPlayTime = oldState.meta.totalPlayTime
        gameData.firstLaunchDate = oldState.meta.firstLaunchDate
        
        let unlockedSizes = oldState.progression.unlockedFlaskSizes.map { $0.rawValue }.joined(separator: ",")
        gameData.unlockedFlaskSizes = unlockedSizes
        
        // Migrate PowerUpProgress
        let progressions = oldState.progression.powerUps.map { oldProgress -> PowerUpProgression in
            let newProgress = PowerUpProgression(context: context)
            newProgress.id = oldProgress.id
            newProgress.isUnlocked = oldProgress.isUnlocked
            newProgress.level = Int64(oldProgress.level)
            return newProgress
        }
        gameData.addToPowerUpProgressions(NSSet(array: progressions))

        // Migrate RunState if it exists
        if let oldRun = oldState.run {
            let newRun = Run(context: context)
            newRun.score = Int64(oldRun.score)
            newRun.level = Int64(oldRun.level)
            newRun.xp = Int64(oldRun.xp)
            newRun.selectedFlaskSize = oldRun.selectedFlaskSize.rawValue
            
            // Migrate equipped power-ups
            let equippedPowerUps = oldRun.equipped.compactMap { oldEquipped -> EquippedPowerUp? in
                guard let oldEquipped = oldEquipped else { return nil }
                let newEquipped = EquippedPowerUp(context: context)
                newEquipped.id = oldEquipped.id
                newEquipped.level = Int64(oldEquipped.level)
                newEquipped.slotIndex = Int64(oldEquipped.slotIndex)
                newEquipped.isActive = oldEquipped.isActive
                newEquipped.isPrimed = oldEquipped.isPrimed
                newEquipped.remainingDuration = oldEquipped.remainingDuration
                newEquipped.type = oldEquipped.type.rawValue
                newEquipped.currentCharges = Int64(oldEquipped.currentCharges)
                newEquipped.isRecharging = oldEquipped.isRecharging
                newEquipped.mergesUntilRecharge = Int64(oldEquipped.mergesUntilRecharge)
                return newEquipped
            }
            newRun.addToEquippedPowerUps(NSSet(array: equippedPowerUps))

            // Migrate spheres
            let spheres = oldRun.spheres.map { oldSphere -> Sphere in
                let newSphere = Sphere(context: context)
                newSphere.tier = Int64(oldSphere.tier)
                newSphere.positionX = oldSphere.position.x
                newSphere.positionY = oldSphere.position.y
                newSphere.activePowerUps = oldSphere.activePowerUps.joined(separator: ",")
                return newSphere
            }
            newRun.addToSpheres(NSSet(array: spheres))
            
            gameData.currentRun = newRun
        }

        do {
            try context.save()
            #if DEBUG
            print("[MigrationManager] Successfully migrated JSON data to Core Data.")
            #endif
            deleteOldSaveFile()
        } catch {
            #if DEBUG
            print("[MigrationManager] Failed to save migrated context: \(error)")
            #endif
        }
    }

    private func loadOldState() -> GameState? {
        do {
            let data = try Data(contentsOf: saveURL)
            let state = try JSONDecoder().decode(GameState.self, from: data)
            return state
        } catch {
            print("Failed to load old game state for migration: \(error)")
            return nil
        }
    }

    private func deleteOldSaveFile() {
        do {
            try FileManager.default.removeItem(at: saveURL)
            #if DEBUG
            print("[MigrationManager] Old JSON save file deleted.")
            #endif
        } catch {
            #if DEBUG
            print("[MigrationManager] Failed to delete old JSON save file: \(error)")
            #endif
        }
    }
} 