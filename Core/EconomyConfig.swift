import Foundation

public struct EconomyConfig: Codable, Equatable {
    public var player: PlayerConfig
    public var processing: ProcessingConfig
    public var sell: SellConfig
    public var zones: [ZoneConfig]
    public var upgrades: UpgradeConfig
    public var meta: MetaConfig
    public var premium: PremiumConfig

    public init(
        player: PlayerConfig,
        processing: ProcessingConfig,
        sell: SellConfig,
        zones: [ZoneConfig],
        upgrades: UpgradeConfig,
        meta: MetaConfig,
        premium: PremiumConfig = PremiumConfig()
    ) {
        self.player = player
        self.processing = processing
        self.sell = sell
        self.zones = zones
        self.upgrades = upgrades
        self.meta = meta
        self.premium = premium
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.player = try container.decode(PlayerConfig.self, forKey: .player)
        self.processing = try container.decode(ProcessingConfig.self, forKey: .processing)
        self.sell = try container.decode(SellConfig.self, forKey: .sell)
        self.zones = try container.decode([ZoneConfig].self, forKey: .zones)
        self.upgrades = try container.decode(UpgradeConfig.self, forKey: .upgrades)
        self.meta = try container.decode(MetaConfig.self, forKey: .meta)
        self.premium = try container.decodeIfPresent(PremiumConfig.self, forKey: .premium) ?? PremiumConfig()
    }

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

    /// Configuration for the premium production chain (Processor C).
    /// Input is `processedInventory`; output is `premiumInventory`, sold at
    /// `unitPrice` coins. Unlock costs `unlockPrice` coins.
    public struct PremiumConfig: Codable, Equatable {
        public var inputPerBatch: Int
        public var outputPerBatch: Int
        public var baseProcessTimeSec: Double
        public var unitPrice: Int
        public var unlockPrice: Int

        public init(
            inputPerBatch: Int = 2,
            outputPerBatch: Int = 1,
            baseProcessTimeSec: Double = 2.4,
            unitPrice: Int = 28,
            unlockPrice: Int = 220
        ) {
            self.inputPerBatch = inputPerBatch
            self.outputPerBatch = outputPerBatch
            self.baseProcessTimeSec = baseProcessTimeSec
            self.unitPrice = unitPrice
            self.unlockPrice = unlockPrice
        }
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
        public var offline: OfflineConfig
        public var streak: StreakConfig

        public init(
            prestigeMinCoins: Int,
            prestigeCoinsPerPoint: Int,
            upgrades: MetaUpgradesConfig,
            offline: OfflineConfig = OfflineConfig(),
            streak: StreakConfig = StreakConfig()
        ) {
            self.prestigeMinCoins = prestigeMinCoins
            self.prestigeCoinsPerPoint = prestigeCoinsPerPoint
            self.upgrades = upgrades
            self.offline = offline
            self.streak = streak
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.prestigeMinCoins = try container.decode(Int.self, forKey: .prestigeMinCoins)
            self.prestigeCoinsPerPoint = try container.decode(Int.self, forKey: .prestigeCoinsPerPoint)
            self.upgrades = try container.decode(MetaUpgradesConfig.self, forKey: .upgrades)
            self.offline = try container.decodeIfPresent(OfflineConfig.self, forKey: .offline) ?? OfflineConfig()
            self.streak = try container.decodeIfPresent(StreakConfig.self, forKey: .streak) ?? StreakConfig()
        }

        public func upgrade(for type: MetaUpgradeType) -> MetaUpgradeEntry {
            switch type {
            case .startingCoins: return upgrades.startingCoins
            case .sellPriceMultiplier: return upgrades.sellPriceMultiplier
            case .processorSpeed: return upgrades.processorSpeed
            case .moveSpeedBonus: return upgrades.moveSpeedBonus
            }
        }
    }

    public struct OfflineConfig: Codable, Equatable {
        public var coinsPerSecond: Double
        public var maxOfflineSeconds: Double
        public var minAwardCoins: Int

        public init(
            coinsPerSecond: Double = 0.5,
            maxOfflineSeconds: Double = 4 * 60 * 60,
            minAwardCoins: Int = 1
        ) {
            self.coinsPerSecond = coinsPerSecond
            self.maxOfflineSeconds = maxOfflineSeconds
            self.minAwardCoins = minAwardCoins
        }
    }

    public struct StreakConfig: Codable, Equatable {
        /// Flat coin reward on day 1 of a streak.
        public var baseBonusCoins: Int
        /// Additional coins added per consecutive day (capped by ``maxStreakDays``).
        public var bonusPerDay: Int
        /// Cap on how many streak days contribute to the bonus payout.
        public var maxStreakDays: Int

        public init(
            baseBonusCoins: Int = 20,
            bonusPerDay: Int = 10,
            maxStreakDays: Int = 7
        ) {
            self.baseBonusCoins = baseBonusCoins
            self.bonusPerDay = bonusPerDay
            self.maxStreakDays = maxStreakDays
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
