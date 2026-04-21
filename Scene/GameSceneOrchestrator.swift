import Foundation

public final class GameSceneOrchestrator {
    private let stateSource: GameSessionStateSource

    public init(stateSource: GameSessionStateSource) {
        self.stateSource = stateSource
    }

    public var sessionState: GameSessionState {
        stateSource.sessionState
    }

    public var metaProgress: MetaProgress {
        stateSource.metaProgress
    }

    public var effectiveMaxSpeed: Double {
        stateSource.effectiveMaxSpeed
    }

    public var effectiveCarryCapacity: Int {
        stateSource.effectiveCarryCapacity
    }

    public var effectiveProcessTimeSec: Double {
        stateSource.effectiveProcessTimeSec
    }

    public var effectiveSellPriceMultiplier: Double {
        stateSource.effectiveSellPriceMultiplier
    }

    public var currentPrestigeReward: Int {
        stateSource.currentPrestigeReward
    }

    public func metaUpgradePrice(for type: MetaUpgradeType) -> Int {
        stateSource.metaUpgradePrice(for: type)
    }

    // Scene should call this method on interactions and then update visuals/HUD from the returned state.
    @discardableResult
    public func perform(_ action: GameAction) -> GameSessionState {
        stateSource.dispatch(action)
    }
}
