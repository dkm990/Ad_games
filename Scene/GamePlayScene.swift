import SpriteKit
import UIKit

final class GamePlayScene: SKScene {
    private let orchestrator: GameSceneOrchestrator
    private let config: EconomyConfig

    private let worldNode = SKNode()
    private let player = SKShapeNode(circleOfRadius: 18)
    private let cameraNode = SKCameraNode()
    private let hudNode = SKNode()

    private let carryLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let guidanceLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let processorStatusLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let coinsLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private let upgradeToggleButton = SKShapeNode(rectOf: CGSize(width: 68, height: 26), cornerRadius: 6)
    private let upgradeToggleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let upgradesPanelNode = SKShapeNode(rectOf: CGSize(width: 280, height: 150), cornerRadius: 10)
    private let upgradesHeaderLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var isUpgradesPanelVisible = false
    private var upgradeRowLabels: [UpgradeType: SKLabelNode] = [:]

    private var resourceNodes: [Int: SKShapeNode] = [:]
    private var resourceRespawnTime: [Int: TimeInterval] = [:]
    private var interactionZoneNodes: [Int: SKShapeNode] = [:]
    private var highlightNodes: [Int: SKShapeNode] = [:]
    private var resourceZoneByID: [Int: Int] = [:]

    private let processorBaseNode = SKShapeNode(rectOf: CGSize(width: 190, height: 140), cornerRadius: 10)
    private let processorInputZoneNode = SKShapeNode(circleOfRadius: 56)
    private let processorOutputZoneNode = SKShapeNode(circleOfRadius: 50)
    private let processorProgressBackground = SKShapeNode(rectOf: CGSize(width: 140, height: 10), cornerRadius: 5)
    private let processorProgressFill = SKShapeNode(rectOf: CGSize(width: 138, height: 8), cornerRadius: 4)
    private let processorLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private let sellZoneNode = SKShapeNode(circleOfRadius: 58)
    private let sellZoneLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private var gateZoneNodes: [Int: SKShapeNode] = [:]
    private var gateBlockNodes: [Int: SKShapeNode] = [:]
    private var gateLabelNodes: [Int: SKLabelNode] = [:]

    private var touchLocationInCamera: CGPoint?
    private var velocity: CGVector = .zero
    private var lastUpdateTime: TimeInterval = 0
    private var lastPickupCheckTime: TimeInterval = 0
    private var lastDepositTime: TimeInterval = 0
    private var lastOutputCollectTime: TimeInterval = 0
    private var lastSellTime: TimeInterval = 0
    private var lastGateAttemptTime: [Int: TimeInterval] = [:]
    private var currentPrimaryTargetID: Int?
    private var unlockFocusZoneID: Int?
    private var unlockFocusUntil: TimeInterval?
    private var shownZoneBonus: Set<Int> = []

    private var tunedPlayerAcceleration: CGFloat
    private var tunedPlayerMaxSpeed: CGFloat
    private var tunedPickupRadius: CGFloat
    private var tunedCameraFollowSmoothing: CGFloat = 0.18

    private var processingTimeRemaining: TimeInterval = 0
    private var currentBatchTotalTime: TimeInterval = 0

    private enum LoopStage {
        case awaitCollect
        case awaitDeposit
        case awaitProcessComplete
        case awaitCollectOutput
        case awaitSell
    }

    private struct SessionMetrics {
        var sessionStartTime: TimeInterval?
        var loopsCompleted: Int = 0
        var totalLoopDurationSec: TimeInterval = 0
        var currentLoopStartTime: TimeInterval?
        var loopStage: LoopStage = .awaitCollect
        var resourcesCollected: Int = 0
        var processedOutputsCollected: Int = 0
        var processedUnitsSold: Int = 0
        var upgradesPurchased: Int = 0
        var zonesUnlocked: Int = 0
        var coinsEarned: Int = 0
        var coinsSpent: Int = 0
    }

    private var sessionMetrics = SessionMetrics()

    private let processorZoneInputID = 9001
    private let processorZoneOutputID = 9002
    private let sellZoneID = 9003
    private let gateZoneBaseID = 9100

    #if DEBUG
    private let debugPanelNode = SKNode()
    private let debugSpeedLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let debugTargetLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let debugParamsLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugProcessorLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugStateLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugSessionLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugLoopLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugActionsLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugEconomyLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let pickupRadiusDebugCircle = SKShapeNode(circleOfRadius: 12)
    #endif

    init(size: CGSize, orchestrator: GameSceneOrchestrator, config: EconomyConfig) {
        self.orchestrator = orchestrator
        self.config = config
        self.tunedPlayerAcceleration = CGFloat(config.player.playerAcceleration)
        self.tunedPlayerMaxSpeed = CGFloat(config.player.playerMaxSpeed)
        self.tunedPickupRadius = CGFloat(config.player.pickupRadius)
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        addChild(worldNode)
        buildMap()
        buildPlayer()
        buildResources()
        buildProcessor()
        buildSellZone()
        buildUnlockGates()
        setupCameraAndHUD()
        setupUpgradesPanel()
        applyUnlockVisualStateFromSession()

        #if DEBUG
        setupDebugOverlay()
        #endif

        refreshHUD()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        #if DEBUG
        if handleDebugTap(touch) {
            touchLocationInCamera = nil
            return
        }
        #endif

        let cameraPoint = touch.location(in: cameraNode)
        if handleUpgradeUITap(at: cameraPoint) {
            touchLocationInCamera = nil
            return
        }

        touchLocationInCamera = cameraPoint
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if isUpgradesPanelVisible {
            return
        }
        touchLocationInCamera = touch.location(in: cameraNode)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocationInCamera = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocationInCamera = nil
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(max(currentTime - lastUpdateTime, 0), 1.0 / 20.0)
        lastUpdateTime = currentTime

        if sessionMetrics.sessionStartTime == nil {
            sessionMetrics.sessionStartTime = currentTime
        }

        updateMovement(dt: dt)
        updateCamera(dt: dt)
        updateResourceRespawns(currentTime: currentTime)
        runPickupIfNeeded(currentTime: currentTime)
        runZoneBonusEntryFeedback()
        runProcessorInteractions(currentTime: currentTime)
        runSellInteractions(currentTime: currentTime)
        runUnlockInteractions(currentTime: currentTime)
        updateProcessingLifecycle(dt: dt)
        updateProcessorVisualState()
        updateSellZoneVisualState()
        updateGateVisualState()
        updateHighlighting()
        refreshHUD()

        #if DEBUG
        updateDebugOverlay(currentTime: currentTime)
        #endif
    }
    private func buildMap() {
        let floor = SKShapeNode(rectOf: CGSize(width: 1500, height: 1200), cornerRadius: 6)
        floor.fillColor = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
        floor.strokeColor = UIColor(red: 0.21, green: 0.25, blue: 0.29, alpha: 1)
        floor.lineWidth = 6
        floor.zPosition = 0
        worldNode.addChild(floor)

        createBlockingRect(size: CGSize(width: 180, height: 44), position: CGPoint(x: -120, y: 40))
        createBlockingRect(size: CGSize(width: 200, height: 44), position: CGPoint(x: 200, y: -100))
        createBlockingRect(size: CGSize(width: 140, height: 44), position: CGPoint(x: -220, y: -220))
        createBoundary(size: CGSize(width: 1400, height: 1100))
    }

