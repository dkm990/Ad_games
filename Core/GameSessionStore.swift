import Foundation

public final class GameSessionStore: GameSessionStateSource {
    private let reducer: GameStateReducer
    private let progressStore: LocalProgressStore

    public init(config: EconomyConfig, progressStore: LocalProgressStore) {
        self.progressStore = progressStore

        let restored = progressStore.loadState()
        self.reducer = GameStateReducer(initialState: restored ?? GameSessionState(), config: config)
    }

    public var sessionState: GameSessionState {
        reducer.state
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

    @discardableResult
    public func dispatch(_ action: GameAction) -> GameSessionState {
        let updated = reducer.send(action)
        progressStore.saveState(updated)
        return updated
    }
}
