import XCTest
@testable import AdGamesCore

final class GameStateReducerTests: XCTestCase {
    private func makeConfig(
        prestigeMin: Int = 100,
        coinsPerPoint: Int = 25
    ) -> EconomyConfig {
        EconomyConfig(
            player: EconomyConfig.PlayerConfig(
                pickupRadius: 88,
                playerAcceleration: 900,
                playerMaxSpeed: 300,
                baseCarryCapacity: 5
            ),
            processing: EconomyConfig.ProcessingConfig(
                inputPerBatch: 2,
                outputPerBatch: 1,
                baseProcessTimeSec: 2.0
            ),
            sell: EconomyConfig.SellConfig(processedUnitPrice: 10),
            zones: [
                EconomyConfig.ZoneConfig(id: 1, unlockPrice: 0),
                EconomyConfig.ZoneConfig(id: 2, unlockPrice: 60),
                EconomyConfig.ZoneConfig(id: 3, unlockPrice: 140),
            ],
            upgrades: EconomyConfig.UpgradeConfig(
                moveSpeed: EconomyConfig.MoveSpeedConfig(basePrice: 30, priceMultiplier: 1.55, maxSpeedDeltaPerLevel: 45),
                carryCapacity: EconomyConfig.CarryCapacityConfig(basePrice: 25, priceMultiplier: 1.6, capacityDeltaPerLevel: 2),
                processingSpeed: EconomyConfig.ProcessingSpeedConfig(basePrice: 35, priceMultiplier: 1.65, timeMultiplierPerLevel: 0.75)
            ),
            meta: EconomyConfig.MetaConfig(
                prestigeMinCoins: prestigeMin,
                prestigeCoinsPerPoint: coinsPerPoint,
                upgrades: EconomyConfig.MetaUpgradesConfig(
                    startingCoins: EconomyConfig.MetaUpgradeEntry(basePrice: 1, priceMultiplier: 1.5, effectPerLevel: 0, effectPerLevelInt: 10),
                    sellPriceMultiplier: EconomyConfig.MetaUpgradeEntry(basePrice: 2, priceMultiplier: 1.6, effectPerLevel: 0.05, effectPerLevelInt: 0),
                    processorSpeed: EconomyConfig.MetaUpgradeEntry(basePrice: 2, priceMultiplier: 1.6, effectPerLevel: 0.04, effectPerLevelInt: 0),
                    moveSpeedBonus: EconomyConfig.MetaUpgradeEntry(basePrice: 1, priceMultiplier: 1.5, effectPerLevel: 0.03, effectPerLevelInt: 0)
                )
            )
        )
    }

    // MARK: - Core loop

    func test_collectRaw_respectsCarryCapacity() {
        let reducer = GameStateReducer(config: makeConfig())
        reducer.send(.collectRaw(units: 100))
        XCTAssertEqual(reducer.state.carryAmount, reducer.effectiveCarryCapacity)
    }

    func test_depositAndProcess_producesProcessedOutput() {
        let reducer = GameStateReducer(config: makeConfig())
        reducer.send(.collectRaw(units: 4))
        reducer.send(.depositRawForProcessing(units: 4))
        reducer.send(.processingCompleted)
        reducer.send(.processingCompleted)
        reducer.send(.collectProcessedOutput(units: 10))
        XCTAssertEqual(reducer.state.processedInventory, 2)
        XCTAssertEqual(reducer.state.processingQueue.queuedRawUnits, 0)
    }

    func test_sellProcessed_withoutMeta_paysBasePrice() {
        let reducer = GameStateReducer(config: makeConfig())
        reducer.send(.collectRaw(units: 2))
        reducer.send(.depositRawForProcessing(units: 2))
        reducer.send(.processingCompleted)
        reducer.send(.collectProcessedOutput(units: 1))
        reducer.send(.sellProcessed(units: 1))
        XCTAssertEqual(reducer.state.coins, 10)
    }

    // MARK: - Meta effects on session formulas

