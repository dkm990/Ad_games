import Foundation

public enum GuidanceTextPresenter {
    public static func text(for guidance: GuidanceState) -> String {
        switch guidance.target {
        case .collectResource:
            return "Collect resources"
        case .goProcessorInput:
            return "Bring resources to processor"
        case .collectProcessedOutput:
            return "Collect processed output"
        case .goSellZone:
            return "Sell processed goods"
        case .unlockGate:
            return "Unlock next zone"
        }
    }
}
