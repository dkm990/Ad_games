import Foundation

public enum UpgradeType: String, Codable {
    case moveSpeed
    case carryCapacity
    case processingSpeed
}

public enum GameAction {
    case collectRaw(units: Int)
    case depositRawForProcessing(units: Int)
    case processingCompleted
    case collectProcessedOutput(units: Int)
    case sellProcessed(units: Int)
    case sellProcessedAtUnitPrice(units: Int, unitPrice: Int)
    case unlockZone(id: Int)
    case purchaseUpgrade(type: UpgradeType)
    case recalculateGuidance
    case resetProgress
    case skipUnlockNextZone
}
