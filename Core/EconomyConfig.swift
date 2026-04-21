import Foundation

public struct EconomyConfig: Codable, Equatable {
    public var player: PlayerConfig
    public var processing: ProcessingConfig
    public var sell: SellConfig
    public var zones: [ZoneConfig]
    public var upgrades: UpgradeConfig
    public var meta: MetaConfig

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

    public struct MetaConfig: Codable, Equatable {
        public var prestigeMinCoins: Int
        public var prestigeCoinsPerPoint: Int
        public var upgrades: MetaUpgradesConfig

        public func upgrade(for type: MetaUpgradeType) -> MetaUpgradeEntry {
            switch type {
            case .startingCoins: return upgrades.startingCoins
            case .sellPriceMultiplier: return upgrades.sellPriceMultiplier
            case .processorSpeed: return upgrades.processorSpeed
            case .moveSpeedBonus: return upgrades.moveSpeedBonus
            }
        }
    }

    public struct MetaUpgradesConfig: Codable, Equatable {
        public var startingCoins: MetaUpgradeEntry
        public var sellPriceMultiplier: MetaUpgradeEntry
        public var processorSpeed: MetaUpgradeEntry
        public var moveSpeedBonus: MetaUpgradeEntry
    }

    public struct MetaUpgradeEntry: Codable, Equatable {
        public var basePrice: Int
        public var priceMultiplier: Double
        /// Used by percentage-style upgrades (e.g. 0.05 = +5% per level).
        public var effectPerLevel: Double
        /// Used by integer-style upgrades (e.g. +10 coins per level).
        public var effectPerLevelInt: Int

        public init(
            basePrice: Int,
            priceMultiplier: Double,
            effectPerLevel: Double = 0,
            effectPerLevelInt: Int = 0
        ) {
            self.basePrice = basePrice
            self.priceMultiplier = priceMultiplier
            self.effectPerLevel = effectPerLevel
            self.effectPerLevelInt = effectPerLevelInt
        }
    }
}

public enum EconomyConfigLoader {
    public static func load(from url: URL) throws -> EconomyConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(EconomyConfig.self, from: data)
    }
}
