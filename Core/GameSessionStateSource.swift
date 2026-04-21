import Foundation

public protocol GameSessionStateSource: AnyObject {
    var sessionState: GameSessionState { get }
    var metaProgress: MetaProgress { get }
    var effectiveMaxSpeed: Double { get }
    var effectiveCarryCapacity: Int { get }
    var effectiveProcessTimeSec: Double { get }
    var effectiveSellPriceMultiplier: Double { get }
    var currentPrestigeReward: Int { get }

    func metaUpgradePrice(for type: MetaUpgradeType) -> Int

    /// Returns the pending offline-earnings reward queued at launch and
    /// clears it so subsequent scene transitions don't re-present the
    /// same banner.
    func consumePendingOfflineReward() -> Int

    @discardableResult
    func dispatch(_ action: GameAction) -> GameSessionState
}
