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

    public init(
        prestigePoints: Int = 0,
        upgrades: MetaUpgradeLevels = MetaUpgradeLevels(),
        totalPrestiges: Int = 0,
        lifetimeCoinsEarned: Int = 0
    ) {
        self.prestigePoints = prestigePoints
        self.upgrades = upgrades
        self.totalPrestiges = totalPrestiges
        self.lifetimeCoinsEarned = lifetimeCoinsEarned
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
}