    func test_sellPriceMultiplier_isAppliedOnSell() {
        var meta = MetaProgress()
        meta.upgrades.sellPriceMultiplier = 4 // +20%
        let reducer = GameStateReducer(
            initialState: GameSessionState(processedInventory: 5),
            initialMeta: meta,
            config: makeConfig()
        )
        reducer.send(.sellProcessed(units: 5))
        XCTAssertEqual(reducer.state.coins, 60) // round(5 * 10 * 1.2) = 60
    }

    func test_moveSpeedMultiplier_isAppliedToEffectiveSpeed() {
        var meta = MetaProgress()
        meta.upgrades.moveSpeedBonus = 10 // +30%
        let config = makeConfig()
        let reducer = GameStateReducer(initialMeta: meta, config: config)
        XCTAssertEqual(reducer.effectiveMaxSpeed, config.player.playerMaxSpeed * 1.3, accuracy: 1e-6)
    }

    func test_processorSpeed_reducesEffectiveProcessTime() {
        var meta = MetaProgress()
        meta.upgrades.processorSpeed = 5 // -20%
        let config = makeConfig()
        let reducer = GameStateReducer(initialMeta: meta, config: config)
        XCTAssertEqual(reducer.effectiveProcessTimeSec, config.processing.baseProcessTimeSec * 0.8, accuracy: 1e-6)
    }

    // MARK: - Prestige

    func test_prestige_belowMinimum_isNoOp() {
        let reducer = GameStateReducer(initialState: GameSessionState(coins: 80), config: makeConfig())
        reducer.send(.prestige)
        XCTAssertEqual(reducer.meta.prestigePoints, 0)
        XCTAssertEqual(reducer.meta.totalPrestiges, 0)
        XCTAssertEqual(reducer.state.coins, 80)
    }

    func test_prestige_atMinimum_awardsPointsAndResetsSession() {
        let reducer = GameStateReducer(
            initialState: GameSessionState(
                carryAmount: 3,
                processedInventory: 2,
                coins: 400,
                unlockedZoneIDs: [1, 2]
            ),
            config: makeConfig()
        )
        reducer.send(.prestige)
        XCTAssertEqual(reducer.meta.prestigePoints, 4) // floor(sqrt(400/25)) = 4
        XCTAssertEqual(reducer.meta.totalPrestiges, 1)
        XCTAssertEqual(reducer.meta.lifetimeCoinsEarned, 400)
        XCTAssertEqual(reducer.state.carryAmount, 0)
        XCTAssertEqual(reducer.state.processedInventory, 0)
        XCTAssertEqual(reducer.state.coins, 0)
        XCTAssertEqual(reducer.state.unlockedZoneIDs, [1])
    }

    func test_prestige_appliesStartingCoinsFromMeta() {
        var meta = MetaProgress()
        meta.upgrades.startingCoins = 2 // +20 coins on fresh state
        let reducer = GameStateReducer(
            initialState: GameSessionState(coins: 2_500),
            initialMeta: meta,
            config: makeConfig()
        )
        reducer.send(.prestige)
        XCTAssertEqual(reducer.state.coins, 20)
    }

    // MARK: - Purchase meta upgrade

    func test_purchaseMetaUpgrade_withoutFunds_isNoOp() {
        let reducer = GameStateReducer(config: makeConfig())
        reducer.send(.purchaseMetaUpgrade(type: .sellPriceMultiplier))
        XCTAssertEqual(reducer.meta.upgrades.sellPriceMultiplier, 0)
    }

    func test_purchaseMetaUpgrade_spendsPointsAndIncrementsLevel() {
        var meta = MetaProgress(prestigePoints: 10)
        meta.upgrades.sellPriceMultiplier = 0
        let reducer = GameStateReducer(initialMeta: meta, config: makeConfig())
        reducer.send(.purchaseMetaUpgrade(type: .sellPriceMultiplier))
        XCTAssertEqual(reducer.meta.upgrades.sellPriceMultiplier, 1)
        XCTAssertEqual(reducer.meta.prestigePoints, 8) // base price 2
    }

