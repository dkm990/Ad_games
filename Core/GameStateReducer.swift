import Foundation

public final class GameStateReducer {
    public private(set) var state: GameSessionState
    public let config: EconomyConfig

    public init(initialState: GameSessionState = GameSessionState(), config: EconomyConfig) {
        self.state = initialState
        self.config = config
        recalculateGuidanceState()
    }

    @discardableResult
    public func send(_ action: GameAction) -> GameSessionState {
        switch action {
        case let .collectRaw(units):
            let capacity = effectiveCarryCapacity
            let free = max(0, capacity - state.carryAmount)
            let accepted = min(units, free)
            state.carryAmount += accepted

        case let .depositRawForProcessing(units):
            let deposited = min(units, state.carryAmount)
            state.carryAmount -= deposited
            state.processingQueue.queuedRawUnits += deposited

        case .processingCompleted:
            guard state.processingQueue.queuedRawUnits >= config.processing.inputPerBatch else { break }
            state.processingQueue.queuedRawUnits -= config.processing.inputPerBatch
            state.processingQueue.processedReadyUnits += config.processing.outputPerBatch

        case let .collectProcessedOutput(units):
            let taken = min(units, state.processingQueue.processedReadyUnits)
            state.processingQueue.processedReadyUnits -= taken
            state.processedInventory += taken

        case let .sellProcessed(units):
            let sold = min(units, state.processedInventory)
            state.processedInventory -= sold
            state.coins += sold * config.sell.processedUnitPrice

        case let .unlockZone(id):
            guard !state.unlockedZoneIDs.contains(id) else { break }
            guard let zone = config.zones.first(where: { $0.id == id }) else { break }
            guard state.coins >= zone.unlockPrice else { break }
            state.coins -= zone.unlockPrice
            state.unlockedZoneIDs.insert(id)

        case let .purchaseUpgrade(type):
            purchaseUpgrade(type)

        case .recalculateGuidance:
            break

        case .resetProgress:
            state = GameSessionState()

        case .skipUnlockNextZone:
            if let nextLocked = config.zones
                .sorted(by: { $0.id < $1.id })
                .first(where: { !state.unlockedZoneIDs.contains($0.id) }) {
                state.unlockedZoneIDs.insert(nextLocked.id)
            }
        }

        recalculateGuidanceState()
        return state
    }

    public var effectiveMaxSpeed: Double {
        config.player.playerMaxSpeed + (Double(state.upgrades.moveSpeed) * config.upgrades.moveSpeed.maxSpeedDeltaPerLevel)
    }

    public var effectiveCarryCapacity: Int {
        config.player.baseCarryCapacity + (state.upgrades.carryCapacity * config.upgrades.carryCapacity.capacityDeltaPerLevel)
    }

    public var effectiveProcessTimeSec: Double {
        let level = state.upgrades.processingSpeed
        return config.processing.baseProcessTimeSec * pow(config.upgrades.processingSpeed.timeMultiplierPerLevel, Double(level))
    }

    private func purchaseUpgrade(_ type: UpgradeType) {
        let price: Int

        switch type {
        case .moveSpeed:
            price = scaledPrice(base: config.upgrades.moveSpeed.basePrice, multiplier: config.upgrades.moveSpeed.priceMultiplier, level: state.upgrades.moveSpeed)
            guard state.coins >= price else { return }
            state.coins -= price
            state.upgrades.moveSpeed += 1

        case .carryCapacity:
            price = scaledPrice(base: config.upgrades.carryCapacity.basePrice, multiplier: config.upgrades.carryCapacity.priceMultiplier, level: state.upgrades.carryCapacity)
            guard state.coins >= price else { return }
            state.coins -= price
            state.upgrades.carryCapacity += 1

        case .processingSpeed:
            price = scaledPrice(base: config.upgrades.processingSpeed.basePrice, multiplier: config.upgrades.processingSpeed.priceMultiplier, level: state.upgrades.processingSpeed)
            guard state.coins >= price else { return }
            state.coins -= price
            state.upgrades.processingSpeed += 1
        }
    }

    private func scaledPrice(base: Int, multiplier: Double, level: Int) -> Int {
        Int((Double(base) * pow(multiplier, Double(level))).rounded(.toNearestOrAwayFromZero))
    }

    private func recalculateGuidanceState() {
        if state.processingQueue.processedReadyUnits > 0 {
            state.guidanceState = GuidanceState(target: .collectProcessedOutput)
            return
        }

        if state.processedInventory > 0 {
            state.guidanceState = GuidanceState(target: .goSellZone)
            return
        }

        if state.carryAmount > 0 {
            state.guidanceState = GuidanceState(target: .goProcessorInput)
            return
        }

        if let nextZone = nextLockedZone(), state.coins >= nextZone.unlockPrice {
            state.guidanceState = GuidanceState(target: .unlockGate, zoneID: nextZone.id)
            return
        }

        state.guidanceState = GuidanceState(target: .collectResource)
    }

    private func nextLockedZone() -> EconomyConfig.ZoneConfig? {
        config.zones
            .sorted(by: { $0.id < $1.id })
            .first(where: { !state.unlockedZoneIDs.contains($0.id) })
    }
}
