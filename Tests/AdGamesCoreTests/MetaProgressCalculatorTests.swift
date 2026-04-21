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

    // MARK: - Offline earnings

    private var offlineMetaConfig: EconomyConfig.MetaConfig {
        EconomyConfig.MetaConfig(
            prestigeMinCoins: 100,
            prestigeCoinsPerPoint: 25,
            upgrades: metaConfig.upgrades,
            offline: EconomyConfig.OfflineConfig(
                coinsPerSecond: 1.0,
                maxOfflineSeconds: 600,
                minAwardCoins: 1
            )
        )
    }

    func test_offlineCoins_returnsZero_whenLastSeenIsNil() {
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: nil,
            now: Date(timeIntervalSince1970: 1_000),
            upgrades: MetaUpgradeLevels(),
            config: offlineMetaConfig
        )
        XCTAssertEqual(reward, 0)
    }

    func test_offlineCoins_returnsZero_whenClockRanBackwards() {
        let now = Date(timeIntervalSince1970: 1_000)
        let future = Date(timeIntervalSince1970: 2_000)
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: future,
            now: now,
            upgrades: MetaUpgradeLevels(),
            config: offlineMetaConfig
        )
        XCTAssertEqual(reward, 0)
    }

    func test_offlineCoins_scalesLinearlyWithElapsedTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-30) // 30 seconds
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: last,
            now: now,
            upgrades: MetaUpgradeLevels(),
            config: offlineMetaConfig
        )
        // 30s * 1 coin/s * 1.0 processor boost * 1.0 sell boost = 30
        XCTAssertEqual(reward, 30)
    }

    func test_offlineCoins_capsAtMaxOfflineSeconds() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-24 * 3600) // 24 hours
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: last,
            now: now,
            upgrades: MetaUpgradeLevels(),
            config: offlineMetaConfig
        )
        // cap = 600s * 1 * 1 * 1 = 600
        XCTAssertEqual(reward, 600)
    }

    func test_offlineCoins_appliesProcessorAndSellBoosts() {
        var upgrades = MetaUpgradeLevels()
        upgrades.processorSpeed = 5 // +0.04 * 5 = 1.20x
        upgrades.sellPriceMultiplier = 4 // +0.05 * 4 = 1.20x
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-100)
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: last,
            now: now,
            upgrades: upgrades,
            config: offlineMetaConfig
        )
        // 100 * 1 * 1.2 * 1.2 = 144
        XCTAssertEqual(reward, 144)
    }

    func test_offlineCoins_floorsBelowMinAwardCoins() {
        let sparseConfig = EconomyConfig.MetaConfig(
            prestigeMinCoins: 100,
            prestigeCoinsPerPoint: 25,
            upgrades: metaConfig.upgrades,
            offline: EconomyConfig.OfflineConfig(
                coinsPerSecond: 0.01,
                maxOfflineSeconds: 600,
                minAwardCoins: 5
            )
        )
        let now = Date(timeIntervalSince1970: 10_000)
        // 10 seconds * 0.01 = 0.1 coins, below minAwardCoins=5 → 0
        let reward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: now.addingTimeInterval(-10),
            now: now,
            upgrades: MetaUpgradeLevels(),
            config: sparseConfig
        )
        XCTAssertEqual(reward, 0)
    }

    // MARK: - Daily streak

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var streakConfig: EconomyConfig.MetaConfig {
        EconomyConfig.MetaConfig(
            prestigeMinCoins: 100,
            prestigeCoinsPerPoint: 25,
            upgrades: metaConfig.upgrades,
            streak: EconomyConfig.StreakConfig(
                baseBonusCoins: 20,
                bonusPerDay: 10,
                maxStreakDays: 7
            )
        )
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return utcCalendar.date(from: comps)!
    }

    func test_streakBonus_grewFromBaseAndCapsAtMaxDays() {
        XCTAssertEqual(MetaProgressCalculator.streakBonusCoins(streak: 0, config: streakConfig), 0)
        XCTAssertEqual(MetaProgressCalculator.streakBonusCoins(streak: 1, config: streakConfig), 20)
        XCTAssertEqual(MetaProgressCalculator.streakBonusCoins(streak: 2, config: streakConfig), 30)
        XCTAssertEqual(MetaProgressCalculator.streakBonusCoins(streak: 7, config: streakConfig), 80)
        // Cap: day 10 still pays the day-7 amount
        XCTAssertEqual(MetaProgressCalculator.streakBonusCoins(streak: 10, config: streakConfig), 80)
    }

    func test_streakEvaluator_firstCheckIn_startsStreak() {
        let now = utcDate(year: 2026, month: 4, day: 21)
        let outcome = DailyStreakEvaluator.evaluate(
            lastCheckInDay: nil,
            previousStreak: 0,
            now: now,
            calendar: utcCalendar,
            config: streakConfig
        )
        XCTAssertEqual(outcome.transition, .started)
        XCTAssertEqual(outcome.newStreak, 1)
        XCTAssertEqual(outcome.bonusCoins, 20)
    }

    func test_streakEvaluator_sameDay_isAlreadyClaimed() {
        let today = utcDate(year: 2026, month: 4, day: 21, hour: 3)
        let later = utcDate(year: 2026, month: 4, day: 21, hour: 23)
        let outcome = DailyStreakEvaluator.evaluate(
            lastCheckInDay: today,
            previousStreak: 5,
            now: later,
            calendar: utcCalendar,
            config: streakConfig
        )
        XCTAssertEqual(outcome.transition, .alreadyClaimed)
        XCTAssertEqual(outcome.newStreak, 5)
        XCTAssertEqual(outcome.bonusCoins, 0)
    }

    func test_streakEvaluator_nextDay_continuesStreak() {
        let yesterday = utcDate(year: 2026, month: 4, day: 20)
        let today = utcDate(year: 2026, month: 4, day: 21)
        let outcome = DailyStreakEvaluator.evaluate(
            lastCheckInDay: yesterday,
            previousStreak: 3,
            now: today,
            calendar: utcCalendar,
            config: streakConfig
        )
        XCTAssertEqual(outcome.transition, .continued)
        XCTAssertEqual(outcome.newStreak, 4)
        XCTAssertEqual(outcome.bonusCoins, 50) // 20 + 10 * 3
    }

    func test_streakEvaluator_skipDay_resetsToOne() {
        let twoDaysAgo = utcDate(year: 2026, month: 4, day: 19)
        let today = utcDate(year: 2026, month: 4, day: 21)
        let outcome = DailyStreakEvaluator.evaluate(
            lastCheckInDay: twoDaysAgo,
            previousStreak: 6,
            now: today,
            calendar: utcCalendar,
            config: streakConfig
        )
        XCTAssertEqual(outcome.transition, .reset)
        XCTAssertEqual(outcome.newStreak, 1)
        XCTAssertEqual(outcome.bonusCoins, 20)
    }

    func test_streakEvaluator_clockRewind_resetsToOne() {
        let tomorrow = utcDate(year: 2026, month: 4, day: 22)
        let today = utcDate(year: 2026, month: 4, day: 21)
        let outcome = DailyStreakEvaluator.evaluate(
            lastCheckInDay: tomorrow,
            previousStreak: 4,
            now: today,
            calendar: utcCalendar,
            config: streakConfig
        )
        XCTAssertEqual(outcome.transition, .reset)
        XCTAssertEqual(outcome.newStreak, 1)
    }
}