    func test_purchaseMetaUpgrade_priceGrowsWithLevel() {
        let reducer = GameStateReducer(initialMeta: MetaProgress(prestigePoints: 100), config: makeConfig())
        let firstPrice = reducer.metaUpgradePrice(for: .sellPriceMultiplier)
        reducer.send(.purchaseMetaUpgrade(type: .sellPriceMultiplier))
        let secondPrice = reducer.metaUpgradePrice(for: .sellPriceMultiplier)
        XCTAssertEqual(firstPrice, 2)
        XCTAssertGreaterThan(secondPrice, firstPrice)
    }

    // MARK: - Guidance

    func test_guidanceState_transitionsAcrossLoop() {
        let reducer = GameStateReducer(config: makeConfig())
        XCTAssertEqual(reducer.state.guidanceState.target, .collectResource)
        reducer.send(.collectRaw(units: 2))
        XCTAssertEqual(reducer.state.guidanceState.target, .goProcessorInput)
        reducer.send(.depositRawForProcessing(units: 2))
        reducer.send(.processingCompleted)
        XCTAssertEqual(reducer.state.guidanceState.target, .collectProcessedOutput)
        reducer.send(.collectProcessedOutput(units: 1))
        XCTAssertEqual(reducer.state.guidanceState.target, .goSellZone)
    }

    // MARK: - Offline earnings

    func test_applyOfflineEarnings_addsCoinsAndTouchesLastSeen() {
        let fixedNow = Date(timeIntervalSince1970: 42_000)
        let reducer = GameStateReducer(
            initialState: GameSessionState(coins: 50),
            config: makeConfig(),
            clock: { fixedNow }
        )
        reducer.send(.applyOfflineEarnings(coins: 25))
        XCTAssertEqual(reducer.state.coins, 75)
        XCTAssertEqual(reducer.meta.lastSeenAt, fixedNow)
    }

    func test_applyOfflineEarnings_withZeroCoins_isNoOp() {
        let reducer = GameStateReducer(
            initialState: GameSessionState(coins: 50),
            config: makeConfig()
        )
        reducer.send(.applyOfflineEarnings(coins: 0))
        XCTAssertEqual(reducer.state.coins, 50)
    }

    func test_lastSeenAt_isTouchedOnEveryDispatch() {
        var clockValue = Date(timeIntervalSince1970: 1_000)
        let reducer = GameStateReducer(
            config: makeConfig(),
            clock: { clockValue }
        )
        reducer.send(.collectRaw(units: 1))
        XCTAssertEqual(reducer.meta.lastSeenAt, clockValue)
        clockValue = Date(timeIntervalSince1970: 2_000)
        reducer.send(.recalculateGuidance)
        XCTAssertEqual(reducer.meta.lastSeenAt, clockValue)
    }

    // MARK: - Daily streak

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return utcCalendar().date(from: comps)!
    }

    func test_checkInDaily_firstTime_startsStreakAndAwardsCoins() {
        var now = utcDate(year: 2026, month: 4, day: 21)
        let reducer = GameStateReducer(
            config: makeConfig(),
            clock: { now },
            calendar: utcCalendar()
        )
        reducer.send(.checkInDaily)
        XCTAssertEqual(reducer.meta.dailyStreak, 1)
        XCTAssertEqual(reducer.state.coins, 20) // base bonus from default StreakConfig
        XCTAssertEqual(reducer.lastStreakOutcome?.transition, .started)

        // Re-dispatch on the same day should be a no-op
        now = utcDate(year: 2026, month: 4, day: 21, hour: 23)
        reducer.send(.checkInDaily)
        XCTAssertEqual(reducer.meta.dailyStreak, 1)
        XCTAssertEqual(reducer.state.coins, 20)
        XCTAssertEqual(reducer.lastStreakOutcome?.transition, .alreadyClaimed)
    }

    func test_checkInDaily_consecutiveDays_incrementStreak() {
        var now = utcDate(year: 2026, month: 4, day: 21)
        let reducer = GameStateReducer(
            config: makeConfig(),
            clock: { now },
            calendar: utcCalendar()
        )
        reducer.send(.checkInDaily)
        now = utcDate(year: 2026, month: 4, day: 22)
        reducer.send(.checkInDaily)
        XCTAssertEqual(reducer.meta.dailyStreak, 2)
        // base (20) for day 1 + continued (30) for day 2
        XCTAssertEqual(reducer.state.coins, 50)
    }
}
