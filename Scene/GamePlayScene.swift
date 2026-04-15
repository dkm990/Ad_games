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

    private var resourceNodes: [Int: SKShapeNode] = [:]
    private var resourceRespawnTime: [Int: TimeInterval] = [:]
    private var interactionZoneNodes: [Int: SKShapeNode] = [:]
    private var highlightNodes: [Int: SKShapeNode] = [:]

    private let processorBaseNode = SKShapeNode(rectOf: CGSize(width: 190, height: 140), cornerRadius: 10)
    private let processorInputZoneNode = SKShapeNode(circleOfRadius: 56)
    private let processorOutputZoneNode = SKShapeNode(circleOfRadius: 50)
    private let processorProgressBackground = SKShapeNode(rectOf: CGSize(width: 140, height: 10), cornerRadius: 5)
    private let processorProgressFill = SKShapeNode(rectOf: CGSize(width: 138, height: 8), cornerRadius: 4)
    private let processorLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private var touchLocation: CGPoint?
    private var velocity: CGVector = .zero
    private var lastUpdateTime: TimeInterval = 0
    private var lastPickupCheckTime: TimeInterval = 0
    private var lastDepositTime: TimeInterval = 0
    private var lastOutputCollectTime: TimeInterval = 0
    private var currentPrimaryTargetID: Int?

    private var tunedPlayerAcceleration: CGFloat
    private var tunedPlayerMaxSpeed: CGFloat
    private var tunedPickupRadius: CGFloat
    private var tunedCameraFollowSmoothing: CGFloat = 8.0

    private var processingTimeRemaining: TimeInterval = 0
    private var currentBatchTotalTime: TimeInterval = 0

    private let processorZoneInputID = 9001
    private let processorZoneOutputID = 9002

    #if DEBUG
    private let debugPanelNode = SKNode()
    private let debugSpeedLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let debugTargetLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let debugParamsLabel = SKLabelNode(fontNamed: "Menlo-Regular")
    private let debugProcessorLabel = SKLabelNode(fontNamed: "Menlo-Regular")
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
        setupCameraAndHUD()
        #if DEBUG
        setupDebugOverlay()
        #endif
        refreshHUD()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        #if DEBUG
        if handleDebugTap(touch) {
            return
        }
        #endif
        touchLocation = touch.location(in: worldNode)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchLocation = touch.location(in: worldNode)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchLocation = nil
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(max(currentTime - lastUpdateTime, 0), 1.0 / 20.0)
        lastUpdateTime = currentTime

        updateMovement(dt: dt)
        updateCamera(dt: dt)
        updateResourceRespawns(currentTime: currentTime)
        runPickupIfNeeded(currentTime: currentTime)
        runProcessorInteractions(currentTime: currentTime)
        updateProcessingLifecycle(dt: dt)
        updateProcessorVisualState()
        updateHighlighting()
        refreshHUD()
        #if DEBUG
        updateDebugOverlay()
        #endif
    }

    private func buildMap() {
        let floor = SKShapeNode(rectOf: CGSize(width: 1200, height: 1200), cornerRadius: 6)
        floor.fillColor = UIColor(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
        floor.strokeColor = UIColor(red: 0.21, green: 0.25, blue: 0.29, alpha: 1)
        floor.lineWidth = 6
        floor.zPosition = 0
        worldNode.addChild(floor)

        createBlockingRect(size: CGSize(width: 180, height: 44), position: CGPoint(x: -120, y: 40))
        createBlockingRect(size: CGSize(width: 200, height: 44), position: CGPoint(x: 200, y: -100))
        createBlockingRect(size: CGSize(width: 140, height: 44), position: CGPoint(x: -220, y: -220))
        createBoundary(size: CGSize(width: 1120, height: 1120))
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
        player.position = CGPoint(x: 0, y: 0)

        let body = SKPhysicsBody(circleOfRadius: 18)
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 8
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = CollisionLayer.player.rawValue
        body.collisionBitMask = CollisionPolicy.playerCollisionMask.rawValue
        body.contactTestBitMask = CollisionPolicy.playerContactMask.rawValue
        player.physicsBody = body

        worldNode.addChild(player)
    }

    private func buildResources() {
        let positions = [
            CGPoint(x: -320, y: 220),
            CGPoint(x: -120, y: 280),
            CGPoint(x: 80, y: 220),
            CGPoint(x: 260, y: 180),
            CGPoint(x: 320, y: -20)
        ]

        for (index, point) in positions.enumerated() {
            let id = 100 + index
            let node = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 4)
            node.position = point
            node.fillColor = UIColor(red: 1.0, green: 0.75, blue: 0.22, alpha: 1)
            node.strokeColor = UIColor(red: 0.62, green: 0.33, blue: 0.02, alpha: 1)
            node.lineWidth = 2
            node.zPosition = 5
            node.name = "resource_\(id)"

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
            interactionZone.name = "interaction_resource_\(id)"

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
        }
    }

    private func buildProcessor() {
        let processorCenter = CGPoint(x: -40, y: -80)

        processorBaseNode.position = processorCenter
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

        processorInputZoneNode.position = CGPoint(x: processorCenter.x - 112, y: processorCenter.y - 12)
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

        processorOutputZoneNode.position = CGPoint(x: processorCenter.x + 112, y: processorCenter.y - 12)
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

    private func setupCameraAndHUD() {
        camera = cameraNode
        addChild(cameraNode)

        carryLabel.fontSize = 18
        carryLabel.horizontalAlignmentMode = .left
        carryLabel.verticalAlignmentMode = .center
        carryLabel.fontColor = .white
        carryLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.42)

        guidanceLabel.fontSize = 16
        guidanceLabel.horizontalAlignmentMode = .left
        guidanceLabel.verticalAlignmentMode = .center
        guidanceLabel.fontColor = UIColor(red: 0.78, green: 0.9, blue: 1.0, alpha: 1)
        guidanceLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.36)

        processorStatusLabel.fontSize = 15
        processorStatusLabel.horizontalAlignmentMode = .left
        processorStatusLabel.verticalAlignmentMode = .center
        processorStatusLabel.fontColor = UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1)
        processorStatusLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.30)

        hudNode.zPosition = 1000
        hudNode.addChild(carryLabel)
        hudNode.addChild(guidanceLabel)
        hudNode.addChild(processorStatusLabel)
        cameraNode.addChild(hudNode)
    }

    private func updateMovement(dt: TimeInterval) {
        let acceleration = tunedPlayerAcceleration
        let effectiveMaxSpeed = max(120, tunedPlayerMaxSpeed)

        var inputVector = CGVector.zero
        if let location = touchLocation {
            let delta = CGVector(dx: location.x - player.position.x, dy: location.y - player.position.y)
            let length = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)
            if length > 8 {
                inputVector = CGVector(dx: delta.dx / length, dy: delta.dy / length)
            }
        }

        if inputVector == .zero {
            velocity.dx *= 0.84
            velocity.dy *= 0.84
            if abs(velocity.dx) < 1 { velocity.dx = 0 }
            if abs(velocity.dy) < 1 { velocity.dy = 0 }
        } else {
            velocity.dx += inputVector.dx * acceleration * CGFloat(dt)
            velocity.dy += inputVector.dy * acceleration * CGFloat(dt)
            let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
            if speed > effectiveMaxSpeed {
                let k = effectiveMaxSpeed / speed
                velocity.dx *= k
                velocity.dy *= k
            }
        }

        player.physicsBody?.velocity = velocity
    }

    private func updateCamera(dt: TimeInterval) {
        let followStrength: CGFloat = min(1, CGFloat(dt) * tunedCameraFollowSmoothing)
        cameraNode.position.x += (player.position.x - cameraNode.position.x) * followStrength
        cameraNode.position.y += (player.position.y - cameraNode.position.y) * followStrength
    }

    private func runPickupIfNeeded(currentTime: TimeInterval) {
        guard currentTime - lastPickupCheckTime > 0.1 else { return }
        lastPickupCheckTime = currentTime

        let state = orchestrator.sessionState
        let carryCapacity = max(1, orchestrator.effectiveCarryCapacity)
        guard state.carryAmount < carryCapacity else { return }

        let nearest = resourceNodes
            .filter { _, node in
                node.isHidden == false && node.parent != nil
            }
            .min { lhs, rhs in
                player.position.distanceSquared(to: lhs.value.position) < player.position.distanceSquared(to: rhs.value.position)
            }

        guard let (id, node) = nearest else { return }
        guard player.position.distance(to: node.position) <= tunedPickupRadius else { return }

        orchestrator.perform(.collectRaw(units: 1))
        node.isHidden = true
        interactionZoneNodes[id]?.isHidden = true
        resourceRespawnTime[id] = currentTime + 2.0
    }

    private func runProcessorInteractions(currentTime: TimeInterval) {
        let state = orchestrator.sessionState

        if currentTime - lastDepositTime > 0.2,
           state.carryAmount > 0,
           player.position.distance(to: processorInputZoneNode.position) <= 56 {
            lastDepositTime = currentTime
            orchestrator.perform(.depositRawForProcessing(units: state.carryAmount))
        }

        if currentTime - lastOutputCollectTime > 0.2,
           state.processingQueue.processedReadyUnits > 0,
           player.position.distance(to: processorOutputZoneNode.position) <= 50 {
            lastOutputCollectTime = currentTime
            orchestrator.perform(.collectProcessedOutput(units: state.processingQueue.processedReadyUnits))
        }
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
        }
    }

    private func updateProcessorVisualState() {
        let state = orchestrator.sessionState
        let hasReadyOutput = state.processingQueue.processedReadyUnits > 0
        let isProcessing = processingTimeRemaining > 0

        if hasReadyOutput {
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
        } else if isProcessing {
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
        if isProcessing, currentBatchTotalTime > 0 {
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

    private func updateResourceRespawns(currentTime: TimeInterval) {
        for (id, respawnTime) in resourceRespawnTime where currentTime >= respawnTime {
            resourceNodes[id]?.isHidden = false
            interactionZoneNodes[id]?.isHidden = false
            resourceRespawnTime.removeValue(forKey: id)
        }
    }

    private func updateHighlighting() {
        let guidance = orchestrator.sessionState.guidanceState

        var candidates: [InteractionCandidate] = resourceNodes.compactMap { id, node in
            guard node.isHidden == false else { return nil }
            let distance = player.position.distance(to: node.position)
            let inRange = distance <= tunedPickupRadius
            return InteractionCandidate(
                zoneID: id,
                kind: .resource,
                distanceToPlayer: distance,
                isWithinInteractionRadius: inRange
            )
        }

        let inputDistance = player.position.distance(to: processorInputZoneNode.position)
        candidates.append(
            InteractionCandidate(
                zoneID: processorZoneInputID,
                kind: .processorInput,
                distanceToPlayer: inputDistance,
                isWithinInteractionRadius: inputDistance <= 56
            )
        )

        let outputDistance = player.position.distance(to: processorOutputZoneNode.position)
        let outputAvailable = orchestrator.sessionState.processingQueue.processedReadyUnits > 0
        candidates.append(
            InteractionCandidate(
                zoneID: processorZoneOutputID,
                kind: .processorOutput,
                distanceToPlayer: outputDistance,
                isWithinInteractionRadius: outputAvailable && outputDistance <= 50
            )
        )

        let decision = PrimaryTargetResolver.resolve(candidates: candidates, guidance: guidance)
        currentPrimaryTargetID = decision.primaryZoneID

        for (id, highlight) in highlightNodes {
            let active = decision.primaryZoneID == id
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
        guidanceLabel.text = GuidanceTextPresenter.text(for: state.guidanceState)

        if state.processingQueue.processedReadyUnits > 0 {
            processorStatusLabel.text = "Processor: ready (\(state.processingQueue.processedReadyUnits))"
        } else if processingTimeRemaining > 0 {
            processorStatusLabel.text = String(format: "Processor: processing (%.1fs)", processingTimeRemaining)
        } else {
            processorStatusLabel.text = "Processor: idle"
        }
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
        debugSpeedLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.24)

        debugTargetLabel.fontSize = 12
        debugTargetLabel.horizontalAlignmentMode = .left
        debugTargetLabel.verticalAlignmentMode = .center
        debugTargetLabel.fontColor = .white
        debugTargetLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.20)

        debugParamsLabel.fontSize = 11
        debugParamsLabel.horizontalAlignmentMode = .left
        debugParamsLabel.verticalAlignmentMode = .center
        debugParamsLabel.fontColor = UIColor(red: 0.78, green: 1.0, blue: 0.78, alpha: 1)
        debugParamsLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.16)

        debugProcessorLabel.fontSize = 11
        debugProcessorLabel.horizontalAlignmentMode = .left
        debugProcessorLabel.verticalAlignmentMode = .center
        debugProcessorLabel.fontColor = UIColor(red: 1.0, green: 0.9, blue: 0.66, alpha: 1)
        debugProcessorLabel.position = CGPoint(x: -size.width * 0.45, y: size.height * 0.12)

        debugPanelNode.addChild(debugSpeedLabel)
        debugPanelNode.addChild(debugTargetLabel)
        debugPanelNode.addChild(debugParamsLabel)
        debugPanelNode.addChild(debugProcessorLabel)

        let controls: [(String, String, CGFloat, CGFloat)] = [
            ("A-", "dbg_accel_minus", -size.width * 0.45, size.height * 0.07),
            ("A+", "dbg_accel_plus", -size.width * 0.38, size.height * 0.07),
            ("V-", "dbg_speed_minus", -size.width * 0.30, size.height * 0.07),
            ("V+", "dbg_speed_plus", -size.width * 0.23, size.height * 0.07),
            ("R-", "dbg_radius_minus", -size.width * 0.15, size.height * 0.07),
            ("R+", "dbg_radius_plus", -size.width * 0.08, size.height * 0.07),
            ("C-", "dbg_camera_minus", 0.00, size.height * 0.07),
            ("C+", "dbg_camera_plus", 0.07, size.height * 0.07)
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
        case "dbg_camera_minus": tunedCameraFollowSmoothing = max(1, tunedCameraFollowSmoothing - 0.5)
        case "dbg_camera_plus": tunedCameraFollowSmoothing = min(20, tunedCameraFollowSmoothing + 0.5)
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

    private func updateDebugOverlay() {
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        debugSpeedLabel.text = String(format: "Speed: %.1f", speed)

        if let targetID = currentPrimaryTargetID {
            debugTargetLabel.text = "Primary target: \(targetID)"
        } else {
            debugTargetLabel.text = "Primary target: -"
        }

        debugParamsLabel.text = String(
            format: "A %.0f | V %.0f | R %.0f | C %.1f",
            tunedPlayerAcceleration,
            tunedPlayerMaxSpeed,
            tunedPickupRadius,
            tunedCameraFollowSmoothing
        )

        let queue = orchestrator.sessionState.processingQueue
        debugProcessorLabel.text = String(
            format: "Q:%d T:%.1f O:%d",
            queue.queuedRawUnits,
            processingTimeRemaining,
            queue.processedReadyUnits
        )

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