    private func createBoundary(size: CGSize) {
        let boundary = SKNode()
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        ))
        boundary.physicsBody?.isDynamic = false
        boundary.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
        boundary.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        boundary.physicsBody?.contactTestBitMask = 0
        worldNode.addChild(boundary)
    }

    private func createBlockingRect(size: CGSize, position: CGPoint) {
        let node = SKShapeNode(rectOf: size, cornerRadius: 8)
        node.position = position
        node.fillColor = UIColor(red: 0.18, green: 0.27, blue: 0.35, alpha: 1)
        node.strokeColor = UIColor(red: 0.44, green: 0.66, blue: 0.83, alpha: 1)
        node.lineWidth = 3
        node.zPosition = 1

        node.physicsBody = SKPhysicsBody(rectangleOf: size)
        node.physicsBody?.isDynamic = false
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
        node.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        node.physicsBody?.contactTestBitMask = 0

        worldNode.addChild(node)
    }

    private func buildPlayer() {
        player.fillColor = UIColor(red: 0.25, green: 0.94, blue: 0.45, alpha: 1)
        player.strokeColor = UIColor(red: 0.04, green: 0.2, blue: 0.08, alpha: 1)
        player.lineWidth = 3
        player.zPosition = 10
        player.position = CGPoint(x: -240, y: 0)

        let body = SKPhysicsBody(circleOfRadius: 18)
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = CollisionLayer.player.rawValue
        body.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        body.contactTestBitMask = CollisionPolicy.playerContactMask.rawValue
        player.physicsBody = body

        worldNode.addChild(player)
    }

    private func buildResources() {
        let items: [(Int, CGPoint, Int)] = [
            (100, CGPoint(x: -340, y: 220), 1),
            (101, CGPoint(x: -180, y: 260), 1),
            (102, CGPoint(x: -30, y: 210), 1),
            (200, CGPoint(x: 60, y: 20), 2),
            (201, CGPoint(x: 95, y: 35), 2),
            (202, CGPoint(x: 115, y: -5), 2),
            (203, CGPoint(x: 140, y: 20), 2),
            (204, CGPoint(x: 160, y: -20), 2),
            (300, CGPoint(x: -10, y: -5), 3),
            (301, CGPoint(x: 15, y: 12), 3),
            (302, CGPoint(x: 35, y: -12), 3),
            (303, CGPoint(x: 55, y: 8), 3),
            (304, CGPoint(x: 72, y: -16), 3),
            (305, CGPoint(x: 88, y: 6), 3),
            (306, CGPoint(x: 102, y: -8), 3)
        ]

        for (id, point, zoneID) in items {
            let node = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 4)
            node.position = point
            node.fillColor = UIColor(red: 1.0, green: 0.75, blue: 0.22, alpha: 1)
            node.strokeColor = UIColor(red: 0.62, green: 0.33, blue: 0.02, alpha: 1)
            node.lineWidth = 2
            node.zPosition = 5

            let body = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: 28))
            body.isDynamic = false
            body.affectedByGravity = false
            body.categoryBitMask = CollisionLayer.resourceNode.rawValue
            body.collisionBitMask = CollisionPolicy.resourceCollisionMask.rawValue
            body.contactTestBitMask = CollisionLayer.player.rawValue
            node.physicsBody = body

            let highlight = SKShapeNode(rectOf: CGSize(width: 40, height: 40), cornerRadius: 8)
            highlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
            highlight.glowWidth = 3
            highlight.lineWidth = 2
            highlight.fillColor = .clear
            highlight.isHidden = true
            highlight.zPosition = 7
            node.addChild(highlight)

            let interactionZone = SKShapeNode(circleOfRadius: tunedPickupRadius)
            interactionZone.position = point
            interactionZone.strokeColor = .clear
            interactionZone.fillColor = .clear
            interactionZone.zPosition = 2

            let interactionBody = SKPhysicsBody(circleOfRadius: tunedPickupRadius)
            interactionBody.isDynamic = false
            interactionBody.affectedByGravity = false
            interactionBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
            interactionBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
            interactionBody.contactTestBitMask = CollisionLayer.player.rawValue
            interactionZone.physicsBody = interactionBody

            worldNode.addChild(interactionZone)
            worldNode.addChild(node)

            resourceNodes[id] = node
            interactionZoneNodes[id] = interactionZone
            highlightNodes[id] = highlight
            resourceZoneByID[id] = zoneID
        }
    }

    private func buildProcessor() {
        let center = CGPoint(x: -80, y: -120)

        processorBaseNode.position = center
        processorBaseNode.fillColor = UIColor(red: 0.22, green: 0.24, blue: 0.28, alpha: 1)
        processorBaseNode.strokeColor = UIColor(red: 0.67, green: 0.72, blue: 0.8, alpha: 1)
        processorBaseNode.lineWidth = 3
        processorBaseNode.zPosition = 3
        worldNode.addChild(processorBaseNode)

        processorLabel.fontSize = 13
        processorLabel.fontColor = .white
        processorLabel.text = "Processor: idle"
        processorLabel.position = CGPoint(x: 0, y: 38)
        processorLabel.zPosition = 5
        processorBaseNode.addChild(processorLabel)

        processorProgressBackground.fillColor = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        processorProgressBackground.strokeColor = UIColor(red: 0.38, green: 0.42, blue: 0.48, alpha: 1)
        processorProgressBackground.lineWidth = 1
        processorProgressBackground.position = CGPoint(x: 0, y: 16)
        processorProgressBackground.zPosition = 4
        processorBaseNode.addChild(processorProgressBackground)

        processorProgressFill.fillColor = UIColor(red: 0.24, green: 0.95, blue: 0.66, alpha: 1)
        processorProgressFill.strokeColor = .clear
        processorProgressFill.position = CGPoint(x: 0, y: 16)
        processorProgressFill.zPosition = 5
        processorBaseNode.addChild(processorProgressFill)

        processorInputZoneNode.position = CGPoint(x: center.x - 112, y: center.y - 12)
        processorInputZoneNode.fillColor = UIColor(red: 0.20, green: 0.44, blue: 0.92, alpha: 0.26)
        processorInputZoneNode.strokeColor = UIColor(red: 0.57, green: 0.76, blue: 1.0, alpha: 1)
        processorInputZoneNode.lineWidth = 2
        processorInputZoneNode.zPosition = 2
        worldNode.addChild(processorInputZoneNode)

        let inputBody = SKPhysicsBody(circleOfRadius: 56)
        inputBody.isDynamic = false
        inputBody.affectedByGravity = false
        inputBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
        inputBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
        inputBody.contactTestBitMask = CollisionLayer.player.rawValue
        processorInputZoneNode.physicsBody = inputBody

        let inputHighlight = SKShapeNode(circleOfRadius: 63)
        inputHighlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
        inputHighlight.lineWidth = 2
        inputHighlight.glowWidth = 2
        inputHighlight.fillColor = .clear
        inputHighlight.isHidden = true
        inputHighlight.zPosition = 6
        processorInputZoneNode.addChild(inputHighlight)

        processorOutputZoneNode.position = CGPoint(x: center.x + 112, y: center.y - 12)
        processorOutputZoneNode.fillColor = UIColor(red: 0.95, green: 0.67, blue: 0.14, alpha: 0.22)
        processorOutputZoneNode.strokeColor = UIColor(red: 1.0, green: 0.86, blue: 0.56, alpha: 1)
        processorOutputZoneNode.lineWidth = 2
        processorOutputZoneNode.zPosition = 2
        worldNode.addChild(processorOutputZoneNode)

        let outputBody = SKPhysicsBody(circleOfRadius: 50)
        outputBody.isDynamic = false
        outputBody.affectedByGravity = false
        outputBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
        outputBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
        outputBody.contactTestBitMask = CollisionLayer.player.rawValue
        processorOutputZoneNode.physicsBody = outputBody

        let outputHighlight = SKShapeNode(circleOfRadius: 57)
        outputHighlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
        outputHighlight.lineWidth = 2
        outputHighlight.glowWidth = 2
        outputHighlight.fillColor = .clear
        outputHighlight.isHidden = true
        outputHighlight.zPosition = 6
        processorOutputZoneNode.addChild(outputHighlight)

        highlightNodes[processorZoneInputID] = inputHighlight
        highlightNodes[processorZoneOutputID] = outputHighlight
    }
    private func buildSellZone() {
        let position = CGPoint(x: 240, y: -220)
        sellZoneNode.position = position
        sellZoneNode.fillColor = UIColor(red: 0.19, green: 0.58, blue: 0.19, alpha: 0.30)
        sellZoneNode.strokeColor = UIColor(red: 0.56, green: 0.95, blue: 0.56, alpha: 1)
        sellZoneNode.lineWidth = 2
        sellZoneNode.zPosition = 2
        worldNode.addChild(sellZoneNode)

        let body = SKPhysicsBody(circleOfRadius: 58)
        body.isDynamic = false
        body.affectedByGravity = false
        body.categoryBitMask = CollisionLayer.interactionZone.rawValue
        body.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
        body.contactTestBitMask = CollisionLayer.player.rawValue
        sellZoneNode.physicsBody = body

        sellZoneLabel.fontSize = 14
        sellZoneLabel.fontColor = UIColor(red: 0.88, green: 1.0, blue: 0.88, alpha: 1)
        sellZoneLabel.text = "SELL"
        sellZoneLabel.position = CGPoint(x: 0, y: -6)
        sellZoneLabel.zPosition = 4
        sellZoneNode.addChild(sellZoneLabel)

        let highlight = SKShapeNode(circleOfRadius: 65)
        highlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
        highlight.lineWidth = 2
        highlight.glowWidth = 2
        highlight.fillColor = .clear
        highlight.isHidden = true
        highlight.zPosition = 6
        sellZoneNode.addChild(highlight)

        highlightNodes[sellZoneID] = highlight
    }

    private func buildUnlockGates() {
        let gateSpecs: [(zoneID: Int, x: CGFloat, gateX: CGFloat, y: CGFloat)] = [
            (2, 120, 70, 120),
            (3, 390, 340, 120)
        ]

        for spec in gateSpecs {
            let block = SKShapeNode(rectOf: CGSize(width: 28, height: 280), cornerRadius: 6)
            block.position = CGPoint(x: spec.x, y: 120)
            block.fillColor = UIColor(red: 0.36, green: 0.18, blue: 0.18, alpha: 1)
            block.strokeColor = UIColor(red: 0.85, green: 0.45, blue: 0.45, alpha: 1)
            block.lineWidth = 2
            block.zPosition = 3
            block.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: 280))
            block.physicsBody?.isDynamic = false
            block.physicsBody?.affectedByGravity = false
            block.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
            block.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
            worldNode.addChild(block)
            gateBlockNodes[spec.zoneID] = block

            let gateZone = SKShapeNode(circleOfRadius: 48)
            gateZone.position = CGPoint(x: spec.gateX, y: spec.y)
            gateZone.fillColor = UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 0.28)
            gateZone.strokeColor = UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)
            gateZone.lineWidth = 2
            gateZone.zPosition = 2

            let gateBody = SKPhysicsBody(circleOfRadius: 48)
            gateBody.isDynamic = false
            gateBody.affectedByGravity = false
            gateBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
            gateBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
            gateBody.contactTestBitMask = CollisionLayer.player.rawValue
            gateZone.physicsBody = gateBody
            worldNode.addChild(gateZone)
            gateZoneNodes[spec.zoneID] = gateZone

            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.fontSize = 12
            label.fontColor = UIColor(red: 1.0, green: 0.86, blue: 0.86, alpha: 1)
            label.position = CGPoint(x: 0, y: -6)
            label.zPosition = 4
            gateZone.addChild(label)
            gateLabelNodes[spec.zoneID] = label

            let highlight = SKShapeNode(circleOfRadius: 56)
            highlight.strokeColor = UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
            highlight.lineWidth = 2
            highlight.glowWidth = 2
            highlight.fillColor = .clear
            highlight.isHidden = true
            highlight.zPosition = 6
            gateZone.addChild(highlight)
            highlightNodes[gateZoneBaseID + spec.zoneID] = highlight
        }
    }

    private func setupCameraAndHUD() {
        camera = cameraNode
        addChild(cameraNode)

        carryLabel.fontSize = 18
        carryLabel.horizontalAlignmentMode = .left
        carryLabel.verticalAlignmentMode = .center
        carryLabel.fontColor = .white
        carryLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.42)

        coinsLabel.fontSize = 18
        coinsLabel.horizontalAlignmentMode = .left
        coinsLabel.verticalAlignmentMode = .center
        coinsLabel.fontColor = UIColor(red: 1.0, green: 0.93, blue: 0.58, alpha: 1)
        coinsLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.38)

        guidanceLabel.fontSize = 16
        guidanceLabel.horizontalAlignmentMode = .left
        guidanceLabel.verticalAlignmentMode = .center
        guidanceLabel.fontColor = UIColor(red: 0.78, green: 0.9, blue: 1.0, alpha: 1)
        guidanceLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.34)

        processorStatusLabel.fontSize = 15
        processorStatusLabel.horizontalAlignmentMode = .left
        processorStatusLabel.verticalAlignmentMode = .center
        processorStatusLabel.fontColor = UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1)
        processorStatusLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.30)

        upgradeToggleButton.name = "btn_upg_toggle"
        upgradeToggleButton.fillColor = UIColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 0.96)
        upgradeToggleButton.strokeColor = UIColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1)
        upgradeToggleButton.lineWidth = 1.2
        upgradeToggleButton.position = CGPoint(x: size.width * 0.42, y: size.height * 0.42)

        upgradeToggleLabel.name = "btn_upg_toggle"
        upgradeToggleLabel.text = "UPGR"
        upgradeToggleLabel.fontName = "AvenirNext-Bold"
        upgradeToggleLabel.fontSize = 12
        upgradeToggleLabel.verticalAlignmentMode = .center
        upgradeToggleLabel.fontColor = .white
        upgradeToggleButton.addChild(upgradeToggleLabel)

        hudNode.zPosition = 1000
        hudNode.addChild(carryLabel)
        hudNode.addChild(coinsLabel)
        hudNode.addChild(guidanceLabel)
        hudNode.addChild(processorStatusLabel)
        hudNode.addChild(upgradeToggleButton)
        cameraNode.addChild(hudNode)
    }

    private func setupUpgradesPanel() {
        upgradesPanelNode.name = "panel_upgrades"
        upgradesPanelNode.fillColor = UIColor(red: 0.14, green: 0.15, blue: 0.2, alpha: 0.95)
        upgradesPanelNode.strokeColor = UIColor(red: 0.6, green: 0.78, blue: 0.95, alpha: 1)
        upgradesPanelNode.lineWidth = 1.5
        upgradesPanelNode.position = CGPoint(x: size.width * 0.22, y: size.height * 0.22)
        upgradesPanelNode.zPosition = 1050
        upgradesPanelNode.isHidden = true

        upgradesHeaderLabel.text = "Upgrades"
        upgradesHeaderLabel.fontSize = 14
        upgradesHeaderLabel.fontColor = .white
        upgradesHeaderLabel.position = CGPoint(x: 0, y: 58)
        upgradesHeaderLabel.zPosition = 1
        upgradesPanelNode.addChild(upgradesHeaderLabel)

        addUpgradeRow(type: .moveSpeed, y: 24, title: "Move")
        addUpgradeRow(type: .carryCapacity, y: -8, title: "Carry")
        addUpgradeRow(type: .processingSpeed, y: -40, title: "Process")

        cameraNode.addChild(upgradesPanelNode)
    }

    private func addUpgradeRow(type: UpgradeType, y: CGFloat, title: String) {
        let button = SKShapeNode(rectOf: CGSize(width: 250, height: 26), cornerRadius: 6)
        button.name = "btn_upg_\(type.rawValue)"
        button.position = CGPoint(x: 0, y: y)
        button.fillColor = UIColor(red: 0.2, green: 0.22, blue: 0.3, alpha: 0.95)
        button.strokeColor = UIColor(red: 0.48, green: 0.64, blue: 0.85, alpha: 1)
        button.lineWidth = 1

        let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
        label.name = "btn_upg_\(type.rawValue)"
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -115, y: 0)
        label.fontSize = 12
        label.fontColor = .white
        label.text = "\(title)"
        button.addChild(label)

        let buyLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        buyLabel.name = "btn_upg_\(type.rawValue)"
        buyLabel.horizontalAlignmentMode = .right
        buyLabel.verticalAlignmentMode = .center
        buyLabel.position = CGPoint(x: 115, y: 0)
        buyLabel.fontSize = 11
        buyLabel.fontColor = UIColor(red: 1.0, green: 0.92, blue: 0.6, alpha: 1)
        button.addChild(buyLabel)

        upgradeRowLabels[type] = buyLabel
        upgradesPanelNode.addChild(button)
    }
    private func handleUpgradeUITap(at point: CGPoint) -> Bool {
        let nodesAtPoint = cameraNode.nodes(at: point)
        guard let name = nodesAtPoint.compactMap({ $0.name }).first(where: { $0.hasPrefix("btn_upg_") }) else {
            return false
        }

        if name == "btn_upg_toggle" {
            isUpgradesPanelVisible.toggle()
            upgradesPanelNode.isHidden = !isUpgradesPanelVisible
            updateUpgradePanelTexts()
            return true
        }

        guard isUpgradesPanelVisible else { return false }

        if name == "btn_upg_moveSpeed" {
            tryPurchaseUpgrade(type: .moveSpeed)
            return true
        }
        if name == "btn_upg_carryCapacity" {
            tryPurchaseUpgrade(type: .carryCapacity)
            return true
        }
        if name == "btn_upg_processingSpeed" {
            tryPurchaseUpgrade(type: .processingSpeed)
            return true
        }

        return false
    }

    private func tryPurchaseUpgrade(type: UpgradeType) {
        let before = orchestrator.sessionState
        orchestrator.perform(.purchaseUpgrade(type: type))
        let after = orchestrator.sessionState

        let changed: Bool
        let feedbackText: String
        switch type {
        case .moveSpeed:
            changed = after.upgrades.moveSpeed > before.upgrades.moveSpeed
            feedbackText = "speed++"
        case .carryCapacity:
            changed = after.upgrades.carryCapacity > before.upgrades.carryCapacity
            feedbackText = "carry++"
        case .processingSpeed:
            changed = after.upgrades.processingSpeed > before.upgrades.processingSpeed
            feedbackText = "process++"
        }

        if changed {
            let spent = max(0, before.coins - after.coins)
            sessionMetrics.upgradesPurchased += 1
            sessionMetrics.coinsSpent += spent
            flashZone(upgradesPanelNode, color: UIColor(red: 0.35, green: 0.72, blue: 0.35, alpha: 0.9))
            showFloatingText(text: feedbackText, color: UIColor(red: 0.72, green: 1.0, blue: 0.72, alpha: 1), at: player.position)
        } else {
            flashZone(upgradesPanelNode, color: UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 0.9))
            showFloatingText(text: "Not enough coins", color: UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1), at: player.position)
        }

        updateUpgradePanelTexts()
    }

    private func updateUpgradePanelTexts() {
        let state = orchestrator.sessionState
        let rows: [(UpgradeType, Int)] = [
            (.moveSpeed, state.upgrades.moveSpeed),
            (.carryCapacity, state.upgrades.carryCapacity),
            (.processingSpeed, state.upgrades.processingSpeed)
        ]

        for (type, level) in rows {
            let price = nextUpgradePrice(type: type, level: level)
            upgradeRowLabels[type]?.text = "Lv \(level)  \(price)c"
        }
    }

    private func nextUpgradePrice(type: UpgradeType, level: Int) -> Int {
        switch type {
        case .moveSpeed:
            return Int((Double(config.upgrades.moveSpeed.basePrice) * pow(config.upgrades.moveSpeed.priceMultiplier, Double(level))).rounded(.toNearestOrAwayFromZero))
        case .carryCapacity:
            return Int((Double(config.upgrades.carryCapacity.basePrice) * pow(config.upgrades.carryCapacity.priceMultiplier, Double(level))).rounded(.toNearestOrAwayFromZero))
        case .processingSpeed:
            return Int((Double(config.upgrades.processingSpeed.basePrice) * pow(config.upgrades.processingSpeed.priceMultiplier, Double(level))).rounded(.toNearestOrAwayFromZero))
        }
    }

    private func updateMovement(dt: TimeInterval) {
        _ = dt
        let upgradeSpeedBonus = CGFloat(orchestrator.sessionState.upgrades.moveSpeed) * CGFloat(config.upgrades.moveSpeed.maxSpeedDeltaPerLevel)
        let maxSpeed = max(120, tunedPlayerMaxSpeed + upgradeSpeedBonus)

        let desiredDirection: CGVector
        if let touchPoint = touchLocationInCamera {
            let playerInCamera = cameraNode.convert(player.position, from: worldNode)
            let delta = CGVector(dx: touchPoint.x - playerInCamera.x, dy: touchPoint.y - playerInCamera.y)
            let length = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
            let deadZone: CGFloat = 20
            if length > deadZone {
                desiredDirection = CGVector(dx: delta.dx / length, dy: delta.dy / length)
            } else {
                desiredDirection = .zero
            }
        } else {
            desiredDirection = .zero
        }

        if desiredDirection == .zero {
            velocity = .zero
        } else {
            velocity.dx = desiredDirection.dx * maxSpeed
            velocity.dy = desiredDirection.dy * maxSpeed
        }

        player.physicsBody?.velocity = velocity
    }

    private func updateCamera(dt: TimeInterval) {
        let followStrength: CGFloat = max(0.15, 1.0 - tunedCameraFollowSmoothing)
        cameraNode.position.x += (player.position.x - cameraNode.position.x) * followStrength
        cameraNode.position.y += (player.position.y - cameraNode.position.y) * followStrength

        if dt > 0, player.position.distance(to: cameraNode.position) < 0.6 {
            cameraNode.position = player.position
        }
    }

    private func runPickupIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastPickupCheckTime > 0.1 else { return }
        lastPickupCheckTime = currentTime

        let state = orchestrator.sessionState
        let carryCapacity = max(1, orchestrator.effectiveCarryCapacity)
        guard state.carryAmount < carryCapacity else { return }

        let nearest = resourceNodes
            .filter { id, node in
                guard node.isHidden == false else { return false }
                let zoneID = resourceZoneByID[id] ?? 1
                return state.unlockedZoneIDs.contains(zoneID)
            }
            .min { lhs, rhs in
                player.position.distanceSquared(to: lhs.value.position) < player.position.distanceSquared(to: rhs.value.position)
            }

        guard let (id, node) = nearest else { return }
        guard player.position.distance(to: node.position) <= tunedPickupRadius else { return }

        let zoneID = resourceZoneByID[id] ?? 1
        let pickupUnits = pickupMultiplier(for: zoneID)
        let beforeCollect = orchestrator.sessionState

        orchestrator.perform(.collectRaw(units: pickupUnits))
        let afterCollect = orchestrator.sessionState
        let acceptedToCarry = max(0, afterCollect.carryAmount - beforeCollect.carryAmount)
        let overflow = max(0, pickupUnits - acceptedToCarry)
        registerCollect(units: pickupUnits, fromZoneID: zoneID, currentTime: currentTime)

        if overflow > 0, player.position.distance(to: processorInputZoneNode.position) <= 72 {
            let carryBeforeDeposit = orchestrator.sessionState.carryAmount
            orchestrator.perform(.depositRawForProcessing(units: overflow))
            let carryAfterDeposit = orchestrator.sessionState.carryAmount
            let deposited = max(0, carryBeforeDeposit - carryAfterDeposit)
            if deposited > 0 {
                registerDeposit(units: deposited)
                flashZone(processorInputZoneNode, color: UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.60))
                showFloatingText(
                    text: "auto queue +\(deposited)",
                    color: UIColor(red: 0.70, green: 0.90, blue: 1.0, alpha: 1),
                    at: CGPoint(x: processorInputZoneNode.position.x, y: processorInputZoneNode.position.y + 10)
                )
            }
        }

        interactionZoneNodes[id]?.isHidden = true
        resourceRespawnTime[id] = currentTime + 2.0

        playPickupFeedback(for: node)
        showFloatingText(text: "+\(pickupUnits)", color: UIColor(red: 1, green: 0.86, blue: 0.2, alpha: 1), at: node.position)
        if pickupUnits > 1 {
            showFloatingText(
                text: "x\(pickupUnits) pickup",
                color: UIColor(red: 0.88, green: 1.0, blue: 0.78, alpha: 1),
                at: CGPoint(x: node.position.x, y: node.position.y + 14)
            )
        }
    }

    private func pickupMultiplier(for zoneID: Int) -> Int {
        switch zoneID {
        case 2:
            return 2
        case 3:
            return 3
        default:
            return 1
        }
    }

    private func playPickupFeedback(for node: SKShapeNode) {
        let originalFill = node.fillColor
        let pulseUp = SKAction.scale(to: 1.24, duration: 0.06)
        let pulseDown = SKAction.scale(to: 1.0, duration: 0.06)
        let flashIn = SKAction.run { node.fillColor = UIColor(red: 1.0, green: 0.93, blue: 0.48, alpha: 1) }
        let flashOut = SKAction.run { node.fillColor = originalFill }
        let hide = SKAction.run { node.isHidden = true }
        node.removeAction(forKey: "pickupFeedback")
        node.run(SKAction.sequence([flashIn, pulseUp, pulseDown, flashOut, hide]), withKey: "pickupFeedback")
    }

    private func runZoneBonusEntryFeedback() {
        let state = orchestrator.sessionState
        for zoneID in [2, 3] {
            guard state.unlockedZoneIDs.contains(zoneID) else { continue }
            guard shownZoneBonus.contains(zoneID) == false else { continue }

            let nearest = resourceNodes
                .filter { id, node in
                    guard !node.isHidden else { return false }
                    return resourceZoneByID[id] == zoneID
                }
                .min { lhs, rhs in
                    player.position.distanceSquared(to: lhs.value.position) < player.position.distanceSquared(to: rhs.value.position)
                }

            guard let (_, node) = nearest else { continue }
            guard player.position.distance(to: node.position) <= 110 else { continue }

            shownZoneBonus.insert(zoneID)
            let bonusText = zoneID == 2 ? "ZONE BONUS x2" : "ZONE BONUS x3"
            showFloatingText(
                text: bonusText,
                color: UIColor(red: 0.90, green: 1.0, blue: 0.78, alpha: 1),
                at: CGPoint(x: node.position.x, y: node.position.y + 20)
            )
        }
    }

    private func runProcessorInteractions(currentTime: TimeInterval) {
        let state = orchestrator.sessionState

        if currentTime - lastDepositTime > 0.2,
           state.carryAmount > 0,
           player.position.distance(to: processorInputZoneNode.position) <= 56 {
            lastDepositTime = currentTime
            let deposited = state.carryAmount
            orchestrator.perform(.depositRawForProcessing(units: deposited))
            registerDeposit(units: deposited)
            flashZone(processorInputZoneNode, color: UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.75))
            showFloatingText(text: "-\(deposited) raw", color: UIColor(red: 0.63, green: 0.85, blue: 1.0, alpha: 1), at: processorInputZoneNode.position)
        }

        let refreshedState = orchestrator.sessionState
        if currentTime - lastOutputCollectTime > 0.2,
           refreshedState.processingQueue.processedReadyUnits > 0,
           player.position.distance(to: processorOutputZoneNode.position) <= 50 {
            lastOutputCollectTime = currentTime
            let collected = refreshedState.processingQueue.processedReadyUnits
            orchestrator.perform(.collectProcessedOutput(units: collected))
            registerProcessedOutputCollected(units: collected)
            flashZone(processorOutputZoneNode, color: UIColor(red: 1.0, green: 0.82, blue: 0.35, alpha: 0.75))
            showFloatingText(text: "+\(collected) processed", color: UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1), at: processorOutputZoneNode.position)
        }
    }
    private func runSellInteractions(currentTime: TimeInterval) {
        let state = orchestrator.sessionState
        guard currentTime - lastSellTime > 0.2 else { return }
        guard state.processedInventory > 0 else { return }
        guard player.position.distance(to: sellZoneNode.position) <= 58 else { return }

        lastSellTime = currentTime
        let soldUnits = state.processedInventory
        let gained = soldUnits * config.sell.processedUnitPrice
        orchestrator.perform(.sellProcessed(units: soldUnits))
        registerSell(units: soldUnits, gainedCoins: gained, currentTime: currentTime)

        flashZone(sellZoneNode, color: UIColor(red: 0.62, green: 1.0, blue: 0.62, alpha: 0.85))
        showFloatingText(text: "+\(gained) coins", color: UIColor(red: 1.0, green: 0.93, blue: 0.58, alpha: 1), at: sellZoneNode.position)
    }

    private func runUnlockInteractions(currentTime: TimeInterval) {
        for zone in config.zones.sorted(by: { $0.id < $1.id }) where zone.id > 1 {
            guard orchestrator.sessionState.unlockedZoneIDs.contains(zone.id) == false else { continue }
            guard let gate = gateZoneNodes[zone.id] else { continue }

            let distance = player.position.distance(to: gate.position)
            guard distance <= 48 else { continue }

            let lastAttempt = lastGateAttemptTime[zone.id] ?? 0
            guard currentTime - lastAttempt > 0.5 else { continue }
            lastGateAttemptTime[zone.id] = currentTime

            let before = orchestrator.sessionState
            if before.coins >= zone.unlockPrice {
                orchestrator.perform(.unlockZone(id: zone.id))
                let after = orchestrator.sessionState
                if after.unlockedZoneIDs.contains(zone.id) {
                    sessionMetrics.zonesUnlocked += 1
                    sessionMetrics.coinsSpent += max(0, before.coins - after.coins)
                    unlockFocusZoneID = zone.id
                    unlockFocusUntil = currentTime + 10.0
                    applyUnlockVisualStateFromSession()
                    flashZone(gate, color: UIColor(red: 0.62, green: 1.0, blue: 0.62, alpha: 0.85))
                    playUnlockReveal(for: gate)
                    showFloatingText(text: "NEW AREA OPENED", color: UIColor(red: 0.78, green: 1.0, blue: 0.78, alpha: 1), at: CGPoint(x: gate.position.x, y: gate.position.y + 16))
                    showFloatingText(text: "new resources unlocked", color: UIColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1), at: CGPoint(x: gate.position.x, y: gate.position.y - 8))
                    showFloatingText(text: "FASTER COLLECTION AREA", color: UIColor(red: 0.92, green: 1.0, blue: 0.8, alpha: 1), at: CGPoint(x: gate.position.x, y: gate.position.y - 30))
                }
            } else {
                flashZone(gate, color: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 0.85))
                showFloatingText(text: "Need \(zone.unlockPrice)", color: UIColor(red: 1.0, green: 0.64, blue: 0.64, alpha: 1), at: gate.position)
            }
        }
    }

    private func playUnlockReveal(for gate: SKShapeNode) {
        gate.removeAction(forKey: "unlockReveal")
        let up = SKAction.scale(to: 1.16, duration: 0.10)
        let down = SKAction.scale(to: 1.0, duration: 0.10)
        gate.run(SKAction.sequence([up, down]), withKey: "unlockReveal")
    }

    private func updateProcessingLifecycle(dt: TimeInterval) {
        let state = orchestrator.sessionState
        if processingTimeRemaining <= 0,
           state.processingQueue.queuedRawUnits >= config.processing.inputPerBatch {
            currentBatchTotalTime = max(0.3, orchestrator.effectiveProcessTimeSec)
            processingTimeRemaining = currentBatchTotalTime
        }

        guard processingTimeRemaining > 0 else { return }
        processingTimeRemaining = max(0, processingTimeRemaining - dt)

        if processingTimeRemaining <= 0 {
            orchestrator.perform(.processingCompleted)
            registerProcessingCompleted()
        }
    }

    private func registerCollect(units: Int, fromZoneID: Int, currentTime: TimeInterval) {
        guard units > 0 else { return }
        sessionMetrics.resourcesCollected += units
        if unlockFocusZoneID == fromZoneID {
            unlockFocusZoneID = nil
            unlockFocusUntil = nil
        }
        if sessionMetrics.loopStage == .awaitCollect {
            sessionMetrics.loopStage = .awaitDeposit
            sessionMetrics.currentLoopStartTime = currentTime
        }
    }

    private func registerDeposit(units: Int) {
        guard units > 0 else { return }
        if sessionMetrics.loopStage == .awaitDeposit {
            sessionMetrics.loopStage = .awaitProcessComplete
        }
    }

    private func registerProcessingCompleted() {
        if sessionMetrics.loopStage == .awaitProcessComplete {
            sessionMetrics.loopStage = .awaitCollectOutput
        }
    }

    private func registerProcessedOutputCollected(units: Int) {
        guard units > 0 else { return }
        sessionMetrics.processedOutputsCollected += units
        if sessionMetrics.loopStage == .awaitCollectOutput {
            sessionMetrics.loopStage = .awaitSell
        }
    }

    private func registerSell(units: Int, gainedCoins: Int, currentTime: TimeInterval) {
        guard units > 0 else { return }
        sessionMetrics.processedUnitsSold += units
        sessionMetrics.coinsEarned += max(0, gainedCoins)

        if sessionMetrics.loopStage == .awaitSell {
            sessionMetrics.loopsCompleted += 1
            if let startedAt = sessionMetrics.currentLoopStartTime {
                sessionMetrics.totalLoopDurationSec += max(0, currentTime - startedAt)
            }
            sessionMetrics.currentLoopStartTime = nil
            sessionMetrics.loopStage = .awaitCollect
        }
    }

    private func updateProcessorVisualState() {
        let state = orchestrator.sessionState
        let ready = state.processingQueue.processedReadyUnits > 0
        let processing = processingTimeRemaining > 0

        if ready {
            processorBaseNode.fillColor = UIColor(red: 0.27, green: 0.36, blue: 0.2, alpha: 1)
            processorBaseNode.strokeColor = UIColor(red: 0.85, green: 0.95, blue: 0.58, alpha: 1)
            processorLabel.text = "Processor: ready"
            if processorOutputZoneNode.action(forKey: "readyPulse") == nil {
                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: 0.3),
                    SKAction.fadeAlpha(to: 0.55, duration: 0.3)
                ])
                processorOutputZoneNode.run(SKAction.repeatForever(pulse), withKey: "readyPulse")
            }
        } else if processing {
            processorBaseNode.fillColor = UIColor(red: 0.22, green: 0.29, blue: 0.39, alpha: 1)
            processorBaseNode.strokeColor = UIColor(red: 0.58, green: 0.79, blue: 1.0, alpha: 1)
            processorLabel.text = "Processor: processing"
            processorOutputZoneNode.removeAction(forKey: "readyPulse")
            processorOutputZoneNode.alpha = 1.0
        } else {
            processorBaseNode.fillColor = UIColor(red: 0.22, green: 0.24, blue: 0.28, alpha: 1)
            processorBaseNode.strokeColor = UIColor(red: 0.67, green: 0.72, blue: 0.8, alpha: 1)
            processorLabel.text = "Processor: idle"
            processorOutputZoneNode.removeAction(forKey: "readyPulse")
            processorOutputZoneNode.alpha = 1.0
        }

        let progress: CGFloat
        if processing, currentBatchTotalTime > 0 {
            progress = CGFloat(1.0 - (processingTimeRemaining / currentBatchTotalTime))
        } else {
            progress = 0
        }

        let width = max(2, 138 * progress)
        processorProgressFill.path = CGPath(
            roundedRect: CGRect(x: -69, y: -4, width: width, height: 8),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
    }

    private func updateSellZoneVisualState() {
        let hasProcessed = orchestrator.sessionState.processedInventory > 0
        if hasProcessed {
            sellZoneNode.fillColor = UIColor(red: 0.25, green: 0.72, blue: 0.25, alpha: 0.35)
            sellZoneNode.strokeColor = UIColor(red: 0.62, green: 1.0, blue: 0.62, alpha: 1)
        } else {
            sellZoneNode.fillColor = UIColor(red: 0.19, green: 0.58, blue: 0.19, alpha: 0.30)
            sellZoneNode.strokeColor = UIColor(red: 0.56, green: 0.95, blue: 0.56, alpha: 1)
        }
    }

    private func updateGateVisualState() {
        let unlocked = orchestrator.sessionState.unlockedZoneIDs
        for zone in config.zones where zone.id > 1 {
            let isUnlocked = unlocked.contains(zone.id)
            let gateNode = gateZoneNodes[zone.id]
            let label = gateLabelNodes[zone.id]

            if isUnlocked {
                gateNode?.fillColor = UIColor(red: 0.25, green: 0.72, blue: 0.25, alpha: 0.24)
                gateNode?.strokeColor = UIColor(red: 0.66, green: 1.0, blue: 0.66, alpha: 1)
                label?.text = "OPEN"
                label?.fontColor = UIColor(red: 0.76, green: 1.0, blue: 0.76, alpha: 1)
            } else {
                gateNode?.fillColor = UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 0.28)
                gateNode?.strokeColor = UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)
                label?.text = "UNLOCK \(zone.unlockPrice)"
                label?.fontColor = UIColor(red: 1.0, green: 0.86, blue: 0.86, alpha: 1)
            }
        }
    }

    private func applyUnlockVisualStateFromSession() {
        let unlocked = orchestrator.sessionState.unlockedZoneIDs

        for zone in config.zones where zone.id > 1 {
            let isUnlocked = unlocked.contains(zone.id)

            if let block = gateBlockNodes[zone.id] {
                block.isHidden = isUnlocked
                if isUnlocked {
                    block.physicsBody = nil
                } else if block.physicsBody == nil {
                    block.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 28, height: 280))
                    block.physicsBody?.isDynamic = false
                    block.physicsBody?.affectedByGravity = false
                    block.physicsBody?.categoryBitMask = CollisionLayer.blockingGeometry.rawValue
                    block.physicsBody?.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
                }
            }
        }

        for (resourceID, zoneID) in resourceZoneByID {
            let visibleByZone = unlocked.contains(zoneID)
            let stillRespawning = resourceRespawnTime[resourceID] != nil
            let shouldBeVisible = visibleByZone && !stillRespawning
            resourceNodes[resourceID]?.isHidden = !shouldBeVisible
            interactionZoneNodes[resourceID]?.isHidden = !shouldBeVisible
        }
    }

    private func updateResourceRespawns(currentTime: TimeInterval) {
        for (id, respawnTime) in resourceRespawnTime where currentTime >= respawnTime {
            let zoneID = resourceZoneByID[id] ?? 1
            let unlocked = orchestrator.sessionState.unlockedZoneIDs.contains(zoneID)
            resourceNodes[id]?.isHidden = !unlocked
            interactionZoneNodes[id]?.isHidden = !unlocked
            resourceRespawnTime.removeValue(forKey: id)
        }
    }
    private func updateHighlighting() {
        let guidance = orchestrator.sessionState.guidanceState
        let state = orchestrator.sessionState
        if let until = unlockFocusUntil, lastUpdateTime >= until {
            unlockFocusZoneID = nil
            unlockFocusUntil = nil
        }

        var candidates: [InteractionCandidate] = resourceNodes.compactMap { id, node in
            guard !node.isHidden else { return nil }
            let zoneID = resourceZoneByID[id] ?? 1
            guard state.unlockedZoneIDs.contains(zoneID) else { return nil }
            let distance = player.position.distance(to: node.position)
            return InteractionCandidate(
                zoneID: id,
                kind: .resource,
                distanceToPlayer: distance,
                isWithinInteractionRadius: distance <= tunedPickupRadius
            )
        }

        let inputDistance = player.position.distance(to: processorInputZoneNode.position)
        candidates.append(InteractionCandidate(
            zoneID: processorZoneInputID,
            kind: .processorInput,
            distanceToPlayer: inputDistance,
            isWithinInteractionRadius: inputDistance <= 56
        ))

        let outputDistance = player.position.distance(to: processorOutputZoneNode.position)
        let outputAvailable = state.processingQueue.processedReadyUnits > 0
        candidates.append(InteractionCandidate(
            zoneID: processorZoneOutputID,
            kind: .processorOutput,
            distanceToPlayer: outputDistance,
            isWithinInteractionRadius: outputAvailable && outputDistance <= 50
        ))

        let sellDistance = player.position.distance(to: sellZoneNode.position)
        let hasProcessed = state.processedInventory > 0
        candidates.append(InteractionCandidate(
            zoneID: sellZoneID,
            kind: .sell,
            distanceToPlayer: sellDistance,
            isWithinInteractionRadius: hasProcessed && sellDistance <= 58
        ))

        for zone in config.zones where zone.id > 1 {
            let isLocked = !state.unlockedZoneIDs.contains(zone.id)
            guard isLocked, let gate = gateZoneNodes[zone.id] else { continue }
            let gateDistance = player.position.distance(to: gate.position)
            candidates.append(InteractionCandidate(
                zoneID: gateZoneBaseID + zone.id,
                kind: .gate,
                distanceToPlayer: gateDistance,
                isWithinInteractionRadius: gateDistance <= 48
            ))
        }

        let decision = PrimaryTargetResolver.resolve(candidates: candidates, guidance: guidance)
        var primaryID = decision.primaryZoneID
        if primaryID == nil,
           let focusZone = unlockFocusZoneID,
           guidance.target == .collectResource {
            let focused = resourceNodes
                .filter { id, node in
                    guard !node.isHidden else { return false }
                    return resourceZoneByID[id] == focusZone
                }
                .min { lhs, rhs in
                    player.position.distanceSquared(to: lhs.value.position) < player.position.distanceSquared(to: rhs.value.position)
                }
            primaryID = focused?.key
        }
        currentPrimaryTargetID = primaryID

        for (id, highlight) in highlightNodes {
            let active = primaryID == id
            if active {
                if highlight.isHidden {
                    highlight.isHidden = false
                    let pulse = SKAction.sequence([
                        SKAction.scale(to: 1.12, duration: 0.25),
                        SKAction.scale(to: 1.0, duration: 0.25)
                    ])
                    highlight.run(SKAction.repeatForever(pulse), withKey: "pulse")
                }
            } else {
                highlight.removeAction(forKey: "pulse")
                highlight.isHidden = true
                highlight.setScale(1.0)
            }
        }
    }

    private func refreshHUD() {
        let state = orchestrator.sessionState
        let capacity = max(1, orchestrator.effectiveCarryCapacity)

        carryLabel.text = "Carry: \(state.carryAmount)/\(capacity)"
        coinsLabel.text = "Coins: \(state.coins)"
        if let focusZone = unlockFocusZoneID, state.guidanceState.target == .collectResource {
            guidanceLabel.text = "Collect resources in Zone \(focusZone)"
        } else {
            guidanceLabel.text = GuidanceTextPresenter.text(for: state.guidanceState)
        }

        if state.processingQueue.processedReadyUnits > 0 {
            processorStatusLabel.text = "Processor: ready (\(state.processingQueue.processedReadyUnits))"
        } else if processingTimeRemaining > 0 {
            processorStatusLabel.text = String(format: "Processor: processing (%.1fs)", processingTimeRemaining)
        } else {
            processorStatusLabel.text = "Processor: idle"
        }

        updateUpgradePanelTexts()
    }

    private func flashZone(_ node: SKNode, color: UIColor) {
        guard let shape = node as? SKShapeNode else { return }
        let original = shape.fillColor
        shape.removeAction(forKey: "flash")
        let flashIn = SKAction.run { shape.fillColor = color }
        let wait = SKAction.wait(forDuration: 0.10)
        let flashOut = SKAction.run { shape.fillColor = original }
        shape.run(SKAction.sequence([flashIn, wait, flashOut]), withKey: "flash")
    }

    private func showFloatingText(text: String, color: UIColor, at position: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 14
        label.fontColor = color
        label.position = CGPoint(x: position.x, y: position.y + 12)
        label.zPosition = 30
        worldNode.addChild(label)

        let move = SKAction.moveBy(x: 0, y: 26, duration: 0.45)
        let fade = SKAction.fadeOut(withDuration: 0.45)
        let group = SKAction.group([move, fade])
        label.run(SKAction.sequence([group, .removeFromParent()]))
    }

    #if DEBUG
    private func setupDebugOverlay() {
        pickupRadiusDebugCircle.strokeColor = UIColor(red: 0.95, green: 0.2, blue: 0.95, alpha: 0.85)
        pickupRadiusDebugCircle.lineWidth = 1.5
        pickupRadiusDebugCircle.fillColor = .clear
        pickupRadiusDebugCircle.zPosition = 9
        worldNode.addChild(pickupRadiusDebugCircle)

        debugPanelNode.zPosition = 1100

        debugSpeedLabel.fontSize = 12
        debugSpeedLabel.horizontalAlignmentMode = .left
        debugSpeedLabel.verticalAlignmentMode = .center
        debugSpeedLabel.fontColor = .white
        debugSpeedLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.22)

        debugTargetLabel.fontSize = 12
        debugTargetLabel.horizontalAlignmentMode = .left
        debugTargetLabel.verticalAlignmentMode = .center
        debugTargetLabel.fontColor = .white
        debugTargetLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.18)

        debugParamsLabel.fontSize = 11
        debugParamsLabel.horizontalAlignmentMode = .left
        debugParamsLabel.verticalAlignmentMode = .center
        debugParamsLabel.fontColor = UIColor(red: 0.78, green: 1.0, blue: 0.78, alpha: 1)
        debugParamsLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.14)

        debugProcessorLabel.fontSize = 11
        debugProcessorLabel.horizontalAlignmentMode = .left
        debugProcessorLabel.verticalAlignmentMode = .center
        debugProcessorLabel.fontColor = UIColor(red: 1.0, green: 0.9, blue: 0.66, alpha: 1)
        debugProcessorLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.10)

        debugStateLabel.fontSize = 11
        debugStateLabel.horizontalAlignmentMode = .left
        debugStateLabel.verticalAlignmentMode = .center
        debugStateLabel.fontColor = UIColor(red: 0.9, green: 1.0, blue: 0.9, alpha: 1)
        debugStateLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.06)

        debugSessionLabel.fontSize = 11
        debugSessionLabel.horizontalAlignmentMode = .left
        debugSessionLabel.verticalAlignmentMode = .center
        debugSessionLabel.fontColor = UIColor(red: 0.86, green: 0.92, blue: 1.0, alpha: 1)
        debugSessionLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.02)

        debugLoopLabel.fontSize = 11
        debugLoopLabel.horizontalAlignmentMode = .left
        debugLoopLabel.verticalAlignmentMode = .center
        debugLoopLabel.fontColor = UIColor(red: 0.86, green: 0.98, blue: 0.86, alpha: 1)
        debugLoopLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * -0.02)

        debugActionsLabel.fontSize = 10
        debugActionsLabel.horizontalAlignmentMode = .left
        debugActionsLabel.verticalAlignmentMode = .center
        debugActionsLabel.fontColor = UIColor(red: 1.0, green: 0.92, blue: 0.8, alpha: 1)
        debugActionsLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * -0.06)

        debugEconomyLabel.fontSize = 10
        debugEconomyLabel.horizontalAlignmentMode = .left
        debugEconomyLabel.verticalAlignmentMode = .center
        debugEconomyLabel.fontColor = UIColor(red: 0.86, green: 1.0, blue: 0.95, alpha: 1)
        debugEconomyLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * -0.10)

        debugPanelNode.addChild(debugSpeedLabel)
        debugPanelNode.addChild(debugTargetLabel)
        debugPanelNode.addChild(debugParamsLabel)
        debugPanelNode.addChild(debugProcessorLabel)
        debugPanelNode.addChild(debugStateLabel)
        debugPanelNode.addChild(debugSessionLabel)
        debugPanelNode.addChild(debugLoopLabel)
        debugPanelNode.addChild(debugActionsLabel)
        debugPanelNode.addChild(debugEconomyLabel)

        let controls: [(String, String, CGFloat, CGFloat)] = [
            ("A-", "dbg_accel_minus", -size.width * 0.45, size.height * -0.16),
            ("A+", "dbg_accel_plus", -size.width * 0.38, size.height * -0.16),
            ("V-", "dbg_speed_minus", -size.width * 0.30, size.height * -0.16),
            ("V+", "dbg_speed_plus", -size.width * 0.23, size.height * -0.16),
            ("R-", "dbg_radius_minus", -size.width * 0.15, size.height * -0.16),
            ("R+", "dbg_radius_plus", -size.width * 0.08, size.height * -0.16),
            ("C-", "dbg_camera_minus", 0.00, size.height * -0.16),
            ("C+", "dbg_camera_plus", 0.07, size.height * -0.16),
            ("RST", "dbg_session_reset", 0.17, size.height * -0.16)
        ]

        for (title, name, x, y) in controls {
            debugPanelNode.addChild(makeDebugButton(title: title, name: name, position: CGPoint(x: x, y: y)))
        }

        cameraNode.addChild(debugPanelNode)
    }
    private func makeDebugButton(title: String, name: String, position: CGPoint) -> SKNode {
        let container = SKShapeNode(rectOf: CGSize(width: 48, height: 24), cornerRadius: 5)
        container.name = name
        container.position = position
        container.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.95)
        container.strokeColor = UIColor(red: 0.65, green: 0.9, blue: 1.0, alpha: 1)
        container.lineWidth = 1.2

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = name
        label.text = title
        label.fontSize = 11
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.fontColor = .white
        container.addChild(label)
        return container
    }

    private func handleDebugTap(_ touch: UITouch) -> Bool {
        let point = touch.location(in: cameraNode)
        let nodesAtPoint = cameraNode.nodes(at: point)
        guard let buttonName = nodesAtPoint.compactMap({ $0.name }).first(where: { $0.hasPrefix("dbg_") }) else {
            return false
        }

        switch buttonName {
        case "dbg_accel_minus": tunedPlayerAcceleration = max(100, tunedPlayerAcceleration - 50)
        case "dbg_accel_plus": tunedPlayerAcceleration = min(2500, tunedPlayerAcceleration + 50)
        case "dbg_speed_minus": tunedPlayerMaxSpeed = max(80, tunedPlayerMaxSpeed - 10)
        case "dbg_speed_plus": tunedPlayerMaxSpeed = min(600, tunedPlayerMaxSpeed + 10)
        case "dbg_radius_minus":
            tunedPickupRadius = max(24, tunedPickupRadius - 4)
            updateResourceInteractionZoneRadii()
        case "dbg_radius_plus":
            tunedPickupRadius = min(200, tunedPickupRadius + 4)
            updateResourceInteractionZoneRadii()
        case "dbg_camera_minus": tunedCameraFollowSmoothing = max(0.02, tunedCameraFollowSmoothing - 0.05)
        case "dbg_camera_plus": tunedCameraFollowSmoothing = min(0.90, tunedCameraFollowSmoothing + 0.05)
        case "dbg_session_reset":
            resetSessionMetrics()
            showFloatingText(text: "Session metrics reset", color: UIColor(red: 0.8, green: 0.95, blue: 1.0, alpha: 1), at: player.position)
        default: break
        }

        return true
    }

    private func updateResourceInteractionZoneRadii() {
        for (_, zoneNode) in interactionZoneNodes {
            zoneNode.path = CGPath(
                ellipseIn: CGRect(x: -tunedPickupRadius, y: -tunedPickupRadius, width: tunedPickupRadius * 2, height: tunedPickupRadius * 2),
                transform: nil
            )
            let interactionBody = SKPhysicsBody(circleOfRadius: tunedPickupRadius)
            interactionBody.isDynamic = false
            interactionBody.affectedByGravity = false
            interactionBody.categoryBitMask = CollisionLayer.interactionZone.rawValue
            interactionBody.collisionBitMask = CollisionPolicy.interactionZoneCollisionMask.rawValue
            interactionBody.contactTestBitMask = CollisionLayer.player.rawValue
            zoneNode.physicsBody = interactionBody
        }
    }

    private func updateDebugOverlay(currentTime: TimeInterval) {
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        debugSpeedLabel.text = String(format: "Speed: %.1f", speed)

        if let targetID = currentPrimaryTargetID {
            debugTargetLabel.text = "Primary target: \(targetID)"
        } else {
            debugTargetLabel.text = "Primary target: -"
        }

        debugParamsLabel.text = String(
            format: "A %.0f | V %.0f | R %.0f | C %.2f",
            tunedPlayerAcceleration,
            tunedPlayerMaxSpeed,
            tunedPickupRadius,
            tunedCameraFollowSmoothing
        )

        let queue = orchestrator.sessionState.processingQueue
        let upgrades = orchestrator.sessionState.upgrades
        let unlocked = orchestrator.sessionState.unlockedZoneIDs.sorted().map(String.init).joined(separator: ",")
        debugProcessorLabel.text = String(format: "Q:%d T:%.1f O:%d", queue.queuedRawUnits, processingTimeRemaining, queue.processedReadyUnits)
        debugStateLabel.text = "Coins:\(orchestrator.sessionState.coins) ProcInv:\(orchestrator.sessionState.processedInventory) U:[\(unlocked)] L:\(upgrades.moveSpeed)/\(upgrades.carryCapacity)/\(upgrades.processingSpeed)"

        let elapsedSec = max(0, currentTime - (sessionMetrics.sessionStartTime ?? currentTime))
        let minutes = Int(elapsedSec) / 60
        let seconds = Int(elapsedSec) % 60
        let averageLoop = sessionMetrics.loopsCompleted > 0
            ? sessionMetrics.totalLoopDurationSec / Double(sessionMetrics.loopsCompleted)
            : 0

        debugSessionLabel.text = String(format: "Session: %02d:%02d", minutes, seconds)
        debugLoopLabel.text = String(format: "Loops: %d | Avg loop: %.1fs", sessionMetrics.loopsCompleted, averageLoop)
        debugActionsLabel.text = "Act C:\(sessionMetrics.resourcesCollected) O:\(sessionMetrics.processedOutputsCollected) S:\(sessionMetrics.processedUnitsSold) U:\(sessionMetrics.upgradesPurchased) Z:\(sessionMetrics.zonesUnlocked)"
        debugEconomyLabel.text = "Session Economy +\(sessionMetrics.coinsEarned) / -\(sessionMetrics.coinsSpent)"

        pickupRadiusDebugCircle.position = player.position
        pickupRadiusDebugCircle.path = CGPath(
            ellipseIn: CGRect(
                x: -tunedPickupRadius,
                y: -tunedPickupRadius,
                width: tunedPickupRadius * 2,
                height: tunedPickupRadius * 2
            ),
            transform: nil
        )
    }

    private func resetSessionMetrics() {
        sessionMetrics = SessionMetrics()
    }
    #endif
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt(distanceSquared(to: other))
    }

    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
