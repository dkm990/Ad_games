import Foundation

public struct DebugTuningState: Equatable {
    public var playerAcceleration: Double
    public var playerMaxSpeed: Double
    public var pickupRadius: Double
    public var cameraFollowSmoothing: Double

    public init(
        playerAcceleration: Double,
        playerMaxSpeed: Double,
        pickupRadius: Double,
        cameraFollowSmoothing: Double
    ) {
        self.playerAcceleration = playerAcceleration
        self.playerMaxSpeed = playerMaxSpeed
        self.pickupRadius = pickupRadius
        self.cameraFollowSmoothing = cameraFollowSmoothing
    }
}

public enum DebugPanelAction {
    case setPlayerAcceleration(Double)
    case setPlayerMaxSpeed(Double)
    case setPickupRadius(Double)
    case setCameraFollowSmoothing(Double)
}

public protocol DebugPanelDelegate: AnyObject {
    func apply(action: DebugPanelAction)
}

public enum DebugPanelAvailability {
    #if DEBUG
    public static let isEnabled = true
    #else
    public static let isEnabled = false
    #endif
}
