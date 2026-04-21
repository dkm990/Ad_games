import Foundation

public enum MetaUpgradeType: String, Codable, CaseIterable {
    case startingCoins
    case sellPriceMultiplier
    case processorSpeed
    case moveSpeedBonus
}

public struct MetaUpgradeLevels: Codable, Equatable {
    public var startingCoins: Int
    public var sellPriceMultiplier: Int
    public var processorSpeed: Int
    public var moveSpeedBonus: Int

    public init(
        startingCoins: Int = 0,
        sellPriceMultiplier: Int = 0,
        processorSpeed: Int = 0,
        moveSpeedBonus: Int = 0
    ) {
        self.startingCoins = startingCoins
        self.sellPriceMultiplier = sellPriceMultiplier
        self.processorSpeed = processorSpeed
        self.moveSpeedBonus = moveSpeedBonus
    }

    public func level(for type: MetaUpgradeType) -> Int {
        switch type {
        case .startingCoins: return startingCoins
        case .sellPriceMultiplier: return sellPriceMultiplier
        case .processorSpeed: return processorSpeed
        case .moveSpeedBonus: return moveSpeedBonus
        }
    }

    public mutating func increment(_ type: MetaUpgradeType) {
        switch type {
        case .startingCoins: startingCoins += 1
        case .sellPriceMultiplier: sellPriceMultiplier += 1
        case .processorSpeed: processorSpeed += 1
        case .moveSpeedBonus: moveSpeedBonus += 1
        }
    }
}

public struct MetaProgress: Codable, Equatable {
    public var prestigePoints: Int
    public var upgrades: MetaUpgradeLevels
    public var totalPrestiges: Int
    public var lifetimeCoinsEarned: Int
    /// Wall-clock timestamp of the last dispatched action. Used to compute
    /// offline earnings on the next launch. `nil` for fresh installs, which
    /// suppresses the offline reward until the first session checkpoints.
    public var lastSeenAt: Date?

    public init(
        prestigePoints: Int = 0,
        upgrades: MetaUpgradeLevels = MetaUpgradeLevels(),
        totalPrestiges: Int = 0,
        lifetimeCoinsEarned: Int = 0,
        lastSeenAt: Date? = nil
    ) {
        self.prestigePoints = prestigePoints
        self.upgrades = upgrades
        self.totalPrestiges = totalPrestiges
        self.lifetimeCoinsEarned = lifetimeCoinsEarned
        self.lastSeenAt = lastSeenAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prestigePoints = try container.decodeIfPresent(Int.self, forKey: .prestigePoints) ?? 0
        self.upgrades = try container.decodeIfPresent(MetaUpgradeLevels.self, forKey: .upgrades) ?? MetaUpgradeLevels()
        self.totalPrestiges = try container.decodeIfPresent(Int.self, forKey: .totalPrestiges) ?? 0
        self.lifetimeCoinsEarned = try container.decodeIfPresent(Int.self, forKey: .lifetimeCoinsEarned) ?? 0
        self.lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
    }
}

public enum MetaProgressCalculator {
    /// Prestige reward = floor(sqrt(coins / coinsPerPoint)), gated by minimum coins.
    public static func prestigeReward(
        sessionCoins: Int,
        config: EconomyConfig.MetaConfig
    ) -> Int {
        guard sessionCoins >= config.prestigeMinCoins else { return 0 }
        let ratio = Double(sessionCoins) / Double(max(1, config.prestigeCoinsPerPoint))
        return max(0, Int(ratio.squareRoot().rounded(.down)))
    }

    public static func upgradePrice(
        type: MetaUpgradeType,
        level: Int,
        config: EconomyConfig.MetaConfig
    ) -> Int {
        let entry = config.upgrade(for: type)
        let raw = Double(entry.basePrice) * pow(entry.priceMultiplier, Double(level))
        return max(1, Int(raw.rounded(.toNearestOrAwayFromZero)))
    }

    public static func startingCoins(
        upgrades: MetaUpgradeLevels,
        config: EconomyConfig.MetaConfig
    ) -> Int {
        upgrades.startingCoins * config.upgrade(for: .startingCoins).effectPerLevelInt
    }

    /// Multiplier applied to base sell price (>= 1.0).
    public static func sellPriceMultiplier(
        upgrades: MetaUpgradeLevels,
        config: EconomyConfig.MetaConfig
    ) -> Double {
        1.0 + Double(upgrades.sellPriceMultiplier) * config.upgrade(for: .sellPriceMultiplier).effectPerLevel
    }

    /// Multiplier applied to base processor time (<= 1.0 means faster).
    public static func processTimeMultiplier(
        upgrades: MetaUpgradeLevels,
        config: EconomyConfig.MetaConfig
    ) -> Double {
        let raw = 1.0 - Double(upgrades.processorSpeed) * config.upgrade(for: .processorSpeed).effectPerLevel
        return max(0.25, raw)
    }

    /// Multiplier applied to base player max speed (>= 1.0).
    public static func moveSpeedMultiplier(
        upgrades: MetaUpgradeLevels,
        config: EconomyConfig.MetaConfig
    ) -> Double {
        1.0 + Double(upgrades.moveSpeedBonus) * config.upgrade(for: .moveSpeedBonus).effectPerLevel
    }

    /// Coins earned while the app was in the background. Negative deltas
    /// (clock skew, wall-clock jumps) are treated as zero, the delta is
    /// capped at `maxOfflineSeconds`, and the final value is scaled by meta
    /// processor-speed and sell-price bonuses. Returns 0 if `lastSeenAt` is
    /// `nil` (fresh install) or the award would be below `minAwardCoins`.
    public static func offlineCoins(
        lastSeenAt: Date?,
        now: Date,
        upgrades: MetaUpgradeLevels,
        config: EconomyConfig.MetaConfig
    ) -> Int {
        guard let last = lastSeenAt else { return 0 }
        let rawDelta = now.timeIntervalSince(last)
        guard rawDelta > 0 else { return 0 }
        let clamped = min(rawDelta, max(0, config.offline.maxOfflineSeconds))
        let processorBoost = 1.0 + Double(upgrades.processorSpeed) * config.upgrade(for: .processorSpeed).effectPerLevel
        let sellBoost = sellPriceMultiplier(upgrades: upgrades, config: config)
        let raw = clamped * config.offline.coinsPerSecond * processorBoost * sellBoost
        let award = Int(raw.rounded(.down))
        return award >= config.offline.minAwardCoins ? award : 0
    }
}
