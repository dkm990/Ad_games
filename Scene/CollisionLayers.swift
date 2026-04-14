import Foundation

public struct CollisionLayer: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let player = CollisionLayer(rawValue: 1 << 0)
    public static let resourceNode = CollisionLayer(rawValue: 1 << 1)
    public static let interactionZone = CollisionLayer(rawValue: 1 << 2)
    public static let blockingGeometry = CollisionLayer(rawValue: 1 << 3)
}

public struct CollisionPolicy {
    public static let playerCollisionMask: CollisionLayer = [.blockingGeometry]
    public static let playerContactMask: CollisionLayer = [.resourceNode, .interactionZone]

    public static let resourceCollisionMask: CollisionLayer = []
    public static let interactionZoneCollisionMask: CollisionLayer = []

    // Interaction zones are contact-only and must never push/block entities.
    public static let interactionZoneIsPhysicalBlocker = false
}
