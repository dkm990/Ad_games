import Foundation

public enum GuidanceTargetType: String, Codable {
    case collectResource
    case goProcessorInput
    case collectProcessedOutput
    case goSellZone
    case unlockGate
}

public struct GuidanceState: Codable, Equatable {
    public var target: GuidanceTargetType
    public var zoneID: Int?

    public init(target: GuidanceTargetType, zoneID: Int? = nil) {
        self.target = target
        self.zoneID = zoneID
    }
}

public struct ProcessingQueueState: Codable, Equatable {
    public var queuedRawUnits: Int
    public var processedReadyUnits: Int

    public init(queuedRawUnits: Int = 0, processedReadyUnits: Int = 0) {
        self.queuedRawUnits = queuedRawUnits
        self.processedReadyUnits = processedReadyUnits
    }

    public var processorWaitingForInput: Bool {
        queuedRawUnits == 0 && processedReadyUnits == 0
    }
}

public struct UpgradeLevels: Codable, Equatable {
    public var moveSpeed: Int
    public var carryCapacity: Int
    public var processingSpeed: Int

    public init(moveSpeed: Int = 0, carryCapacity: Int = 0, processingSpeed: Int = 0) {
        self.moveSpeed = moveSpeed
        self.carryCapacity = carryCapacity
        self.processingSpeed = processingSpeed
    }
}

public struct GameSessionState: Codable, Equatable {
    public var carryAmount: Int
    public var processedInventory: Int
    public var coins: Int
    public var unlockedZoneIDs: Set<Int>
    public var upgrades: UpgradeLevels
    public var processingQueue: ProcessingQueueState
    public var guidanceState: GuidanceState

    public init(
        carryAmount: Int = 0,
        processedInventory: Int = 0,
        coins: Int = 0,
        unlockedZoneIDs: Set<Int> = [1],
        upgrades: UpgradeLevels = UpgradeLevels(),
        processingQueue: ProcessingQueueState = ProcessingQueueState(),
        guidanceState: GuidanceState = GuidanceState(target: .collectResource)
    ) {
        self.carryAmount = carryAmount
        self.processedInventory = processedInventory
        self.coins = coins
        self.unlockedZoneIDs = unlockedZoneIDs
        self.upgrades = upgrades
        self.processingQueue = processingQueue
        self.guidanceState = guidanceState
    }
}
