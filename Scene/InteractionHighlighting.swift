import CoreGraphics
import Foundation

public enum ZoneKind: String {
    case resource
    case processorInput
    case processorOutput
    case sell
    case gate
}

public struct InteractionCandidate {
    public var zoneID: Int
    public var kind: ZoneKind
    public var distanceToPlayer: CGFloat
    public var isWithinInteractionRadius: Bool

    public init(zoneID: Int, kind: ZoneKind, distanceToPlayer: CGFloat, isWithinInteractionRadius: Bool) {
        self.zoneID = zoneID
        self.kind = kind
        self.distanceToPlayer = distanceToPlayer
        self.isWithinInteractionRadius = isWithinInteractionRadius
    }
}

public enum HighlightStyle: String {
    case outline
    case scalePulse
    case colorHighlight
    case arrowIndicator
}

public struct HighlightDecision {
    public var primaryZoneID: Int?
    public var style: HighlightStyle

    public init(primaryZoneID: Int?, style: HighlightStyle = .outline) {
        self.primaryZoneID = primaryZoneID
        self.style = style
    }
}

public enum PrimaryTargetResolver {
    public static func resolve(
        candidates: [InteractionCandidate],
        guidance: GuidanceState
    ) -> HighlightDecision {
        let inRange = candidates.filter { $0.isWithinInteractionRadius }
        guard !inRange.isEmpty else { return HighlightDecision(primaryZoneID: nil) }

        let guidanceFiltered = inRange.filter { matchesGuidance(kind: $0.kind, guidance: guidance) }
        let source = guidanceFiltered.isEmpty ? inRange : guidanceFiltered

        let best = source.min {
            if $0.distanceToPlayer == $1.distanceToPlayer {
                return $0.zoneID < $1.zoneID
            }
            return $0.distanceToPlayer < $1.distanceToPlayer
        }

        return HighlightDecision(primaryZoneID: best?.zoneID)
    }

    private static func matchesGuidance(kind: ZoneKind, guidance: GuidanceState) -> Bool {
        switch (kind, guidance.target) {
        case (.resource, .collectResource),
             (.processorInput, .goProcessorInput),
             (.processorOutput, .collectProcessedOutput),
             (.sell, .goSellZone),
             (.gate, .unlockGate):
            return true
        default:
            return false
        }
    }
}
