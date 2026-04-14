import Foundation

public protocol GameSessionStateSource: AnyObject {
    var sessionState: GameSessionState { get }
    var effectiveMaxSpeed: Double { get }
    var effectiveCarryCapacity: Int { get }
    var effectiveProcessTimeSec: Double { get }

    @discardableResult
    func dispatch(_ action: GameAction) -> GameSessionState
}
