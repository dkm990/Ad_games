import Foundation

public struct DebugTuningState: Equatable {
    public var moveSpeed: Double
    public var carryCapacity: Int
    public var processingTimeSec: Double
    public var sellPrice: Int
    public var zoneUnlockPrices: [Int: Int]

    public init(
        moveSpeed: Double,
        carryCapacity: Int,
        processingTimeSec: Double,
        sellPrice: Int,
        zoneUnlockPrices: [Int: Int]
    ) {
        self.moveSpeed = moveSpeed
        self.carryCapacity = carryCapacity
        self.processingTimeSec = processingTimeSec
        self.sellPrice = sellPrice
        self.zoneUnlockPrices = zoneUnlockPrices
    }
}

public enum DebugPanelAction {
    case setMoveSpeed(Double)
    case setCarryCapacity(Int)
    case setProcessingTimeSec(Double)
    case setSellPrice(Int)
    case setUnlockPrice(zoneID: Int, price: Int)
    case resetProgress
    case skipUnlockNextZone
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
