import Foundation

public struct EconomyConfig: Codable, Equatable {
    public var player: PlayerConfig
    public var processing: ProcessingConfig
    public var sell: SellConfig
    public var zones: [ZoneConfig]
    public var upgrades: UpgradeConfig

    public struct PlayerConfig: Codable, Equatable {
        public var pickupRadius: Double
        public var playerAcceleration: Double
        public var playerMaxSpeed: Double
        public var baseCarryCapacity: Int
    }

    public struct ProcessingConfig: Codable, Equatable {
        public var inputPerBatch: Int
        public var outputPerBatch: Int
        public var baseProcessTimeSec: Double
    }

    public struct SellConfig: Codable, Equatable {
        public var processedUnitPrice: Int
    }

    public struct ZoneConfig: Codable, Equatable {
        public var id: Int
        public var unlockPrice: Int
    }

    public struct UpgradeConfig: Codable, Equatable {
        public var moveSpeed: MoveSpeedConfig
        public var carryCapacity: CarryCapacityConfig
        public var processingSpeed: ProcessingSpeedConfig
    }

    public struct MoveSpeedConfig: Codable, Equatable {
        public var basePrice: Int
        public var priceMultiplier: Double
        public var maxSpeedDeltaPerLevel: Double
    }

    public struct CarryCapacityConfig: Codable, Equatable {
        public var basePrice: Int
        public var priceMultiplier: Double
        public var capacityDeltaPerLevel: Int
    }

    public struct ProcessingSpeedConfig: Codable, Equatable {
        public var basePrice: Int
        public var priceMultiplier: Double
        public var timeMultiplierPerLevel: Double
    }
}

public enum EconomyConfigLoader {
    public static func load(from url: URL) throws -> EconomyConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(EconomyConfig.self, from: data)
    }
}
