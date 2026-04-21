import Foundation

public final class GameStateReducer {
    public private(set) var state: GameSessionState
    public private(set) var meta: MetaProgress
    public let config: EconomyConfig
    private let clock: () -> Date

    public init(
        initialState: GameSessionState = GameSessionState(),
        initialMeta: MetaProgress = MetaProgress(),
        config: EconomyConfig,
        clock: @escaping () -> Date = Date.init
    ) {
        self.state = initialState
        self.meta = initialMeta
        self.config = config
        self.clock = clock
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
            state.coins += adjustedEarnings(units: sold, unitPrice: config.sell.processedUnitPrice)

        case let .sellProcessedAtUnitPrice(units, unitPrice):
            let sold = min(units, state.processedInventory)
            state.processedInventory -= sold
            state.coins += adjustedEarnings(units: sold, unitPrice: max(0, unitPrice))

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
            state = freshSessionState()

        case .skipUnlockNextZone:
            if let nextLocked = config.zones
                .sorted(by: { $0.id < $1.id })
                .first(where: { !state.unlockedZoneIDs.contains($0.id) }) {
                state.unlockedZoneIDs.insert(nextLocked.id)
            }

        case .prestige:
            let reward = MetaProgressCalculator.prestigeReward(sessionCoins: state.coins, config: config.meta)
            guard reward > 0 else { break }
            meta.prestigePoints += reward
            meta.totalPrestiges += 1
            meta.lifetimeCoinsEarned += state.coins
            state = freshSessionState()

        case let .purchaseMetaUpgrade(type):
            let level = meta.upgrades.level(for: type)
            let price = MetaProgressCalculator.upgradePrice(type: type, level: level, config: config.meta)
            guard meta.prestigePoints >= price else { break }
            meta.prestigePoints -= price
            meta.upgrades.increment(type)

        case let .applyOfflineEarnings(coins):
            guard coins > 0 else { break }
            state.coins += coins
        }

        meta.lastSeenAt = clock()
        recalculateGuidanceState()
        return state
    }

    public var effectiveMaxSpeed: Double {
        let sessionBase = config.player.playerMaxSpeed + (Double(state.upgrades.moveSpeed) * config.upgrades.moveSpeed.maxSpeedDeltaPerLevel)
        let metaMultiplier = MetaProgressCalculator.moveSpeedMultiplier(upgrades: meta.upgrades, config: config.meta)
        return sessionBase * metaMultiplier
    }

    public var effectiveCarryCapacity: Int {
        let level = state.upgrades.carryCapacity
        let firstLevelBonus = level > 0 ? 1 : 0
        return config.player.baseCarryCapacity + (level * config.upgrades.carryCapacity.capacityDeltaPerLevel) + firstLevelBonus
    }

    public var effectiveProcessTimeSec: Double {
        let level = state.upgrades.processingSpeed
        let sessionFactor = pow(config.upgrades.processingSpeed.timeMultiplierPerLevel, Double(level))
        let metaFactor = MetaProgressCalculator.processTimeMultiplier(upgrades: meta.upgrades, config: config.meta)
        return config.processing.baseProcessTimeSec * sessionFactor * metaFactor
    }

    public var effectiveSellPriceMultiplier: Double {
        MetaProgressCalculator.sellPriceMultiplier(upgrades: meta.upgrades, config: config.meta)
    }

    public var currentPrestigeReward: Int {
        MetaProgressCalculator.prestigeReward(sessionCoins: state.coins, config: config.meta)
    }

    public func metaUpgradePrice(for type: MetaUpgradeType) -> Int {
        let level = meta.upgrades.level(for: type)
        return MetaProgressCalculator.upgradePrice(type: type, level: level, config: config.meta)
    }

    private func adjustedEarnings(units: Int, unitPrice: Int) -> Int {
        guard units > 0, unitPrice > 0 else { return 0 }
        let multiplier = effectiveSellPriceMultiplier
        let raw = Double(units) * Double(unitPrice) * multiplier
        return Int(raw.rounded(.toNearestOrAwayFromZero))
    }

    private func freshSessionState() -> GameSessionState {
        let startingCoins = MetaProgressCalculator.startingCoins(upgrades: meta.upgrades, config: config.meta)
        return GameSessionState(coins: startingCoins)
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
