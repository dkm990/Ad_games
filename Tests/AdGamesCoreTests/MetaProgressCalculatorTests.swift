import XCTest
@testable import AdGamesCore

final class MetaProgressCalculatorTests: XCTestCase {
    private let metaConfig = EconomyConfig.MetaConfig(
        prestigeMinCoins: 100,
        prestigeCoinsPerPoint: 25,
        upgrades: EconomyConfig.MetaUpgradesConfig(
            startingCoins: EconomyConfig.MetaUpgradeEntry(basePrice: 1, priceMultiplier: 1.5, effectPerLevel: 0, effectPerLevelInt: 10),
            sellPriceMultiplier: EconomyConfig.MetaUpgradeEntry(basePrice: 2, priceMultiplier: 1.6, effectPerLevel: 0.05, effectPerLevelInt: 0),
            processorSpeed: EconomyConfig.MetaUpgradeEntry(basePrice: 2, priceMultiplier: 1.6, effectPerLevel: 0.04, effectPerLevelInt: 0),
            moveSpeedBonus: EconomyConfig.MetaUpgradeEntry(basePrice: 1, priceMultiplier: 1.5, effectPerLevel: 0.03, effectPerLevelInt: 0)
        )
    )

    func test_prestigeReward_belowMinimum_returnsZero() {
        XCTAssertEqual(MetaProgressCalculator.prestigeReward(sessionCoins: 0, config: metaConfig), 0)
        XCTAssertEqual(MetaProgressCalculator.prestigeReward(sessionCoins: 99, config: metaConfig), 0)
    }

    func test_prestigeReward_atMinimum_returnsAtLeastOne() {
        // floor(sqrt(100 / 25)) = floor(2) = 2
        XCTAssertEqual(MetaProgressCalculator.prestigeReward(sessionCoins: 100, config: metaConfig), 2)
    }

    func test_prestigeReward_scalesWithSqrt() {
        // floor(sqrt(2500 / 25)) = floor(sqrt(100)) = 10
        XCTAssertEqual(MetaProgressCalculator.prestigeReward(sessionCoins: 2_500, config: metaConfig), 10)
        // floor(sqrt(10_000 / 25)) = floor(sqrt(400)) = 20
        XCTAssertEqual(MetaProgressCalculator.prestigeReward(sessionCoins: 10_000, config: metaConfig), 20)
    }

    func test_upgradePrice_growsGeometrically() {
        let lvl0 = MetaProgressCalculator.upgradePrice(type: .sellPriceMultiplier, level: 0, config: metaConfig)
        let lvl1 = MetaProgressCalculator.upgradePrice(type: .sellPriceMultiplier, level: 1, config: metaConfig)
        let lvl5 = MetaProgressCalculator.upgradePrice(type: .sellPriceMultiplier, level: 5, config: metaConfig)

        XCTAssertEqual(lvl0, 2)
        XCTAssertGreaterThan(lvl1, lvl0)
        XCTAssertGreaterThan(lvl5, lvl1 * 3)
    }

    func test_startingCoins_scalesWithLevel() {
        var upgrades = MetaUpgradeLevels()
        XCTAssertEqual(MetaProgressCalculator.startingCoins(upgrades: upgrades, config: metaConfig), 0)

        upgrades.startingCoins = 3
        XCTAssertEqual(MetaProgressCalculator.startingCoins(upgrades: upgrades, config: metaConfig), 30)
    }

    func test_sellPriceMultiplier_isAtLeastOneAndGrowsLinearly() {
        var upgrades = MetaUpgradeLevels()
        XCTAssertEqual(MetaProgressCalculator.sellPriceMultiplier(upgrades: upgrades, config: metaConfig), 1.0, accuracy: 1e-9)

        upgrades.sellPriceMultiplier = 4
        XCTAssertEqual(MetaProgressCalculator.sellPriceMultiplier(upgrades: upgrades, config: metaConfig), 1.2, accuracy: 1e-9)
    }

    func test_processTimeMultiplier_reducesButFloorsAt0_25() {
        var upgrades = MetaUpgradeLevels()
        XCTAssertEqual(MetaProgressCalculator.processTimeMultiplier(upgrades: upgrades, config: metaConfig), 1.0, accuracy: 1e-9)

        upgrades.processorSpeed = 5
        XCTAssertEqual(MetaProgressCalculator.processTimeMultiplier(upgrades: upgrades, config: metaConfig), 0.8, accuracy: 1e-9)

        upgrades.processorSpeed = 1_000
        XCTAssertEqual(MetaProgressCalculator.processTimeMultiplier(upgrades: upgrades, config: metaConfig), 0.25, accuracy: 1e-9)
    }

    func test_moveSpeedMultiplier_growsLinearly() {
        var upgrades = MetaUpgradeLevels()
        upgrades.moveSpeedBonus = 10
        XCTAssertEqual(MetaProgressCalculator.moveSpeedMultiplier(upgrades: upgrades, config: metaConfig), 1.3, accuracy: 1e-9)
    }
}
