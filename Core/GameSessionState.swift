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
    /// Premium goods waiting to be sold. Produced by feeding processed
    /// output into Processor C (the premium chain, see ``PremiumConfig``).
    public var premiumInventory: Int
    /// Premium chain queue. `queuedRawUnits` here means "processed units
    /// deposited into Processor C". `processedReadyUnits` means "premium
    /// goods ready to collect". Reuses the existing struct to keep save
    /// shape and render code simple.
    public var premiumQueue: ProcessingQueueState
    /// Whether the premium chain (Processor C) has been paid for and
    /// unlocked in this session. Resets on prestige.
    public var isPremiumChainUnlocked: Bool

    public init(
        carryAmount: Int = 0,
        processedInventory: Int = 0,
        coins: Int = 0,
        unlockedZoneIDs: Set<Int> = [1],
        upgrades: UpgradeLevels = UpgradeLevels(),
        processingQueue: ProcessingQueueState = ProcessingQueueState(),
        guidanceState: GuidanceState = GuidanceState(target: .collectResource),
        premiumInventory: Int = 0,
        premiumQueue: ProcessingQueueState = ProcessingQueueState(),
        isPremiumChainUnlocked: Bool = false
    ) {
        self.carryAmount = carryAmount
        self.processedInventory = processedInventory
        self.coins = coins
        self.unlockedZoneIDs = unlockedZoneIDs
        self.upgrades = upgrades
        self.processingQueue = processingQueue
        self.guidanceState = guidanceState
        self.premiumInventory = premiumInventory
        self.premiumQueue = premiumQueue
        self.isPremiumChainUnlocked = isPremiumChainUnlocked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.carryAmount = try container.decode(Int.self, forKey: .carryAmount)
        self.processedInventory = try container.decode(Int.self, forKey: .processedInventory)
        self.coins = try container.decode(Int.self, forKey: .coins)
        self.unlockedZoneIDs = try container.decode(Set<Int>.self, forKey: .unlockedZoneIDs)
        self.upgrades = try container.decode(UpgradeLevels.self, forKey: .upgrades)
        self.processingQueue = try container.decode(ProcessingQueueState.self, forKey: .processingQueue)
        self.guidanceState = try container.decode(GuidanceState.self, forKey: .guidanceState)
        self.premiumInventory = try container.decodeIfPresent(Int.self, forKey: .premiumInventory) ?? 0
        self.premiumQueue = try container.decodeIfPresent(ProcessingQueueState.self, forKey: .premiumQueue) ?? ProcessingQueueState()
        self.isPremiumChainUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isPremiumChainUnlocked) ?? false
    }
}
