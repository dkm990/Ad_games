import Foundation

public final class GameSessionStore: GameSessionStateSource {
    private let reducer: GameStateReducer
    private let progressStore: LocalProgressStore
    private let metaStore: LocalMetaStore

    public init(
        config: EconomyConfig,
        progressStore: LocalProgressStore,
        metaStore: LocalMetaStore
    ) {
        self.progressStore = progressStore
        self.metaStore = metaStore

        let restoredMeta = metaStore.loadMeta() ?? MetaProgress()
        let restoredState = progressStore.loadState()
        self.reducer = GameStateReducer(
            initialState: restoredState ?? GameSessionStore.freshState(meta: restoredMeta, config: config),
            initialMeta: restoredMeta,
            config: config
        )
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
