import Foundation

public final class GameSessionStore: GameSessionStateSource {
    private let reducer: GameStateReducer
    private let progressStore: LocalProgressStore
    private let metaStore: LocalMetaStore
    private var pendingOfflineReward: Int
    private var pendingStreakOutcome: DailyStreakOutcome?

    public init(
        config: EconomyConfig,
        progressStore: LocalProgressStore,
        metaStore: LocalMetaStore,
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.progressStore = progressStore
        self.metaStore = metaStore

        let restoredMeta = metaStore.loadMeta() ?? MetaProgress()
        let restoredState = progressStore.loadState()
        let reducer = GameStateReducer(
            initialState: restoredState ?? GameSessionStore.freshState(meta: restoredMeta, config: config),
            initialMeta: restoredMeta,
            config: config,
            clock: clock,
            calendar: calendar
        )
        self.reducer = reducer

        let offlineReward = MetaProgressCalculator.offlineCoins(
            lastSeenAt: restoredMeta.lastSeenAt,
            now: clock(),
            upgrades: restoredMeta.upgrades,
            config: config.meta
        )

        if offlineReward > 0 {
            _ = reducer.send(.applyOfflineEarnings(coins: offlineReward))
        }
        self.pendingOfflineReward = offlineReward

        _ = reducer.send(.checkInDaily)
        let outcome = reducer.lastStreakOutcome
        switch outcome?.transition {
        case .started, .continued, .reset:
            self.pendingStreakOutcome = outcome
        case .alreadyClaimed, .none:
            self.pendingStreakOutcome = nil
        }

        if offlineReward > 0 || pendingStreakOutcome != nil {
            progressStore.saveState(reducer.state)
            metaStore.saveMeta(reducer.meta)
        }
    }

    public var sessionState: GameSessionState {
        reducer.state
    }

    public var metaProgress: MetaProgress {
        reducer.meta
    }

    public var effectiveMaxSpeed: Double {
        reducer.effectiveMaxSpeed
    }

    public var effectiveCarryCapacity: Int {
        reducer.effectiveCarryCapacity
    }

    public var effectiveProcessTimeSec: Double {
        reducer.effectiveProcessTimeSec
    }

    public var effectiveSellPriceMultiplier: Double {
        reducer.effectiveSellPriceMultiplier
    }

    public var currentPrestigeReward: Int {
        reducer.currentPrestigeReward
    }

    public func metaUpgradePrice(for type: MetaUpgradeType) -> Int {
        reducer.metaUpgradePrice(for: type)
    }

    public func consumePendingOfflineReward() -> Int {
        let reward = pendingOfflineReward
        pendingOfflineReward = 0
        return reward
    }

    public func consumePendingStreakOutcome() -> DailyStreakOutcome? {
        let outcome = pendingStreakOutcome
        pendingStreakOutcome = nil
        return outcome
    }

    @discardableResult
    public func dispatch(_ action: GameAction) -> GameSessionState {
        let updated = reducer.send(action)
        progressStore.saveState(updated)
        metaStore.saveMeta(reducer.meta)
        return updated
    }

    private static func freshState(meta: MetaProgress, config: EconomyConfig) -> GameSessionState {
        let startingCoins = MetaProgressCalculator.startingCoins(upgrades: meta.upgrades, config: config.meta)
        return GameSessionState(coins: startingCoins)
    }
}
